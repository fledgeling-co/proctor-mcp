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
    private var paused = false
    private var stopped = false
    private var pausedAt: Double?

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
        guard !paused else { return }
        paused = true
        pausedAt = now()
    }

    func resume() {
        lock.lock(); defer { lock.unlock() }
        paused = false
        pausedAt = nil
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        paused = false
        pausedAt = nil
    }

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    /// A new run starts with nobody's hand on it. Pause and Stop act on the run
    /// the panel is showing, so a decision made about a run that has already
    /// ended does not carry into the next one.
    func begin() {
        lock.lock(); defer { lock.unlock() }
        paused = false
        stopped = false
        pausedAt = nil
    }

    // MARK: - The run's side

    /// Called before each step. Nil means carry on.
    func checkpoint() async -> Halt? {
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
        let held = now() - since
        guard held >= pauseLimit else { return nil }
        // A pause nobody ever lifts gives up the way a stop does, and says so —
        // reported as a fault it is not would send somebody after the app.
        stopped = true
        paused = false
        pausedAt = nil
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
