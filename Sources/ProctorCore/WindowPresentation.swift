import Foundation

/// Which of this process's windows is the Status / walkthrough window, and
/// whether a reopen should bring it back.
///
/// The rule lives here because `Package.swift` has no `ProctorUI` test target
/// and `swift test` has no window server. AppKit's `hasVisibleWindows` is the
/// wrong signal: after setup the extras item stays up, so that flag is true
/// while the Status window is gone, and `applicationShouldHandleReopen` then
/// activates a process that shows nothing. Measured 2026-08-19: AX close left
/// `axWindowCount=0`; `proctor_apps activate` and `open -a` both left it that
/// way; Window ▸ Proctor restored it.
public enum WindowPresentation {

    /// Title of the Status / walkthrough `Window` scene.
    public static let mainTitle = "Proctor"

    /// Posted when reopen must create the scene rather than order an existing
    /// window. The SwiftUI app listens and calls `openWindow(id: "main")`.
    public static let presentMainNotification = "app.fledgeling.procter.presentMainWindow"

    /// Whether a window with this title is the Status / walkthrough window.
    public static func isMainWindow(title: String) -> Bool {
        title == mainTitle
    }

    /// Whether reopen should present the Status window.
    ///
    /// `visibleMainExists` is true only when a window titled `mainTitle` is
    /// currently on screen. The extras item, History, and untitled overlays
    /// do not count. No such window, or one that is ordered out, both present.
    public static func shouldPresentMain(visibleMainExists: Bool) -> Bool {
        !visibleMainExists
    }

    /// Index of the Status window in parallel title / visibility arrays, or
    /// nil when it is not in the list at all (closed, not merely ordered out).
    public static func mainWindowIndex(titles: [String], visible: [Bool]) -> Int? {
        guard titles.count == visible.count else { return nil }
        return titles.firstIndex(where: isMainWindow)
    }

    /// Present when the titled window is missing or not visible.
    public static func shouldPresentMain(titles: [String], visible: [Bool]) -> Bool {
        guard let index = mainWindowIndex(titles: titles, visible: visible) else {
            return true
        }
        return !visible[index]
    }
}
