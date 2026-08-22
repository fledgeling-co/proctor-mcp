import Foundation

/// What the window is waiting for while it restarts the agent, and what ends the
/// wait.
///
/// PRO-0098, DEF-132. The state this replaces was cleared by
/// `DispatchQueue.main.asyncAfter(deadline: .now() + 1.2)`: a fixed delay that
/// assumed the restart had finished because 1.2 seconds had passed. It is the
/// same oracle this repo has already replaced twice — `ScreenRecordingProbe`'s
/// bound timer and `CuaLineReader`'s monotonic clock — and it fails the same way.
/// A restart that outlives the delay leaves the window claiming the agent is not
/// answering, about a restart Proctor itself asked for, at exactly the moment a
/// person is least able to tell a slow restart from a broken one. A machine under
/// load is when a `launchctl kickstart` takes longer than a second, and it is also
/// when this window is most likely to be open.
///
/// **The delay is not the bug and is not removed.** Polling immediately after
/// asking launchd for a restart races it and reports the agent down every time,
/// so a beat before the *first* probe is correct. What was wrong was clearing the
/// state on that beat instead of on an event.
///
/// So this type holds no clock. It is fed probe results and ends on one of two
/// events:
///
/// - a probe comes back **reachable** — the restart finished, which is the event
///   the flag was always meant to be waiting for;
/// - `giveUpAfterProbes` probes come back **unreachable** — the agent is not
///   coming back on its own, and by then "the agent is not answering" is a true
///   statement rather than a guess.
///
/// The give-up is a count of probes rather than a deadline on purpose. A count is
/// a statement about how much evidence has been gathered; a deadline is a second
/// stopwatch, and swapping one stopwatch for a longer one is the fix this defect
/// was recorded to avoid.
public struct RestartWatch: Equatable, Sendable {

    public enum State: Equatable, Sendable {
        /// No restart is in flight.
        case idle
        /// A restart was asked for and no probe has found the agent yet.
        case applying
        /// A probe found the agent. The restart is over and it worked.
        case settled
        /// Enough probes came back unreachable that the wait is no longer honest.
        /// The agent really is down, and the window should say so.
        case abandoned
    }

    public private(set) var state: State
    /// Probes observed since `begin()`. Reset by every `begin()`, so a second
    /// restart is not judged on the first one's evidence.
    public private(set) var probes: Int
    /// How many unreachable probes are enough to stop claiming a restart is in
    /// flight. Defaulted rather than hardcoded at the call site so a caller on a
    /// different cadence can say what its own count means in seconds.
    public let giveUpAfterProbes: Int

    public init(giveUpAfterProbes: Int = 30) {
        self.state = .idle
        self.probes = 0
        self.giveUpAfterProbes = max(1, giveUpAfterProbes)
    }

    /// Whether the window should be drawing the applying treatment. This is the
    /// value `AgentRecovery.decide(applying:)` takes, and the only reason this
    /// type exists.
    public var isApplying: Bool { state == .applying }

    /// A restart has been asked for.
    public mutating func begin() {
        state = .applying
        probes = 0
    }

    /// One probe landed. Returns the state it left the watch in.
    ///
    /// Probes arriving when no restart is in flight are ignored rather than
    /// counted: the polling timer runs for the app's whole life, and a watch that
    /// counted every tick would abandon a restart that had not started.
    @discardableResult
    public mutating func observed(reachable: Bool) -> State {
        guard state == .applying else { return state }
        probes += 1
        if reachable {
            state = .settled
        } else if probes >= giveUpAfterProbes {
            state = .abandoned
        }
        return state
    }

    /// Put the watch back to rest without judging the restart — for a window that
    /// is going away, or a caller that has decided the question another way.
    public mutating func cancel() {
        state = .idle
        probes = 0
    }
}
