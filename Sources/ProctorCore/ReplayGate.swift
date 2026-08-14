import Foundation

// Gating a replay, decision half. `act` and the two computer facades already pass
// through the policy gate and the redacting trail; a recorded flow replayed
// through `proctor_flow`, and the determinism instrument that replays one N
// times, did not. This file holds the parts of closing that gap which are pure:
// what a refusal says, what a tool calls itself in the trail, and what a repeated
// run does when the authority it started under stops being valid partway through.
//
// The rule that shapes all of it: a replay is judged on the application it is
// driving now, by the same decision function a live drive is judged by, and the
// only thing that distinguishes the entries it leaves behind is the name of the
// tool that drove them.

// MARK: - Tool names in the trail

/// The names the audit trail knows the drive paths by. A trail that cannot tell a
/// replay from a live action cannot answer "who did this", so each path names
/// itself distinctly, following the `tool.subaction` form `proctor_apps.activate`
/// already established for a tool's sub-actions.
public enum AuditTool {
    /// A live drive through `proctor_act`.
    public static let act = "proctor_act"
    /// Activating an application — app-scoped, so it has no window to key on.
    public static let appsActivate = "proctor_apps.activate"
    /// One replay of a recorded flow through `proctor_flow` action "replay".
    public static let flowReplay = "proctor_flow.replay"
    /// One measured repeat inside a `proctor_stability` run.
    public static let stabilityReplay = "proctor_stability.replay"
    /// The reset sequence a stability run interposes between repeats. It drives
    /// the app exactly as a replayed step does, so it is gated and recorded like
    /// one — and named apart so the trail shows which steps were the measurement
    /// and which were putting the app back.
    public static let stabilityReset = "proctor_stability.reset"

    /// Every drive path, for the "these are distinct" property.
    public static let all: [String] = [act, appsActivate, flowReplay,
                                       stabilityReplay, stabilityReset]
}

// MARK: - Refusal text

/// What a caller is told when the gate refuses, and what to do about it. Lifted
/// out of the agent so every gated path — live drive, replay, determinism run,
/// the reset between repeats — emits the identical reason and remedy. The tool
/// name in the audit record is then the only thing that differs between them,
/// which is what makes the trail useful without making the refusal a new thing to
/// learn per tool.
public struct PolicyRefusal: Sendable, Equatable {
    public let reason: String
    public let remedy: String

    public init(reason: String, remedy: String) {
        self.reason = reason
        self.remedy = remedy
    }
}

public extension PolicyDecision {
    /// Nil when the decision permits the action; otherwise the reason and the
    /// remedy that go with it.
    var refusal: PolicyRefusal? {
        switch self {
        case .allow:
            return nil
        case .blocked(let reason):
            return PolicyRefusal(
                reason: reason,
                remedy: "Remove the app from the block list with proctor_policy action "
                      + "\"configure\", or drive a different application.")
        case .needsApproval(let reason):
            return PolicyRefusal(
                reason: reason,
                remedy: "Mint an approval token with proctor_policy action \"approve\" "
                      + "(optionally scoped to this bundle id), then retry within its TTL.")
        }
    }
}

// MARK: - The repeated-run gate

/// What a replay-driving tool does with a gate decision, given how much of the
/// run has already happened.
public enum ReplayGate {

    public enum Verdict: Sendable, Equatable {
        /// Permitted: run this repeat.
        case proceed
        /// Refused before anything ran. The call fails and reports no numbers —
        /// there is nothing to report, and a report of zero repeats reads as a
        /// measurement rather than a refusal.
        case refuseRun(PolicyRefusal)
        /// Refused partway through. The run stops here and keeps what it measured:
        /// a TTL-bounded approval that expires between repeats must actually
        /// expire, and there is nobody to ask for a fresh one mid-run.
        case stopRun(PolicyRefusal)
    }

    /// The verdict for one repeat. `completedRuns` is how many repeats have
    /// already finished, which is the whole of what separates "refuse the call"
    /// from "stop and report what we have".
    public static func verdict(for decision: PolicyDecision, completedRuns: Int) -> Verdict {
        guard let refusal = decision.refusal else { return .proceed }
        return completedRuns > 0 ? .stopRun(refusal) : .refuseRun(refusal)
    }

    /// The note that marks a report as measured on fewer repeats than were asked
    /// for, and says why. It carries the refusal reason so the report answers
    /// "why did this stop" without a second lookup in the trail.
    public static func earlyStopNote(completedRuns: Int, requestedRuns: Int,
                                     reason: String) -> String {
        "The run stopped after \(completedRuns) of \(requestedRuns) repeats because permission "
        + "to drive the application was withdrawn between repeats: \(reason) Every number below "
        + "was measured on the \(completedRuns) repeats that completed."
    }
}
