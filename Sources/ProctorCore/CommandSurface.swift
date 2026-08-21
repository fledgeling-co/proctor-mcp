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

        /// What the menu itself is called in the menu bar.
        ///
        /// PRO-0090. `ProctorUIApp` wrote `CommandMenu("Run")` — the one menu
        /// Proctor declares rather than inherits — so the name of the menu the
        /// kill switch lives under was a literal in a view while every item
        /// inside it came from the catalogue. AppKit supplies the other three
        /// and spells them itself; they are named here so the switch is
        /// exhaustive and a reader can see which one Proctor owns.
        public var title: String {
            switch self {
            case .proctor: return "Proctor"
            case .run: return "Run"
            case .window: return "Window"
            case .help: return "Help"
            }
        }
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
        .init(id: CommandID.about, title: "About Proctor", menu: .proctor, surfaces: [.menuBar]),
        .init(id: CommandID.setupAgain, title: "Run Setup Again…", menu: .proctor, surfaces: [.menuBar]),
        .init(id: CommandID.restartAgent, title: "Restart the Agent", menu: .proctor,
              surfaces: [.menuBar], requires: .agent),
        .init(id: CommandID.revealSocket, title: "Reveal the Socket in Finder", menu: .proctor,
              surfaces: [.menuBar]),
        .init(id: CommandID.quit, title: "Quit Proctor", shortcut: "⌘Q", menu: .proctor,
              surfaces: [.menuBar, .extrasMenu]),

        // Run — the kill switch and everything around it.
        .init(id: CommandID.pause, title: "Pause Run", shortcut: "⌘.", menu: .run,
              surfaces: [.menuBar, .extrasMenu, .runPanel], requires: .liveRun),
        .init(id: CommandID.resume, title: "Resume Run", shortcut: "⌃⌘.", menu: .run,
              surfaces: [.menuBar, .extrasMenu, .runPanel], requires: .heldRun),
        .init(id: CommandID.stop, title: "Stop Run", shortcut: "⇧⌘.", menu: .run,
              surfaces: [.menuBar, .extrasMenu, .runPanel], requires: .liveRun),
        .init(id: CommandID.dropWaiting, title: "Clear Waiting Runs", menu: .run,
              surfaces: [.menuBar, .runPanel], requires: .liveRun),
        .init(id: CommandID.showPanel, title: "Show Run Panel", menu: .run,
              surfaces: [.menuBar, .extrasMenu], requires: .panelEnabled),
        .init(id: CommandID.hidePanel, title: "Hide Run Panel", menu: .run,
              surfaces: [.menuBar, .extrasMenu]),
        .init(id: CommandID.takeoverNotice, title: "Takeover Notice", menu: .run, surfaces: [.menuBar]),
        .init(id: CommandID.drawnPointer, title: "Drawn Pointer", menu: .run, surfaces: [.menuBar]),

        // Window
        .init(id: CommandID.status, title: "Status", shortcut: "⌘0", menu: .window,
              surfaces: [.menuBar, .extrasMenu]),
        .init(id: CommandID.history, title: "History", shortcut: "⌘Y", menu: .window,
              surfaces: [.menuBar, .extrasMenu]),
        // AppKit supplies this item and spells it its own way. The repo writes
        // British English everywhere it chooses the words; this string is not
        // Proctor's to choose, and a catalogue claiming "Minimise" describes a
        // menu bar that says "Minimize".
        .init(id: CommandID.minimise, title: "Minimize", shortcut: "⌘M", menu: .window, surfaces: [.menuBar]),
        .init(id: CommandID.bringAll, title: "Bring All to Front", menu: .window, surfaces: [.menuBar]),

        // Help
        .init(id: CommandID.help, title: "Proctor Help", shortcut: "⌘?", menu: .help, surfaces: [.menuBar]),
        .init(id: CommandID.refusals, title: "What Proctor Refuses to Do", menu: .help, surfaces: [.menuBar]),
        .init(id: CommandID.diagnostics, title: "Copy Diagnostics", menu: .help, surfaces: [.menuBar]),
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

    /// The command ids, as named constants.
    ///
    /// PRO-0090. `ProctorUIApp.swift` called `commandButton("pause")` fifteen
    /// times, so a lookup key into the table below was a literal in a view — and
    /// `command(_:)` returns an optional that a missing id resolves to nil,
    /// which `commandButton` then draws as nothing at all. A typo took a menu
    /// item off the menu bar silently. Both the table and its callers name the
    /// commands from here, so a typo is a compile error instead.
    public enum CommandID {
        public static let about = "about"
        public static let setupAgain = "setup-again"
        public static let restartAgent = "restart-agent"
        public static let revealSocket = "reveal-socket"
        public static let quit = "quit"
        public static let pause = "pause"
        public static let resume = "resume"
        public static let stop = "stop"
        public static let dropWaiting = "drop-waiting"
        public static let showPanel = "show-panel"
        public static let hidePanel = "hide-panel"
        public static let takeoverNotice = "takeover-notice"
        public static let drawnPointer = "drawn-pointer"
        public static let status = "status"
        public static let history = "history"
        public static let minimise = "minimise"
        public static let bringAll = "bring-all"
        public static let help = "help"
        public static let refusals = "refusals"
        public static let diagnostics = "diagnostics"

        public static let all: [String] = [
            about, setupAgain, restartAgent, revealSocket, quit,
            pause, resume, stop, dropWaiting, showPanel, hidePanel,
            takeoverNotice, drawnPointer,
            status, history, minimise, bringAll,
            help, refusals, diagnostics,
        ]
    }

    /// What the menu-bar extra draws, where its wording is not the catalogue's.
    ///
    /// PRO-0090. Most of the extra's items say exactly what `all` says and now
    /// read it from there. Three do not, and they are kept and named rather than
    /// reconciled, because choosing which wording ships is a reader's call and
    /// wave 9 settled these surfaces — the same handling `StatusSurface.Copy`
    /// gives `toolsNote` and `toolsNoteInDesign`. DEF-035.
    public enum ExtrasCopy {
        /// The catalogue calls this `Status`; the extra has always drawn the
        /// longer form, because in a menu hanging off an unlabelled icon
        /// "Status" alone does not say whose.
        public static let status = "Proctor Status…"
        /// The catalogue calls this `History`.
        public static let history = "History…"
        /// The catalogue calls this `Quit Proctor` and the extra agrees; it is
        /// listed here only so the three that the extra draws by hand sit
        /// together rather than two here and one elsewhere.
        public static let quit = "Quit Proctor"
    }

    /// The catalogue's title for a command, for a surface that draws the item
    /// itself instead of going through `commandButton`.
    ///
    /// PRO-0090. The menu-bar extra draws Pause, Resume, Stop, Show Run Panel
    /// and Run Setup Again by hand, because their actions and their enablement
    /// are not the menu bar's. It wrote the words out again to do it, which is
    /// DEF-035's shape: two spellings of one command, and nothing that fails
    /// when they part.
    ///
    /// Total by construction rather than by luck. Every id `CommandID` names is
    /// in `all`, and `CommandSurfaceTests` fails when one stops resolving; the
    /// fallback returns the id so an unresolved command draws something a reader
    /// can trace rather than the empty item `commandButton` used to draw.
    public static func title(_ id: String) -> String { command(id)?.title ?? id }

    /// Where Help's two items point.
    ///
    /// PRO-0090. Beside the commands that open them, which is the same handling
    /// `ObscuraTool.docs` and `CuaDriverTool.docs` already get.
    public enum Help {
        public static let readme = "https://github.com/fledgeling-co/proctor-mcp#readme"
        public static let refusals =
            "https://github.com/fledgeling-co/proctor-mcp#what-it-can-and-cannot-do"
    }

    /// The menu-bar spelling of the modifier keys.
    ///
    /// PRO-0090. `KeyEquivalentParser` matched these four glyphs against the
    /// `shortcut` strings above, and both halves of that agreement were
    /// literals — one set in a view, one set in this table. The parser still
    /// owns the mapping to `EventModifiers`, which is SwiftUI's type and cannot
    /// come here; what moved is the glyph each modifier is written with.
    public enum ShortcutGlyph {
        public static let command: Character = "⌘"
        public static let shift: Character = "⇧"
        public static let control: Character = "⌃"
        public static let option: Character = "⌥"

        /// In the order a menu bar writes them, which is the order the shortcut
        /// strings in `all` are written in.
        public static let all: [Character] = [command, shift, control, option]
    }

    public enum ID {
        public static func command(_ id: String) -> String { "proctor.command.\(id)" }
        public static func menu(_ m: Menu) -> String { "proctor.menu.\(m.rawValue)" }
    }
}
