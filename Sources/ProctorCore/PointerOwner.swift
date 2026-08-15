import Foundation

// PRO-0046. Which of two pointers draws.
//
// Proctor draws a pointer in the target window's own z-order while a run acts
// (PRO-0025), and a delegated driver draws an agent cursor of its own. Two
// cursors on one screen is worse than either: they annotate the same action in
// two places, and a reader has no way to tell which one the machine is following.
//
// PROCTOR'S IS PREFERRED, on three grounds that are properties of the code
// rather than taste. It is drawn in the target window's z-order, so a window
// stacked above the target occludes it. It is excluded from evidence — the
// invariant in `CursorOverlay`'s header — where another process's window is not
// something Proctor can exclude from anything. And it is the one
// `PROCTOR_CURSOR=0` switches off.
//
// BUT THE GUARANTEE IS SEPARATE FROM THE PREFERENCE, and that is the whole shape
// of this decision. "Never two" is not achievable by choosing the driver's:
// Proctor would be relying on a request to another process to suppress its own
// drawing, and an unhonoured request leaves two on screen. It is achievable by
// being willing to switch Proctor's own off, which Proctor can do with
// certainty. So the fallback is the one Proctor can enforce.
//
// THE SECOND CASE IS NAMED FOR WHAT PROCTOR KNOWS. A driver that reports no
// cursor control and then draws nothing leaves the step unannotated — the cheaper
// of the two failures, and the same call PRO-0025 already made when it chose to
// hide rather than dim a pointer whose target was off screen: hiding loses
// nothing, because the HUD still says what is happening. Calling that case
// "the driver drew" would state a fact Proctor never observed.
public enum PointerOwner: String, Sendable, Equatable, Codable, CaseIterable {
    /// Proctor draws, as it always has.
    case proctor
    /// Proctor stands down. Whether anything is then drawn is the driver's, and
    /// is not something Proctor can see.
    case deferredToDriver
}

public enum PointerOwnership {

    /// Decided ONCE PER RUN, from that run's own backend, and held on the run.
    ///
    /// Not consulted per step from a process-wide value: two runs on different
    /// applications genuinely overlap — `RunQueuePlan.grantable` starts an entry
    /// whose lanes are disjoint from what is busy — so a machine-wide decision
    /// would flip between a native run's step and a delegated one's.
    ///
    /// `driverSuppressible` is what the installed build said it can do, and it
    /// fails closed: a build that reports nothing counts as unable, so Proctor
    /// stands down rather than risking two.
    public static func decide(delegated: Bool, driverSuppressible: Bool) -> PointerOwner {
        guard delegated else { return .proctor }
        return driverSuppressible ? .proctor : .deferredToDriver
    }
}
