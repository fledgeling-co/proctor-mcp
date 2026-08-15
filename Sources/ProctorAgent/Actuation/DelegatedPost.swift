import Foundation
import ProctorCore

// PRO-0046. Who is actuating right now, when it is not Proctor.
//
// THE PROBLEM THIS EXISTS FOR. Proctor's supervision guards recognise an event
// by asking whether Proctor posted it — `InputBlock.isOurs`, which matches
// Proctor's own tag or Proctor's own pid. Delegate actuation and that question
// stops identifying the same set: the driver's events carry the driver's pid and
// none of Proctor's marks, so an armed input block swallows the very events the
// run depends on, and a driver's click that lands on the run panel's Stop
// rectangle stops the run somebody was supervising.
//
// The scheduler makes that reachable rather than theoretical.
// `RunQueuePlan.grantable` grants an entry whose lanes are disjoint from what is
// busy, and `.global` is a lane rather than a barrier against app lanes — so a
// native `foreground: true` run holding `{app(X), global}` and a delegated run
// holding `{app(Y)}` both start, while `InputBlocker.shared` is one tap for the
// whole process.
//
// So the pass rule admits ONE further identity: the pid of the driver Proctor is
// currently delegating to. This is the keeper of that fact.
//
// WHY IT IS SHAPED LIKE `SyntheticPost` AND `RunHUDGeometry`. Two readers cannot
// wait: the event tap's `.defaultTap` callback, which macOS disables if it does
// not answer promptly, and the run panel's own view on the main actor. So every
// accessor takes one lock, copies a value out, and returns. Nothing is held
// across work and this lock is shared with nothing that hops to main.
//
// THREE ACCOUNTING RULES, each of which the plan's out-of-family gate found the
// first draft getting wrong:
//
//   * A CALL IS THE UNIT, NOT A PID. Two delegated runs can share one driver —
//     both hold only an app lane, so the scheduler runs them together. Keyed on
//     the pid alone, the first call to end would lapse a pid the second call is
//     still using, dropping it mid-gesture.
//   * MEMBERSHIP OUTLIVES THE CALL BY A GRACE. A driver's `mouseDown` can land
//     while the call is open and its `mouseUp` arrive after it returns; a window
//     ending at the boundary strips the end off a gesture and leaves the
//     application holding a button nobody is pressing — the state PRO-0026's
//     pair rule exists to prevent, and one that outlives the block, the run and
//     the process.
//   * EVERY CALL CARRIES A CEILING. A `perform` that hangs, a cancelled task or
//     a driver that dies mid-call would otherwise leak an entry forever, and a
//     leaked entry leaves a reused pid exempt from the block indefinitely. The
//     session releases in a `defer`, which covers a throw; the ceiling covers the
//     rest, in the same spirit as `InputBlocker`'s own deadline.
//
// Expiry happens on read rather than on a timer, because the tap may not run one
// and a sweeper would be a second thing to keep true.
final class DelegatedPost: @unchecked Sendable {

    static let shared = DelegatedPost()

    /// One outstanding delegated call. Opaque, and releasing it twice is a no-op:
    /// the ceiling can already have dropped the call, and a release that
    /// decremented a counter would then double-count.
    struct Token: Sendable, Equatable {
        fileprivate let id: Int
    }

    private struct Call {
        var pid: Int64?
        var ceiling: Double
    }

    private let lock = NSLock()
    private var calls: [Int: Call] = [:]
    /// Pids whose last call has ended, and when their membership lapses.
    private var lapsing: [Int64: Double] = [:]
    private var nextID = 0

    var now: @Sendable () -> Double = { Date().timeIntervalSince1970 }

    /// A delegated actuation is about to happen.
    ///
    /// Called BEFORE the request goes out rather than around the wait: an event
    /// posted between the request leaving and this opening would be classified
    /// as foreign, swallowed by an armed block, and reported to the contention
    /// monitor as somebody using the machine.
    ///
    /// A pid of `0` or Proctor's own is refused here and recorded as
    /// unrecognised. Zero is what hardware carries, so admitting it would turn
    /// "recognise the driver" into "everything is ours" and the block would pass
    /// the whole of a person's input while claiming to hold it.
    @discardableResult
    func begin(pid: Int64?) -> Token {
        lock.lock(); defer { lock.unlock() }
        expireLocked()
        nextID &+= 1
        let usable = pid.flatMap { $0 == 0 || $0 == Self.ourPid ? nil : $0 }
        calls[nextID] = Call(pid: usable, ceiling: now() + Takeover.ceilingSeconds)
        if let usable { lapsing.removeValue(forKey: usable) }
        return Token(id: nextID)
    }

    /// That actuation is over. Idempotent.
    func end(_ token: Token) {
        lock.lock(); defer { lock.unlock() }
        guard let call = calls.removeValue(forKey: token.id) else { return }
        if let pid = call.pid, !calls.values.contains(where: { $0.pid == pid }) {
            lapsing[pid] = now() + PersonInput.graceSeconds
        }
        expireLocked()
    }

    /// The pids whose events the guards should treat as Proctor's own doing.
    var recognisedPids: Set<Int64> {
        lock.lock(); defer { lock.unlock() }
        expireLocked()
        return Set(calls.values.compactMap(\.pid)).union(lapsing.keys)
    }

    /// Whether a delegated actuation is in flight whose driver Proctor could not
    /// recognise. Such a batch takes the exclusive lane rather than arming a
    /// hold it could not tell its own driver apart from a person.
    var hasUnrecognised: Bool {
        lock.lock(); defer { lock.unlock() }
        expireLocked()
        return calls.values.contains { $0.pid == nil }
    }

    var outstanding: Int {
        lock.lock(); defer { lock.unlock() }
        expireLocked()
        return calls.count
    }

    /// Forget everything. For a test harness, so one suite's keeper state cannot
    /// decide another's.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        calls.removeAll()
        lapsing.removeAll()
    }

    /// Drop what has gone. Only ever removes keys — it never adjusts a count,
    /// so a ceiling firing and a release arriving cannot both account for the
    /// same call.
    private func expireLocked() {
        let t = now()
        calls = calls.filter { $0.value.ceiling > t }
        lapsing = lapsing.filter { $0.value > t }
    }

    private static let ourPid = Int64(ProcessInfo.processInfo.processIdentifier)
}
