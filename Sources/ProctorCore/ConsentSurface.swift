import Foundation

// PRO-0072. The sheets that stand in front of the two switches that hand
// something away, and the one rule that governs all of them.
//
// `SwitchCatalogue` already carries `requiresConsent` and `pairingWarning` as
// tested pure values, and nothing renders them: the disclosure exists with no
// surface. This is where a sheet reads it.
//
// **Turning a capability ON asks; turning it OFF never does.** A person
// withdrawing a capability must not be argued with, and the asymmetry mirrors
// the defaults' — drawing switches start on, capabilities start off, and off
// wins from either source.

public enum ConsentSurface {

    public enum Sheet: String, Sendable, CaseIterable {
        /// The event tap that swallows a person's own keyboard and mouse.
        case holdInput
        /// The capability is going on while the notice that would explain it is off.
        case pairing
        /// Naming an autonomous browser agent to a model.
        case secondLane
        /// Unlocking the screen for a bounded turn.
        case unlock
    }

    /// Whether flipping a switch raises a sheet.
    ///
    /// Direction is the whole of it. `SwitchCatalogue.requiresConsent` says
    /// which switches hand something away; this says a sheet appears only on the
    /// way in.
    public static func raisesSheet(_ s: ProctorSwitch, turningOn: Bool) -> Bool {
        turningOn && s.requiresConsent
    }

    /// The pairing sheet's condition: a capability going on while the drawing
    /// switch that announces it is off.
    ///
    /// Holding somebody's keyboard with the takeover notice switched off is a
    /// Mac that stops responding with nothing on screen explaining why.
    public static func raisesPairingSheet(capabilityOn: Bool, announcesOn: Bool) -> Bool {
        capabilityOn && !announcesOn
    }

    /// Which action a sheet leads with.
    ///
    /// For the pairing sheet the prominent action is the **recovery** — turn the
    /// notice back on — and the risky path stays available and unfilled. A
    /// prominent button on the risky path is a sheet that argues for the thing
    /// it is supposed to be disclosing.
    public static func prominentAction(for sheet: Sheet) -> String {
        switch sheet {
        case .holdInput: return "Hold my input"
        case .pairing: return "Turn the notice back on"
        case .secondLane: return "Let Proctor name it"
        case .unlock: return "Allow for 2 minutes"
        }
    }

    /// The unfilled alternatives, in order. `Cancel` leads on every sheet.
    public static func secondaryActions(for sheet: Sheet) -> [String] {
        switch sheet {
        case .pairing: return ["Cancel", "Hold input anyway"]
        case .unlock: return ["Deny"]
        default: return ["Cancel"]
        }
    }

    /// What each sheet discloses. The consequence comes first; the mechanism is
    /// named honestly rather than softened, because a sheet that reads as a
    /// formality produces consent that is one.
    public static func disclosure(for sheet: Sheet) -> String {
        switch sheet {
        case .holdInput:
            return "This is the same mechanism a keylogger uses, on the Accessibility grant "
                 + "Proctor already holds. Two things stay true whatever happens: Stop always "
                 + "works, and the block never survives the process."
        case .pairing:
            return "Your keyboard and mouse will be held while Proctor acts, and nothing on "
                 + "screen will say why. The Mac will simply stop responding."
        case .secondLane:
            return "browser-use is an autonomous agent. Its default local mode drives a real "
                 + "browser with your real logins, and nothing it does reaches Proctor's audit "
                 + "trail."
        case .unlock:
            return "A short turn opens, macOS evaluates the unlock right, and Proctor relocks "
                 + "when the turn ends or you touch the machine. The login window stays "
                 + "available, so you are never locked out."
        }
    }

    /// When a sheet's decision takes effect.
    ///
    /// Stated on the sheet, because otherwise a person presses the button, sees
    /// nothing change, and presses it again.
    public static func timing(for sheet: Sheet) -> String {
        switch sheet {
        case .unlock: return "Takes effect now, for this turn only."
        default: return "Applies at the next agent start."
        }
    }

    /// No sheet ships a shell command.
    ///
    /// The same rule the browser handoff already holds: a command in a surface a
    /// model can read is a command a model will run, and this process holds
    /// Accessibility and Screen Recording.
    public static func containsShellCommand(_ text: String) -> Bool {
        let markers = ["curl ", "sh -c", "brew install", "npm i", "pip install",
                       "sudo ", "| sh", "wget ", "$(", "`"]
        return markers.contains { text.contains($0) }
    }

    public enum ID {
        public static func sheet(_ s: Sheet) -> String { "proctor.consent.\(s.rawValue)" }
        public static func prominent(_ s: Sheet) -> String { "proctor.consent.\(s.rawValue).primary" }
        public static func cancel(_ s: Sheet) -> String { "proctor.consent.\(s.rawValue).cancel" }
    }
}
