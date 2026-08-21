import Foundation

// PRO-0029. The eight environment variables that change how a running agent
// behaves, as a value rather than as eight literals spread across seven files.
//
// **Why a catalogue at all.** The brief this item came from listed six switches.
// By the time it was built there were eight: PRO-0044 added `PROCTOR_ACTUATION`,
// PRO-0025 had already added `PROCTOR_TAKEOVER`, and `PROCTOR_SECOND_LANE` had
// stopped being a boolean and become a tool name. A document went stale because
// nothing tied it to the code. `SwitchCatalogueDriftTests` is what ties this one:
// it resolves through this catalogue and compares the answer against the original
// function at each call site, so a switch whose shape changes reddens the build
// rather than quietly disagreeing with a window.
//
// **Everything here is pure**, for the reason `StatusChecks` gives: `Package.swift`
// declares no `ProctorUI` test target and there is no window server under
// `swift test`, so a rule written in a view body is a rule this repo cannot prove.
//
// Out of scope, deliberately, and the spec carries the reasons: the numeric tuning
// variables, the policy and jail configuration, and the two `PROCTOR_CUA_ALLOW_*`
// preflight bypasses. A one-click bypass of a signature check does not belong in
// the same card as "show the pointer".

/// One switch's identity and shape.
public struct ProctorSwitch: Sendable, Equatable, Hashable {

    /// What kind of thing turning this on does, which is what decides both the
    /// precedence rule and whether the control can be locked.
    public enum Class: String, Sendable, Equatable {
        /// Something Proctor puts on the screen. On by default, because a run that
        /// draws nothing and can be halted by nobody is the state opting out is
        /// opting out of.
        case drawing
        /// A capability over the person's own machine that is never acquired
        /// unless somebody asks. Off by default, and — the part that matters —
        /// **off wins from either source**, so a person can always decline one.
        case capability
        /// Which code path a run takes. Off by default, and its value is a name
        /// rather than a boolean.
        case lane
    }

    /// When a change to this switch reaches the agent.
    public enum Timing: String, Sendable, Equatable {
        /// A control channel already exists and the change lands now.
        case live
        /// Read once per process. Changing it needs a fresh agent.
        case nextStart
    }

    public let variable: String
    public let kind: Class
    public let timing: Timing
    /// The value that turns a lane on. Nil for a boolean-shaped switch.
    public let onValue: String?
    /// A short label for the window.
    public let title: String
    /// One sentence saying what turning it on does.
    public let summary: String
    /// Whether turning this ON takes a second press, with the disclosure on
    /// screen above it.
    ///
    /// True for the two switches that hand something away: a person's own
    /// keyboard, and a browser holding their real logins. `PROCTOR_YIELD_INPUT`
    /// is deliberately NOT one — it observes input to notice a person sooner and
    /// intercepts nothing, so a confirmation there would train people to click
    /// through the two that matter.
    ///
    /// Turning any of them OFF never confirms. A person withdrawing a capability
    /// must not be argued with, and the asymmetry mirrors the defaults'.
    public let requiresConsent: Bool

    public var defaultOn: Bool { kind == .drawing }

    init(variable: String, kind: Class, timing: Timing, onValue: String? = nil,
         title: String, summary: String, requiresConsent: Bool = false) {
        self.variable = variable
        self.kind = kind
        self.timing = timing
        self.onValue = onValue
        self.title = title
        self.summary = summary
        self.requiresConsent = requiresConsent
    }
}

public enum SwitchCatalogue {

    public static let hud = ProctorSwitch(
        variable: "PROCTOR_HUD", kind: .drawing, timing: .live,
        title: "Run panel",
        summary: "The panel that says a run is happening and carries Pause and Stop.")

    public static let cursor = ProctorSwitch(
        variable: "PROCTOR_CURSOR", kind: .drawing, timing: .nextStart,
        title: "Drawn pointer",
        summary: "A pointer drawn where Proctor is about to act, so a step is visible "
               + "before it lands.")

    public static let takeover = ProctorSwitch(
        variable: "PROCTOR_TAKEOVER", kind: .drawing, timing: .nextStart,
        title: "Takeover notice",
        summary: "The tint and label saying Proctor is driving this Mac, on every display.")

    public static let yield = ProctorSwitch(
        variable: "PROCTOR_YIELD", kind: .drawing, timing: .nextStart,
        title: "Yield to a person",
        summary: "Pause a run when somebody starts using the machine.")

    public static let yieldInput = ProctorSwitch(
        variable: "PROCTOR_YIELD_INPUT", kind: .capability, timing: .nextStart,
        title: "Watch input to notice sooner",
        summary: "Observe keyboard and mouse events so a person is noticed at the first "
               + "keystroke rather than at the next window change.")

    public static let takeoverInput = ProctorSwitch(
        variable: "PROCTOR_TAKEOVER_INPUT", kind: .capability, timing: .nextStart,
        title: "Hold the keyboard and mouse",
        summary: "Create an event tap that swallows your own keyboard and mouse while "
               + "Proctor posts a step, so your typing cannot land in the app it is driving.",
        requiresConsent: true)

    public static let overlayCapture = ProctorSwitch(
        variable: OverlayCapture.variable, kind: .capability, timing: .nextStart,
        title: "Let captures see Proctor's overlays",
        summary: "Drop the run panel's and the takeover tint's exclusion from screen "
               + "captures, so a test can photograph what they draw. While this is on, "
               + "anything recording the screen sees them too.",
        requiresConsent: true)

    public static let secondLane = ProctorSwitch(
        variable: BrowserUseTool.laneVariable, kind: .lane, timing: .nextStart,
        onValue: BrowserUseTool.binary,
        title: "Second browser lane",
        summary: "Name browser-use to the model for pages Obscura cannot open.",
        requiresConsent: true)

    public static let actuation = ProctorSwitch(
        variable: CuaDriverTool.laneEnv, kind: .lane, timing: .nextStart,
        onValue: CuaDriverTool.laneValue,
        title: "Delegated actuation",
        summary: "Send clicks, typing and drags through cua-driver instead of Proctor's "
               + "own planes.")

    /// Every switch that gets a home, in the order the window draws them:
    /// what you see, then what Proctor may take, then which path a run runs on.
    public static let all: [ProctorSwitch] = [
        hud, cursor, takeover, yield,
        yieldInput, takeoverInput, overlayCapture,
        secondLane, actuation
    ]

    /// The two capability switches, which the precedence rule treats differently.
    public static var capabilities: [ProctorSwitch] { all.filter { $0.kind == .capability } }

    public static func named(_ variable: String) -> ProctorSwitch? {
        all.first { $0.variable == variable }
    }

    // MARK: - The pairings

    /// A capability switch and the drawing switch that would otherwise say it is
    /// happening. Holding somebody's keyboard with the takeover notice turned off
    /// is a Mac that stops responding for no stated reason.
    public static let pairings: [(capability: ProctorSwitch, announces: ProctorSwitch)] = [
        (takeoverInput, takeover),
        (yieldInput, yield)
    ]

    /// The warning for one pairing, or nil when the pair is not in the state that
    /// warrants one. Pure, and here rather than in the view, so the four
    /// combinations are testable.
    public static func pairingWarning(capabilityOn: Bool, announcesOn: Bool,
                                      capability: ProctorSwitch) -> String? {
        guard capabilityOn, !announcesOn else { return nil }
        if capability == takeoverInput {
            return "Your keyboard and mouse will be held while Proctor acts, and the notice "
                 + "that would say so is switched off. The Mac will stop responding with "
                 + "nothing on screen explaining why."
        }
        return "Proctor will watch your input to notice you, but will not pause the run when "
             + "it does. Watching without yielding is the cost of the capability with none "
             + "of its benefit."
    }
}
