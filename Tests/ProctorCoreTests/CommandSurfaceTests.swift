import Foundation
import Testing
@testable import ProctorCore

// PRO-0068. The command surface, judged without a menu.

@Suite("Command surface")
struct CommandSurfaceTests {

    @Test("A1 · every command offered anywhere also exists in the menu bar")
    func menuBarIsComplete() {
        // The clause this item exists for. People hide and customise toolbars,
        // so a panel-only command is one that can disappear — and two of the
        // three that were panel-only are Pause and Stop.
        let missing = CommandSurface.commandsMissingFromMenuBar
        #expect(missing.isEmpty,
                "not in the menu bar: \(missing.map(\.title).joined(separator: ", "))")
    }

    @Test("A1 · the kill switch is reachable from every surface that has one")
    func stopEverywhere() {
        for id in ["pause", "stop"] {
            let command = CommandSurface.command(id)
            #expect(command != nil)
            #expect(command?.surfaces.contains(.menuBar) == true, "\(id) is not in the menu bar")
            #expect(command?.surfaces.contains(.extrasMenu) == true, "\(id) is not in the extras menu")
            #expect(command?.surfaces.contains(.runPanel) == true, "\(id) is not on the run panel")
        }
    }

    @Test("A2 · a command that cannot act is dimmed, never absent")
    func presenceIsUnconditional() {
        // Enablement is a separate question from presence. A control that
        // disappears makes the layout jump and teaches the user the feature
        // does not exist.
        let idle = CommandSurface.all.filter {
            !CommandSurface.isEnabled($0, hasLiveRun: false, runIsHeld: false,
                                      agentReachable: false, panelEnabled: false)
        }
        #expect(!idle.isEmpty, "some commands should be disabled when nothing is running")
        for command in idle {
            // Still present on every surface it belongs to.
            #expect(!command.surfaces.isEmpty, "\(command.id) vanished when disabled")
        }
        // Pause and Stop are disabled with no run and enabled with one.
        for id in ["pause", "stop"] {
            let c = CommandSurface.command(id)!
            #expect(!CommandSurface.isEnabled(c, hasLiveRun: false, runIsHeld: false,
                                              agentReachable: true, panelEnabled: true))
            #expect(CommandSurface.isEnabled(c, hasLiveRun: true, runIsHeld: false,
                                             agentReachable: true, panelEnabled: true))
        }
    }

    @Test("A5 · the panel switch needs an agent launched with the panel enabled")
    func panelSwitchGated() {
        let show = CommandSurface.command("show-panel")!
        #expect(show.requires == .panelEnabled)
        #expect(!CommandSurface.isEnabled(show, hasLiveRun: false, runIsHeld: false,
                                          agentReachable: true, panelEnabled: false))
        // Hiding stays available, and is always reversible within the launch.
        let hide = CommandSurface.command("hide-panel")!
        #expect(CommandSurface.isEnabled(hide, hasLiveRun: false, runIsHeld: false,
                                         agentReachable: true, panelEnabled: false))
    }

    @Test("A4 · shortcuts are unique across the whole surface")
    func shortcutsUnique() {
        let shortcuts = CommandSurface.all.compactMap(\.shortcut)
        #expect(Set(shortcuts).count == shortcuts.count,
                "a key equivalent is claimed twice: \(shortcuts.sorted())")
    }

    @Test("every command has an id, a title and a menu, and ids are unique")
    func wellFormed() {
        let ids = CommandSurface.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for c in CommandSurface.all {
            #expect(!c.id.isEmpty)
            #expect(!c.title.isEmpty)
            #expect(!c.surfaces.isEmpty, "\(c.id) appears nowhere")
            #expect(c.surfaces.contains(.menuBar), "\(c.id) is not in the complete command surface")
        }
    }

    @Test("menu-bar items take title case, which is the sourced convention")
    func titleCase() {
        // Sentence case is right for body copy and labels; menu-bar items are
        // the documented exception.
        let lowercaseWords: Set<String> = ["the", "a", "to", "in", "of", "and", "for"]
        for c in CommandSurface.all {
            let words = c.title.split(separator: " ").map(String.init)
            for (i, word) in words.enumerated() where i > 0 {
                guard let first = word.first, first.isLetter else { continue }
                if lowercaseWords.contains(word.lowercased()) { continue }
                #expect(first.isUppercase,
                        "“\(c.title)” — “\(word)” should be capitalised in a menu item")
            }
        }
    }

    @Test("every menu has commands and every command lands in one")
    func menusPopulated() {
        for menu in CommandSurface.Menu.allCases {
            #expect(!CommandSurface.commands(in: menu).isEmpty, "\(menu.rawValue) is empty")
        }
        #expect(CommandSurface.commands(in: .run).count >= 5)
    }
}
