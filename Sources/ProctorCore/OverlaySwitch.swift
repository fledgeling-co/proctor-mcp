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

    /// Whether a surface that draws on this Mac may be raised.
    ///
    /// Two terms, and the second one is the whole of PRO-0075's defect: every
    /// switch above is on when the variable is absent, which is the right
    /// default for the agent and the wrong one for any other process that links
    /// the same code. A switch says what an operator asked for. It cannot say
    /// who is asking, and a process that is not the agent has not been asked to
    /// paint on anybody's screen.
    ///
    /// Kept here, as arithmetic over two facts, so the invariant has one home
    /// and a test rather than being three `&&`s that can each be forgotten
    /// separately — which is exactly how the missing one went unnoticed.
    public static func mayRaise(isAgent: Bool, switchedOn: Bool) -> Bool {
        isAgent && switchedOn
    }
}
