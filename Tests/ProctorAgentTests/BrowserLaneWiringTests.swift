import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0024 — the wiring half of the second browser lane.
//
// The decision is pure and tested in `BrowserLaneTests`. What is tested here is
// where it reaches the wire: that the gate travels from an injected environment
// through the encoded JSON, that `proctor_doctor` reports both tools and the
// lane's three states without letting either touch `ready`, and that the two
// probes are cached independently under an injected clock.
//
// Every test injects its own probes, its own clock **and its own environment**. A
// process's environment is cached at launch, so `setenv` in a test does nothing
// and a suite that reaches for `ProcessInfo` lets whichever test ran first decide
// for the whole process.
//
// Not testable here: the status window's browser-use row (no window server), and
// anything about what browser-use actually does — verifying that would mean
// installing it on this machine, which the operator's standing instruction
// forbids, and which is the act this feature exists to avoid provoking.

@Suite("Second lane wiring")
struct BrowserLaneWiringTests {

    private static let chrome = "com.google.Chrome"
    private static let safari = "com.apple.Safari"

    private static let pageProbe = WebContentProbe(areas: [
        WebArea(url: "https://example.com/dashboard", frame: Rect(x: 0, y: 0, w: 800, h: 600))
    ])
    private static let internalProbe = WebContentProbe(areas: [
        WebArea(url: "chrome://newtab", frame: Rect(x: 0, y: 0, w: 800, h: 600))
    ])

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = 1_000.0
        var now: Double { lock.withLock { t } }
        func advance(_ seconds: Double) { lock.withLock { t += seconds } }
    }

    private final class Counted: @unchecked Sendable {
        private let lock = NSLock()
        private let tool: String
        private var _available: Bool
        private var _calls = 0
        init(tool: String, available: Bool) { self.tool = tool; _available = available }
        var calls: Int { lock.withLock { _calls } }
        func set(_ available: Bool) { lock.withLock { _available = available } }
        func read() -> ToolPresence {
            lock.withLock {
                _calls += 1
                return ToolPresence(tool: tool, available: _available,
                                    path: _available ? "/opt/homebrew/bin/" + tool : nil,
                                    searched: ["/opt/homebrew/bin/" + tool])
            }
        }
    }

    private func harness(obscura: Bool, browserUse: Bool, laneSet: Bool,
                         bundleId: String = chrome, probe: WebContentProbe = pageProbe)
    async throws -> (Session, Counted, Counted, Clock) {
        let ax = FakeAX(bundleId: bundleId)
        ax.webContentProbe = probe
        let o = Counted(tool: ObscuraTool.binary, available: obscura)
        let b = Counted(tool: BrowserUseTool.binary, available: browserUse)
        let clock = Clock()
        let session = Session(
            ax: ax, capture: FakeCapture(),
            tools: ToolProbes(
                obscura: ToolProbe(probe: { o.read() }, now: { clock.now }),
                browserUse: ToolProbe(probe: { b.read() }, now: { clock.now },
                                      presentTTL: ToolProbe.presentTTL,
                                      absentTTL: ToolProbe.presentTTL),
                environment: laneSet ? [BrowserUseTool.laneVariable: BrowserUseTool.binary] : [:]),
            screenRecordingProbe: .fake())
        await session.setAuditSink(AuditCollector().sink)
        _ = try await session.attachResolved(bundleId: bundleId, pid: nil, name: nil)
        return (session, o, b, clock)
    }

    private func attachHandoff(_ session: Session, _ bundleId: String = chrome) async throws
    -> [String: JSONValue] {
        let result = try await session.attach(bundleId: bundleId, pid: nil, name: nil)
        return try #require(result.objectValue?["browser"]?.objectValue)
    }

    // MARK: - Clause 17 — the lane travels end to end

    @Test("an enabled lane reaches the encoded JSON of a page result with its reason")
    func theLaneReachesTheWire() async throws {
        // A browser-internal page needs a window, so this is the snapshot surface
        // rather than attach: the app-level handoff has no URL to route on, by
        // construction.
        let (session, _, _, _) = try await harness(obscura: true, browserUse: true, laneSet: true,
                                                   probe: Self.internalProbe)
        let snapshot = try await session.snapshot(window: "win-1", options: .init(),
                                                  sinceRevision: nil)
        let encoded = try JSONEncoder().encode(snapshot)
        let wire = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let handoff = try #require(wire["browser"] as? [String: Any])
        #expect(handoff["use"] as? String == "browser-use")
        #expect(handoff["why"] as? String == BrowserTarget.whyInternalScheme)
        #expect(handoff["url"] as? String == "chrome://newtab")
        #expect(handoff["commands"] == nil)
        // The disclosure the brief form must not wait for: this is the brief form.
        #expect((handoff["boundary"] as? String)?.contains("autonomous agent") == true)
        #expect((handoff["continuity"] as? String)?.contains("audit trail") == true)
    }

    @Test("attach has no page to route on, so it never reaches the second lane")
    func attachNeverReachesTheSecondLane() async throws {
        // The app-level handoff carries no URL by construction, and the only rule
        // that names the second lane is about the page's own scheme.
        let (session, _, _, _) = try await harness(obscura: false, browserUse: true, laneSet: true)
        let handoff = try await attachHandoff(session)
        #expect(handoff["use"] == nil)
        #expect(handoff["toolUnavailable"]?.objectValue?["tool"]?.stringValue == "obscura")
    }

    @Test("with the variable unset the wire never carries the name")
    func theGateHoldsAtTheWire() async throws {
        // The same machine, the same page, the tool installed — and the operator's
        // rule says it is removed, so nothing names it.
        for probe in [Self.internalProbe, Self.pageProbe] {
            for obscura in [true, false] {
                let (session, _, _, _) = try await harness(obscura: obscura, browserUse: true,
                                                           laneSet: false, probe: probe)
                let result = try await session.attach(bundleId: Self.chrome, pid: nil, name: nil)
                #expect(!String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
                            .contains("browser-use"))
                let snapshot = try await session.snapshot(window: "win-1", options: .init(),
                                                          sinceRevision: nil)
                #expect(!String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
                            .contains("browser-use"))
                // The health report too, which is a tool result like any other.
                let report = await session.doctor(verbose: false)
                #expect(!String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
                            .contains("browser-use"))
            }
        }
    }

    @Test("an ordinary page never reaches the second lane, whatever is installed")
    func anOrdinaryPageNeverReachesTheSecondLane() async throws {
        let (session, _, _, _) = try await harness(obscura: false, browserUse: true, laneSet: true)
        let handoff = try #require(await session.snapshot(window: "win-1", options: .init(),
                                                          sinceRevision: nil).browser)
        #expect(handoff.use == nil)
        #expect(handoff.toolUnavailable == ObscuraTool.absence)
    }

    @Test("a Safari window with Obscura gone is told Obscura is gone, not handed a Chromium agent")
    func aNonChromiumWindowNeverGetsTheSecondLane() async throws {
        let (session, _, _, _) = try await harness(obscura: false, browserUse: true, laneSet: true,
                                                   bundleId: Self.safari)
        let handoff = try await attachHandoff(session, Self.safari)
        #expect(handoff["use"] == nil)
        #expect(handoff["toolUnavailable"]?.objectValue?["tool"]?.stringValue == "obscura")
    }

    // MARK: - Clause 15 — proctor_doctor

    @Test("doctor reports both tools, the lane's state, and never lets either touch ready")
    func doctorReportsBothToolsAndTheLaneState() async throws {
        var readies: Set<Bool> = []
        var blockerCounts: Set<Int> = []
        for obscura in [true, false] {
            for browserUse in [true, false] {
                for laneSet in [true, false] {
                    let (session, _, _, _) = try await harness(obscura: obscura,
                                                               browserUse: browserUse,
                                                               laneSet: laneSet)
                    let report = await session.doctor(verbose: false)

                    // The array is the growth surface, in a fixed order, always both.
                    // The second tool is listed only when the operator named it,
                    // so with the lane off its name is absent from the whole
                    // result rather than only from a handoff.
                    //
                    // simctl (PRO-0048) is the growth surface working as intended:
                    // an unconditional third row rather than a fourth top-level
                    // boolean. It is unconditional because "does this machine have
                    // an iOS lane" is not behind an operator switch the way the
                    // second browser lane is.
                    #expect(report.tools.map(\.tool)
                            == (laneSet ? [ObscuraTool.binary, BrowserUseTool.binary, "simctl"]
                                        : [ObscuraTool.binary, "simctl"]))
                    // The grandfathered spelling has to agree with the array's
                    // first entry, or an old client and a new one see different
                    // machines.
                    #expect(report.obscura == report.tools[0])
                    #expect(report.obscuraAvailable == report.tools[0].available)
                    #expect((report.obscuraUnavailable == nil) == report.obscuraAvailable)
                    if laneSet { #expect(report.tools[1].available == browserUse) }

                    let expected: SecondLaneState = !laneSet ? .off
                        : (browserUse ? .enabled : .unavailable)
                    #expect(report.secondLane == expected.rawValue,
                            "obscura \(obscura) browserUse \(browserUse) laneSet \(laneSet)")

                    readies.insert(report.ready)
                    blockerCounts.insert(report.blockers.count)
                }
            }
        }
        // `ready` means Proctor can do its own job, and Proctor drives native
        // applications without any browser tool at all.
        #expect(readies.count == 1)
        #expect(blockerCounts.count == 1)
    }

    // MARK: - Clause 18 — no install text anywhere in a tool result

    @Test("the whole doctor result carries no install command for either tool")
    func theDoctorResultCarriesNoInstallCommand() async throws {
        let (session, _, _, _) = try await harness(obscura: false, browserUse: false, laneSet: true)
        let report = await session.doctor(verbose: false)
        let encoded = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        for fragment in ["curl", "tar ", "mkdir", " mv ", "uvx", "pip ", "pipx"] {
            #expect(!encoded.contains(fragment), "\(fragment) reached a tool result")
        }
        // They exist, and they exist only where a person is present to read them.
        #expect(ObscuraTool.installCommands(architecture: .appleSilicon).count == 3)
    }

    // MARK: - Clause 16 — two caches, independent, and one write-through

    @Test("the two probes are cached independently and expire on their own terms")
    func theTwoCachesAreIndependent() async throws {
        let (session, obscuraProbe, browserUseProbe, clock) =
            try await harness(obscura: false, browserUse: false, laneSet: true)
        _ = try await attachHandoff(session)
        let obscuraAfterFirst = obscuraProbe.calls
        let browserUseAfterFirst = browserUseProbe.calls

        // Inside both windows: one probe each serves a batch of handoffs.
        for _ in 0..<3 { _ = try await attachHandoff(session) }
        #expect(obscuraProbe.calls == obscuraAfterFirst)
        #expect(browserUseProbe.calls == browserUseAfterFirst)

        // Past Obscura's short absent window. Obscura re-probes because Proctor is
        // what provokes somebody to install it; browser-use does not, because
        // Proctor asks nobody to install that one.
        clock.advance(ToolProbe.absentTTL + 1)
        _ = try await attachHandoff(session)
        #expect(obscuraProbe.calls > obscuraAfterFirst)
        #expect(browserUseProbe.calls == browserUseAfterFirst)

        // Past the long one, and the second probe finally re-reads.
        clock.advance(ToolProbe.presentTTL + 1)
        _ = try await attachHandoff(session)
        #expect(browserUseProbe.calls > browserUseAfterFirst)
    }

    @Test("a doctor call re-probes both and writes through to what the handoffs read")
    func aDoctorCallWritesThroughBothCaches() async throws {
        // Somebody installs browser-use mid-session and sets the lane. Without the
        // write-through the health report and the next handoff would describe the
        // same machine differently at the same instant, for five minutes.
        let (session, _, browserUseProbe, _) =
            try await harness(obscura: true, browserUse: false, laneSet: true,
                              probe: Self.internalProbe)
        let before = try #require(await session.snapshot(window: "win-1", options: .init(),
                                                         sinceRevision: nil).browser)
        #expect(before.use == nil)
        #expect(before.toolUnavailable?.tool == "browser-use")

        browserUseProbe.set(true)
        let report = await session.doctor(verbose: false)
        #expect(report.secondLane == SecondLaneState.enabled.rawValue)

        let after = try #require(await session.snapshot(window: "win-1", options: .init(),
                                                        sinceRevision: nil).browser)
        #expect(after.use == "browser-use")
    }

    // MARK: - Clause 19 — the surface gains no verb

    @Test("no new tool verb, and the doctor output schema documents the new fields")
    func theToolSurfaceIsUnchanged() {
        #expect(!ToolCatalogue.all.contains { $0.name.contains("browser") })
        let schema = ToolCatalogue.outputSchema(for: "proctor_doctor")
        let properties = schema.objectValue?["properties"]?.objectValue
        #expect(properties?["tools"] != nil)
        #expect(properties?["secondLane"] != nil)
        #expect(properties?["obscuraAvailable"] != nil)
    }
}
