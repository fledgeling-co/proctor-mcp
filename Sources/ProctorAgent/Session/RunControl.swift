import Foundation
import ProctorCore

// The kill switch behind the HUD's Pause and Stop.
//
// Two threads meet here and neither may block the other. A person's click
// arrives on the main thread, where the panel lives; the run reads the decision
// from inside the `Session` actor, between steps. So the lock is held for a flag
// read or a flag write and never across a wait: a pause parks with
// `Task.sleep`, which yields the actor's executor rather than occupying it, and
// leaves the main thread free to deliver the Stop that ends the pause. A latch
// that slept holding its lock would deadlock the very button that releases it.
//
// The halt is checked *between* steps, never during one. Killing a step
// mid-flight leaves the application in a state nobody can describe, which is
// worse than the extra second the run takes to notice; the step in flight
// finishes settling and the run stops before the next one.
final class RunControl: @unchecked Sendable {

    static let shared = RunControl()

    /// How a run ended when it was not the run's own doing.
    enum Halt: Equatable {
        case stopped
        case pauseExpired(seconds: Double)
    }

    /// How long a pause nobody resumes may hold. A paused run still holds
    /// Proctor's attention, so an unbounded hold leaves every other request
    /// queued behind it; long enough that somebody who walked off to check
    /// something comes back to a live pause.
    static let defaultPauseLimit: TimeInterval = 900

    /// Read from the same shape of setting as the off-switches.
    static func pauseLimit(from environment: [String: String]) -> TimeInterval {
        guard let raw = environment["PROCTOR_HUD_PAUSE_LIMIT"],
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds > 0 else { return defaultPauseLimit }
        return seconds
    }

    private let lock = NSLock()
    /// One latch with two causes, deliberately not two latches.
    ///
    /// A person's Pause and an automatic yield hold the run the same way, on the
    /// same clock, under the same backstop. A separate yield flag beside this
    /// one would be a second mechanism with a second way to strand a run, and
    /// the only thing it would buy is the attribution — which is one more field.
    private var pausedByPerson = false
    private var yieldReason: YieldReason?
    private var paused: Bool { pausedByPerson || yieldReason != nil }
    private var stopped = false
    /// When the hold started, whichever cause started it. Set when the first
    /// cause latches and cleared when the last one lets go, so the backstop
    /// bounds a yield exactly as it bounds a person's pause and a run cannot be
    /// held by a cause that forgot to start the clock.
    private var pausedAt: Double?
    private var personResumePending = false
    /// How long this run has ALREADY spent yielded, across every hold. The
    /// backstop bounds the run rather than the episode, so a condition that
    /// flaps cannot hold a run forever in individually-legal chunks.
    private var yieldHeldTotal: Double = 0

    /// Substitutable so the backstop is testable in milliseconds rather than in
    /// fifteen minutes.
    var pauseLimit: TimeInterval
    var now: @Sendable () -> Double
    var pollNanoseconds: UInt64 = 60_000_000

    init(pauseLimit: TimeInterval = RunControl.pauseLimit(from: ProcessInfo.processInfo.environment),
         now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.pauseLimit = pauseLimit
        self.now = now
    }

    // MARK: - The buttons

    func pause() {
        lock.lock(); defer { lock.unlock() }
        guard !pausedByPerson else { return }
        pausedByPerson = true
        if pausedAt == nil { pausedAt = now() }
    }

    func resume() {
        lock.lock(); defer { lock.unlock() }
        pausedByPerson = false
        yieldReason = nil
        pausedAt = nil
        // A person has decided. Recorded here rather than at either call site
        // because BOTH surfaces write this latch directly — the panel's own
        // button reaches for `RunControl.shared`, and the menu bar goes through
        // the agent's `proctor_hud` verb — and a decision that only one of them
        // registered would make Resume work from one surface and be undone on
        // the next poll from the other.
        personResumePending = true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        pausedByPerson = false
        yieldReason = nil
        pausedAt = nil
    }

    // MARK: - The automatic half

    /// Hold the run because somebody is using the machine. The same latch and
    /// the same clock as `pause`; only the attribution differs.
    func yield(_ reason: YieldReason) {
        lock.lock(); defer { lock.unlock() }
        yieldReason = reason
        if pausedAt == nil { pausedAt = now() }
    }

    /// The contention cleared. Lifts ONLY the yield — a pause a person pressed
    /// while the run happened to be yielded stays exactly where they put it.
    func release() {
        lock.lock(); defer { lock.unlock() }
        guard yieldReason != nil else { return }
        // Bank what this hold cost before letting go. Without this a condition
        // that flaps — an application taking and losing the front, secure input
        // going on and off — would start a fresh backstop every time it
        // re-latched, and a run could be held indefinitely in chunks each one
        // of which is individually within the bound. The bound is on the run,
        // not on the episode.
        if let since = pausedAt { yieldHeldTotal += max(0, now() - since) }
        yieldReason = nil
        if !pausedByPerson { pausedAt = nil }
    }

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    var isYielded: Bool { lock.lock(); defer { lock.unlock() }; return yieldReason != nil }
    var pausedByAPerson: Bool { lock.lock(); defer { lock.unlock() }; return pausedByPerson }

    /// Whether a person has resumed since this was last asked, consumed in the
    /// asking. The contention probe reads it to override the reasons that were
    /// holding the run, so a still-true condition cannot re-yield on the next
    /// poll and leave Resume looking like a dead button.
    func takePersonResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { personResumePending = false }
        return personResumePending
    }

    /// A new run starts with nobody's hand on it. Pause and Stop act on the run
    /// the panel is showing, so a decision made about a run that has already
    /// ended does not carry into the next one.
    func begin() {
        lock.lock(); defer { lock.unlock() }
        pausedByPerson = false
        yieldReason = nil
        stopped = false
        pausedAt = nil
        personResumePending = false
        yieldHeldTotal = 0
    }

    // MARK: - The run's side

    /// Called before each step. Nil means carry on.
    ///
    /// `probe` is where contention is read: it runs once before the first look
    /// and once per poll while the run is parked, so a yield can both BEGIN at a
    /// checkpoint and END while the run is already held, with no second timer
    /// anywhere. It is supplied by the session, which owns the policy; this
    /// class knows only that something may set or clear the latch.
    func checkpoint(probe: (@Sendable () async -> Void)? = nil) async -> Halt? {
        // The run loop is where the buttons live. A pause waited on from the main
        // thread would block the click that releases it, and the run would hang
        // until the backstop gave up — a deadlock that looks exactly like a slow
        // step. `Session` is an actor with its own executor and this method is
        // non-isolated, so neither runs on main today; the assertion is here so
        // that a later change making either main-actor-bound fails a test rather
        // than hanging a person's kill switch.
        assert(!Thread.isMainThread,
               "the halt checkpoint must never be waited on from the main thread")
        while true {
            await probe?()
            if let halt = look() { return halt }
            if !isPaused { return nil }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    /// One reading of the latch, under the lock and without waiting.
    private func look() -> Halt? {
        lock.lock(); defer { lock.unlock() }
        if stopped { return .stopped }
        guard paused, let since = pausedAt else { return nil }
        // What this hold has cost, plus what earlier automatic holds already
        // cost this run. A person's own pause is judged on this episode alone,
        // because a person deciding again is a person deciding; an automatic
        // hold that keeps re-latching is not.
        let held = (now() - since) + (yieldReason != nil ? yieldHeldTotal : 0)
        guard held >= pauseLimit else { return nil }
        // A pause nobody ever lifts gives up the way a stop does, and says so —
        // reported as a fault it is not would send somebody after the app. A
        // yield reaches this the same way, which is the whole reason it rides
        // this latch: an automatic hold cannot outlast the bound a person's own
        // hold has.
        stopped = true
        pausedByPerson = false
        yieldReason = nil
        pausedAt = nil
        yieldHeldTotal = 0
        return .pauseExpired(seconds: pauseLimit)
    }
}

extension RunControl.Halt {

    /// The refusal a halted step carries. It gets its own code: the policy gate's
    /// `policyDenied` would report a person's decision as a configured rule, and
    /// `actionFailed` would send the caller to look for a fault in an app where
    /// there is none.
    var refusal: AgentError {
        switch self {
        case .stopped:
            return AgentError(
                code: .haltedByPerson,
                message: "a person stopped this run from Proctor's run HUD, so this step and the "
                       + "ones after it never ran",
                remedy: "Nothing failed. Somebody watching the run decided to end it, and the steps "
                      + "that completed before the halt are reported alongside this. Ask before "
                      + "starting it again rather than retrying.")
        case .pauseExpired(let seconds):
            return AgentError(
                code: .haltedByPerson,
                message: "this run was paused from Proctor's run HUD and nobody resumed it within "
                       + "\(Int(seconds)) seconds, so it was given up before this step ran",
                remedy: "A pause holds the whole agent, so it gives up rather than waiting forever. "
                      + "The steps that completed before the pause are reported alongside this. "
                      + "Start the run again once whoever paused it is ready.")
        }
    }
}
