import Foundation

// The menu's one action when something is wrong with the agent, and nothing
// otherwise.
//
// This replaced a menu row labelled "Re-check now". It called the model's
// refresh — the doctor call and the activity call, run immediately — and the
// argument for keeping it was the permission moment: a grant made in System
// Settings, in another application, that macOS never tells a running app about.
//
// MEASURED, 2026-08-15: the same doctor refresh is already on a 2-second
// repeating timer that starts with the model and runs for the app's whole life,
// window open or closed. So the button advanced a read by about two seconds — and
// for the grant it was defended for, it advanced nothing at all.
//
// Accessibility is probed with AXIsProcessTrusted(), which reads live, so the
// poll sees a grant made in Settings on its next tick. Screen Recording is probed
// by asking ScreenCaptureKit for shareable content and reading the failure, and
// macOS caches that answer PER PROCESS FOR THE LIFE OF THAT PROCESS. The agent is
// long-lived. Once it has been told no it keeps being told no, and the poll and
// the button ask that same process. This app already relies on the fact: granting
// through Proctor's own dialog calls `reprobeAfterGrant`, which kickstarts the
// agent so it re-probes. That path exists precisely because a running agent
// cannot be told.
//
// So the row is gone, and its slot carries the two actions that actually resolve
// the two states where the menu had nothing to offer.
//
// SCREEN RECORDING SPECIFICALLY, not "a required grant is missing". A missing
// Accessibility grant does not need a restart — the poll picks it up — and
// offering a SIGKILL for it would drop a run in flight to fix nothing.
//
// AND ONLY WHEN THIS PROCESS CAN SEE THE GRANT ITSELF. A first draft offered the
// restart whenever the agent reported Screen Recording ungranted, with a sentence
// hedged on "if you have just granted it". The out-of-family critic was right
// about what that ships: every install that has not granted Screen Recording, and
// is not going to, gets a permanent row whose button cannot create a grant. A
// restart is the cure for a stale answer, not for an absent permission, so the
// offer now requires independent evidence that the permission is there —
// `CGPreflightScreenCaptureAccess()` in the window's own process, which reads the
// same TCC record because `build-app.sh` signs every nested binary with `-i
// $BUNDLE_ID` (verified on the installed bundle: `Proctor` and `proctor-agent`
// both report `Identifier=app.fledgeling.procter`).
//
// The cost of that gate, accepted knowingly: if `CGPreflightScreenCaptureAccess`
// caches per process the way its ScreenCaptureKit neighbour does, a window that
// was running before the grant will agree with the agent and the offer will never
// appear. That is bounded — the same restart is one row below, through Proctor
// Status… — where a permanent nag on every ungranted Mac is not.
public enum AgentRecovery {

    public enum Kind: Equatable, Sendable {
        /// The agent is not answering. Bring it back.
        case startAgent
        /// The agent is answering and holding a Screen Recording denial that is no
        /// longer true. Only a fresh process can re-probe.
        case restartAgent
    }

    /// A sentence saying what is wrong, and the button that fixes it.
    public struct Offer: Equatable, Sendable {
        public let kind: Kind
        public let reason: String
        public let action: String

        public init(kind: Kind, reason: String, action: String) {
            self.kind = kind
            self.reason = reason
            self.action = action
        }
    }

    /// Button titles, in the register of their neighbours — `Relaunch Proctor`,
    /// `Quit Proctor`, `Stop Run`, `Pause Run`.
    public static let startAction = "Start Agent"
    public static let restartAction = "Restart Agent"

    /// What the menu should offer, if anything.
    ///
    /// - Parameters:
    ///   - applying: a restart is already in flight. Checked first and above
    ///     everything, because during it the agent is legitimately unreachable:
    ///     without this the menu would offer to start an agent that is coming
    ///     back on its own, and a second click would stack a second SIGKILL on a
    ///     process mid-launch.
    ///   - reachable: whether the agent answered at all.
    ///   - agentSeesScreenRecording: what the agent's own doctor report says. This
    ///     is the cached answer; that is the whole point. Tri-state since PRO-0041:
    ///     `denied` is macOS having said no, `unconfirmed` is macOS not having
    ///     answered the bounded probe at all. Both offer the restart when this
    ///     window can see the grant — a fresh process is the cure for either — but
    ///     they must not share a sentence, because one of them claims the agent is
    ///     reading an earlier answer and in the other case there was no answer to
    ///     read.
    ///   - windowSeesScreenRecording: this process's own live, non-prompting read
    ///     of the same TCC record, or nil when it could not be taken. Required to
    ///     be `true` before any restart is offered — see the note above.
    ///   - runInFlight: whether a run is going. A run CAN be live with Screen
    ///     Recording denied, because the accessibility plane still works, and the
    ///     restart is `launchctl kickstart -k`, a SIGKILL that drops it. So the
    ///     cost is stated in the sentence. Not a confirmation sheet: a menu is a
    ///     poor place to confirm anything, and the run at risk is one that cannot
    ///     capture. This arrives on the 0.5s activity poll, the faster of the two
    ///     cadences feeding this, so it is the fresher input rather than the
    ///     staler one.
    public static func decide(applying: Bool,
                              reachable: Bool,
                              agentSeesScreenRecording: GrantState,
                              windowSeesScreenRecording: Bool?,
                              runInFlight: Bool) -> Offer? {
        if applying { return nil }

        guard reachable else {
            // Removing "Re-check now" would otherwise have left the menu with
            // nothing to do about a wedged agent — and the old row's refresh was
            // never the cure for that either. The window has had a working Start
            // all along; this is the same one, on the surface people actually
            // reach for.
            return Offer(
                kind: .startAgent,
                reason: "Proctor's agent is not answering. Nothing can run until it is back.",
                action: startAction)
        }

        guard !agentSeesScreenRecording.isConfirmedGranted,
              windowSeesScreenRecording == true else { return nil }

        var reason = agentSeesScreenRecording == .unconfirmed
            ? "Screen Recording is granted, but the agent's check for it did not come back."
            : "Screen Recording is granted, but the agent is still reading macOS's earlier answer."
        if runInFlight { reason += " Restarting stops the run in flight." }
        return Offer(kind: .restartAgent, reason: reason, action: restartAction)
    }
}
