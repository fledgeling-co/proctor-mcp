import Foundation

// Whether Proctor's own overlays are excluded from screen captures.
//
// The Run HUD and the takeover tint set `sharingType = .none`, so evidence does
// not change because somebody was watching. That guarantee also means the panels
// cannot be photographed at all, by anything: measured on macOS 26, window-scoped
// ScreenCaptureKit delivers no frame, `screencapture -l` exits 1 with "could not
// create image from window", a region capture of the rect returns what is behind
// the panel, and the same refusal holds for the process that owns the window.
//
// So a campaign can check that the panels reach the display server, and can check
// that they stay out of a capture of the app under test, but cannot check what
// they render. This switch is the way to check that last property, and it is a
// capability rather than a drawing option: it is off unless somebody sets it, and
// turning it on weakens the guarantee for as long as it is on.
public enum OverlayCapture {

    /// Read at each panel's construction, so a change needs a fresh agent.
    public static let variable = "PROCTOR_OVERLAY_CAPTURE"

    /// Whether the exclusion has been lifted. Off for anything unset, empty or
    /// not affirmative, so the guarantee is what a machine has unless a person
    /// went and asked for the opposite.
    public static func lifted(in environment: [String: String] = ProctorEnvironment.current) -> Bool {
        SwitchResolver.isOn(environment[variable], for: SwitchCatalogue.overlayCapture)
    }

    /// What a panel should set. The name is the property rather than the switch,
    /// because every call site is asking the first question and not the second.
    public static func excludedFromCapture(
        in environment: [String: String] = ProctorEnvironment.current) -> Bool {
        !lifted(in: environment)
    }
}
