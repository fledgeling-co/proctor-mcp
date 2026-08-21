import Foundation

/// What Proctor writes to the system log, as opposed to what it says to a person.
///
/// PRO-0090. `status_literals.py` is default-deny: a string that is not inside an
/// identifier construct it recognises is reported as user-facing, and an `NSLog`
/// format is not. That answer is right rather than a false positive — a log line
/// is still a sentence somebody reads, and the one below is the only account
/// anybody gets of a login item that failed to register. It does not belong in a
/// `Copy` enum, because `Copy` means "drawn on a surface" and the doc comment
/// saying so is what DEF-039 exists to keep true. So it has its own home, named
/// for what it addresses.
public enum AppLog {

    /// The app's prefix in `Console.app`, so a line of Proctor's is findable
    /// among everything else the system writes.
    public static let prefix = "Proctor: "

    /// Registration of the login item failed. Logged rather than surfaced: a
    /// missing login item costs the menu-bar icon after a reboot, which degrades
    /// convenience and not function, and a modal about it on first launch would
    /// be the loudest thing in the app for the smallest reason.
    public static func loginItemNotRegistered(_ reason: String) -> String {
        prefix + "could not register login item — " + reason
    }
}
