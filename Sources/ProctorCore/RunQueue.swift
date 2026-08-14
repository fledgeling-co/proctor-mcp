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

    public var description: String {
        switch self {
        case .app(let id): return "app:\(id)"
        case .global: return "global"
        }
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

    public init(project: String, connection: String, key: String) {
        self.project = project
        self.connection = connection
        self.key = key
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

    public init(id: Int, identity: RunSessionIdentity, summary: String,
                lanes: Set<RunLane>, since: Double) {
        self.id = id; self.identity = identity; self.summary = summary
        self.lanes = lanes; self.since = since
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
    public static func grantable(waiting: [RunTicketInfo], busy: Set<RunLane>,
                                 held: Bool) -> [Int] {
        guard !held else { return [] }
        var taken = busy
        var granted: [Int] = []
        for entry in waiting {
            if entry.lanes.isDisjoint(with: taken) {
                granted.append(entry.id)
                taken.formUnion(entry.lanes)
                continue
            }
            // It cannot start. A run needing the whole machine becomes a barrier
            // at this point rather than being walked past forever.
            if entry.lanes.contains(.global) { break }
            taken.formUnion(entry.lanes)
        }
        return granted
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
