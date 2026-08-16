import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0055 — a session does not inherit the machine's state unless it is handed it.
//
// The defect these hold shut was measured, not theorised. `Session.runControl`
// defaulted to `RunControl.shared` and `Session.contentionMonitor` to
// `ContentionMonitor.shared`, so any session that named neither watched the
// actual Mac and parked the actual latch. In the agent that is right. Everywhere
// else it is a trap, and a test process is the case that proves it: a test can
// never satisfy "the application under test is frontmost", because there is no
// such application and the front belongs to whatever the developer last clicked.
//
// Sampled from inside `RunControl.checkpoint`'s poll, that reading yields the
// run, and yields it again on the next poll, and again, until a 900-second
// backstop gives up. Five suites reached that state and the whole run wedged
// with no verdict line, because the poll never returns and the queue is behind
// it. The stack was identical on six threads: scheduled → runSteps →
// haltCheckpoint → checkpoint.
//
// So the safe values are the defaults and the process-wide ones are named at the
// single construction that wants them. What is proved here is that inversion,
// and the diagnostic that makes a park legible if one ever happens anyway.
@Suite("PRO-0055 · a session is isolated from the machine unless it asks")
struct SessionIsolationWiringTests {

    private static let target = "com.example.target"

    private func session() async throws -> Session {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture())
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return session
    }

    // MARK: - The inversion

    @Test("a session that names no latch does not get the process-wide one")
    func aFreshSessionDoesNotTakeTheSharedLatch() async throws {
        let session = try await self.session()
        let mine = await session.runControl
        #expect(mine !== RunControl.shared)
    }

    @Test("a run parked on the process-wide latch does not park a fresh session")
    func aSharedParkDoesNotReachAFreshSession() async throws {
        // Exactly the shape that wedged the suite: something parks the singleton,
        // and a session constructed afterwards has to be unaffected by it.
        RunControl.shared.pause()
        defer { RunControl.shared.resume() }

        let session = try await self.session()
        let mine = await session.runControl
        #expect(mine.isParked(run: 0) == false)
        // And the halt checkpoint returns rather than polling, which is the
        // behaviour the wedge was the absence of.
        let halt = await mine.checkpoint(run: 0)
        #expect(halt == nil)
    }

    @Test("the agent's own construction names both process-wide seams")
    func productionOptsIn() async throws {
        // The inversion is only safe because the one construction that wants
        // process-wide state says so. If that call ever loses its arguments the
        // panel's Pause and Stop reach a latch no run is reading, which is a
        // silent loss of the kill switch — so the call site is asserted here
        // rather than left to a reviewer's eye.
        let main = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ProctorAgentTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/ProctorAgent/main.swift")
        let source = try String(contentsOf: main, encoding: .utf8)
        #expect(source.contains("runControl: .shared"))
        #expect(source.contains("contentionMonitor: ContentionMonitor.shared"))
    }

    // MARK: - The quiet machine

    @Test("the default monitor reports a machine nobody is using")
    func theDefaultMonitorIsQuiet() {
        let sample = NullContentionMonitor().sample()
        #expect(sample.expectedPid == nil)
        #expect(sample.frontmostPid == nil)
        #expect(sample.secureInput == false)
        #expect(sample.lastUserInputAt == nil)
    }

    @Test("a quiet sample never yields, however many times it is read")
    func aQuietSampleNeverYields() {
        // The wedge was not one yield: it was a yield re-decided on every poll.
        // So the property that matters is that repeated reads stay quiet.
        var watch = ContentionWatch()
        let monitor = NullContentionMonitor()
        for _ in 0..<50 {
            #expect(watch.sample(monitor.sample()) == .none)
        }
    }

    @Test("a session that names no monitor watches the quiet one")
    func aFreshSessionWatchesAQuietMachine() async throws {
        let session = try await self.session()
        let monitor = await session.contentionMonitor
        #expect(monitor is NullContentionMonitor)
    }

    // MARK: - A park that happens anyway says so

    @Test("a long park names the run and a person's pause as its cause")
    func aLongParkNamesAPersonsPause() {
        let control = RunControl(pauseLimit: 900, now: { 0 })
        control.pause()
        let line = control.longParkMessage(run: 4, heldFor: 31)
        #expect(line.contains("run 4"))
        #expect(line.contains("31s"))
        #expect(line.contains("a person's Pause"))
        #expect(line.contains("900s"))
    }

    @Test("a long park names the automatic cause when that is what holds it")
    func aLongParkNamesTheAutomaticCause() {
        let control = RunControl(pauseLimit: 900, now: { 0 })
        control.yield(run: 7, hold: HoldAttribution(reason: .frontmostChanged,
                                                    session: "proctor-mcp a3f1"))
        let line = control.longParkMessage(run: 7, heldFor: 25)
        #expect(line.contains("run 7"))
        #expect(line.contains(YieldReason.frontmostChanged.rawValue))
    }

    @Test("a park with no nameable cause says that, rather than saying nothing")
    func aParkWithNoCauseIsStillReported() {
        // This is the state the wedge would have been in if the diagnostic had
        // existed: held, and unable to say by what. Reporting the absence is the
        // point — a blank line would read as a healthy run.
        let control = RunControl(pauseLimit: 900, now: { 0 })
        let line = control.longParkMessage(run: 2, heldFor: 44)
        #expect(line.contains("nothing this latch can name"))
    }

    @Test("the diagnostic waits long enough that an ordinary pause never trips it")
    func theThresholdIsWellShortOfTheBackstop() {
        #expect(RunControl.diagnosticAfter > 10)
        #expect(RunControl.diagnosticAfter < RunControl.defaultPauseLimit / 10)
    }
}
