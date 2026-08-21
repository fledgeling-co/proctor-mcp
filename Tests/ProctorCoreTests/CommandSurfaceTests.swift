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
    func presenceIsUnconditional() throws {
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
        //
        // PRO-0090. `command(id)!` on a literal id used to be here, and it fails
        // in the worst way available: an id that stops resolving is a fatal error
        // that takes the whole runner down — measured, 1,963 tests aborted with no
        // verdict line — rather than one test reporting one failure. `#require`
        // fails this test and lets the rest report, and the ids come from
        // `CommandID` so a rename moves both ends at once. DEF-135.
        for id in [CommandSurface.CommandID.pause, CommandSurface.CommandID.stop] {
            let c = try #require(CommandSurface.command(id),
                                 "CommandSurface.all no longer defines \(id)")
            #expect(!CommandSurface.isEnabled(c, hasLiveRun: false, runIsHeld: false,
                                              agentReachable: true, panelEnabled: true))
            #expect(CommandSurface.isEnabled(c, hasLiveRun: true, runIsHeld: false,
                                             agentReachable: true, panelEnabled: true))
        }
    }

    @Test("A5 · the panel switch needs an agent launched with the panel enabled")
    func panelSwitchGated() throws {
        // PRO-0090, DEF-135, the same shape as the loop above: a literal id and
        // `!`. Measured with the panel commands dropped from the catalogue, the
        // pre-fix form aborted the runner on SIGTRAP with 0 tests and 0 suites
        // reporting and no verdict line at all.
        let show = try #require(CommandSurface.command(CommandSurface.CommandID.showPanel),
                                "CommandSurface.all no longer defines show-panel")
        #expect(show.requires == .panelEnabled)
        #expect(!CommandSurface.isEnabled(show, hasLiveRun: false, runIsHeld: false,
                                          agentReachable: true, panelEnabled: false))
        // Hiding stays available, and is always reversible within the launch.
        let hide = try #require(CommandSurface.command(CommandSurface.CommandID.hidePanel),
                                "CommandSurface.all no longer defines hide-panel")
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

// PRO-0075. What the value-level check could not see.
//
// `commandsMissingFromMenuBar` compares the catalogue against its own `surfaces`
// field, so it passes whether or not a command is rendered. The campaign drove
// `proctor_menu` against the running app and found three commands declared for
// the menu bar that SwiftUI never declared at all — Clear Waiting Runs, Takeover
// Notice and Drawn Pointer. The count published alongside it was wrong too.
//
// The rendered menu can only be settled on glass, and that case lives in the
// campaign. These are the two facts a unit test can hold: the count, and that
// every declared command has a home to be rendered into.

@Suite("The command count, pinned")
struct CommandCountTests {

    @Test("the catalogue carries twenty commands across four menus")
    func theCountIsWhatWasPublished() {
        #expect(CommandSurface.all.count == 20)
        #expect(Set(CommandSurface.all.map(\.menu)).count == 4)
    }

    @Test("every command names a menu, so none can be declared with nowhere to draw")
    func everyCommandHasAMenu() {
        for command in CommandSurface.all {
            #expect(CommandSurface.Menu.allCases.contains(command.menu),
                    "\(command.id) names no menu this build draws")
        }
    }

    @Test("no two commands share an id, because the menu item is built from it")
    func idsAreUnique() {
        let ids = CommandSurface.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
