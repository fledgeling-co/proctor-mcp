import Foundation
import ProctorCore

// PRO-0074. Fan one observer out to many watchers.
//
// `RunScheduler.observe` takes a single observer and the agent sets it at
// start-up, which was right while the only consumers lived in this process. A
// supervision client over a socket is a second consumer, and replacing the
// observer to add one would silently stop the HUD drawing — the panel and the
// menu bar would keep their last frame and look correct.
//
// So the scheduler keeps its one observer and that observer publishes here. A
// watcher that goes away is removed on its next failed write rather than by
// asking it, because a client over SSH disappears without saying so.

final class SupervisionBroadcast: @unchecked Sendable {
    static let shared = SupervisionBroadcast()

    private let lock = NSLock()
    private var watchers: [Int: @Sendable (SupervisionFrame) -> Void] = [:]
    private var nextID = 1
    /// The last frame published, handed to a watcher the moment it subscribes.
    /// Without it a client that connected during a quiet minute draws an empty
    /// screen until something happens, which reads as a broken agent.
    private var last: SupervisionFrame?

    /// Register a watcher. Returns its id and the frame it should draw now.
    func add(_ watcher: @escaping @Sendable (SupervisionFrame) -> Void)
        -> (id: Int, current: SupervisionFrame?) {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        watchers[id] = watcher
        return (id, last)
    }

    func remove(_ id: Int) {
        lock.lock()
        watchers[id] = nil
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return watchers.count
    }

    func publish(_ frame: SupervisionFrame) {
        lock.lock()
        last = frame
        let current = Array(watchers.values)
        lock.unlock()
        for watcher in current { watcher(frame) }
    }

    /// Project the scheduler's snapshot onto the wire.
    ///
    /// The run in front is the longest-running active one rather than the
    /// lowest-numbered: a person watching wants the run that has been holding
    /// the machine, and ticket order is an implementation detail of the queue.
    static func frame(from snapshot: RunQueueSnapshot, now: Double) -> SupervisionFrame {
        var lanes: [SupervisionFrame.Lane] = []
        for ticket in snapshot.active {
            for lane in ticket.lanes.sorted(by: { $0.description < $1.description }) {
                lanes.append(SupervisionFrame.Lane(
                    lane: lane.description,
                    holder: ticket.identity.label,
                    state: ticket.held != nil ? "paused" : "holding",
                    seconds: Int(max(0, now - ticket.since))))
            }
        }
        for ticket in snapshot.waiting {
            for lane in ticket.lanes.sorted(by: { $0.description < $1.description }) {
                lanes.append(SupervisionFrame.Lane(
                    lane: lane.description,
                    holder: ticket.identity.label,
                    state: "waiting",
                    seconds: Int(max(0, now - ticket.since))))
            }
        }
        let front = snapshot.active.min { $0.since < $1.since }
        var run: SupervisionFrame.Run?
        if let front {
            run = SupervisionFrame.Run(
                summary: front.summary,
                held: front.held != nil,
                holdReason: front.held?.reason.line,
                seconds: Int(max(0, now - front.since)),
                machine: "host")
        }
        return SupervisionFrame(at: now, run: run, lanes: lanes,
                                queueHeld: snapshot.held,
                                waiting: snapshot.waitingCount)
    }
}
