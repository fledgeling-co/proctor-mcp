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
    ///
    /// WHAT PRO-0037 ADDED, AND WHAT IT DELIBERATELY DID NOT. Still one flag
    /// set, one `pausedAt`, one bound. What is new is a *key*: which run read
    /// the automatic cause. The two causes park different populations, and that
    /// difference is the whole of it:
    ///
    ///   A person's Pause is a decision about the machine, and parks every run.
    ///   That is what the panel's one pair of buttons means.
    ///
    ///   A yield is one run's reading about one event stream and one expected
    ///   pid. An accessibility press into Slack is not fighting somebody who
    ///   cmd-tabbed away from Safari, and parking it told its caller nothing
    ///   while stopping it for up to the whole backstop.
    ///
    /// The key costs a dictionary and no second mechanism: there is still one
    /// flag set, one clock and one bound.
    private var pausedByPerson = false
    /// The automatic holds, keyed by the run that read each one, carrying who
    /// each belongs to for every surface that can carry a name.
    ///
    /// A DICTIONARY RATHER THAN ONE OWNER, and the reason is worth stating
    /// because a scalar looked sufficient. At most one run can be yielded at a
    /// time today: arming implies the batch takes the foreground, which takes
    /// the exclusive global lane. But that invariant is enforced two files away,
    /// and if it ever stopped holding, a single owner would be silently
    /// retargeted by the second yield — the first run's park would evaporate and
    /// it would carry on posting into the very person it had just got out of the
    /// way of, with nothing anywhere saying so. Keying by run costs one
    /// dictionary and removes the dependency instead of documenting it.
    private var yields: [Int: HoldAttribution] = [:]
    private var paused: Bool { pausedByPerson || !yields.isEmpty }
    private var stopped = false
    /// When the hold started, whichever cause started it. Set when the first
    /// cause latches and cleared when the last one lets go, so the backstop
    /// bounds a yield exactly as it bounds a person's pause and a run cannot be
    /// held by a cause that forgot to start the clock.
    private var pausedAt: Double?
    private var personResumePending = false
    /// How long each run has ALREADY spent yielded, across every hold. The
    /// backstop bounds the run rather than the episode, so a condition that
    /// flaps cannot hold a run forever in individually-legal chunks.
    ///
    /// Keyed by run rather than kept as one number, which is what makes that
    /// sentence true across runs: a single total is reset by whichever run
    /// happens to begin next, handing a flapping condition a fresh bound it had
    /// already spent. This is a ledger, not a second clock — the clock is still
    /// `pausedAt` and there is still one of it.
    private var yieldBanked: [Int: Double] = [:]

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
        clearYield()
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
        clearYield()
        pausedAt = nil
    }

    /// Every automatic cause, gone. Held under the lock by every caller, and
    /// used only where the decision really is about the whole machine: a
    /// person's Resume, a person's Stop, and a person's pause running out.
    private func clearYield() { yields.removeAll() }

    // MARK: - The automatic half

    /// Hold ONE run because somebody is using the machine. The same latch and
    /// the same clock as `pause`; what differs is the attribution and who it
    /// parks.
    ///
    /// `run` is the scheduler's ticket id — the same value the queue bar keys a
    /// row on, so the hold a person reads and the run it belongs to are the same
    /// identity rather than two things that have to be correlated. The reason is
    /// not a second parameter: it lives on the attribution, and two places to
    /// say it is two places to disagree.
    func yield(run: Int, hold: HoldAttribution) {
        lock.lock(); defer { lock.unlock() }
        yields[run] = hold
        if pausedAt == nil { pausedAt = now() }
    }

    /// The contention cleared. Lifts ONLY the yield — a pause a person pressed
    /// while the run happened to be yielded stays exactly where they put it.
    func release(run: Int) {
        lock.lock(); defer { lock.unlock() }
        guard yields[run] != nil else { return }
        let owner = run
        // Bank what this hold cost before letting go. Without this a condition
        // that flaps — an application taking and losing the front, secure input
        // going on and off — would start a fresh backstop every time it
        // re-latched, and a run could be held indefinitely in chunks each one
        // of which is individually within the bound. The bound is on the run,
        // not on the episode, which is why the ledger is keyed by run.
        if let since = pausedAt { yieldBanked[owner, default: 0] += max(0, now() - since) }
        yields[run] = nil
        if !paused { pausedAt = nil }
    }

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    var isYielded: Bool { lock.lock(); defer { lock.unlock() }; return !yields.isEmpty }
    var pausedByAPerson: Bool { lock.lock(); defer { lock.unlock() }; return pausedByPerson }
    /// Whose the automatic hold is, readable without entering the session.
    /// The hold worth reading when more than one is somehow open: highest
    /// precedence first, the order the reasons are declared in.
    var heldBy: HoldAttribution? {
        lock.lock(); defer { lock.unlock() }
        let open = yields.values
        return YieldReason.allCases.lazy
            .compactMap { reason in open.first { $0.reason == reason } }.first
    }
    /// Whose hold this particular run is under, when it is under one.
    func heldBy(run: Int) -> HoldAttribution? {
        lock.lock(); defer { lock.unlock() }
        return yields[run]
    }

    /// Whether THIS run is being held. A person's pause parks every run; a yield
    /// parks the run that read it and nobody else.
    func isParked(run: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pausedByPerson || yields[run] != nil
    }

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
    ///
    /// IT CLEARS THIS RUN'S HOLD AND NOBODY ELSE'S, which is the fix for a fault
    /// the out-of-family gate found and the build did not. `RunScheduler.acquire`
    /// never consults this latch, so a run against a free app lane starts while
    /// another run is yielded — and an unconditional reset here cleared that
    /// run's hold, its clock and its bound. Its next look saw nothing holding it
    /// and it carried on posting into the person it had just got out of the way
    /// of. A run beginning is a statement about itself.
    func begin(run: Int) {
        lock.lock(); defer { lock.unlock() }
        pausedByPerson = false
        stopped = false
        personResumePending = false
        yieldBanked[run] = nil
        // Somebody else's automatic hold is not this run's to lift.
        yields[run] = nil
        if !paused { pausedAt = nil }
    }

    // MARK: - The run's side

    /// Called before each step. Nil means carry on.
    ///
    /// `probe` is where contention is read: it runs once before the first look
    /// and once per poll while the run is parked, so a yield can both BEGIN at a
    /// checkpoint and END while the run is already held, with no second timer
    /// anywhere. It is supplied by the session, which owns the policy; this
    /// class knows only that something may set or clear the latch.
    ///
    /// `run` is the scheduler's ticket id. It is what separates "this run is
    /// held" from "something on this Mac is held" — the second is true of every
    /// run in flight the moment any one of them yields, and acting on it is what
    /// parked runs that had nothing to do with the contention.
    func checkpoint(run: Int, probe: (@Sendable () async -> Void)? = nil) async -> Halt? {
        // The run loop is where the buttons live. A pause waited on from the main
        // thread would block the click that releases it, and the run would hang
        // until the backstop gave up — a deadlock that looks exactly like a slow
        // step. `Session` is an actor with its own executor and this method is
        // non-isolated, so neither runs on main today; the assertion is here so
        // that a later change making either main-actor-bound fails a test rather
        // than hanging a person's kill switch.
        assert(!Thread.isMainThread,
               "the halt checkpoint must never be waited on from the main thread")
        // A park that nobody intended is silent, and that silence is half its
        // cost: the poll below never returns, the queue behind it never moves,
        // and the process looks slow rather than held. The backstop is not
        // shortened to fix that — how long a person's pause may hold a run is a
        // product decision, and cutting it would turn a hang into a wrong answer
        // — so the wait says what is holding it instead, once, after long enough
        // that no ordinary pause reaches it.
        var announced = false
        let startedAt = now()
        while true {
            await probe?()
            if let halt = look(run: run) { return halt }
            if !isParked(run: run) { return nil }
            if !announced, now() - startedAt >= RunControl.diagnosticAfter {
                announced = true
                announceLongPark(run: run, heldFor: now() - startedAt)
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    /// How long a park runs before it says so. Well past a person pausing to
    /// look at something and well short of the backstop, so the line lands while
    /// somebody is still watching the run rather than after they gave up on it.
    static let diagnosticAfter: TimeInterval = 20

    /// One line, to stderr, naming the run and its cause.
    ///
    /// Deliberately not the audit trail: this is a note about Proctor's own
    /// state for whoever is reading a terminal, not a record of what the run did
    /// to the machine, and putting it in the trail would make an ordinary long
    /// pause look like an event worth investigating.
    private func announceLongPark(run: Int, heldFor: TimeInterval) {
        FileHandle.standardError.write(Data(longParkMessage(run: run, heldFor: heldFor).utf8))
    }

    /// The sentence, apart from the writing of it, so a test can read what a
    /// person would read rather than capturing a file descriptor.
    func longParkMessage(run: Int, heldFor: TimeInterval) -> String {
        lock.lock()
        let byPerson = pausedByPerson
        let hold = yields[run]
        lock.unlock()
        let cause: String
        if byPerson {
            cause = "a person's Pause"
        } else if let hold {
            cause = "an automatic hold: \(hold.reason.rawValue)"
        } else {
            cause = "nothing this latch can name, which is itself the fault"
        }
        return "proctor: run \(run) has been held \(Int(heldFor))s by \(cause). "
             + "It carries on when the hold lifts, or gives up at "
             + "\(Int(pauseLimit))s.\n"
    }

    /// One reading of the latch, under the lock and without waiting.
    private func look(run: Int) -> Halt? {
        lock.lock(); defer { lock.unlock() }
        if stopped { return .stopped }
        let byYield = yields[run] != nil
        guard pausedByPerson || byYield, let since = pausedAt else { return nil }
        // What this hold has cost, plus what earlier automatic holds already
        // cost THIS run. A person's own pause is judged on this episode alone,
        // because a person deciding again is a person deciding; an automatic
        // hold that keeps re-latching is not. A run parked only by a person's
        // pause banks nothing, so it never inherits another run's spent bound.
        let banked = byYield ? (yieldBanked[run] ?? 0) : 0
        let held = (now() - since) + banked
        guard held >= pauseLimit else { return nil }
        // A pause nobody ever lifts gives up the way a stop does, and says so —
        // reported as a fault it is not would send somebody after the app.
        //
        // WHICH RUNS IT GIVES UP ON follows which cause expired, and the gate
        // found the version that got this wrong: setting the global stop flag
        // for an expired *yield* made a sibling's next look return `.stopped`,
        // so a run nobody touched reported that a person had stopped it from the
        // run HUD. A person's pause held everything, so its expiry stops
        // everything; an automatic hold held one run, so its expiry gives up on
        // that one.
        if pausedByPerson {
            stopped = true
            pausedByPerson = false
            clearYield()
            pausedAt = nil
            yieldBanked.removeAll()
            return .pauseExpired(seconds: pauseLimit)
        }
        yields[run] = nil
        yieldBanked[run] = nil
        if !paused { pausedAt = nil }
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
