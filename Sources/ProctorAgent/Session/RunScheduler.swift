import Foundation
import ProctorCore

// The keeper: the thing that actually holds a lane for the whole length of a run.
//
// WHY THIS IS NOT THE `Session` ACTOR, and this is the load-bearing fact of the
// whole feature. `Session` is a Swift actor, and `runSteps` is one of its
// methods — but actors are reentrant. Isolation drops at every `await`, and
// `runSteps` awaits on settling and on capture at every single step. That is
// precisely why two MCP clients driving the same Mac interleaved their steps
// before this existed. A lane held by the actor's own turn-taking would be
// handed to the other session at the first settle, which is no lane at all. So
// the lane is held here, by a keeper the actor's reentrancy cannot reach into,
// for the run's whole length.
//
// A WHOLE BATCH QUEUES, NEVER A STEP. Acquisition happens at the four call
// entry points — act, a flow replay, a stability sweep, the CUA façade — once
// per call, after the permission gate and before the first step. Splitting a
// six-step login across two sessions' interleaved turns is the exact failure
// this exists to prevent, and a sweep that rejoined the line between passes
// would be that failure spread over five repeats.
//
// A LANE COMES BACK HOWEVER A RUN ENDS. `release` is idempotent and is called on
// every exit path; `LaneTicket.deinit` calls it again as a backstop, so a lane
// whose holder simply went away is reclaimed rather than wedging the machine
// until Proctor restarts.

/// The receipt for a held lane set. Holding it is what holds the lanes, so
/// letting go of it — returning, throwing, or being torn down — gives them back.
final class LaneTicket: @unchecked Sendable {
    let id: Int
    let lanes: Set<RunLane>
    private let scheduler: RunScheduler
    private let released = NSLock()
    private var done = false

    init(id: Int, lanes: Set<RunLane>, scheduler: RunScheduler) {
        self.id = id
        self.lanes = lanes
        self.scheduler = scheduler
    }

    /// True the first time only, so the normal path and the backstop cannot both
    /// count as a release.
    func claimRelease() -> Bool {
        released.lock(); defer { released.unlock() }
        if done { return false }
        done = true
        return true
    }

    deinit {
        // The holder is gone. If it never released — a crash between acquiring
        // and running, a task torn down mid-flight — the lane would otherwise
        // stay held forever, and a leaked hold wedges the machine.
        guard claimRelease() else { return }
        let scheduler = self.scheduler
        let id = self.id
        Task.detached { await scheduler.forceRelease(id: id) }
    }
}

actor RunScheduler {

    /// Whether the task running right now already holds a lane set.
    ///
    /// Nothing in the tree nests one entry point inside another today — act, a
    /// replay, a sweep and the façade each reach `runSteps` directly — but a
    /// future call that did would wait on lanes it is already holding and hang
    /// forever with no error and nothing on screen to explain it. This makes the
    /// second acquisition a no-op instead: one ticket per run, and the outermost
    /// one owns it.
    @TaskLocal static var holdingLanes = false

    /// This task's ticket id, so anything running inside a run can name the run
    /// it is in without being handed the id through every frame.
    ///
    /// A task-local rather than a field because it has to survive the `Session`
    /// actor's reentrancy: isolation drops at every settle and every capture
    /// await, and a value stored on the actor would be whatever the last
    /// interleaved run wrote. Task-locals travel with the task, which is exactly
    /// why `SessionIdentity.current` already works this way through the same
    /// awaits.
    ///
    /// Zero means "no ticket", which is the short-circuited nested path and the
    /// tests that drive a run without a scheduler.
    @TaskLocal static var currentRun: Int = 0

    /// Substitutable so the ceiling is provable in milliseconds rather than in
    /// forty-five seconds, and so a test's clock is its own.
    var waitLimit: TimeInterval
    var now: @Sendable () -> Double
    /// How the ceiling waits.
    ///
    /// Injected alongside `now`, because the comment above used to promise "a
    /// test's clock is its own" while `deadlineTask` slept on the wall clock and
    /// ignored `now` entirely. A test injecting `now: { 0 }` is saying time does
    /// not pass; with a real `Task.sleep` underneath, the ceiling fired anyway
    /// whenever the machine was loaded enough for the work to outlast it.
    /// Measured 2026-08-20: `two sessions driving the same app take turns` failed
    /// roughly one run in five under a parallel suite, with the queue refusing a
    /// run that was about to succeed.
    var sleep: @Sendable (TimeInterval) async -> Void
    /// How many runs one session may keep waiting.
    var perSessionCap: Int = RunQueuePlan.perSessionWaitingCap

    /// How many holders each counted lane admits. The guest pools by default;
    /// a test overrides it to prove capacity is genuinely a parameter rather
    /// than a constant read at the point of use.
    var capacities: [String: Int] = GuestPool.capacities
    func setCapacities(_ capacities: [String: Int]) { self.capacities = capacities }

    init(waitLimit: TimeInterval = RunQueuePlan.waitLimit(from: ProcessInfo.processInfo.environment),
         now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 },
         sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
             try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
         }) {
        self.waitLimit = waitLimit
        self.now = now
        self.sleep = sleep
    }

    /// A scheduler whose ceiling never fires, for a test that injects a stopped
    /// clock. The deadline task is cancelled on every path out of the queue, so
    /// this suspends until cancellation rather than leaking.
    static func stoppedClock(waitLimit: TimeInterval = 5) -> RunScheduler {
        RunScheduler(waitLimit: waitLimit, now: { 0 },
                     sleep: { _ in try? await Task.sleep(nanoseconds: .max) })
    }

    // A waiting run leaves this list exactly once, and only ever from inside this
    // actor: granted by `promote`, given up by `expire`, or removed by a person
    // through `drop` or `clear`. Each of those removes the entry before resuming
    // it, so whichever arrives second finds nothing and does nothing. Resuming a
    // continuation twice traps the process, and a scheduler that crashed the
    // agent under contention would be worse than the interleaving it replaced.

    private struct Waiter {
        let info: RunTicketInfo
        let continuation: CheckedContinuation<LaneTicket, Error>
        /// The give-up timer, cancelled the moment this run leaves the list, so a
        /// granted run does not keep a task asleep for the rest of the ceiling.
        let deadline: Task<Void, Never>
    }

    private var active: [Int: RunTicketInfo] = [:]
    private var waiting: [Waiter] = []
    private var held = false
    private var nextID = 1

    /// Told when anything changes, so the panel and the menu bar can redraw
    /// without polling. Set once by the agent at start-up.
    private var observer: (@Sendable (RunQueueSnapshot) -> Void)?
    func observe(_ observer: @escaping @Sendable (RunQueueSnapshot) -> Void) {
        self.observer = observer
        publish()
    }

    // MARK: - Taking a lane

    /// Take every lane this run needs, at once, or wait for them.
    ///
    /// Every lane is taken together or none is: acquiring them one at a time is
    /// how two runs wedge each other, and a run that is already running can never
    /// come back for another.
    func acquire(lanes: LaneDemand, identity: RunSessionIdentity,
                 summary: String) async throws -> LaneTicket {
        let id = nextID
        nextID += 1
        let info = RunTicketInfo(id: id, identity: identity, summary: summary,
                                 lanes: lanes.lanes, since: now())

        // Nothing running that this contends with, and nobody ahead of it, and
        // the queue is not held: start immediately. Most calls take this path,
        // which is what stops the queue making Proctor feel broken for the
        // common case.
        // The fast path has to ask the same question the scan does, or a counted
        // lane would be a mutex here and a pool there. `admits` is that question
        // asked once, against what is running right now.
        if waiting.isEmpty && !held && admits(lanes.lanes) {
            active[id] = info
            publish()
            return LaneTicket(id: id, lanes: lanes.lanes, scheduler: self)
        }

        // A session in a loop cannot be allowed to starve the others, so its
        // fourth waiting run is refused outright rather than joining a line it
        // would only lengthen.
        let mine = waiting.filter { $0.info.identity == identity }.count
        guard mine < perSessionCap else {
            throw RunQueueRefusal.tooManyWaiting(cap: perSessionCap).error
        }

        let deadline = deadlineTask(for: id)
        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(Waiter(info: info, continuation: continuation, deadline: deadline))
            // Joining the line is not the same as waiting in it. A run against a
            // different app than everything ahead of it can start at once, and
            // only a scan of the whole list can tell — without this, a run that
            // contends with nobody would sit there until some unrelated release
            // happened to wake it.
            promote()
            publish()
        }
    }

    /// The give-up ceiling. A waiting call is held open until its turn — removing
    /// a run has to return that caller's call, so the call must still be open —
    /// but not forever: hosts cut a tool call off around a minute, and a caller
    /// that gets the host's silent timeout instead of Proctor's reason learns
    /// nothing and retries.
    private func deadlineTask(for id: Int) -> Task<Void, Never> {
        let limit = waitLimit
        let sleeper = sleep
        return Task { [weak self] in
            await sleeper(limit)
            guard !Task.isCancelled else { return }
            await self?.expire(id: id)
        }
    }

    private func expire(id: Int) {
        guard let index = waiting.firstIndex(where: { $0.info.id == id }) else { return }
        let waiter = waiting.remove(at: index)
        let refusal = RunQueueRefusal.timedOut(seconds: waitLimit, position: index + 1,
                                               waiting: waiting.count + 1)
        waiter.continuation.resume(throwing: refusal.error)
        publish()
        promote()
    }

    // MARK: - Giving it back

    /// Give the lanes back and wake whoever can now start. Idempotent: the
    /// normal path and the ticket's own backstop must not both count.
    func release(_ ticket: LaneTicket) {
        guard ticket.claimRelease() else { return }
        forceRelease(id: ticket.id)
    }

    /// The backstop, and the only path a torn-down ticket can take.
    func forceRelease(id: Int) {
        guard active.removeValue(forKey: id) != nil else { return }
        publish()
        promote()
    }

    /// Re-examine the WHOLE waiting list, not only the lane that just freed. A
    /// run waiting on two lanes would never be woken by one of them, and a
    /// wake-up that never comes is indistinguishable from a wedged machine.
    private func promote() {
        let grantable = RunQueuePlan.grantable(waiting: waiting.map(\.info),
                                               busy: busyLanes(), held: held,
                                               occupancy: poolOccupancy(),
                                               capacities: capacities)
        guard !grantable.isEmpty else { return }
        for id in grantable {
            guard let index = waiting.firstIndex(where: { $0.info.id == id }) else { continue }
            let waiter = waiting.remove(at: index)
            waiter.deadline.cancel()
            active[id] = waiter.info
            waiter.continuation.resume(
                returning: LaneTicket(id: id, lanes: waiter.info.lanes, scheduler: self))
        }
        publish()
    }

    /// The MUTEX lanes held right now. A counted lane is deliberately excluded:
    /// membership is the wrong question for it, and including it here would make
    /// the pool exclusive against itself — a cap of one wearing a cap of two's
    /// clothes.
    private func busyLanes() -> Set<RunLane> {
        active.values.reduce(into: Set<RunLane>()) { out, run in
            out.formUnion(run.lanes.filter { !$0.isCounted })
        }
    }

    /// How many holders each counted lane has right now.
    private func poolOccupancy() -> [String: Int] {
        RunQueuePlan.occupancy(of: Array(active.values))
    }

    /// Whether this lane set could start immediately: its mutex lanes free, and
    /// room left in every pool it needs.
    private func admits(_ lanes: Set<RunLane>) -> Bool {
        let mutex = lanes.filter { !$0.isCounted }
        guard mutex.isDisjoint(with: busyLanes()) else { return false }
        let occupancy = poolOccupancy()
        for lane in lanes {
            guard let key = lane.poolKey else { continue }
            // Unbounded when unstated, matching `RunQueuePlan.grantable`. The
            // two must agree or the fast path and the scan would answer
            // differently for the same lanes.
            if (occupancy[key] ?? 0) >= (capacities[key] ?? GuestPool.unbounded) { return false }
        }
        return true
    }

    // MARK: - The queue's own controls

    /// Hold stops any waiting run starting — the active session's own next run
    /// included, not only other sessions'. A hold a session can jump by simply
    /// sending its next batch is not a control. The run in flight is untouched
    /// and finishes.
    @discardableResult
    func setHeld(_ on: Bool) -> Bool {
        guard held != on else { return held }
        held = on
        publish()
        if !on { promote() }
        return held
    }

    var isHeld: Bool { held }

    /// Every waiting run is removed and every one of their calls returns saying a
    /// person did it. The active run is untouched.
    @discardableResult
    func clear() -> Int {
        let removed = waiting
        waiting.removeAll()
        for waiter in removed {
            waiter.deadline.cancel()
            waiter.continuation.resume(throwing: RunQueueRefusal.droppedByPerson(cleared: true).error)
        }
        publish()
        // Clear frees no lane — a waiting run holds none — but it can lift a
        // barrier, so whatever was blocked behind a cleared whole-machine run is
        // re-examined. The active run is untouched either way.
        promote()
        return removed.count
    }

    /// One waiting run goes; everything else keeps its position. Takes effect at
    /// once — the removed caller is being held open on this decision, so any
    /// undo delay would be paid by that caller.
    @discardableResult
    func drop(id: Int) -> Bool {
        guard let index = waiting.firstIndex(where: { $0.info.id == id }) else { return false }
        let waiter = waiting.remove(at: index)
        waiter.deadline.cancel()
        waiter.continuation.resume(throwing: RunQueueRefusal.droppedByPerson(cleared: false).error)
        publish()
        promote()
        return true
    }

    // MARK: - Reading it

    /// A run is being held because somebody is using the machine. Published here
    /// rather than read out of the session at draw time — the session is a
    /// reentrant actor and the panel must not queue behind its settles.
    ///
    /// A no-op for an id that is not active, which is what stops a Stop racing a
    /// release from resurrecting a hold on a ticket that has already gone.
    func hold(run id: Int, _ attribution: HoldAttribution) {
        guard active[id] != nil else { return }
        active[id]?.held = attribution
        publish()
    }

    /// The hold is over, however it ended — the contention cleared, a person
    /// resumed, a person stopped it, the backstop gave up, or the run simply
    /// finished. Every one of those paths calls this, which is the invariant
    /// that keeps this copy from outliving the latch it copies.
    func unhold(run id: Int) {
        guard active[id]?.held != nil else { return }
        active[id]?.held = nil
        publish()
    }

    func snapshot() -> RunQueueSnapshot {
        RunQueueSnapshot(active: active.values.sorted { $0.id < $1.id },
                         waiting: waiting.map(\.info),
                         held: held)
    }

    private func publish() {
        observer?(snapshot())
    }
}
