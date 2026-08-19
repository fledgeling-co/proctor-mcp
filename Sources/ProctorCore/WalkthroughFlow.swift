import Foundation

// PRO-0067. The first-run flow, as a value.
//
// The step a person is on is a decision about two grants and whether they have
// read the intro, and this repo cannot test a decision made in a view body. So
// the rule lives here, tested at all eight combinations, and `Walkthrough` reads
// it.
//
// The state the shipped flow was missing is the third one: the moment a grant
// lands, played back on its own row before the step advances. Somebody who
// clicked Grant, met a macOS dialog and came back to a window that had simply
// moved on has no evidence their click did anything — and the grant they just
// gave is the hardest thing in this app to give again.

public enum WalkthroughFlow {

    public enum Step: String, Sendable, CaseIterable {
        /// What Proctor is. Auto-advance is armed only after this step, so the
        /// flow can never skip the one that explains the app.
        case intro
        /// The two grants as one sheet, each asking macOS for the real dialog.
        case permissions
        /// Both landed, each played back on its row.
        case granted
        /// The snippet, a copy button, and where Proctor lives from here.
        case connect
    }

    /// A grant, as this flow needs to know it.
    public enum Grant: String, Sendable, CaseIterable {
        case accessibility, screenRecording

        public var title: String {
            switch self {
            case .accessibility: return "Accessibility"
            case .screenRecording: return "Screen Recording"
            }
        }

        public var why: String {
            switch self {
            case .accessibility:
                return "Read the tree, and write to it. Without it, every tree comes back empty."
            case .screenRecording:
                return "Window pixels, and the frame status that says whether they are fresh."
            }
        }

        /// macOS caches the Screen Recording answer per process through
        /// `SCShareableContent` for that process's life, so a grant given now is
        /// not visible to this process until it restarts. PRO-0028 and PRO-0041
        /// both hit this. The row states the fact whether or not the restart is
        /// offered, because the fact is true either way and the offer is gated
        /// on evidence that may not arrive.
        public var needsRestart: Bool { self == .screenRecording }
    }

    /// Which step the flow is on.
    ///
    /// Pure, and tested at all eight combinations of its three inputs. The
    /// `introSeen` guard is the one that matters: without it a machine that
    /// already has both grants opens the flow on `connect` and the person never
    /// learns what they installed.
    public static func step(introSeen: Bool,
                            accessibility: Bool,
                            screenRecording: Bool) -> Step {
        guard introSeen else { return .intro }
        if accessibility && screenRecording { return .granted }
        return .permissions
    }

    /// Whether the flow may move on by itself.
    ///
    /// Only from `granted`, and only once both grants are in. Auto-advancing out
    /// of `intro` would skip the explanation; auto-advancing out of
    /// `permissions` would move while a grant is still missing.
    public static func advancesAutomatically(from step: Step,
                                             accessibility: Bool,
                                             screenRecording: Bool) -> Bool {
        step == .granted && accessibility && screenRecording
    }

    /// The step after this one, or nil at the end.
    public static func next(after step: Step) -> Step? {
        switch step {
        case .intro: return .permissions
        case .permissions: return .granted
        case .granted: return .connect
        case .connect: return nil
        }
    }

    // MARK: - Copy
    //
    // A primary button names its outcome. "Continue" predicts nothing, which is
    // what a screen reader reads out of context, and this flow used to say it
    // three times.

    public static func primaryAction(for step: Step) -> String {
        switch step {
        case .intro: return "Set up permissions"
        case .permissions, .granted: return "Connect a model"
        case .connect: return "Done"
        }
    }

    public static func heading(for step: Step) -> String {
        switch step {
        case .intro: return "A model can test this Mac"
        case .permissions, .granted: return "Two permissions, asked once"
        case .connect: return "You’re all set"
        }
    }

    public static func lede(for step: Step) -> String {
        switch step {
        case .intro:
            return "Proctor reads what is actually on screen, drives the controls, and checks "
                 + "what the app rendered — then records how it knew."
        case .permissions, .granted:
            return "macOS holds these, not Proctor. Granting them here asks the system directly."
        case .connect:
            return "Point a model at Proctor with this. It speaks MCP over stdio and holds no "
                 + "permissions of its own."
        }
    }

    public enum Copy {
        public static let skip = "Skip setup"
        public static let back = "Back"
        public static let grant = "Grant"
        public static let copy = "Copy"
        public static let openGuide = "Open the guide"
        public static let advancing = "Moving on…"
        public static let restartNote =
            "Screen Recording needs Proctor to restart before it takes effect. Proctor will say "
            + "so when it lands."
        public static let menuBarNote =
            "Proctor lives in the menu bar from here. The window is always one click away from "
            + "the icon."
        public static let connectSnippet = #"{ "proctor": { "command": "proctor-shim" } }"#
    }

    // MARK: - Identifiers

    public enum ID {
        public static func step(_ s: Step) -> String { "proctor.walkthrough.\(s.rawValue)" }
        public static func grantRow(_ g: Grant) -> String { "proctor.walkthrough.grant.\(g.rawValue)" }
        public static func grantButton(_ g: Grant) -> String {
            "proctor.walkthrough.grant.\(g.rawValue).action"
        }
        public static let primary = "proctor.walkthrough.action.primary"
        public static let skip = "proctor.walkthrough.action.skip"
        public static let back = "proctor.walkthrough.action.back"
        public static let copySnippet = "proctor.walkthrough.action.copy"

        public static var all: [String] {
            var out = [primary, skip, back, copySnippet]
            out += Step.allCases.map(step)
            out += Grant.allCases.map(grantRow)
            out += Grant.allCases.map(grantButton)
            return out
        }
    }

    /// Completing and skipping reach the same terminal state.
    ///
    /// Skipping *is* completing, and that is deliberate rather than accidental:
    /// the alternative is a window that reappears at every launch for somebody
    /// who has already decided against it. The campaign observed
    /// `walkthroughCompleted` set by Skip setup and this makes it a rule.
    public static let completionDefaultsKey = "walkthroughCompleted"
    public static func completes(_ exit: Exit) -> Bool { true }

    public enum Exit: String, Sendable, CaseIterable { case finished, skipped }
}
