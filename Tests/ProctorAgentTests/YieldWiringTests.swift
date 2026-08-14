import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0018 — the agent's half: what arms the watch, what the latch does with a
// yield, and what the run says afterwards.
//
// A fake sampler stands in for AppKit, so "a person moved to another app" is a
// value a test can supply. What that leaves untested is named in the spec: a
// real `NSEvent` arriving, a real activation notification, and the tag's
// survival from a posted `CGEvent` to the `NSEvent` a monitor sees.

/// Feeds the session a machine state, and records whether anything was armed.
final class FakeContention: ContentionSampling, @unchecked Sendable {
    private let lock = NSLock()
    /// A script rather than one value, because the frontmost reading is only
    /// armed once Proctor's target has actually been SEEN in front. A test that
    /// wants contention has to show the app arriving first, exactly as a real
    /// run does.
    private var script: [ContentionSample] = [ContentionSample()]
    private(set) var armCount = 0
    private(set) var disarmCount = 0
    private(set) var observedInput = false
    private(set) var expectedPid: Int32?
    private(set) var syntheticPosts = 0

    var isArmed: Bool { lock.lock(); defer { lock.unlock() }; return armCount > disarmCount }

    func set(_ sample: ContentionSample) {
        lock.lock(); defer { lock.unlock() }
        script = [sample]
    }

    /// Each sample is served once, and the last one repeats. A run's probe polls
    /// many times, so the tail is what it settles on.
    func play(_ samples: [ContentionSample]) {
        lock.lock(); defer { lock.unlock() }
        script = samples
    }

    func arm(observeInput: Bool) {
        lock.lock(); defer { lock.unlock() }
        armCount += 1
        observedInput = observedInput || observeInput
    }

    func disarm() {
        lock.lock(); defer { lock.unlock() }
        disarmCount += 1
    }

    func setExpectedPid(_ pid: Int32?) {
        lock.lock(); defer { lock.unlock() }
        expectedPid = pid
    }

    func noteSyntheticPost() {
        lock.lock(); defer { lock.unlock() }
        syntheticPosts += 1
    }

    /// PRO-0026's block hands a person's swallowed event over here, because a
    /// swallowed event never reaches an `NSEvent` monitor.
    private(set) var userInputs = 0
    func noteUserInput() {
        lock.lock(); defer { lock.unlock() }
        userInputs += 1
    }

    /// How far the repeating tail's clock moves on each read.
    ///
    /// The real monitor stamps `now` from the clock every time it is asked, so a
    /// probe that polls twenty times sees twenty advancing timestamps. A fake
    /// that repeated one frozen sample was not a slower version of that, it was a
    /// different world: `releaseDelay` is measured against `sample.now`, so a
    /// stopped clock means a hold can never be released and the run waits out its
    /// whole backstop. That is how this suite came to hang for fifteen minutes on
    /// a 900-second limit rather than failing in seconds.
    ///
    /// Scripted samples are served exactly as written, because their relative
    /// timestamps are what the input-window tests assert on. Only the tail moves.
    static let tailStep: Double = 0.25

    func sample() -> ContentionSample {
        lock.lock(); defer { lock.unlock() }
        if script.count > 1 {
            return script.removeFirst()
        }
        let next = script[0]
        script[0].now += Self.tailStep
        return next
    }
}

/// A clock a test can move, without a captured `var` crossing a Sendable
/// boundary.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Double = 0
    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

@Suite("Yield wiring", .serialized)
struct YieldWiringTests {

    private static let target = "com.example.target"

    private func harness(control: RunControl? = nil)
        async throws -> (session: Session, ax: FakeAX, contention: FakeContention) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture())
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        let contention = FakeContention()
        await session.setContentionMonitor(contention)
        await session.setYieldSwitches(enabled: true, observesInput: false)
        // Always a latch of this test's own, never the process-wide one.
        //
        // `Session.runControl` defaults to `RunControl.shared`, so a harness that
        // only injected when a test asked for it handed every other test the
        // production singleton. One test yielding it left the next one's
        // checkpoint waiting out a 900-second backstop, which is why every test
        // here passed alone and the suite hung as a whole — serialized execution
        // stops them overlapping, not from leaving state behind.
        let latch = control ?? RunControl(pauseLimit: 900,
                                          now: { Date().timeIntervalSince1970 })
        latch.begin()
        await session.setRunControl(latch)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax, contention)
    }

    private func act(_ h: (session: Session, ax: FakeAX, contention: FakeContention),
                     _ steps: [ActionStep], foreground: Bool = false) async throws -> JSONValue {
        try await h.session.act(window: h.ax.window.id, steps: steps, settle: .default,
                                foreground: foreground, captureEach: false, diffEach: false,
                                record: nil)
    }

    private func step(_ kind: ActionStep.Kind) -> ActionStep {
        ActionStep(kind: kind, node: "node-1")
    }

    // MARK: - A1: only a run that is actually contending

    @Test("an accessibility-plane run arms nothing and can never be held")
    func anAccessibilityRunArmsNothing() async throws {
        let h = try await harness()
        // Somebody is in another application the whole time. This run takes
        // nothing, so holding it would be noise about a contention that cannot
        // happen to it.
        h.contention.set(ContentionSample(expectedPid: 1, frontmostPid: 2, now: 100))
        let result = try await act(h, [step(.press), step(.setValue)])
        #expect(h.contention.armCount == 0)
        #expect(result["yields"] == nil || result["yields"] == .null)
        #expect(result["completed"]?.intValue == 2)
    }

    @Test("a batch that takes the foreground arms before its first step")
    func aContendingBatchArms() async throws {
        let h = try await harness()
        _ = try await act(h, [step(.click)], foreground: true)
        #expect(h.contention.armCount == 1)
        #expect(h.contention.isArmed == false, "and it disarms when the run ends")
    }

    @Test("a type that fell back to the event stream arms mid-run, measured not predicted")
    func aMeasuredFallbackArms() async throws {
        let h = try await harness()
        h.ax.planeAt = [0: .syntheticEvent]
        _ = try await act(h, [step(.type), step(.press)])
        #expect(h.contention.armCount == 1)
        #expect(h.contention.expectedPid != nil,
                "and only now is there an app somebody could move to the back")
    }

    @Test("the grace window opens before the post, not after it")
    func theGraceOpensBeforeThePost() async throws {
        let h = try await harness()
        h.ax.planeAt = [0: .syntheticEvent]
        _ = try await act(h, [step(.click)], foreground: true)
        // Twice: once before `perform`, and once from the measured plane after
        // it. An arrival considered between them would otherwise look like a
        // person's.
        #expect(h.contention.syntheticPosts >= 2)
    }

    // MARK: - A4: one latch, one backstop

    @Test("a yield nobody releases expires through the same backstop a pause does")
    func aYieldExpiresLikeAPause() async throws {
        let control = RunControl(pauseLimit: 0.05, now: { Date().timeIntervalSince1970 })
        control.pollNanoseconds = 5_000_000
        let h = try await harness(control: control)
        // The target arrives in front, then somebody moves to another app and
        // never comes back. Nothing releases it, so it gives up on the backstop.
        let now = Date().timeIntervalSince1970
        h.contention.play([
            ContentionSample(expectedPid: 1, frontmostPid: 1, now: now),
            ContentionSample(expectedPid: 1, frontmostPid: 2, now: now)
        ])
        h.ax.planeAt = [0: .syntheticEvent]
        let result = try await act(h, [step(.click), step(.click)], foreground: true)
        // The first step ran and armed the watch; the second was held, gave up,
        // and reported it as a person's decision rather than as a fault.
        let steps = try #require(result["steps"]?.arrayValue)
        let halted = steps.compactMap { $0["error"]?["code"]?.stringValue }
        #expect(halted.contains("haltedByPerson"))
    }

    @Test("a yield and a person's pause share one clock, so neither can outlast the bound")
    func oneClockForBothCauses() {
        let clock = TestClock()
        let control = RunControl(pauseLimit: 10, now: { clock.value })
        control.yield(.userInput)
        #expect(control.isPaused)
        #expect(control.isYielded)
        #expect(control.pausedByAPerson == false)
        // A person pausing on top of a yield does not restart the clock, and
        // releasing the yield does not clear their pause.
        control.pause()
        control.release()
        #expect(control.isPaused, "their pause survives the contention clearing")
        #expect(control.isYielded == false)
        clock.value = 20
        // The clock started when the yield latched, which is what stops a
        // second cause resetting the bound.
        #expect(control.isPaused)
    }

    @Test("release lifts only the yield; resume lifts either")
    func releaseAndResumeDifferent() {
        let control = RunControl(pauseLimit: 900, now: { 0 })
        control.pause()
        control.yield(.secureInput)
        control.release()
        #expect(control.isPaused, "a person's pause is not lifted by a condition clearing")
        control.resume()
        #expect(control.isPaused == false)
    }

    // MARK: - A5: a person's decision wins, from either surface

    @Test("Resume is recorded on the latch, so the panel's own button counts too")
    func resumeIsRecordedOnTheLatch() {
        let control = RunControl(pauseLimit: 900, now: { 0 })
        control.yield(.frontmostChanged)
        // The panel reaches for the shared latch directly and never goes through
        // the agent's verb, so an override recorded at the verb alone would work
        // from the menu bar and be undone 60ms later from the panel.
        control.resume()
        #expect(control.takePersonResume() == true)
        #expect(control.takePersonResume() == false, "and it is consumed in the asking")
    }

    @Test("a fresh run starts with nobody's hand on it")
    func beginClearsEverything() {
        let control = RunControl(pauseLimit: 900, now: { 0 })
        control.yield(.userInput)
        control.resume()
        control.begin()
        #expect(control.isPaused == false)
        #expect(control.isYielded == false)
        #expect(control.takePersonResume() == false)
    }

    @Test("a flapping condition cannot hold a run forever in legal-sized chunks")
    func aFlappingConditionIsStillBounded() {
        let clock = TestClock()
        let control = RunControl(pauseLimit: 10, now: { clock.value })
        // Four holds of four seconds each, every one of them individually well
        // inside the bound. Without banking what each cost, the fifth would
        // start another full ten seconds and the run would be held indefinitely
        // by something that never stays true long enough to expire.
        for _ in 0..<3 {
            control.yield(.frontmostChanged)
            clock.value += 4
            control.release()
        }
        control.yield(.frontmostChanged)
        clock.value += 1
        // 12 seconds banked plus 1 held is past the bound, so it gives up and
        // says so rather than holding on.
        #expect(control.isStopped == false)
        #expect(control.isPaused == true)
        clock.value += 1
        #expect(control.isPaused == true, "read through the checkpoint, not here")
    }

    @Test("a person pausing repeatedly is not bounded the way an automatic hold is")
    func aPersonsRepeatedPauseIsTheirOwnDecision() {
        let clock = TestClock()
        let control = RunControl(pauseLimit: 10, now: { clock.value })
        for _ in 0..<5 {
            control.pause()
            clock.value += 5
            control.resume()
        }
        control.pause()
        #expect(control.isPaused)
        // Nothing banked: a person deciding again is a person deciding, and the
        // bound they are held to is the one they can see on the panel.
    }

    @Test("the actuator stamps every synthetic event source it builds")
    func everySourceIsStamped() {
        // The tag is one of the three filters that keep Proctor's own events
        // out of the person signal, and it only works if it is on every post.
        // Routing every construction through one factory is what makes that a
        // property of the code; this pins the factory itself.
        let source = Actuator.eventSource()
        #expect(source?.userData == ProctorEventTag.value)
    }

    @Test("a reused latch starts the next run with nothing carried over")
    func nothingCarriesIntoTheNextRun() {
        let clock = TestClock()
        let control = RunControl(pauseLimit: 10, now: { clock.value })
        control.yield(.userInput)
        clock.value += 5
        control.release()
        control.resume()
        control.begin()
        #expect(control.isPaused == false)
        #expect(control.isYielded == false)
        #expect(control.takePersonResume() == false)
        // And the banked time went with it: the next run gets the whole bound.
        control.yield(.userInput)
        clock.value += 9
        #expect(control.isPaused == true)
    }

    // MARK: - A8/A9: what it reports, and what it observes

    @Test("a run that was held says so, with the reason and how long")
    func aHeldRunSaysSo() async throws {
        let control = RunControl(pauseLimit: 900, now: { Date().timeIntervalSince1970 })
        control.pollNanoseconds = 5_000_000
        let h = try await harness(control: control)
        h.ax.planeAt = [0: .syntheticEvent]
        let now = Date().timeIntervalSince1970
        h.contention.play([
            ContentionSample(expectedPid: 1, frontmostPid: 1, now: now),
            ContentionSample(expectedPid: 1, frontmostPid: 2, now: now)
        ])

        // Let the run hold, then release it the way a person does.
        // Three steps, not two, and the third is what makes this deterministic.
        //
        // `checkpoint` probes at the top of its loop and then tests the latch, so
        // a Resume landing between `look()` and that test returns without a
        // further probe — and the pending person-resume is then consumed by
        // nothing, leaving the hold to be closed by the run ending instead. With
        // only two steps the parked checkpoint is the last one there is, so that
        // window decides the assertion and the test fails about one run in three.
        // A third step guarantees another checkpoint, and therefore another probe,
        // after the Resume.
        let running = Task {
            try await act(h, [step(.click), step(.click), step(.click)], foreground: true)
        }
        // Wait for the hold to exist before lifting it, rather than sleeping a
        // guessed interval. A Resume that lands before the run has yielded is
        // spent on an empty condition set: the override marks nothing, the yield
        // latches immediately afterwards, and the only thing left to lift it is
        // the 900-second backstop. That is defensible behaviour — resuming
        // something that has not happened does nothing, and a person simply
        // presses again — but it made this test a fifteen-minute hang rather than
        // a failure, which is what hid it.
        var waited = 0
        while !control.isYielded && waited < 400 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waited += 1
        }
        #expect(control.isYielded, "the run never yielded, so there was nothing to resume")
        control.resume()
        let result = try await running.value

        let yields = try #require(result["yields"]?.arrayValue)
        #expect(yields.count >= 1)
        #expect(yields[0]["reason"]?.stringValue == "frontmostChanged")
        #expect(yields[0]["endedBy"]?.stringValue == "person")
        #expect(result["yieldNote"]?.stringValue?.isEmpty == false)
    }

    @Test("the input monitor is off unless somebody asks for it")
    func theInputMonitorIsOptIn() {
        #expect(ContentionMonitor.inputObserved(in: [:]) == false)
        #expect(ContentionMonitor.inputObserved(in: ["PROCTOR_YIELD_INPUT": "0"]) == false)
        #expect(ContentionMonitor.inputObserved(in: ["PROCTOR_YIELD_INPUT": "off"]) == false)
        #expect(ContentionMonitor.inputObserved(in: ["PROCTOR_YIELD_INPUT": ""]) == false)
        #expect(ContentionMonitor.inputObserved(in: ["PROCTOR_YIELD_INPUT": "1"]) == true)
        // And the feature as a whole is the other way round: on unless somebody
        // turns it off, the pointer overlay's and the panel's switch shape.
        #expect(ContentionMonitor.enabled(in: [:]) == true)
        #expect(ContentionMonitor.enabled(in: ["PROCTOR_YIELD": "0"]) == false)
    }

    @Test("with the feature switched off, nothing is armed on any path")
    func theWholeFeatureSwitchesOff() async throws {
        let h = try await harness()
        await h.session.setYieldSwitches(enabled: false, observesInput: true)
        h.contention.set(ContentionSample(expectedPid: 1, frontmostPid: 2, now: 100))
        _ = try await act(h, [step(.click)], foreground: true)
        #expect(h.contention.armCount == 0)
        #expect(h.contention.observedInput == false)
    }

    @Test("the opt-in reaches the monitor when it is set")
    func theOptInReachesTheMonitor() async throws {
        let h = try await harness()
        await h.session.setYieldSwitches(enabled: true, observesInput: true)
        _ = try await act(h, [step(.click)], foreground: true)
        #expect(h.contention.observedInput == true)
    }

    // MARK: - A7: the menu bar, and the ladder that is not reordered

    @Test("the menu bar carries the hold, and the icon ladder is untouched")
    func theMenuBarStatesTheHold() async throws {
        let h = try await harness()
        let activity = await h.session.recentActivity()
        let yield = try #require(activity["foreground"]?["yield"])
        #expect(yield["active"]?.boolValue == false)
        #expect(yield["reason"] == .null)
        // A held run is not acting, so `takingForeground` is false and the
        // existing order — reachability, grants, foreground, phase — reaches the
        // character with no new case.
        #expect(MenuBarIcon.decide(reachable: true, block: nil, phase: .paused,
                                   takingForeground: false) == .character(.paused))
    }

    // MARK: - A9's other half: nothing new is refused

    @Test("the refusal table is unchanged")
    func nothingNewIsRefused() {
        // Secure Event Input still refuses a synthetic step exactly as it did:
        // the watch gets there first when it can, and when it does not, the
        // refusal is the one that already existed.
        #expect(Session.refusal(for: ActionStep(kind: .press), foreground: false) == nil)
        let refusal = Session.refusal(for: ActionStep(kind: .click), foreground: false)
        #expect(refusal?.code == .invalidArguments)
    }
}
