import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0026 — the agent's half: what raises the statement, what arms the block,
// and what guarantees both are down when the run is.
//
// A fake stands in for the panels and the tap, so "the block was armed for this
// step" is something a test can assert without a window server or an event tap.
// What that leaves untested is named in the spec: a panel presenting, a tint, a
// tap swallowing anything, and Escape arriving in one.

/// Records every raise, arm and release, in order.
final class FakeTakeover: TakeoverDriving, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var shows: [String?] = []
    private(set) var hides = 0
    private(set) var arms: [Double] = []
    private(set) var releases: [TakeoverRelease] = []
    private(set) var stops: [TakeoverRelease] = []
    private(set) var reports = 0
    private(set) var onStop: (@Sendable () -> Void)?
    private(set) var onPersonInput: (@Sendable () -> Void)?
    var holding = false
    var unavailable: String?
    /// What `report` hands back, so a test can pretend somebody fought the run.
    var swallowed = 0
    var blockedMs = 0

    var armed: Int { lock.lock(); defer { lock.unlock() }; return arms.count - releases.count }

    func bind(onStop: @escaping @Sendable () -> Void,
              onPersonInput: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.onStop = onStop
        self.onPersonInput = onPersonInput
    }

    func show(app: String?) { lock.lock(); shows.append(app); lock.unlock() }
    func hide() { lock.lock(); hides += 1; lock.unlock() }
    func arm(seconds: Double) { lock.lock(); arms.append(seconds); lock.unlock() }
    func release(_ reason: TakeoverRelease) { lock.lock(); releases.append(reason); lock.unlock() }
    func stopAll(_ reason: TakeoverRelease) { lock.lock(); stops.append(reason); lock.unlock() }

    func report(shown: Bool) -> TakeoverReport {
        lock.lock(); defer { lock.unlock() }
        reports += 1
        return TakeoverReport(shown: shown, blocked: blockedMs > 0, blockedMs: blockedMs,
                              swallowed: swallowed, releasedBy: stops.last?.rawValue)
    }

    var isHolding: Bool { lock.lock(); defer { lock.unlock() }; return holding }
    var unavailableReason: String? { lock.lock(); defer { lock.unlock() }; return unavailable }
}

@Suite("Takeover wiring", .serialized)
struct TakeoverWiringTests {

    private static let target = "com.example.target"

    private func harness() async throws
        -> (session: Session, ax: FakeAX, takeover: FakeTakeover, contention: FakeContention,
            control: RunControl) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture(), secureInputProbe: { false })
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        let takeover = FakeTakeover()
        await session.setTakeover(takeover)
        let contention = FakeContention()
        await session.setContentionMonitor(contention)
        await session.setYieldSwitches(enabled: true, observesInput: false)
        // Never the process-wide declaration keeper, for the same reason as the
        // latch below. In production one scheduler hands the exclusive global
        // lane to one run at a time, so a single shared instance is only ever
        // driven by one run; here several sessions exist at once with a
        // scheduler each, and a suite that left its declaration on the shared
        // instance decided whether another suite's batch had already raised the
        // statement.
        await session.setSyntheticPost(SyntheticPost())
        // Never the process-wide latch: a test that yielded the singleton leaves
        // the next one's checkpoint waiting out a 900-second backstop.
        let control = RunControl(pauseLimit: 900, now: { Date().timeIntervalSince1970 })
        control.begin(run: 0)
        await session.setRunControl(control)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax, takeover, contention, control)
    }

    private func act(_ h: (session: Session, ax: FakeAX, takeover: FakeTakeover,
                           contention: FakeContention, control: RunControl),
                     _ steps: [ActionStep], foreground: Bool = true) async throws -> JSONValue {
        try await h.session.act(window: h.ax.window.id, steps: steps, settle: .default,
                                foreground: foreground, captureEach: false, diffEach: false,
                                record: nil)
    }

    private func step(_ kind: ActionStep.Kind) -> ActionStep {
        ActionStep(kind: kind, node: "node-1")
    }

    // MARK: - A1: up for exactly as long as the machine is held

    @Test("an accessibility run raises nothing and arms nothing")
    func accessibilityRunIsUntouched() async throws {
        let h = try await harness()
        _ = try await act(h, [step(.press), step(.setValue), step(.focus)], foreground: false)
        #expect(h.takeover.shows.isEmpty)
        #expect(h.takeover.arms.isEmpty)
        #expect(h.takeover.stops.isEmpty)
        #expect(h.takeover.hides == 0)
    }

    @Test("a synthetic batch raises the statement once and names the application")
    func raisedOncePerBatch() async throws {
        // Per batch, not per step: a full-screen tint flashing between ten clicks
        // is strobing, and strobing is worse than the thing it announces.
        let h = try await harness()
        _ = try await act(h, [step(.click), step(.click), step(.click)])
        #expect(h.takeover.shows.count == 1)
        #expect(h.takeover.shows.first ?? nil != nil)
        #expect(h.takeover.hides == 1)
    }

    @Test("a batch that starts on the accessibility plane raises it at the first synthetic step")
    func raisedAtTheRightStep() async throws {
        let h = try await harness()
        _ = try await act(h, [step(.press), step(.click)])
        #expect(h.takeover.shows.count == 1)
        // One arm, for the one step that posts.
        #expect(h.takeover.arms.count == 1)
    }

    @Test("a guest session raises no statement, arms no block and watches no contention")
    func aGuestRunLeavesThisMacAlone() async throws {
        let h = try await harness()
        await h.session.setMachine(Machine(kind: .guest, name: "sequoia-seed",
                                           provider: "lume", platform: .macos,
                                           tier: .native))
        _ = try await act(h, [step(.click), step(.click)])
        #expect(h.takeover.shows.isEmpty)
        #expect(h.takeover.arms.isEmpty)
        #expect(h.contention.armCount == 0)
    }

    // MARK: - A7: the block cannot outlive the step or the run

    @Test("every arming is matched by a release, and the run ends with a stopAll")
    func armingIsBalanced() async throws {
        let h = try await harness()
        _ = try await act(h, [step(.click), step(.key), step(.hover)])
        #expect(h.takeover.arms.count == 3)
        #expect(h.takeover.releases.count == 3)
        #expect(h.takeover.armed == 0)
        #expect(h.takeover.stops == [.runEnded])
    }

    @Test("a step that throws still releases the block")
    func aThrownStepStillLetsGo() async throws {
        // The failure this feature cannot have. A block held because a step threw
        // between arming and releasing is input held by an accounting mistake.
        let h = try await harness()
        h.ax.failPerformAt = 0
        _ = try await act(h, [step(.click), step(.click)])
        #expect(h.takeover.arms.count == 1)
        #expect(h.takeover.releases == [.stepEnded])
        #expect(h.takeover.armed == 0)
        #expect(h.takeover.stops.count == 1)
    }

    @Test("the arming carries the step's own duration, bounded by the ceiling")
    func armingCarriesTheDeadline() async throws {
        let h = try await harness()
        var drag = ActionStep(kind: .dragPath, node: "node-1")
        drag.durationMs = 1200
        drag.path = [[10, 10], [40, 40]]
        _ = try await act(h, [drag])
        #expect(h.takeover.arms == [Takeover.armSeconds(stepDurationMs: 1200)])
    }

    @Test("a run somebody stopped takes the statement down and says who ended it")
    func aStoppedRunLetsGo() async throws {
        let h = try await harness()
        h.control.stop()
        _ = try await act(h, [step(.click), step(.click)])
        // Halted before the first step, so nothing was raised and nothing needs
        // taking down — the important half is that no arming is left open.
        #expect(h.takeover.armed == 0)
    }

    // MARK: - A11: what the run says afterwards

    @Test("a run that took the machine reports it, in a field and in a sentence")
    func theRunSaysSo() async throws {
        let h = try await harness()
        h.takeover.blockedMs = 1500
        h.takeover.swallowed = 2
        let out = try await act(h, [step(.click)])
        let object = try #require(out.objectValue)
        let takeover = try #require(object["takeover"]?.objectValue)
        #expect(takeover["shown"]?.boolValue == true)
        #expect(takeover["blocked"]?.boolValue == true)
        #expect(takeover["swallowed"]?.intValue == 2)
        let note = try #require(object["takeoverNote"]?.stringValue)
        #expect(note.contains("1.5s"))
        #expect(note.contains("2 times"))
    }

    @Test("a run that took nothing carries no takeover block at all")
    func silenceWhenNothingWasTaken() async throws {
        let h = try await harness()
        let out = try await act(h, [step(.press)], foreground: false)
        let object = try #require(out.objectValue)
        #expect(object["takeover"] == nil || object["takeover"] == .null)
        #expect(object["takeoverNote"] == nil)
    }

    // MARK: - A8: a swallowed event is not a discarded one

    @Test("the block is wired to this run's latch, not to a stale one")
    func boundToThisRun() async throws {
        // Both closures have to reach the objects this run is using: a block
        // bound to a previous run's latch is a Stop that stops nothing.
        let h = try await harness()
        _ = try await act(h, [step(.click)])
        let stop = try #require(h.takeover.onStop)
        let person = try #require(h.takeover.onPersonInput)
        #expect(!h.control.isStopped)
        stop()
        #expect(h.control.isStopped)
        let before = h.contention.userInputs
        person()
        #expect(h.contention.userInputs == before + 1)
    }

    @Test("a swallowed event feeds the yield, so the two features compose")
    func swallowedInputYields() async throws {
        // A swallowed event never reaches an `NSEvent` monitor, so without this
        // the block would eat exactly the input PRO-0018 exists to notice. The
        // person's first keystroke is held so it cannot corrupt the step, and it
        // is also what makes Proctor let go.
        let h = try await harness()
        _ = try await act(h, [step(.click)])
        let person = try #require(h.takeover.onPersonInput)
        person()
        #expect(h.contention.userInputs == 1)
        // And it is recorded without the input monitor being on: the operator who
        // turned the block on granted strictly more than observation.
        #expect(!h.contention.observedInput)
    }

    // MARK: - A4: what doctor says

    @Test("the health report separates asked-for from actually-available")
    func doctorSeparatesTheTwo() async throws {
        let h = try await harness()
        h.takeover.unavailable = "the event tap could not be created"
        let status = await h.session.takeoverStatus()
        let object = try #require(status.objectValue)
        #expect(object["inputBlockAvailable"]?.boolValue == false)
        #expect(object["note"]?.stringValue?.contains("could not be created") == true)
        #expect(object["inputMonitoring"] != nil)
    }

    // MARK: - PRO-0053: only a run that might post drives the declaration keeper

    /// A session sharing one declaration keeper with whoever else is running,
    /// which is the production topology: `SyntheticPost` is process-wide because
    /// the event tap must decline to read Stop while ANY post is open.
    private func sharing(_ post: SyntheticPost) async throws -> (session: Session, ax: FakeAX) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture(), secureInputProbe: { false })
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setTakeover(FakeTakeover())
        await session.setContentionMonitor(FakeContention())
        await session.setYieldSwitches(enabled: true, observesInput: false)
        await session.setSyntheticPost(post)
        let control = RunControl(pauseLimit: 900, now: { Date().timeIntervalSince1970 })
        control.begin(run: 0)
        await session.setRunControl(control)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax)
    }

    /// A batch that could never reach the event stream: nothing certainly
    /// synthetic in it, and it did not ask for the front, which is a
    /// precondition of any fallback post.
    private func runNonPosting(_ h: (session: Session, ax: FakeAX)) async throws {
        _ = try await h.session.act(window: h.ax.window.id, steps: [step(.press), step(.setValue)],
                                    settle: .default, foreground: false, captureEach: false,
                                    diffEach: false, record: nil)
    }

    @Test("a run that cannot post does not clear a posting run's declaration")
    func aNonPostingRunLeavesTheDeclarationAlone() async throws {
        // Two sessions on different apps genuinely run in parallel — `RunLane`
        // says so — and only a batch that might post takes the exclusive global
        // lane. So the background run below is concurrent with a posting one by
        // design, and before PRO-0053 its `beginStep()` at every step boundary
        // cleared the poster's `declared` flag. The poster then read
        // `declaredThisStep` as false, never raised the statement for a `type`
        // or `scroll` that fell back, and under-reported having taken the
        // machine. Nobody was told their machine had been taken.
        let post = SyntheticPost()
        post.declare()
        #expect(post.declaredThisStep)

        try await runNonPosting(try await sharing(post))

        #expect(post.declaredThisStep, "a background run cleared a poster's declaration")
    }

    @Test("a run that cannot post does not close a posting run's in-flight window")
    func aNonPostingRunLeavesTheWindowOpen() async throws {
        // The more serious half. While the window is open the tap declines to
        // read the Stop rectangle at all, which is what makes "Proctor's own
        // click can never press Stop" structural rather than an identity check.
        // A background run closing it early puts the tap back to reading Stop
        // while Proctor's click is still travelling — PRO-0033 failing in the
        // exact way it exists to prevent.
        let post = SyntheticPost()
        // The clock is frozen because `inFlight` is bounded in TIME, not to the
        // step: it is true only while `now() - declaredAt < 0.25`. This test
        // declares, runs a whole batch on the wall clock, then asserts the
        // window is still open, so a batch slower than a quarter second expires
        // it naturally and the test reports a clearing nobody did. Measured at
        // 0.108-0.136s in isolation, which whole-suite load closes.
        //
        // Freezing cannot conceal the defect being guarded. What a background
        // run does wrong is clear `declaredAt`, and `inFlight` returns false on
        // a nil `declaredAt` at every instant, frozen clock or not.
        post.now = { 0 }
        post.declare()
        #expect(post.inFlight)

        try await runNonPosting(try await sharing(post))

        #expect(post.inFlight, "a background run closed a poster's in-flight window")
    }

    @Test("a run that cannot post does not remove a posting run's declaration handler")
    func aNonPostingRunLeavesTheHandlerInstalled() async throws {
        // One handler slot. A background run installing its own took the slot
        // from the poster, and its `defer` cleared the slot for everybody when
        // it finished first — so a later declaration reached nothing and the
        // statement stayed down.
        let post = SyntheticPost()
        let fired = Counter()
        post.onDeclare { fired.bump() }

        try await runNonPosting(try await sharing(post))

        post.declare()
        #expect(fired.value == 1, "a background run removed a poster's handler")
    }

    @Test("a synthetic batch refused for being in the background leaves the keeper alone")
    func aRefusedSyntheticBatchLeavesTheKeeperAlone() async throws {
        // The out-of-family completeness gate's finding, and it was a real hole.
        // `mightPost` counts a certain synthetic kind whatever the batch asked
        // for, but a synthetic step is refused outright when `foreground` is
        // false, so this batch cannot post and has nothing to declare.
        //
        // It matters because of one path: a stability sweep buys its lanes from
        // the FLOW's steps and then runs `resetBetween` through the same loop as
        // a batch of its own. An accessibility-only flow takes no global lane, so
        // a reset containing a `click` would have joined the protocol while
        // holding nothing exclusive, and cleared a real poster's state.
        let post = SyntheticPost()
        // Frozen for the same reason as the test above: `inFlight` expires on
        // the wall clock after a quarter second, and this asserts it after a
        // whole batch has run. A cleared `declaredAt` still reads false.
        post.now = { 0 }
        post.declare()
        let h = try await sharing(post)

        _ = try await h.session.act(window: h.ax.window.id, steps: [step(.click)],
                                    settle: .default, foreground: false, captureEach: false,
                                    diffEach: false, record: nil)

        #expect(post.declaredThisStep, "a batch that cannot post cleared a poster's declaration")
        #expect(post.inFlight, "a batch that cannot post closed a poster's in-flight window")
    }
}

/// A count a `@Sendable` closure can increment.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func bump() { lock.lock(); stored += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
}
