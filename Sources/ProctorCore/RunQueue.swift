import Foundation

// The multi-session scheduler, as values.
//
// Proctor is one agent behind one socket and any number of MCP clients can
// connect. Nothing arbitrated between them before this: two sessions driving the
// same Mac interleaved their steps, and the second one's synthetic click landed
// in whatever window the first had just raised.
//
// Everything here is pure — lanes in, decisions out — so the whole contention
// model is provable with no window, no actor and no client. `RunScheduler` in
// the agent is the keeper that holds a lane for the length of a run; this file
// is what it consults.
//
// THREE LANES, AND THAT IS THE WHOLE MODEL.
//
//   Reads never join the line. `proctor_snapshot`, `find`, `capture`, `menu`,
//   `zoom` and `assert` observe without mutating, and none of them reaches the
//   step loop, so none of them ever reaches this file. Note what that claims and
//   what it does not: reads never *queue*. It is not a claim about the `Session`
//   actor, which deliberately lets other work in at every settle and capture
//   await — that reentrancy is exactly why steps interleaved in the first place,
//   and exactly why a lane has to be held by a keeper outside the actor's own
//   turn-taking.
//
//   Process-directed actuation contends per app. An accessibility press is IPC
//   to one process, so two sessions driving different apps genuinely do not
//   interfere and run in parallel. The same app serialises.
//
//   Synthetic events contend globally. They enter the single WindowServer event
//   stream and need the target frontmost, so one at a time anywhere on the
//   machine — and the run that raises an app also holds that app's lane, because
//   raising changes where everybody else's clicks land.

/// What a run contends for. Reads take no lane at all, which is why there is no
/// case for them.
public enum RunLane: Hashable, Sendable, CustomStringConvertible {
    /// One app's accessibility plane, keyed by the app handle id.
    case app(String)
    /// The single system event stream.
    case global
    /// One named guest, keyed `provider:name`. A MUTEX lane, like the two
    /// above: two campaigns cannot drive one VM, so the second waits however
    /// many slots are free.
    case guest(String)
    /// A COUNTED lane, keyed by platform. This is the one lane that admits
    /// more than one holder, and the number it admits is a parameter rather
    /// than a property of the case — see `GuestPool`.
    case pool(String)

    public var description: String {
        switch self {
        case .app(let id): return "app:\(id)"
        case .global: return "global"
        case .guest(let id): return "guest:\(id)"
        case .pool(let id): return "pool:\(id)"
        }
    }

    /// Whether this lane counts rather than excludes. The admission rule
    /// branches on this once; nothing else needs to know.
    public var isCounted: Bool {
        if case .pool = self { return true }
        return false
    }

    /// The counted lane's key, for the occupancy table.
    public var poolKey: String? {
        if case .pool(let id) = self { return id }
        return nil
    }
}

// MARK: - The guest pool

/// How many guests of a platform may be running at once, and why.
public enum GuestPool {

    /// **Two is Apple's number, not one this project chose.** macOS on Apple
    /// silicon permits at most two concurrently running macOS guests per host.
    /// It is a platform constant with its reason beside it rather than a
    /// tunable, and it constrains macOS guests only: the rule being honoured is
    /// Apple's about macOS, not a property of virtualisation.
    public static let macOSCapacity = 2

    /// No platform rule is known for a Linux or Windows guest, and inventing a
    /// number here would cap something nobody asked to cap. Those pools are
    /// unbounded **by Proctor** and bounded by whatever their provider allows,
    /// which is the honest reading of "at whatever its provider allows".
    public static let unbounded = Int.max

    /// The pool a guest of this platform joins. Keyed by platform, because the
    /// cap is a platform rule — never by the guest's name, which is what
    /// `TartInventory` refuses to read a platform out of for the same reason.
    public static func key(for platform: MachinePlatform) -> String {
        platform.rawValue
    }

    public static func capacity(for platform: MachinePlatform) -> Int {
        switch platform {
        case .macos: return macOSCapacity
        case .linux, .windows: return unbounded
        }
    }

    /// One named guest's lane, keyed so two providers holding the same name do
    /// not collide.
    public static func guestKey(provider: String, name: String) -> String {
        "\(provider):\(name)"
    }

    /// Every pool's capacity, for the scheduler to hand to the plan.
    public static var capacities: [String: Int] {
        var out: [String: Int] = [:]
        for platform in [MachinePlatform.macos, .linux, .windows] {
            out[key(for: platform)] = capacity(for: platform)
        }
        return out
    }
}

/// The lanes one run needs, decided before it starts and never added to.
///
/// Taking them one at a time is how two runs wedge each other, so a run takes
/// everything it needs at once or waits; and because the set is fixed up front,
/// a run that is running can never discover it needs a lane somebody else holds.
public struct LaneDemand: Hashable, Sendable {
    public var lanes: Set<RunLane>

    public init(lanes: Set<RunLane>) { self.lanes = lanes }

    public var needsGlobal: Bool { lanes.contains(.global) }

    /// The lane set for a batch. `syntheticKinds` is supplied rather than
    /// duplicated: the agent already names that set once, and a second copy here
    /// would be a second thing to keep true.
    ///
    /// The global lane is taken in two cases, and they are one case seen twice:
    /// the run changes what is in front. A step that could travel through the
    /// event stream needs the target frontmost, and a `raise` step brings a
    /// window forward, which moves the ground under every synthetic event
    /// anybody else is posting.
    ///
    /// Both are `ForegroundDemand.takesForeground`, which is where that question
    /// is now answered for the scheduler, the panel and the menu bar alike.
    ///
    /// The conditional kinds (`type`, `scroll`) are supplied rather than assumed
    /// away, and the reason is narrow. They are still absent from the predicate
    /// on their own — taking the exclusive lane on the chance one falls back
    /// would serialise runs that never touch the foreground — but a batch that
    /// asked for `foreground` **and** contains one can post, so the lane is
    /// exactly as it was for that case. What changes is the other case: a batch
    /// that asked for the front while containing nothing that could use it now
    /// runs in its app's lane like the background run it always was.
    public static func forBatch(kinds: [ActionStep.Kind], synthetic: Set<ActionStep.Kind>,
                                conditional: Set<ActionStep.Kind> = [],
                                app: String, foreground: Bool) -> LaneDemand {
        let demand = ForegroundDemand.forBatch(kinds: kinds, synthetic: synthetic,
                                               conditional: conditional, foreground: foreground)
        var lanes: Set<RunLane> = [.app(app)]
        if demand.takesForeground { lanes.insert(.global) }
        return LaneDemand(lanes: lanes)
    }

    /// The lane set for `proctor_apps.activate`, which brings an application to
    /// the front and, when it is not running, launches it.
    ///
    /// That is `raise` in every way the scheduler cares about, and `raise` takes
    /// the global lane because raising changes where everybody else's clicks
    /// land. So: **the global lane, always**.
    ///
    /// The app lane is taken only when the target already resolves to an
    /// ATTACHED handle, and the reason is a key space rather than caution. An
    /// unattached process is not keyless — a listing hands out `app:<pid>:0`
    /// where an attach mints `app:<pid>:<epoch>` — so a key taken from the wrong
    /// place would look exactly like contention accounting while never once
    /// contending with the batch it was supposed to serialise against. A batch
    /// can only drive an attached app, so the case that can contend is the case
    /// that gets the key, and the case that cannot is left honestly uncovered.
    /// The lanes an attachment to one guest needs: its own mutex lane and its
    /// platform's counted pool, taken together.
    ///
    /// Both at once, for the reason the whole type exists: taking them one at a
    /// time is how two runs wedge each other. A run holding a slot while
    /// waiting for the guest, or holding the guest while waiting for a slot,
    /// is the deadlock this shape makes unrepresentable.
    public static func forGuest(provider: String, name: String,
                                platform: MachinePlatform) -> LaneDemand {
        LaneDemand(lanes: [.guest(GuestPool.guestKey(provider: provider, name: name)),
                           .pool(GuestPool.key(for: platform))])
    }

    public static func forActivate(app: String?) -> LaneDemand {
        var lanes: Set<RunLane> = [.global]
        if let app { lanes.insert(.app(app)) }
        return LaneDemand(lanes: lanes)
    }
}

/// Who is asking. Derived from the process on the other end of the socket and
/// never supplied by the client: a connection that could name itself could
/// impersonate another one in the very UI a person uses to decide whether to
/// stop it.
public struct RunSessionIdentity: Hashable, Sendable {
    /// The client's own working directory, reduced to its last component —
    /// `diolog-web`, `armada`, `proctor-mcp`.
    public var project: String
    /// Four characters, so two sessions in the same repo are told apart. Stable
    /// for the life of the client process rather than for one call.
    public var connection: String
    /// What identity is actually *judged* on: the peer process, in full.
    ///
    /// The four-character id is for a person reading the panel, and four hex
    /// characters collide about once in a few hundred sessions. A collision in a
    /// display string costs a moment's confusion; a collision in the thing the
    /// waiting cap counts against would silently merge two clients' allowances,
    /// so the two are kept apart and only this one is compared.
    public var key: String
    /// WHICH FRONT END called — `cli`, `mcp`, or nil.
    ///
    /// Read from the peer process's executable name, never from the request, for
    /// the same reason `project` is read from its working directory: a caller
    /// that could name itself could name itself as the other one, in the very
    /// trail used to argue about what happened.
    ///
    /// Nil reads as "the build that wrote this row did not say" and never as
    /// "MCP". Absence is in fact unambiguous today, because every row written
    /// before the CLI existed was an MCP row — but a later front end that forgot
    /// to identify itself would then be indistinguishable from an older honest
    /// row, which is the failure this field exists to prevent.
    public var frontEnd: String?

    public init(project: String, connection: String, key: String, frontEnd: String? = nil) {
        self.project = project
        self.connection = connection
        self.key = key
        self.frontEnd = frontEnd
    }

    public static func == (a: RunSessionIdentity, b: RunSessionIdentity) -> Bool { a.key == b.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }

    /// What the panel prints: `proctor-mcp a3f1`. A pid is not an answer to
    /// "which session is this".
    public var label: String { "\(project) \(connection)" }
}

/// One run the scheduler knows about, waiting or running.
public struct RunTicketInfo: Sendable, Equatable, Identifiable {
    public var id: Int
    public var identity: RunSessionIdentity
    /// What this run wants, in the panel's words — "Act ×6 · Acme Console".
    public var summary: String
    public var lanes: Set<RunLane>
    /// When it joined, so the panel can say how long it has waited without the
    /// scheduler having to tick.
    public var since: Double
    /// Whose the hold is, when this run is being held.
    ///
    /// THE JOIN LIVES HERE, and that is deliberate. A hold is decided inside
    /// `Session`, which is a REENTRANT actor whose isolation drops at every
    /// settle and every capture await — so a surface that read a hold out of the
    /// session at draw time would put a redraw behind the actor's turn-taking.
    /// The scheduler is the keeper that already lives outside it and is already
    /// what the panel, the menu bar mirror and the health report read, so the
    /// hold is *published* into it at the two moments the latch moves.
    ///
    /// It is a copy, not the decision: the latch stays the truth, because Pause
    /// and Stop are synchronous main-thread writes and a hop through an actor
    /// from a button is late by at least one poll. What keeps the copy honest is
    /// that every path clearing the latch's yield also publishes an unhold.
    public var held: HoldAttribution?

    public init(id: Int, identity: RunSessionIdentity, summary: String,
                lanes: Set<RunLane>, since: Double, held: HoldAttribution? = nil) {
        self.id = id; self.identity = identity; self.summary = summary
        self.lanes = lanes; self.since = since; self.held = held
    }
}

/// The scheduler's state as one value, for the panel, the menu bar and the
/// health report.
public struct RunQueueSnapshot: Sendable, Equatable {
    public var active: [RunTicketInfo] = []
    public var waiting: [RunTicketInfo] = []
    public var held: Bool = false

    public init(active: [RunTicketInfo] = [], waiting: [RunTicketInfo] = [],
                held: Bool = false) {
        self.active = active; self.waiting = waiting; self.held = held
    }

    /// The bar counts only the runs that are actually waiting. Counting the ones
    /// already running would overstate how blocked the machine is — a run in
    /// another lane is not queued, and saying it is understates what the
    /// scheduler can do.
    public var waitingCount: Int { waiting.count }

    /// Per-lane occupancy for the health report. A wedged lane is otherwise
    /// invisible.
    public var laneReport: [(lane: String, active: Int, waiting: Int)] {
        var lanes = Set<RunLane>()
        for run in active { lanes.formUnion(run.lanes) }
        for run in waiting { lanes.formUnion(run.lanes) }
        return lanes.map { lane in
            (lane.description,
             active.filter { $0.lanes.contains(lane) }.count,
             waiting.filter { $0.lanes.contains(lane) }.count)
        }.sorted { $0.0 < $1.0 }
    }
}

// MARK: - The waiting list

/// The arrival-ordered waiting list and the one decision made against it: which
/// of the waiting runs may start now.
///
/// Kept apart from the actor that holds the lanes so the fairness rules are
/// testable as arithmetic. Four of them, and each exists because of a failure it
/// prevents:
///
///   FIFO within a lane, so a session cannot be overtaken indefinitely.
///
///   Every release re-examines the whole list, not only the lane that just
///   freed — a run waiting on two lanes would never be woken by one of them.
///
///   Once a run needing the whole machine is at the head of the line, nothing
///   new starts ahead of it. A trickle of single-app work would otherwise starve
///   it for as long as the trickle lasted.
///
///   A held queue starts nothing at all, the active session's own next run
///   included. A hold a session can jump by simply sending its next batch is not
///   a control.
public struct RunQueuePlan: Sendable {

    /// Which waiting entries may start, given what is already running.
    ///
    /// `busy` is the union of the lanes held right now. The scan walks the
    /// waiting list in arrival order and grants an entry when *that entry's own*
    /// lanes are all free — so two sessions driving different apps both start,
    /// which is the whole reason this is three lanes rather than one queue.
    ///
    /// An entry that cannot start either stops the scan, when it needs the whole
    /// machine, or has its lanes marked taken for the rest of this scan so
    /// nothing behind it jumps ahead onto the same lane. That mark is a local of
    /// this function and never scheduler state: it holds FIFO within a lane for
    /// the length of one decision and cannot leak a lane to nobody.
    /// `occupancy` is how many holders each COUNTED lane already has, and it is
    /// the parameter that makes the guest pool a pool rather than a third mutex.
    /// `capacities` says how many each admits; a counted lane with no entry
    /// admits one, which is the conservative direction.
    ///
    /// THE COUNT IS INCREMENTED INSIDE THE SCAN, and that is the whole
    /// correctness of the counted lane. Two other shapes are available and both
    /// are wrong: putting a `.pool` lane into `taken` makes the pool a mutex of
    /// capacity one, and counting only what was already active — without
    /// incrementing as this scan grants — lets a single scan admit three
    /// holders into two slots, because every waiter reads the same stale count.
    /// Both are pinned by tests.
    public static func grantable(waiting: [RunTicketInfo], busy: Set<RunLane>,
                                 held: Bool,
                                 occupancy: [String: Int] = [:],
                                 capacities: [String: Int] = [:]) -> [Int] {
        guard !held else { return [] }
        var taken = busy
        var counts = occupancy
        var granted: [Int] = []

        /// Whether this entry's counted lanes all have room left right now.
        ///
        /// **A pool with no stated capacity is UNBOUNDED, not one.** Defaulting
        /// to 1 turned any pool the caller forgot to describe into a mutex,
        /// which is the wrong answer for the linux and windows pools the spec
        /// says are limited by their provider rather than by Proctor. The macOS
        /// cap cannot go missing by omission: `GuestPool.capacities` names every
        /// platform, and a test fails if a new one is ever added without a
        /// capacity.
        func poolsHaveRoom(_ entry: RunTicketInfo) -> Bool {
            for lane in entry.lanes {
                guard let key = lane.poolKey else { continue }
                let capacity = capacities[key] ?? GuestPool.unbounded
                if (counts[key] ?? 0) >= capacity { return false }
            }
            return true
        }

        for entry in waiting {
            let mutex = entry.lanes.filter { !$0.isCounted }
            if mutex.isDisjoint(with: taken) && poolsHaveRoom(entry) {
                granted.append(entry.id)
                taken.formUnion(mutex)
                // The increment that stops one scan over-granting.
                for lane in entry.lanes {
                    guard let key = lane.poolKey else { continue }
                    counts[key, default: 0] += 1
                }
                continue
            }
            // It cannot start. A run needing the whole machine becomes a barrier
            // at this point rather than being walked past forever.
            if entry.lanes.contains(.global) { break }
            // A full pool MARKS and the scan continues, where `.global` breaks
            // it. A pool that broke the scan would let a busy guest lane starve
            // every Mac run queued behind it, which is a much larger blast
            // radius than the FIFO-within-a-pool this preserves.
            taken.formUnion(mutex)
        }
        return granted
    }

    /// How many holders each counted lane has, folded over the runs in flight.
    /// Derived rather than kept, so there is no second number to keep true.
    public static func occupancy(of active: [RunTicketInfo]) -> [String: Int] {
        var out: [String: Int] = [:]
        for run in active {
            for lane in run.lanes {
                guard let key = lane.poolKey else { continue }
                out[key, default: 0] += 1
            }
        }
        return out
    }

    /// How many runs one session may keep waiting. A session in a loop cannot
    /// starve the others, so a fourth is refused straight away rather than
    /// joining a line it would only lengthen.
    public static let perSessionWaitingCap = 3

    /// How long a waiting call is held open before it gives up.
    ///
    /// Hosts commonly cut a tool call off around a minute, so the ceiling has to
    /// fire inside that or the caller gets the host's silent timeout instead of
    /// Proctor's reason — and a caller that is told nothing retries, which is how
    /// a queue becomes a stampede.
    public static let defaultWaitLimit: TimeInterval = 45

    /// Adjustable by the same kind of setting as Proctor's other switches.
    public static func waitLimit(from environment: [String: String]) -> TimeInterval {
        guard let raw = environment["PROCTOR_QUEUE_WAIT_LIMIT"],
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds > 0 else { return defaultWaitLimit }
        return seconds
    }
}

// MARK: - What a refused caller is told

/// The refusals a queued run can come back with. Both exist so a waiting call
/// never simply hangs, and so the caller can tell a person's decision from a
/// machine that was busy — the first is a signal to stop and ask, the second a
/// signal to try again later.
public enum RunQueueRefusal: Sendable, Equatable {
    /// The give-up ceiling fired. Says where the call stood when it did.
    case timedOut(seconds: Double, position: Int, waiting: Int)
    /// This session already has the most runs it may keep waiting.
    case tooManyWaiting(cap: Int)
    /// A person cleared the queue or dropped this run out of it.
    case droppedByPerson(cleared: Bool)

    public var code: AgentError.Code {
        switch self {
        case .timedOut, .tooManyWaiting: return .queueBusy
        // A person removing a run is not a failure of a step, and it gets the
        // same code a person's Stop already does.
        case .droppedByPerson: return .haltedByPerson
        }
    }

    public var error: AgentError {
        switch self {
        case .timedOut(let seconds, let position, let waiting):
            return AgentError(
                code: .queueBusy,
                message: "another session was driving this Mac, and this run was still waiting "
                       + "\(ordinal(position)) of \(waiting) after \(Int(seconds)) seconds, so it "
                       + "gave up without running any step",
                remedy: "Nothing was actuated, so this is safe to send again. Somebody else's run "
                      + "holds the same application, or holds the whole machine for a synthetic "
                      + "event. Wait for it, or drive a different application — runs against "
                      + "different apps do not contend.")
        case .tooManyWaiting(let cap):
            return AgentError(
                code: .queueBusy,
                message: "this session already has \(cap) runs waiting for Proctor, which is the "
                       + "most one session may hold, so this run was refused rather than queued",
                remedy: "Nothing was actuated. Let the runs already waiting finish before sending "
                      + "another — a session that keeps queueing would starve the other sessions "
                      + "on this machine, which is what this limit prevents.")
        case .droppedByPerson(let cleared):
            return AgentError(
                code: .haltedByPerson,
                message: cleared
                    ? "a person cleared Proctor's queue from the run HUD, so this run was removed "
                    + "before any of its steps ran"
                    : "a person removed this run from Proctor's queue in the run HUD, so none of "
                    + "its steps ran",
                remedy: "Nothing failed and nothing was actuated. Somebody watching the machine "
                      + "decided this run should not go ahead. Ask before sending it again rather "
                      + "than retrying.")
        }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        default: return "\(n)th"
        }
    }
}
