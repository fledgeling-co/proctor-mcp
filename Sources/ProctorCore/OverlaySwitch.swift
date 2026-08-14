import Foundation

// The shape of Proctor's drawing off-switches.
//
// Two things Proctor puts on screen can be turned off independently: the drawn
// pointer (`PROCTOR_CURSOR`) and the run HUD (`PROCTOR_HUD`). They are separate
// because someone may want one and not the other — an unattended suite may want
// no pointer over a machine in use but still want a stop button — and identical
// in shape because two switches that answered to different words would be a
// thing to remember rather than a thing to know.
//
// On by default. A run that draws nothing and can be halted by nobody is the
// state this is opting out of, so opting out has to be deliberate.
public enum OverlaySwitch {

    /// The values that mean off. Everything else, including an unset variable,
    /// means on.
    public static let offValues: Set<String> = ["0", "off", "false", "no"]

    /// Whether a raw environment value leaves the drawing on.
    public static func isOn(_ raw: String?) -> Bool {
        guard let raw else { return true }
        return !offValues.contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Read one of the switches out of an environment dictionary. Taking the
    /// environment as a parameter is what makes the reading testable; the call
    /// sites pass `ProcessInfo.processInfo.environment`.
    public static func isOn(_ name: String, in environment: [String: String]) -> Bool {
        isOn(environment[name])
    }
}
