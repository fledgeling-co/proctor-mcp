import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// Acceptance E2E Tests: Comprehensive verification of end-to-end user journeys
// through the Proctor agent engine across all tool domains, witness tiers,
// actuation planes, and policy governance gates.

final class SuccessFakeCapture: CaptureEngine, @unchecked Sendable {
    func capture(window: WindowHandle, to path: String?, waitForComplete: Bool,
                 timeoutMs: Int, scale: Double?, tileHashes: Bool,
                 includeCursor: Bool, normalize: CaptureNormalizeOptions?,
                 encoding: ImageEncodingOptions) async throws -> CaptureResult {
        CaptureResult(window: window.id,
                      path: path ?? "/tmp/fake-capture.png",
                      width: 800, height: 600, scale: 2.0,
                      status: .complete,
                      contentRect: Rect(x: 0, y: 0, w: 800, h: 600),
                      dirtyRectCount: 0, dirtyArea: 0,
                      capturedAt: Date().timeIntervalSince1970,
                      framesWaited: 1,
                      trustworthy: true,
                      caveat: nil)
    }

    func beginQuietWatch(window: WindowHandle) async throws -> QuietWatch { FakeCapture.IdleWatch() }
}

@Suite("Acceptance E2E: Complete campaign user journeys")
struct AcceptanceE2ETests {

    private static let testBundleID = "com.fledgeling.testapp"

    private func makeHarness(environment: [String: String] = [:]) async throws
        -> (session: Session, ax: FakeAX, capture: SuccessFakeCapture, collector: AuditCollector) {
        let ax = FakeAX(bundleId: Self.testBundleID)
        let capture = SuccessFakeCapture()
        let session = Session(
            ax: ax, capture: capture,
            tools: ToolProbes(environment: environment),
            secureInputProbe: { false })
        let collector = AuditCollector()
        await session.setAuditSink(collector.sink)
        await session.setDrawsHUD(false)
        return (session, ax, capture, collector)
    }

    @Test("E2E Journey 1: Full native testing campaign (attach -> snapshot -> find -> act -> assert -> capture)")
    func completeNativeCampaignJourney() async throws {
        let (session, ax, _, collector) = try await makeHarness()

        // 1. Attach to application
        let (app, windows, provenance) = try await session.attachResolved(bundleId: Self.testBundleID, pid: nil, name: nil)
        #expect(app.bundleId == Self.testBundleID)
        #expect(app.id == ax.app.id)
        #expect(!windows.isEmpty)
        #expect(provenance.elapsedMs >= 0)

        // 2. Snapshot & find elements
        let snapshot = try await session.snapshot(window: ax.window.id, options: .init(), sinceRevision: nil)
        #expect(snapshot.root?.id == "node-1")
        #expect(snapshot.provenance.elapsedMs >= 0)

        let predicate = FindPredicate(json: .object(["role": .string("AXButton")]))
        let findResult = try await session.find(window: ax.window.id, predicate: predicate, limit: 10)
        let foundNodes = try #require(findResult["nodes"]?.arrayValue)
        #expect(foundNodes.count == 1)
        #expect(foundNodes.first?["id"]?.stringValue == "node-1")

        // 3. Batched multi-step actuation on background plane
        let steps = [
            ActionStep(kind: .setValue, node: "node-1", value: .string("Search query")),
            ActionStep(kind: .press, node: "node-1"),
            ActionStep(kind: .scroll, node: "node-1", delta: [0, 2])
        ]
        let actResult = try await session.act(window: ax.window.id, steps: steps, settle: .default,
                                             foreground: false, captureEach: false, diffEach: false,
                                             record: nil)
        let stepReports = try #require(actResult["steps"]?.arrayValue)
        #expect(stepReports.count == 3)
        #expect(stepReports[0]["ok"]?.boolValue == true)
        #expect(stepReports[0]["plane"]?.stringValue == "accessibility")

        // 4. Tri-observer assertions (exists, label)
        let assertResult = try await session.assertAll(
            window: ax.window.id,
            assertions: [
                .object(["kind": .string("exists"), "find": .object(["role": .string("AXButton")])])
            ],
            captureEvidence: false)
        #expect(assertResult["ok"]?.boolValue == true)

        // 5. Visual capture with SCFrameStatus & trustworthiness
        let captureResult = try await session.captureWindow(ax.window.id,
                                                           path: nil,
                                                           waitForComplete: true,
                                                           timeoutMs: 3000,
                                                           scale: nil,
                                                           tileHashes: false,
                                                           includeCursor: false,
                                                           normalize: nil,
                                                           encoding: ImageEncodingOptions(format: .png),
                                                           annotate: Session.AnnotateOptions())
        #expect(captureResult["trustworthy"]?.boolValue == true)
        #expect(captureResult["status"]?.stringValue == "complete" || captureResult["frameStatus"]?.stringValue == "complete")

        // 6. Audit trail verification: act records are written to audit trail with proper redactions
        let entries = collector.records
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.tool == "proctor_act" })
        #expect(entries[0].kind == "setValue")
        #expect(entries[0].value?.len == 12)
        #expect(entries[1].kind == "press")
        #expect(entries[2].kind == "scroll")
    }

    @Test("E2E Journey 2: Flow recording, replay, and determinism stability scoring")
    func flowRecordingAndStabilityJourney() async throws {
        let (session, ax, _, _) = try await makeHarness()
        _ = try await session.attachResolved(bundleId: Self.testBundleID, pid: nil, name: nil)

        // 1. Record flow
        let flowName = "login-flow"
        _ = try await session.flowStart(name: flowName, window: ax.window.id, description: nil)

        let step1 = ActionStep(kind: .setValue, node: "node-1", value: .string("user@example.com"))
        let step2 = ActionStep(kind: .press, node: "node-1")
        _ = try await session.act(window: ax.window.id, steps: [step1, step2], settle: .default,
                                  foreground: false, captureEach: false, diffEach: false,
                                  record: flowName)

        let stopped = try await session.flowStop()
        #expect(stopped["stopped"]?.stringValue == flowName)
        #expect(stopped["steps"]?.intValue == 2)

        // 2. Stability evaluation (5 runs)
        let report = try await session.stability(flow: flowName, runs: 5, window: ax.window.id,
                                                resetBetween: [], includeTiles: false,
                                                captureEach: false, pointerMarks: false)
        #expect(report.runs == 5)
        #expect(report.deterministic == true)
        #expect(report.stepInstability.count == 2)
        #expect(report.stepInstability[0] == 0.0)
        #expect(report.stepInstability[1] == 0.0)
    }

    @Test("E2E Journey 3: Multi-witness tiers, auto-route refusal, and handle namespace defense")
    func witnessTierAndAutoRouteDefenseJourney() async throws {
        let (session, ax, _, _) = try await makeHarness(environment: [GuestRouteConfig.env: "sequoia-seed"])
        _ = try await session.attachResolved(bundleId: Self.testBundleID, pid: nil, name: nil)

        // 1. Handle namespace rejection: gst- and dev- handles cannot be passed to window tools
        do {
            _ = try await session.act(window: "gst-macos-sequoia",
                                      steps: [ActionStep(kind: .click, node: "node-1")],
                                      settle: .default, foreground: true, captureEach: false,
                                      diffEach: false, record: nil)
            Issue.record("gst- handle must be rejected by window tools")
        } catch let error as AgentError {
            #expect(error.message.contains("guest handle"))
        }

        do {
            _ = try await session.snapshot(window: "dev-iphone-15", options: .init(), sinceRevision: nil)
            Issue.record("dev- handle must be rejected by window tools")
        } catch let error as AgentError {
            #expect(error.message.contains("iOS device handle"))
        }

        // 2. Auto-route refusal gate when PROCTOR_GUEST is configured
        // Synthetic click batch on host with PROCTOR_GUEST configured must be refused with remedy
        do {
            _ = try await session.act(window: ax.window.id,
                                      steps: [ActionStep(kind: .click, node: "node-1")],
                                      settle: .default, foreground: true, captureEach: false,
                                      diffEach: false, record: nil)
            Issue.record("Host takeover batch must be refused when PROCTOR_GUEST is set")
        } catch let error as AgentError {
            #expect(error.code == .notImplemented)
            #expect(error.message.contains("wrong machine"))
        }

        // Background-safe setValue is NOT refused by auto-route
        let backgroundAct = try await session.act(window: ax.window.id,
                                                  steps: [ActionStep(kind: .setValue, node: "node-1", value: .string("ok"))],
                                                  settle: .default, foreground: false, captureEach: false,
                                                  diffEach: false, record: nil)
        #expect(backgroundAct["steps"]?.arrayValue?.first?["ok"]?.boolValue == true)
    }
}
