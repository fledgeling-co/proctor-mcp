import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0023 — the wiring half of noticing that Obscura is not installed.
//
// The decision is pure and tested in ProctorCoreTests. What is tested here is
// where it reaches the wire: that the browser advisory stops naming a command
// this machine does not have, that proctor_doctor reports the fact without
// pretending Proctor is broken, and that the cache behaves — one probe for a
// batch of handoffs, a short life for the answer somebody is in the middle of
// changing, and a doctor call that writes through so the two surfaces cannot
// disagree.
//
// Every test injects its own probe and its own clock. The default ToolProbe
// reads the real filesystem, and a suite that let it would answer differently on
// a machine with Obscura installed than on one without.
//
// Not testable here: the status window's Obscura row, its callout and its three
// buttons (no window server), and that `sysctlbyname("hw.optional.arm64")` reads
// the hardware under Rosetta (needs a second machine).

@Suite("Obscura presence")
struct ObscuraPresenceWiringTests {

    private static let chrome = "com.google.Chrome"

    private static let pageProbe = WebContentProbe(areas: [
        WebArea(url: "https://example.com/dashboard", frame: Rect(x: 0, y: 0, w: 800, h: 600))
    ])

    /// A probe a test owns outright: it counts its calls and answers whatever the
    /// test last told it to. A box rather than a captured var because the closure
    /// is @Sendable.
    private final class ScriptedProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var _presence: ToolPresence
        private var _calls = 0

        init(available: Bool) {
            _presence = ToolPresence(tool: "obscura", available: available,
                                     path: available ? "/opt/homebrew/bin/obscura" : nil,
                                     searched: ["/opt/homebrew/bin/obscura"])
        }

        var calls: Int { lock.withLock { _calls } }

        func set(available: Bool) {
            lock.withLock {
                _presence = ToolPresence(tool: "obscura", available: available,
                                         path: available ? "/opt/homebrew/bin/obscura" : nil,
                                         searched: ["/opt/homebrew/bin/obscura"])
            }
        }

        func read() -> ToolPresence {
            lock.withLock { _calls += 1; return _presence }
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = 1_000.0
        var now: Double { lock.withLock { t } }
        func advance(_ seconds: Double) { lock.withLock { t += seconds } }
    }

    private func harness(available: Bool, bundleId: String = chrome)
    async throws -> (Session, ScriptedProbe, Clock) {
        let ax = FakeAX(bundleId: bundleId)
        ax.webContentProbe = Self.pageProbe
        let scripted = ScriptedProbe(available: available)
        let clock = Clock()
        let session = Session(ax: ax, capture: FakeCapture(),
                              tools: ToolProbes(
                                obscura: ToolProbe(probe: { scripted.read() }, now: { clock.now }),
                                browserUse: ToolProbe(probe: {
                                    ToolPresence(tool: BrowserUseTool.binary, available: false)
                                }, now: { clock.now },
                                   presentTTL: ToolProbe.presentTTL,
                                   absentTTL: ToolProbe.presentTTL),
                                environment: [:]))
        await session.setAuditSink(AuditCollector().sink)
        _ = try await session.attachResolved(bundleId: bundleId, pid: nil, name: nil)
        // One handoff up front, so the cache is primed and every call count below
        // is about the cache rather than about a cold start.
        _ = try await session.attach(bundleId: bundleId, pid: nil, name: nil)
        return (session, scripted, clock)
    }

    private func attachHandoff(_ session: Session) async throws -> [String: JSONValue] {
        let result = try await session.attach(bundleId: Self.chrome, pid: nil, name: nil)
        return try #require(result.objectValue?["browser"]?.objectValue)
    }

    private func pageHandoff(_ session: Session) async throws -> BrowserHandoff? {
        try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil).browser
    }

    // MARK: - The handoff

    @Test("attach carries the absence through the encoded JSON, and no command with it")
    func attachCarriesTheAbsenceThroughTheJSON() async throws {
        let (session, _, _) = try await harness(available: false)
        let handoff = try await attachHandoff(session)

        let absence = try #require(handoff["toolUnavailable"]?.objectValue)
        #expect(absence["tool"]?.stringValue == "obscura")
        #expect(absence["docs"]?.stringValue == ObscuraTool.docs)
        #expect(handoff["use"] == nil)
        #expect(handoff["commands"] == nil)
        // Still a disclosure about the boundary, and still the caveats: what
        // Proctor can prove about a page does not change with what is installed.
        #expect(handoff["boundary"]?.stringValue == BrowserTarget.boundary(for: .obscura))
        #expect(handoff["caveats"]?.arrayValue?.count == BrowserTarget.caveats(for: .obscura).count)
    }

    @Test("with Obscura installed the handoff still recommends it")
    func anInstalledToolStillRecommendsIt() async throws {
        let (session, _, _) = try await harness(available: true)
        let handoff = try await attachHandoff(session)
        #expect(handoff["toolUnavailable"] == nil)
        #expect(handoff["use"]?.stringValue == "obscura")
        #expect(handoff["commands"]?.arrayValue?.count == BrowserTarget.commands(for: .obscura)?.count)
    }

    @Test("a snapshot of a page discloses the absence too")
    func everySurfaceDiscloses() async throws {
        let (session, _, _) = try await harness(available: false)
        let handoff = try #require(await pageHandoff(session))
        #expect(handoff.toolUnavailable != nil)
        #expect(handoff.use == nil)
    }

    // MARK: - The health report

    @Test("doctor reports Obscura and leaves readiness alone")
    func doctorReportsObscuraAndLeavesReadinessAlone() async throws {
        let (missing, _, _) = try await harness(available: false)
        let absent = await missing.doctor(verbose: false)
        #expect(absent.obscuraAvailable == false)
        #expect(absent.obscuraUnavailable == ObscuraTool.absence)
        #expect(absent.obscura?.searched == ["/opt/homebrew/bin/obscura"])

        let (installed, _, _) = try await harness(available: true)
        let present = await installed.doctor(verbose: false)
        #expect(present.obscuraAvailable)
        #expect(present.obscuraUnavailable == nil)
        #expect(present.obscura?.path == "/opt/homebrew/bin/obscura")

        // Proctor drives native applications without Obscura, so a health report
        // that failed on it would be lying about what is broken. The grants list
        // is untouched too: this is a tool, not a permission.
        #expect(absent.ready == present.ready)
        #expect(absent.blockers == present.blockers)
        #expect(absent.grants.map(\.name) == present.grants.map(\.name))

        // The three fields have one rule between them, so a client cannot pick
        // the wrong one: the presence record is always there, and the absence
        // object is there exactly when the boolean is false.
        #expect(absent.obscura != nil && present.obscura != nil)
        #expect((absent.obscuraUnavailable != nil) == !absent.obscuraAvailable)
        #expect((present.obscuraUnavailable != nil) == !present.obscuraAvailable)
    }

    // MARK: - The cache

    @Test("a batch of handoffs costs one probe")
    func handoffsShareOneProbe() async throws {
        let (session, probe, _) = try await harness(available: true)
        // The harness primed it; five more handoffs must cost nothing.
        let before = probe.calls
        for _ in 0..<5 { _ = try await pageHandoff(session) }
        #expect(probe.calls == before)
    }

    @Test("the absent answer expires sooner than the present one")
    func theAbsentAnswerExpiresSooner() async throws {
        // The state somebody is actively changing is the one worth re-reading, and
        // this feature is what provokes them to change it. An install has to show
        // up without restarting the agent.
        let (missingSession, missingProbe, missingClock) = try await harness(available: false)
        let missingBefore = missingProbe.calls
        missingClock.advance(ToolProbe.absentTTL + 1)
        _ = try await pageHandoff(missingSession)
        #expect(missingProbe.calls == missingBefore + 1)

        let (presentSession, presentProbe, presentClock) = try await harness(available: true)
        let presentBefore = presentProbe.calls
        presentClock.advance(ToolProbe.absentTTL + 1)
        _ = try await pageHandoff(presentSession)
        #expect(presentProbe.calls == presentBefore)
        presentClock.advance(ToolProbe.presentTTL)
        _ = try await pageHandoff(presentSession)
        #expect(presentProbe.calls == presentBefore + 1)
    }

    @Test("a doctor call re-probes and writes through to the handoff cache")
    func aDoctorCallWritesThroughToTheHandoffCache() async throws {
        let (session, probe, _) = try await harness(available: false)
        // Installed a second ago; the cache does not know yet, and no time passes.
        probe.set(available: true)
        let stale = try await attachHandoff(session)
        #expect(stale["toolUnavailable"] != nil)

        let report = await session.doctor(verbose: false)
        #expect(report.obscuraAvailable)

        // Without the write-through the handoff would keep saying missing until
        // the TTL ran out, and the health report and the advisory would disagree
        // about the same machine at the same instant.
        let fresh = try await attachHandoff(session)
        #expect(fresh["toolUnavailable"] == nil)
        #expect(fresh["use"]?.stringValue == "obscura")
    }

    // MARK: - The rule the whole feature is built on

    @Test("nothing on the tool surface installs anything")
    func theToolSurfaceGainsNoVerb() {
        #expect(ToolCatalogue.all.count == 19)
        for tool in ToolCatalogue.all {
            #expect(!tool.name.contains("install"))
        }
        // The install commands exist in one place, are reached only by the status
        // window, and never enter a result: nothing encoded on the wire mentions
        // them.
        let schema = ToolCatalogue.outputSchema(for: "proctor_doctor")
        let properties = try! #require(schema.objectValue?["properties"]?.objectValue)
        #expect(properties["obscuraAvailable"] != nil)
        #expect(properties["obscura"] != nil)
        #expect(properties["obscuraUnavailable"] != nil)
    }

    // MARK: - The real predicate, against a real filesystem

    @Test("an executable directory named obscura is not the tool")
    func anExecutableDirectoryIsNotTheTool() throws {
        // FileManager.isExecutableFile answers true for a directory carrying the
        // execute bit, so without the regular-file check a directory on the path
        // would be reported as an install.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pro0023-\(UUID().uuidString)")
        let asDirectory = root.appendingPathComponent("obscura")
        try FileManager.default.createDirectory(at: asDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(FileManager.default.isExecutableFile(atPath: asDirectory.path))
        #expect(!ToolProbe.executableRegularFile(asDirectory.path))

        let asFile = root.appendingPathComponent("obscura-worker")
        try Data("#!/bin/sh\n".utf8).write(to: asFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: asFile.path)
        #expect(ToolProbe.executableRegularFile(asFile.path))

        let notExecutable = root.appendingPathComponent("plain")
        try Data("x".utf8).write(to: notExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: notExecutable.path)
        #expect(!ToolProbe.executableRegularFile(notExecutable.path))
    }
}
