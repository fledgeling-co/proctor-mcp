import SwiftUI
import AppKit
import ServiceManagement
import ProctorCore

/// Owns the activation policy and the login-item registration.
///
/// Proctor is a background agent, so it belongs in the menu bar rather than the
/// Dock — but an app that is already an accessory at launch never presents its
/// SwiftUI Window scene, which means a first run shows nothing whatsoever. So
/// it starts as a normal app and demotes itself once setup is done.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Capture which build this window is before anything else runs. `builtAt`
        // is stored on the snapshot, so resolving it now describes the image that
        // is running — an upgrade replacing the file underneath a window that has
        // been up for hours is the whole reason PRO-0027 exists.
        BuildInfo.captureAtLaunch()
        Self.applyPolicy()
        Self.registerLoginItem()

        // Opening Proctor should leave the agent running: the agent is the
        // thing an MCP host actually talks to, and a window reporting that it
        // is down — with a button to fix it — is a worse answer than starting
        // it. Off the main thread because bootstrapping can take a moment and
        // the fallback shells out to the installer; the model's own polling
        // picks the change up and updates the window.
        DispatchQueue.global(qos: .userInitiated).async { Actions.ensureAgent() }

        let firstRun = !UserDefaults.standard.bool(forKey: "walkthroughCompleted")
        let window = NSApp.windows.first(where: { $0.title == "Proctor" })

        if firstRun {
            NSApp.activate(ignoringOtherApps: true)
            // A SwiftUI Window restores its saved frame and ignores the content's
            // own .frame, so a window sized once by a previous layout stays that
            // size forever. Setting it here is the one place that actually holds.
            if let window {
                let wanted = NSSize(width: 640, height: 560)
                if abs(window.frame.width - wanted.width) > 1 || abs(window.frame.height - wanted.height) > 1 {
                    window.setContentSize(wanted)
                    window.center()
                }
            }
        } else {
            // Setup is done — this is a menu-bar (or login) start, so live in the
            // menu bar quietly rather than popping the window in the user's face.
            window?.orderOut(nil)
        }
    }

    /// Quit means everything off. Any quit path — the menu's Quit Proctor, the
    /// app menu, ⌘Q — runs through here and stops the background agent as well
    /// as this window. Both return at the next login (the LaunchAgent plist and
    /// the login-item registration persist), so this is "off now", not uninstall.
    ///
    /// A relaunch is the exception and is not a quit: the agent holds the grants
    /// and may be running something, and swapping this window's build is no
    /// reason to take it down.
    func applicationWillTerminate(_ notification: Notification) {
        guard !Actions.isRelaunching else { return }
        Actions.stopAgent()
    }

    /// Reopening from the Dock or `open -a` should bring the Status window back.
    ///
    /// AppKit's `hasVisibleWindows` is the wrong signal: after setup the extras
    /// item stays up, so the flag is true while Status is gone, and this used
    /// to activate a process that showed nothing. `WindowPresentation` asks
    /// whether a window titled Proctor is actually on screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.presentMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    static func presentMainWindow() {
        let windows = NSApp.windows
        if WindowPresentation.shouldPresentMain(
            titles: windows.map { $0.title },
            visible: windows.map { $0.isVisible }) {
            if let window = windows.first(where: { WindowPresentation.isMainWindow(title: $0.title) }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                NotificationCenter.default.post(
                    name: Notification.Name(WindowPresentation.presentMainNotification),
                    object: nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func applyPolicy() {
        let configured = UserDefaults.standard.bool(forKey: "walkthroughCompleted")
        NSApp.setActivationPolicy(configured ? .accessory : .regular)
    }

    /// Register the app to start at login, so the menu-bar icon is present after
    /// every reboot without the user reopening it. Idempotent; only registers
    /// when it is not already enabled, and a failure is logged rather than
    /// surfaced — a missing login item degrades convenience, not function.
    static func registerLoginItem() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do { try service.register() }
        catch { NSLog("Proctor: could not register login item — \(error.localizedDescription)") }
    }
}

@main
struct ProctorUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AgentModel()
    @AppStorage("walkthroughCompleted") private var walkthroughCompleted = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Proctor is LSUIElement: no Dock icon, because it is a background
        // agent that an MCP host drives, not something you switch to. The menu
        // bar is how you reach it once the window is closed.
        Window("Proctor", id: "main") {
            Group {
                if walkthroughCompleted {
                    MainWindow(model: model)
                        .frame(minWidth: 620, idealWidth: 680, minHeight: 560)
                } else {
                    // Nobody's first encounter with a permissions tool should be
                    // a checklist of things that are switched off.
                    Walkthrough(model: model) {
                        walkthroughCompleted = true
                        // Setup is done, so step out of the Dock and live in
                        // the menu bar from here on.
                        AppDelegate.applyPolicy()
                    }
                }
            }
            .onAppear {
                // Polling is app-lifetime (started in the model), so the menu
                // bar stays live with the window closed. Only pull focus on
                // first-run setup; a menu-bar reopen shouldn't steal the front.
                if !walkthroughCompleted { NSApp.activate(ignoringOtherApps: true) }
            }
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Run Setup Again…") {
                    walkthroughCompleted = false
                    AppDelegate.applyPolicy()
                    openWindow(id: "main")
                }
            }
        }

        // What Proctor did, as opposed to what it is doing. Its own window
        // rather than a section of the status window: the status window answers
        // "is this working", and a scrolling record of past runs inside it would
        // fight that question rather than join it.
        Window("History", id: "history") {
            HistoryWindow()
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)

        MenuBarExtra {
            MenuBarContent(model: model,
                           openMain: { openWindow(id: "main") },
                           openHistory: { openWindow(id: "history") },
                           rerunSetup: {
                               walkthroughCompleted = false
                               AppDelegate.applyPolicy()
                               openWindow(id: "main")
                           })
        } label: {
            // The character, in the state the agent's own run HUD is in — so a
            // glance at the top of the screen answers "what is Proctor doing"
            // without finding the panel, which may be on a display nobody is
            // looking at or hidden outright. Falls back to the agent's status
            // symbol when there is something more urgent to say than a phase.
            MenuBarLabel(icon: model.menuBarIcon, character: model.character)
                // The extras label is the view that stays alive with Status
                // closed. AppDelegate posts when reopen must create the scene
                // rather than order an existing window.
                .onReceive(NotificationCenter.default.publisher(
                    for: Notification.Name(WindowPresentation.presentMainNotification))) { _ in
                    openWindow(id: "main")
                }
        }
    }
}

struct MenuBarContent: View {
    let model: AgentModel
    let openMain: () -> Void
    let openHistory: () -> Void
    let rerunSetup: () -> Void

    var body: some View {
        Text(statusLine)
        // The app on disk is not the app running. Above everything else because
        // it changes what every line below it is worth: a status read from a
        // build that was replaced hours ago is a status about the wrong Proctor,
        // which is exactly how the character's absence got reported as a fault in
        // a rule that was working.
        if model.buildReplaced {
            Divider()
            Text("Proctor was updated. Relaunch to use the new version.")
            Button("Relaunch Proctor") { Actions.relaunch(alsoAgent: model.agentBuildReplaced) }
        }
        // Below the stale build, above everything else, and only when there is
        // something it can fix. This is what "Re-check now" became.
        //
        // That row called the model's refresh — the same call a 2-second timer has
        // been making all along, window open or closed — so it advanced a read by
        // about two seconds. And for the case it was defended for, a grant made in
        // System Settings, it advanced nothing: the agent probes Screen Recording
        // through ScreenCaptureKit, whose answer macOS caches for the life of the
        // process, so asking the same agent again returns the same denial. Only a
        // restart clears it, which is why granting through Proctor's own dialog
        // already restarts the agent. This is that remedy, reached by hand, for a
        // grant that arrived from somewhere else — and a start for the other state
        // the menu had nothing to say about, a wedged agent.
        if let recovery = model.recovery {
            Divider()
            Text(recovery.reason)
            Button(recovery.action) { model.take(recovery) }
        }
        if let activityLine {
            Label(activityLine, systemImage: activityIcon)
        }
        // Before it happens, not only while it does. The wording is the panel's
        // own — one sentence, computed once from the batch's steps — so the two
        // surfaces cannot say different things about the same run.
        if let notice = foregroundNotice {
            Label(notice, systemImage: "rectangle.inset.filled.and.person.filled")
        }
        if runControlsShown {
            Divider()
            // The run's own two controls, and the reason they are here: hiding
            // the panel takes Pause and Stop off the screen, and the panel is the
            // kill switch. So they live where the switch that hid it lives.
            //
            // These are the run's words. Hold and Clear act on the queue, live on
            // the panel's queue bar, and are deliberately not here — the two
            // pairs never sit together and never share a word, because calling
            // both "pause" is how somebody stops the wrong thing.
            Button(model.hudPhase == .paused ? "Resume Run" : "Pause Run") {
                model.togglePause()
            }
            Button("Stop Run") { model.stopRun() }
        }
        Divider()
        Toggle("Show Run Panel", isOn: Binding(
            get: { model.hudDrawing },
            set: { model.setPanel(visible: $0) }))
            .disabled(!panelSwitchEnabled)
        if let refusal = panelRefusal {
            Text(refusal)
        }
        Divider()
        Button("Proctor Status…") { NSApp.activate(ignoringOtherApps: true); openMain() }
        Button("History…") { NSApp.activate(ignoringOtherApps: true); openHistory() }
        Button("Run Setup Again…") { NSApp.activate(ignoringOtherApps: true); rerunSetup() }
        Divider()
        Button("Quit Proctor", role: .destructive) { NSApp.terminate(nil) }
    }

    /// The live "what is it doing" line: the tool in flight, or the last one it
    /// ran, or that it is idle. Nil while the agent is unreachable, since there
    /// is nothing to report until it answers.
    private var activityLine: String? {
        guard case .reachable = model.reachability else { return nil }
        // The waiting count rides alongside whatever is running, so somebody can
        // answer "is something of mine stuck behind another session" without
        // opening the run panel.
        let waiting = model.queueWaiting > 0
            ? " · \(model.queueWaiting) waiting" : ""
        // A run taking the machine is the thing worth reading first, and the
        // reason this line exists on a surface that does not depend on which
        // display the panel landed on.
        // A held run first. It is the state somebody most needs to see from
        // across the room, and it is the one they can do something about — the
        // Resume below this line is the answer to it.
        if model.foreground.yielded, let held = model.foreground.yieldLine {
            return "\(held)\(waiting)"
        }
        if model.foreground.active {
            return "Taking the foreground now\(waiting)"
        }
        if let current = model.currentActivity { return "Running \(current)\(waiting)" }
        if let last = model.recentActivity.first { return "Last: \(last.tool)\(waiting)" }
        return model.queueWaiting > 0
            ? "\(model.queueWaiting) session\(model.queueWaiting == 1 ? "" : "s") waiting"
            : "Idle — no model connected"
    }

    /// Pause and Stop appear only while there is a run for them to act on. A
    /// control that does nothing is worse than an absent one on a menu whose job
    /// is to say what is going on.
    private var runControlsShown: Bool {
        guard case .reachable = model.reachability else { return false }
        return model.hudRunning
    }

    /// The switch itself is off-limits on an agent launched with the run panel
    /// switched off: that launch runs a bare run loop, so a panel drawn now would
    /// carry a Pause and a Stop that could not be clicked. Hiding is always
    /// available, and always reversible within the launch.
    private var panelSwitchEnabled: Bool {
        guard case .reachable = model.reachability else { return false }
        return model.hudDrawing || model.hudCanShow
    }

    /// Said plainly rather than left as a greyed-out item nobody can explain.
    private var panelRefusal: String? {
        guard case .reachable = model.reachability, !model.hudDrawing, !model.hudCanShow
        else { return nil }
        return "Started with PROCTOR_HUD off — restart the agent to bring the panel back"
    }

    private var activityIcon: String {
        if model.foreground.active { return "cursorarrow.rays" }
        return model.currentActivity != nil ? "dot.radiowaves.left.and.right" : "moon.zzz"
    }

    /// What the run in flight is going to do to the foreground. Absent while a
    /// synthetic step is actually being posted, because the line above is
    /// already saying so in the present tense and saying it twice is noise.
    private var foregroundNotice: String? {
        guard case .reachable = model.reachability,
              model.foreground.running, !model.foreground.active else { return nil }
        return model.foreground.notice
    }

    private var statusLine: String {
        switch model.reachability {
        case .unknown: return "Checking…"
        case .unreachable: return "Agent not answering"
        case .reachable:
            guard let r = model.report else { return "Connected" }
            if r.ready { return "Ready · \(r.attachedApps.count) app(s) attached" }
            let missing = r.grants.filter { $0.required && !$0.granted }.count
            return "\(missing) permission\(missing == 1 ? "" : "s") needed"
        }
    }
}
