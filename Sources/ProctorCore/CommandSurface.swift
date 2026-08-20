import Foundation

// PRO-0068. Every command the app offers, and where it appears.
//
// The rule this file exists to make checkable is the platform's, and the app was
// breaking it: **every command reachable from a toolbar or a panel also exists
// in the menu bar**, because people hide and customise toolbars and a
// panel-only command is a command that can disappear.
//
// Today Pause and Stop are reachable from a floating panel and a menu-bar
// extra, and from no menu at all. Somebody who has hidden the panel and does not
// know about the extras item has no path to the kill switch — which is the same
// class of failure PRO-0015 fixed when it moved the agent to
// `NSApplication.run()` so a click could reach a button.
//
// So the surfaces are enumerated here rather than in three view bodies, and
// `CommandSurfaceTests` fails on a command present in one and absent from the
// menu bar.

public enum CommandSurface {

    /// Where a command can be offered.
    public enum Surface: String, Sendable, CaseIterable {
        case menuBar        // the complete command surface
        case extrasMenu     // the menu-bar extra's dropdown
        case runPanel       // the floating run HUD
    }

    /// Which menu-bar menu a command belongs to.
    public enum Menu: String, Sendable, CaseIterable {
        case proctor, run, window, help
    }

    /// What a command needs in order to do anything.
    ///
    /// A command that cannot act is **dimmed, never hidden**: a control that
    /// disappears makes the layout jump and teaches the user the feature does
    /// not exist. So this decides enablement, not presence.
    public enum Requires: String, Sendable, CaseIterable {
        case nothing
        /// A run has to be in flight.
        case liveRun
        /// A run has to be held, for Resume.
        case heldRun
        /// The agent has to be answering.
        case agent
        /// The agent must have been launched with the panel enabled — with
        /// `PROCTOR_HUD` off it runs a bare run loop, so a panel drawn then
        /// would carry buttons nobody could click.
        case panelEnabled
    }

    public struct Command: Sendable, Equatable {
        public let id: String
        public let title: String
        /// The key equivalent, in the menu-bar convention. Nil where there is none.
        public let shortcut: String?
        public let menu: Menu
        public let surfaces: Set<Surface>
        public let requires: Requires

        public init(id: String, title: String, shortcut: String? = nil,
                    menu: Menu, surfaces: Set<Surface>, requires: Requires = .nothing) {
            self.id = id; self.title = title; self.shortcut = shortcut
            self.menu = menu; self.surfaces = surfaces; self.requires = requires
        }
    }

    /// Every command, once.
    ///
    /// Menu-bar items take title case, which is the platform convention and is
    /// sourced; body copy and labels elsewhere take sentence case.
    ///
    /// The run controls say "Pause Run" and "Stop Run" rather than "Pause" and
    /// "Stop", and that is the shipped wording kept deliberately: the queue has
    /// its own pair, the two never sit together, and calling both "pause" is how
    /// somebody stops the wrong thing.
    public static let all: [Command] = [
        // Proctor
        .init(id: "about", title: "About Proctor", menu: .proctor, surfaces: [.menuBar]),
        .init(id: "setup-again", title: "Run Setup Again…", menu: .proctor, surfaces: [.menuBar]),
        .init(id: "restart-agent", title: "Restart the Agent", menu: .proctor,
              surfaces: [.menuBar], requires: .agent),
        .init(id: "reveal-socket", title: "Reveal the Socket in Finder", menu: .proctor,
              surfaces: [.menuBar]),
        .init(id: "quit", title: "Quit Proctor", shortcut: "⌘Q", menu: .proctor,
              surfaces: [.menuBar, .extrasMenu]),

        // Run — the kill switch and everything around it.
        .init(id: "pause", title: "Pause Run", shortcut: "⌘.", menu: .run,
              surfaces: [.menuBar, .extrasMenu, .runPanel], requires: .liveRun),
        .init(id: "resume", title: "Resume Run", shortcut: "⌃⌘.", menu: .run,
              surfaces: [.menuBar, .extrasMenu, .runPanel], requires: .heldRun),
        .init(id: "stop", title: "Stop Run", shortcut: "⇧⌘.", menu: .run,
              surfaces: [.menuBar, .extrasMenu, .runPanel], requires: .liveRun),
        .init(id: "drop-waiting", title: "Clear Waiting Runs", menu: .run,
              surfaces: [.menuBar, .runPanel], requires: .liveRun),
        .init(id: "show-panel", title: "Show Run Panel", menu: .run,
              surfaces: [.menuBar, .extrasMenu], requires: .panelEnabled),
        .init(id: "hide-panel", title: "Hide Run Panel", menu: .run,
              surfaces: [.menuBar, .extrasMenu]),
        .init(id: "takeover-notice", title: "Takeover Notice", menu: .run, surfaces: [.menuBar]),
        .init(id: "drawn-pointer", title: "Drawn Pointer", menu: .run, surfaces: [.menuBar]),

        // Window
        .init(id: "status", title: "Status", shortcut: "⌘0", menu: .window,
              surfaces: [.menuBar, .extrasMenu]),
        .init(id: "history", title: "History", shortcut: "⌘Y", menu: .window,
              surfaces: [.menuBar, .extrasMenu]),
        // AppKit supplies this item and spells it its own way. The repo writes
        // British English everywhere it chooses the words; this string is not
        // Proctor's to choose, and a catalogue claiming "Minimise" describes a
        // menu bar that says "Minimize".
        .init(id: "minimise", title: "Minimize", shortcut: "⌘M", menu: .window, surfaces: [.menuBar]),
        .init(id: "bring-all", title: "Bring All to Front", menu: .window, surfaces: [.menuBar]),

        // Help
        .init(id: "help", title: "Proctor Help", shortcut: "⌘?", menu: .help, surfaces: [.menuBar]),
        .init(id: "refusals", title: "What Proctor Refuses to Do", menu: .help, surfaces: [.menuBar]),
        .init(id: "diagnostics", title: "Copy Diagnostics", menu: .help, surfaces: [.menuBar]),
    ]

    public static func commands(on surface: Surface) -> [Command] {
        all.filter { $0.surfaces.contains(surface) }
    }

    public static func commands(in menu: Menu) -> [Command] {
        all.filter { $0.menu == menu && $0.surfaces.contains(.menuBar) }
    }

    public static func command(_ id: String) -> Command? {
        all.first { $0.id == id }
    }

    /// Whether a command can act right now. Presence is not conditional on this
    /// — a command that cannot act is dimmed and keeps its place.
    public static func isEnabled(_ command: Command,
                                 hasLiveRun: Bool,
                                 runIsHeld: Bool,
                                 agentReachable: Bool,
                                 panelEnabled: Bool) -> Bool {
        switch command.requires {
        case .nothing: return true
        case .liveRun: return hasLiveRun
        case .heldRun: return runIsHeld
        case .agent: return agentReachable
        case .panelEnabled: return panelEnabled
        }
    }

    /// The commands the menu bar is missing, given what the other surfaces
    /// offer. Empty is the only acceptable answer, and the test asserts it.
    public static var commandsMissingFromMenuBar: [Command] {
        let elsewhere = commands(on: .extrasMenu) + commands(on: .runPanel)
        return elsewhere.filter { !$0.surfaces.contains(.menuBar) }
    }

    public enum ID {
        public static func command(_ id: String) -> String { "proctor.command.\(id)" }
        public static func menu(_ m: Menu) -> String { "proctor.menu.\(m.rawValue)" }
    }
}
