import Foundation
import AppKit
import ProctorCore

// proctor_apps action "activate": bring an application to the front, launching
// it if it is not running, and make sure it actually has a window afterwards.
//
// This exists because of a bootstrap gap that has no other way out. Every
// actuating path in Proctor is window-scoped: proctor_act resolves a window
// handle before it does anything, because settle, capture and the policy gate
// all key on one. An application whose windows are all closed still runs, still
// has a menu bar, and still answers proctor_menu, but it has no window handle to
// name. The menu item that would open one (Slack's "File > Show main window",
// and its equivalent in most document apps) can only be invoked through
// proctor_act, which cannot be called without the window that item creates.
// Without this action the only way out of that state is a shell command, which
// puts a step of a computer-use run outside the tool that is supposed to be
// performing it, outside the policy gate, and outside the audit trail.
//
// Activation goes through NSWorkspace.openApplication rather than
// NSRunningApplication.activate. Activating only raises what already exists;
// opening sends the app a reopen event, which is what a Dock click sends and
// what makes a document app restore its main window. For an app that is not
// running at all, the same call launches it.

extension Session {

    /// Activate (and if necessary launch) an application, then report its windows.
    ///
    /// Resolution order is the same as attach: an existing app handle, then pid,
    /// then bundle id, then localised name. The app does not need to be attached
    /// first; a successful activation attaches it, so the returned window handles
    /// are usable immediately.
    func activate(bundleId: String?, pid: Int32?, name: String?, app appId: String?,
                  timeoutMs: Int) async throws -> JSONValue {
        guard bundleId != nil || pid != nil || name != nil || appId != nil else {
            throw AgentError(
                code: .invalidArguments,
                message: "activate needs one of app, bundleId, pid or name",
                remedy: "Call proctor_apps with action \"list\" to find one.")
        }

        // An already-attached handle names a pid directly, which is the least
        // ambiguous route and the one a caller who has attached will reach for.
        var wantedPid = pid
        if let appId, let attached = appHandle(id: appId) { wantedPid = attached.pid }

        let running = Session.findRunning(bundleId: bundleId, pid: wantedPid, name: name)

        // The gate runs before anything is brought to the front. Activation moves
        // the user's screen and is the first step of driving an app, so it is
        // gated exactly as driving is: on the bundle id, failing closed. Resolve
        // the identifier from whatever we found, falling back to what was asked
        // for when the app is not running yet.
        let targetBundleId = running?.bundleIdentifier ?? bundleId
        let known = running.flatMap { attachedApp(pid: $0.processIdentifier) }
        try enforcePolicy(tool: "proctor_apps.activate", app: known, bundleId: targetBundleId)

        guard let url = Session.applicationURL(for: running, bundleId: bundleId, name: name) else {
            throw AgentError(
                code: .appNotFound,
                message: "could not find an application to activate for "
                       + Session.describeTarget(bundleId: bundleId, pid: wantedPid, name: name),
                remedy: running == nil
                    ? "The app is not running and no bundle on disk matched. Pass a bundleId such "
                    + "as com.tinyspeck.slackmacgap, or the exact application name."
                    : "The app is running but its bundle could not be located on disk.")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // addsToRecentItems is left at its default: activation should look to the
        // system exactly like the user opening the app, not like a special case.
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw AgentError(
                code: .actionFailed,
                message: "activating \(url.lastPathComponent) failed: \(error.localizedDescription)",
                remedy: "Confirm the application is installed and can be launched by the current user.")
        }

        // Launching returns as soon as the process is up, which is well before a
        // restored window exists. Poll for one rather than sleeping a fixed
        // interval: a cold launch takes seconds and a reopen takes milliseconds,
        // and reporting zero windows because we looked too early is the exact
        // failure this action exists to remove.
        let deadline = Date().addingTimeInterval(Double(max(0, timeoutMs)) / 1000)
        var handle: AppHandle?
        var windows: [WindowHandle] = []
        var lastError: Error?

        repeat {
            do {
                let (app, found, _) = try attachResolved(
                    bundleId: bundleId,
                    pid: wantedPid ?? running?.processIdentifier,
                    name: name)
                handle = app
                windows = found
                if !windows.isEmpty { break }
            } catch {
                lastError = error
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        } while Date() < deadline

        guard let handle else {
            throw AgentError(
                code: .appNotFound,
                message: "activated \(url.lastPathComponent) but could not attach to it"
                       + (lastError.map { ": \($0.localizedDescription)" } ?? ""),
                remedy: "Confirm Accessibility is granted to Proctor, then retry.")
        }

        var result: [String: JSONValue] = [
            "app": try JSONValue.encode(handle),
            "windows": .array(try windows.map { try JSONValue.encode($0) }),
            "activated": .bool(true),
            "launched": .bool(running == nil)
        ]
        // A window-less result is reported plainly rather than as success. Some
        // apps genuinely have no window to restore (a menu-bar-only agent), and a
        // caller that is about to ask for a window handle needs to know which
        // case it is in before it starts retrying.
        if windows.isEmpty {
            result["note"] = .string(
                "The app is frontmost but exposes no windows after \(timeoutMs)ms. It may be a "
                + "menu-bar-only app, or its window may still be opening; re-read with "
                + "proctor_apps action \"list\". Its menu bar is readable either way with proctor_menu.")
        }
        return .object(result)
    }

    // MARK: - Resolution

    /// The running application matching any supplied condition. All supplied
    /// conditions must hold, so name plus bundle id narrows rather than widens,
    /// matching how proctor_kill reads a query.
    private static func findRunning(bundleId: String?, pid: Int32?,
                                    name: String?) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            if let pid, app.processIdentifier != pid { return false }
            if let bundleId, app.bundleIdentifier?.caseInsensitiveCompare(bundleId) != .orderedSame {
                return false
            }
            if let name, app.localizedName?.caseInsensitiveCompare(name) != .orderedSame {
                return false
            }
            return pid != nil || bundleId != nil || name != nil
        }
    }

    /// Where the application lives on disk. A running app knows its own bundle;
    /// otherwise the bundle id is looked up, and finally the name is resolved
    /// against /Applications and the user's own Applications folder.
    private static func applicationURL(for running: NSRunningApplication?,
                                       bundleId: String?, name: String?) -> URL? {
        if let url = running?.bundleURL { return url }
        if let bundleId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return url
        }
        guard let name else { return nil }
        let candidates = [
            "/Applications/\(name).app",
            "\(NSHomeDirectory())/Applications/\(name).app",
            "/System/Applications/\(name).app"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func describeTarget(bundleId: String?, pid: Int32?, name: String?) -> String {
        var parts: [String] = []
        if let name { parts.append("name \(name.debugDescription)") }
        if let bundleId { parts.append("bundleId \(bundleId.debugDescription)") }
        if let pid { parts.append("pid \(pid)") }
        return parts.isEmpty ? "the given query" : parts.joined(separator: ", ")
    }
}
