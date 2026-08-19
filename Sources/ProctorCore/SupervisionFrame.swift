import Foundation

// PRO-0074. What the agent pushes to a watching supervision client.
//
// A projection of the scheduler's state rather than the state itself, for the
// same reason `RunHistory` is a projection of the trail: a field not on the wire
// is a field a remote client cannot leak, and the wire type can be widened
// deliberately rather than by something upstream gaining a property.
//
// **Pushed, never polled.** A supervision surface that polls shows stale state
// exactly when a run is moving fastest, which is the moment somebody is deciding
// whether to press Stop. The agent already has `RunScheduler.observe`; this is
// what rides it out to a socket.

public struct SupervisionFrame: Codable, Sendable, Equatable {

    /// One lane, as a person reads it.
    public struct Lane: Codable, Sendable, Equatable {
        public var lane: String
        /// Who holds or wants it — the session's own label, never text a caller
        /// supplied.
        public var holder: String
        /// `holding`, `waiting`, `paused`, `free`.
        public var state: String
        /// Seconds waited, as a number rather than as a rendered string: the
        /// surface decides how to say it, and a client in another locale is not
        /// handed English.
        public var seconds: Int

        public init(lane: String, holder: String, state: String, seconds: Int) {
            self.lane = lane; self.holder = holder; self.state = state; self.seconds = seconds
        }
    }

    /// The run in front, when there is one.
    public struct Run: Codable, Sendable, Equatable {
        public var summary: String
        public var held: Bool
        /// Why it is held, in Proctor's own words. Nil when it is running.
        public var holdReason: String?
        public var seconds: Int
        public var machine: String

        public init(summary: String, held: Bool, holdReason: String? = nil,
                    seconds: Int, machine: String) {
            self.summary = summary; self.held = held
            self.holdReason = holdReason; self.seconds = seconds; self.machine = machine
        }
    }

    /// When this frame was taken. A client that has not been told for a while
    /// says the data is stale rather than drawing the last good frame as
    /// current, so it needs to know how old what it holds is.
    public var at: Double
    public var run: Run?
    public var lanes: [Lane]
    /// The whole queue is held, which is not the same as one run being paused.
    public var queueHeld: Bool
    public var waiting: Int

    public init(at: Double, run: Run? = nil, lanes: [Lane] = [],
                queueHeld: Bool = false, waiting: Int = 0) {
        self.at = at; self.run = run; self.lanes = lanes
        self.queueHeld = queueHeld; self.waiting = waiting
    }

    /// The control request a client sends to open a watch. Named as a tool so it
    /// travels the existing frame protocol unchanged, and prefixed with a dot so
    /// it can never collide with a catalogue name.
    public static let watchTool = "proctor.watch"

    /// How long a client waits for a frame before it says so. Longer than any
    /// heartbeat, so a quiet machine is not reported as an unreachable one.
    public static let staleAfter: TimeInterval = 12

    /// Turn a frame into what the surface draws.
    ///
    /// The mapping lives here rather than in the TUI so it can be asserted
    /// without a terminal, and so a second supervision surface reads the wire
    /// the same way this one does.
    public func lanesForSurface() -> [TUISurface.Lane] {
        lanes.map {
            TUISurface.Lane(name: $0.lane, holder: $0.holder, state: $0.state,
                            wait: $0.state == "free" ? "-" : "\($0.seconds)s")
        }
    }

    public func runForSurface(step: Int = 0, steps: Int = 0) -> TUISurface.Run? {
        guard let run else { return nil }
        let elapsed = String(format: "%02d:%02d.0", run.seconds / 60, run.seconds % 60)
        if run.held {
            return TUISurface.Run(
                phase: .paused,
                headline: ["Paused. \(run.holdReason ?? "Held.")", "Press <p> to resume."],
                facts: [.init("held by", run.holdReason ?? "a person"),
                        .init("resumes", "on <p>"),
                        .init("elapsed", elapsed)],
                step: step, steps: steps, machine: run.machine)
        }
        return TUISurface.Run(
            phase: .acting,
            headline: [run.summary, ""],
            facts: [.init("machine", run.machine), .init("elapsed", elapsed)],
            step: step, steps: steps, machine: run.machine)
    }
}
