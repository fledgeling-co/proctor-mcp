import SwiftUI
import AppKit
import ServiceManagement

/// Owns the activation policy and the login-item registration.
///
/// Proctor is a background agent, so it belongs in the menu bar rather than the
/// Dock — but an app that is already an accessory at launch never presents its
/// SwiftUI Window scene, which means a first run shows nothing whatsoever. So
/// it starts as a normal app and demotes itself once setup is done.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
    func applicationWillTerminate(_ notification: Notification) {
        Actions.stopAgent()
    }

    /// Reopening from the Dock or the menu bar should bring the window back
    /// rather than silently doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        return true
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

        MenuBarExtra {
            MenuBarContent(model: model,
                           openMain: { openWindow(id: "main") },
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
        }
    }
}

struct MenuBarContent: View {
    let model: AgentModel
    let openMain: () -> Void
    let rerunSetup: () -> Void

    var body: some View {
        Text(statusLine)
        if let activityLine {
            Label(activityLine, systemImage: activityIcon)
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
        Button("Run Setup Again…") { NSApp.activate(ignoringOtherApps: true); rerunSetup() }
        Button("Re-check now") { model.refresh() }
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
        model.currentActivity != nil ? "dot.radiowaves.left.and.right" : "moon.zzz"
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
