import SwiftUI
import AppKit

/// Owns the activation policy.
///
/// Proctor is a background agent, so it belongs in the menu bar rather than the
/// Dock — but an app that is already an accessory at launch never presents its
/// SwiftUI Window scene, which means a first run shows nothing whatsoever. So
/// it starts as a normal app and demotes itself once setup is done.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.applyPolicy()
        NSApp.activate(ignoringOtherApps: true)
        // A SwiftUI Window restores its saved frame and ignores the content's
        // own .frame, so a window sized once by a previous layout stays that
        // size forever. Setting it here is the one place that actually holds.
        if let window = NSApp.windows.first(where: { $0.title == "Proctor" }) {
            let wanted = NSSize(width: 640, height: 560)
            if abs(window.frame.width - wanted.width) > 1 || abs(window.frame.height - wanted.height) > 1 {
                window.setContentSize(wanted)
                window.center()
            }
        }
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
                model.startPolling()
                NSApp.activate(ignoringOtherApps: true)
            }
            .onDisappear { model.stopPolling() }
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

        MenuBarExtra("Proctor", systemImage: menuIcon) {
            MenuBarContent(model: model,
                           openMain: { openWindow(id: "main") },
                           rerunSetup: {
                               walkthroughCompleted = false
                               AppDelegate.applyPolicy()
                               openWindow(id: "main")
                           })
        }
    }

    private var menuIcon: String {
        switch model.reachability {
        case .reachable:   return model.ready ? "checkmark.seal" : "exclamationmark.triangle"
        case .unreachable: return "bolt.horizontal.circle"
        case .unknown:     return "circle.dashed"
        }
    }
}

struct MenuBarContent: View {
    let model: AgentModel
    let openMain: () -> Void
    let rerunSetup: () -> Void

    var body: some View {
        Text(statusLine)
        Divider()
        Button("Proctor Status…") { NSApp.activate(ignoringOtherApps: true); openMain() }
        Button("Run Setup Again…") { NSApp.activate(ignoringOtherApps: true); rerunSetup() }
        Button("Re-check now") { model.refresh() }
        Divider()
        Button("Quit Proctor's window") { NSApp.terminate(nil) }
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
