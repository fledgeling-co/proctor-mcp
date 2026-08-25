import Foundation

/// Which steps address the application rather than one of its windows.
///
/// `proctor_act` resolves a window handle before any step runs, and a menu-bar
/// -only application has no windows to resolve. Measured 2026-08-25 against
/// Proctor's own app: `proctor_menu` reads the full 165-item bar from the app
/// handle, `proctor_act` refuses the same `menuPath` with `windowNotFound`, and
/// `proctor_apps activate` reports "frontmost but exposes no windows". So the
/// command that would open the first window is unreachable, and Proctor cannot
/// drive its own status item — DEF-336.
///
/// The menu tree hangs off `kAXMenuBarAttribute` of the **application** element,
/// which is why driving it works while the app is behind other windows. Nothing
/// in that path needs a window; only the handle-resolution in front of it did.
///
/// Two kinds qualify, and the list is deliberately short. A step that names a
/// point, a node or a value is talking about something inside a window, and
/// letting it through against an app handle would trade a clear refusal for a
/// confusing failure further in.
public enum WindowlessActuation {

    /// `app:<pid>:<epoch>`, as minted by `proctor_apps`.
    public static func isAppHandle(_ id: String) -> Bool {
        let parts = id.split(separator: ":")
        return parts.count == 3 && parts[0] == "app"
            && Int32(parts[1]) != nil && Int(parts[2]) != nil
    }

    /// `win:<appEpoch>:<ordinal>`.
    public static func isWindowHandle(_ id: String) -> Bool {
        let parts = id.split(separator: ":")
        return parts.count == 3 && parts[0] == "win"
    }

    /// The step kinds the application plane can serve on its own.
    ///
    /// `menu` reaches `kAXMenuBarAttribute` on the app element. `appleScript`
    /// addresses the process. `waitFor` observes and actuates nothing, so it is
    /// admitted to let a batch settle between menu presses rather than forcing
    /// the caller to split it.
    public static let appPlaneKinds: Set<ActionStep.Kind> = [.menu, .appleScript, .waitFor]

    /// Kinds in this batch that need a window, in the order they appear, without
    /// repeats — so a refusal names each offending kind once rather than twenty
    /// times for a twenty-step batch.
    public static func kindsNeedingAWindow(_ kinds: [ActionStep.Kind]) -> [ActionStep.Kind] {
        var seen = Set<ActionStep.Kind>()
        return kinds.filter { appPlaneKinds.contains($0) ? false : seen.insert($0).inserted }
    }

    public static func canRunWithoutWindow(_ kinds: [ActionStep.Kind]) -> Bool {
        !kinds.isEmpty && kindsNeedingAWindow(kinds).isEmpty
    }

    /// What to say when an app handle is passed with steps that need a window.
    ///
    /// It names the kinds rather than the count, because "3 steps need a window"
    /// sends the caller back to read its own batch, and the whole cost of this
    /// refusal is the round trip.
    public static func refusal(kinds: [ActionStep.Kind],
                               app: String) -> (message: String, remedy: String) {
        let needing = kindsNeedingAWindow(kinds)
        let named = needing.map(\.rawValue).joined(separator: ", ")
        return (
            message: "\(app) is an application handle, and \(named) "
                + (needing.count == 1 ? "addresses" : "address")
                + " something inside a window",
            remedy: "Menu, appleScript and waitFor steps run against an app handle. "
                + "For the rest, open a window first — proctor_act with a menu step that "
                + "opens one, then proctor_apps action \"attach\" to read its handle."
        )
    }

    /// What to say when an app handle names nothing attached.
    public static func notAttached(_ app: String) -> (message: String, remedy: String) {
        (message: "no attached application with handle \(app)",
         remedy: "Call proctor_apps with action \"attach\" first — app handles only exist "
             + "for attached applications, and they change when the app relaunches.")
    }
}
