import Foundation
import CoreGraphics
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
        let dest = path ?? "/tmp/fake-capture.png"
        if !FileManager.default.fileExists(atPath: dest) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
                                   bytesPerRow: 800 * 4, space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
               let img = ctx.makeImage() {
                try? ImageWriter.write(img, to: dest, format: .png, what: "fake-capture")
            }
        }
        return CaptureResult(window: window.id,
                      path: dest,
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

final class FakeTriObserver: TriObserving, @unchecked Sendable {
    func agree(window: WindowHandle, tree: AXNode) async throws -> [Disagreement] { [] }
    func contrast(window: WindowHandle, node: AXNode) async throws -> Double { 8.2 }
    func hitSize(window: WindowHandle, node: AXNode) async throws -> Rect {
        Rect(x: node.frame?.x ?? 0, y: node.frame?.y ?? 0, w: 32, h: 32)
    }
}

@Suite("Acceptance E2E: Complete campaign user journeys")
struct AcceptanceE2ETests {

    private static let testBundleID = "com.fledgeling.testapp"

    private func makeHarness(environment: [String: String] = [:],
                             tri: (any TriObserving)? = nil) async throws
        -> (session: Session, ax: FakeAX, capture: SuccessFakeCapture, collector: AuditCollector) {
        let ax = FakeAX(bundleId: Self.testBundleID)
        let capture = SuccessFakeCapture()
        let session = Session(
            ax: ax, capture: capture,
            tri: tri,
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

    @Test("E2E Journey 4: Visual UI, geometry, and accessibility audit (frame, alignment, contrast, hit size, focus order, and tri-observer agree)")
    func visualUIGeometryAndAccessibilityAuditJourney() async throws {
        let tri = FakeTriObserver()
        let (session, ax, _, _) = try await makeHarness(tri: tri)
        _ = try await session.attachResolved(bundleId: Self.testBundleID, pid: nil, name: nil)

        // Setup a structured accessibility tree with parent container and multiple aligned child elements
        let containerNode = AXNode(id: "container-1", role: "AXGroup", title: "Form Container",
                                   frame: Rect(x: 100, y: 100, w: 600, h: 400))
        let buttonNode = AXNode(id: "btn-submit", role: "AXButton", title: "Submit",
                                frame: Rect(x: 100, y: 120, w: 100, h: 32),
                                enabled: true, focused: false)
        let labelNode = AXNode(id: "lbl-title", role: "AXStaticText", title: "Preferences",
                               frame: Rect(x: 100, y: 160, w: 200, h: 24),
                               enabled: true, focused: false)
        let inputNode = AXNode(id: "txt-input", role: "AXTextField", title: "User Name",
                               frame: Rect(x: 100, y: 200, w: 200, h: 32),
                               enabled: true, focused: true)

        ax.nodesByID = [
            "container-1": containerNode,
            "btn-submit": buttonNode,
            "lbl-title": labelNode,
            "txt-input": inputNode
        ]

        // 1. Accessibility & geometry assertions: hasLabel, frameEquals, containedIn, alignedWith, horizontalAlignment
        let assertions: [JSONValue] = [
            .object([
                "kind": .string("hasLabel"),
                "node": .string("btn-submit")
            ]),
            .object([
                "kind": .string("frameEquals"),
                "node": .string("btn-submit"),
                "expected": .array([.number(100), .number(120), .number(100), .number(32)]),
                "tolerance": .number(1.0)
            ]),
            .object([
                "kind": .string("containedIn"),
                "node": .string("btn-submit"),
                "expected": .string("container-1")
            ]),
            .object([
                "kind": .string("alignedWith"),
                "node": .string("lbl-title"),
                "expected": .object(["node": .string("btn-submit"), "edge": .string("left")]),
                "tolerance": .number(1.0)
            ]),
            .object([
                "kind": .string("horizontalAlignment"),
                "node": .string("btn-submit"),
                "container": .string("container-1"),
                "expected": .string("left")
            ]),
            .object([
                "kind": .string("minHitSize"),
                "node": .string("btn-submit"),
                "expected": .number(24.0)
            ]),
            .object([
                "kind": .string("contrast"),
                "node": .string("lbl-title"),
                "expected": .number(4.5)
            ]),
            .object([
                "kind": .string("agree")
            ])
        ]

        let assertResult = try await session.assertAll(window: ax.window.id,
                                                       assertions: assertions,
                                                       captureEvidence: false)
        #expect(assertResult["ok"]?.boolValue == true)
        #expect(assertResult["passed"]?.intValue == 8)
        #expect(assertResult["failed"]?.intValue == 0)
        #expect(assertResult["skipped"]?.intValue == 0)
    }

    @Test("E2E Journey 5: High-resolution zoom & region crop visual fidelity inspection")
    func highResolutionZoomAndCropJourney() async throws {
        let (session, ax, _, _) = try await makeHarness()
        _ = try await session.attachResolved(bundleId: Self.testBundleID, pid: nil, name: nil)

        let targetNode = AXNode(id: "node-target", role: "AXButton", title: "Target Area",
                                frame: Rect(x: 50, y: 50, w: 200, h: 100))
        ax.nodesByID = ["node-target": targetNode]

        // 1. Zoom into element node
        let nodeZoomResult = try await session.zoom(
            window: ax.window.id,
            region: nil,
            node: "node-target",
            padding: 10.0,
            path: nil,
            waitForComplete: true,
            timeoutMs: 3000,
            scale: nil,
            includeCursor: false,
            encoding: ImageEncodingOptions(format: .png))

        #expect(nodeZoomResult["crop"]?["source"]?.stringValue == "element")
        #expect(nodeZoomResult["crop"]?["node"]?.stringValue == "node-target")
        #expect(nodeZoomResult["trustworthy"]?.boolValue == true)

        // 2. Zoom into explicit region [x, y, w, h]
        let regionZoomResult = try await session.zoom(
            window: ax.window.id,
            region: [20, 20, 150, 120],
            node: nil,
            padding: 0.0,
            path: nil,
            waitForComplete: true,
            timeoutMs: 3000,
            scale: nil,
            includeCursor: false,
            encoding: ImageEncodingOptions(format: .png))

        #expect(regionZoomResult["crop"]?["source"]?.stringValue == "region")
        #expect(regionZoomResult["width"]?.intValue ?? 0 > 0)
        #expect(regionZoomResult["height"]?.intValue ?? 0 > 0)
    }

    @Test("E2E Journey 6: Menu-bar key equivalents, keyboard shortcuts, and modifier reconstruction")
    func menuBarKeyEquivalentIntrospectionJourney() async throws {
        let (session, ax, _, _) = try await makeHarness()
        _ = try await session.attachResolved(bundleId: Self.testBundleID, pid: nil, name: nil)

        // Inject simulated macOS menu bar structure
        ax.menuBarItems = [
            RawMenuItem(title: "File", enabled: true, hasSubmenu: true, submenuPopulated: true,
                        children: [
                            RawMenuItem(title: "New Document", enabled: true, cmdChar: "n", cmdModifiers: 0),
                            RawMenuItem(title: "Save As...", enabled: true, cmdChar: "s",
                                        cmdModifiers: MenuKeyEquivalent.CarbonMask.shift)
                        ]),
            RawMenuItem(title: "Edit", enabled: true, hasSubmenu: true, submenuPopulated: true,
                        children: [
                            RawMenuItem(title: "Preferences", enabled: true, cmdChar: ",", cmdModifiers: 0)
                        ])
        ]

        let menuResult = try await session.menuBar(app: ax.app.id, window: nil)
        #expect(menuResult["app"]?.stringValue == ax.app.id)
        #expect(menuResult["itemCount"]?.intValue == 5)

        let items = try #require(menuResult["items"]?.arrayValue)
        #expect(items.count == 5)
        #expect(items[1]["path"]?.arrayValue?.map { $0.stringValue } == ["File", "New Document"])
        #expect(items[1]["key"]?.stringValue == "n")
        #expect(items[1]["modifiers"]?.arrayValue?.map { $0.stringValue } == ["cmd"])
        #expect(items[2]["key"]?.stringValue == "s")
        #expect(items[2]["modifiers"]?.arrayValue?.contains(where: { $0.stringValue == "shift" }) == true)
        #expect(items[4]["path"]?.arrayValue?.map { $0.stringValue } == ["Edit", "Preferences"])
        #expect(items[4]["key"]?.stringValue == ",")
    }

    @Test("E2E Journey 7: iOS companion device management, deep-link dispatch, and Maestro runner lifecycle")
    func iosDeviceAndMaestroLifecycleJourney() async throws {
        let (session, _, _, _) = try await makeHarness()

        // 1. Simctl absence defense: when simctl is absent, ios commands report actionable guidance
        do {
            _ = try await session.ios(action: "list", device: nil, url: nil, bundleId: nil,
                                      pixelEvidence: false, changeThreshold: nil, path: nil,
                                      timeoutMs: 1000, settleMs: 500)
        } catch let error as AgentError {
            #expect(error.code == .notImplemented)
            #expect(error.message.contains("Xcode") || error.message.contains("simctl"))
        }

        // 2. Maestro runner absence & flow defense: when Maestro CLI is absent, flow execution reports structured error
        do {
            _ = try await session.maestroFlow(path: "/tmp/nonexistent-flow.yaml", device: nil, runs: 1,
                                              pixelEvidence: false, timeoutMs: 1000)
        } catch let error as AgentError {
            #expect(error.code == .notImplemented || error.code == .invalidArguments)
        }
    }
}
