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

        /// The SF Symbol the hero row draws beside the name.
        ///
        /// PRO-0090. A symbol name returned from a computed property is one the
        /// literal classifier cannot see as an identifier, because it never
        /// reaches a `systemName:` label — the same case PRO-0081 met with
        /// `StatusChecks.ToolRow.Tone.symbol`, and resolved the same way: the
        /// mapping lives beside the value it describes.
        public var glyph: String {
            switch self {
            case .accessibility: return "accessibility"
            case .screenRecording: return "display"
            }
        }

        /// What the hero row says under the name.
        ///
        /// Not a paraphrase of `why`, and both are kept rather than one deleted.
        /// `why` is the status window's longer sentence about what the grant
        /// buys; this is the walkthrough's shorter one about what Proctor does
        /// with it, and it is what the build has always rendered. Naming each
        /// for where it is drawn is what stops the pair becoming DEF-035 again.
        public var rowDescription: String {
            switch self {
            case .accessibility: return "Lets Proctor read the control tree and drive it"
            case .screenRecording: return "Lets Proctor see what your app drew"
            }
        }

        /// What a screen reader hears on the row's own button, where "Allow"
        /// alone would be one of two identical labels on one screen.
        public var allowLabel: String { "\(WalkthroughFlow.Copy.allow) \(title)" }

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

    /// Whether the primary action may be pressed.
    ///
    /// PRO-0081, closing PRO-0067's carried A3. That clause reads *the disabled
    /// next button is present in the tree in every state where it is disabled* —
    /// and until this function existed there was no such state, because nothing
    /// in the flow ever disabled it. A clause asked over an empty set reads green
    /// and has measured nothing, which is the shape of failure this campaign
    /// exists to remove.
    ///
    /// The design of record settles what the rule is rather than this deciding
    /// it: `design/surfaces/proctor-surfaces.html`, the `walkthrough` surface's
    /// `permissions` pane, draws `Connect a model` disabled while a grant is
    /// missing, captioned *"Continue is disabled and visible rather than absent
    /// — a control that disappears makes the layout jump and teaches the user
    /// the step does not exist."*
    ///
    /// `permissions` is the only step that can refuse, and it refuses only while
    /// a grant is missing. `Skip setup` sits beside it and is never disabled, so
    /// a person macOS will not grant to is never trapped — the flow declines to
    /// pretend the grants landed, it does not hold the door shut.
    public static func primaryEnabled(on step: Step,
                                      accessibility: Bool,
                                      screenRecording: Bool) -> Bool {
        guard step == .permissions else { return true }
        return accessibility && screenRecording
    }

    /// Which grant's button is drawn prominent, or nil when none should be.
    ///
    /// PRO-0090, closing DEF-056. The design of record states the rule in the
    /// permissions frame's own caption: *"Only one Grant is prominent at a time:
    /// the one to press next"* (`design/surfaces/proctor-surfaces.html`,
    /// walkthrough, `data-state="permissions"`), and draws Accessibility's Grant
    /// filled with Screen Recording's plain. The build gave every ungranted row
    /// `.borderedProminent` unconditionally, so with neither grant held — the
    /// state the walkthrough opens in — the frame offered two identical calls to
    /// action and no first move.
    ///
    /// THIS IS A DECISION THAT DID NOT EXIST IN THE VIEW BEFORE. It is not one
    /// lifted out of a view body, which is the widening PRO-0081's carried
    /// clause warns against; it is a new rule, and a rule about which of two rows
    /// is prominent cannot be asked of a repo with no `ProctorUI` test target
    /// unless it is a value. Same footing as `primaryEnabled`.
    ///
    /// Order is `Grant.allCases`, so the answer is the first grant still
    /// missing. That is what "the one to press next" means when both are
    /// missing, and it matches the pane the design draws.
    public static func prominentGrant(accessibility: Bool,
                                      screenRecording: Bool) -> Grant? {
        let held: [Grant: Bool] = [.accessibility: accessibility,
                                   .screenRecording: screenRecording]
        return Grant.allCases.first { held[$0] == false }
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

    /// The title drawn above a step's content, or empty where the step's own
    /// content carries it.
    ///
    /// PRO-0090. A copy table keyed by step, beside the three that already live
    /// here — `primaryAction`, `heading` and `lede`. `permissions` and `granted`
    /// return empty because the hero sheet draws its own title, and an empty
    /// string here is what the view already tested for.
    public static func stepTitle(for step: Step) -> String {
        switch step {
        case .intro: return "What Proctor does"
        case .permissions, .granted: return ""
        case .connect: return "Point a model at it"
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
        /// The short form of the MCP host config, written by PRO-0067 and never
        /// rendered: the walkthrough draws the full object, which is
        /// `StatusSurface.Copy.connectSnippet(shimPath:)` and is the same text
        /// the status window's Connect card copies. Both kept and both named, as
        /// with `StatusSurface.Copy.toolsNote`. DEF-035.
        public static let connectSnippet = #"{ "proctor": { "command": "proctor-shim" } }"#

        // MARK: - PRO-0090. What the walkthrough draws, moved out of the view.
        //
        // Every string below moved character for character from
        // `Sources/ProctorUI/Walkthrough.swift`. No wording changed: wave 9
        // settled this surface's composition and DEF-039 is a move, not a
        // rewrite.

        public static let introParagraph1 =
            "Proctor lets a model test a Mac app the way a person would check it: read what "
            + "is actually on screen, operate the controls, and look at what the app drew."
        public static let introParagraph2 =
            "It works through macOS's accessibility system rather than by faking mouse and "
            + "keyboard input, so it can drive a window that is behind another one, or on "
            + "another Space, without stealing your focus or interrupting what you are doing."
        /// Character-identical to `heading(for: .permissions)` and deliberately a
        /// constant of its own: the intro's callout and the permissions step's
        /// heading say the same thing today because they are about the same two
        /// grants, and binding one to the other would make a later edit to either
        /// silently change the other.
        public static let introCalloutTitle = "Two permissions, asked once"
        public static let introCalloutMessage =
            "macOS gives these to Proctor itself, not to the tool driving it. That is "
            + "why they survive when you upgrade or switch the model you use."
        public static let introCalloutIcon = "lock.shield"

        public static let connectParagraph =
            "Last step. Add Proctor to whichever tool you drive it from. The command below "
            + "holds no permissions of its own; it just forwards to Proctor, which does."
        public static let connectReadyTitle = "You're all set"
        public static let connectReadyMessage =
            "Both permissions are granted. Proctor stays running in the "
            + "background and lives in the menu bar — no Dock icon. Open Proctor "
            + "Status any time to re-check, see attached apps, or copy this again."
        public static let connectReadyIcon = "checkmark.seal.fill"
        public static let connectPendingTitle = "Proctor lives in the menu bar"
        public static let connectPendingMessage =
            "It stays running in the background — no Dock icon, because it is "
            + "something a model drives. You can grant the remaining permission any "
            + "time from Proctor Status."
        public static let copyConfig = "Copy config"

        public static let heroTitle = "Enable Proctor"
        public static let heroLede =
            "Proctor needs two macOS permissions to read and drive your apps. They go to "
            + "Proctor itself, asked once, and are used only when a model you connect asks "
            + "it to run a test."
        public static let openSettings = "Already allowed? Open System Settings"
        public static let allowed = "Allowed"
        /// The build's label on an ungranted row's button. `grant` above is the
        /// design of record's word for the same control and the window has never
        /// rendered it; both kept and both named, as with `toolsNote`. DEF-035.
        public static let allow = "Allow"
        public static let grantedCheckSymbol = "checkmark.circle.fill"
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
