import Foundation

// PRO-0069. What the run panel shows in each of its seven states.
//
// The panel is the most-shipped surface in the app and the one a person is
// actually looking at while a run happens. What the mock added is the
// **provenance chip** — the plane a step travelled and the route within it, on
// the panel itself.
//
// It matters most here for a reason the rest of the product already knows: a
// step that went through the accessibility plane in the background and a step
// that went through the shared event stream with the machine taken prove
// different things, and "Typing into Search in Mail" reads identically either
// way. `docs/architecture.md`: never collapse the two into a single "it worked".
//
// Everything here is pure. The panel is drawn by the *agent* process, so a fault
// in it takes the run and the MCP server with it — which is why `ProctorCatch`
// exists and why as little as possible of this surface is drawing code.

public enum RunHUDSurface {

    /// Which controls a phase offers.
    ///
    /// Stop appears in every phase that has a run to stop. `idle` offers
    /// nothing, because a control that does nothing is worse than an absent one
    /// on a panel whose whole job is to say what is going on.
    public static func controls(for phase: RunHUDPhase) -> [RunHUDControl] {
        switch phase {
        case .idle:
            return []
        case .travelling, .acting:
            return [.pause, .stop]
        case .blocked:
            return [.stop]
        case .paused:
            return [.resume, .stop]
        case .finished, .error:
            return []
        }
    }

    /// Whether a phase has a run that Stop would act on.
    public static func hasStoppableRun(_ phase: RunHUDPhase) -> Bool {
        controls(for: phase).contains(.stop)
    }

    /// The SF Symbol for a phase.
    ///
    /// The mock draws its glyphs as inline SVG because a self-contained HTML
    /// file cannot bundle SF Symbols; the app uses real ones. Named here and
    /// tested for presence, so a typo is a red test rather than a blank panel.
    ///
    /// Each phase's symbol differs in *shape*, not only in tint, because the
    /// panel's tone already carries colour and colour alone fails a greyscale
    /// display and 8% of men.
    public static func symbol(for phase: RunHUDPhase) -> String {
        switch phase {
        case .idle: return "moon.zzz"
        case .travelling: return "figure.walk"
        case .acting: return "cursorarrow.rays"
        case .blocked: return "hourglass"
        case .paused: return "pause.circle"
        case .finished: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    /// What the chip carries in a given phase.
    ///
    /// `nil` where the phase has no plane to report: an idle panel has no step,
    /// and inventing a chip for it would be the panel asserting provenance for
    /// something that never happened.
    public struct Chip: Sendable, Equatable {
        public let fields: [(String, String)]

        public init(_ fields: [(String, String)]) { self.fields = fields }

        public static func == (a: Chip, b: Chip) -> Bool {
            a.fields.count == b.fields.count
                && zip(a.fields, b.fields).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
    }

    /// Build the chip from what the step actually reported.
    ///
    /// Every value is passed in. Nothing here infers a plane from a step kind,
    /// because the plane is a property of the backend that performed it rather
    /// than of the verb that was asked for — `.click` is a synthetic post on
    /// Proctor's own actuator and a routed event on a delegated one, and a panel
    /// that guessed would describe a delegated run as having taken the machine.
    public static func chip(plane: String?, route: String?, machine: String?) -> Chip? {
        var fields: [(String, String)] = []
        if let plane { fields.append(("plane", plane)) }
        if let route { fields.append(("route", route)) }
        if let machine { fields.append(("on", machine)) }
        return fields.isEmpty ? nil : Chip(fields)
    }

    /// Whether a phase's chip may describe the run as background-safe.
    ///
    /// `routedEvent` is background-safe and `unknown` is not, and neither is the
    /// accessibility plane's business. A run holding `unknown` was performed
    /// through a delivery mode this build does not recognise, so nothing here
    /// can say how the machine was driven.
    public static func isBackgroundSafe(plane: String?) -> Bool {
        switch plane {
        case "accessibility", "declared", "appleEvents", "routedEvent":
            return true
        case "syntheticEvent", "unknown", .none:
            return false
        default:
            // A plane this build has not seen is not assumed safe.
            return false
        }
    }

    public enum ID {
        public static func panel(_ phase: RunHUDPhase) -> String { "proctor.hud.\(phase.rawValue)" }
        public static func control(_ c: RunHUDControl) -> String { "proctor.hud.control.\(c.rawValue)" }
        public static let chip = "proctor.hud.chip"
        public static let step = "proctor.hud.step"
    }
}
