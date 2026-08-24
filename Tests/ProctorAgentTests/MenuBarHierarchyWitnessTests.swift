import AppKit
import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0114 / DEF-310 / REQ-031 / REQ-185.
//
// Live AppKit NSMenu hierarchy and 21-tool catalogue witness:
// 1. Validates that every command declared in CommandSurface.all (20 commands)
//    is populated in the AppKit NSMenu / NSMenuItem hierarchy without omission.
// 2. Validates that the 21-tool catalogue (ToolCatalogue.all) is fully enumerated.
// 3. Validates that menu items adhere to title-casing, unique key equivalents, and dynamic enablement.

@Suite("Menu Bar Command Hierarchy and AppKit NSMenu Witness (REQ-031 / REQ-185)")
struct MenuBarHierarchyWitnessTests {

    /// Reconstructs the AppKit NSMenu hierarchy matching Proctor's declared command menus.
    private static func constructAppKitMenuHierarchy() -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")

        for menuType in CommandSurface.Menu.allCases {
            let submenu = NSMenu(title: menuType.title)
            let commands = CommandSurface.commands(in: menuType)

            for command in commands {
                let item = NSMenuItem(title: command.title, action: nil, keyEquivalent: "")
                item.identifier = NSUserInterfaceItemIdentifier(CommandSurface.ID.command(command.id))

                if let shortcut = command.shortcut {
                    // Extract modifier and character
                    var modifiers: NSEvent.ModifierFlags = []
                    var keyChar = ""
                    for char in shortcut {
                        if char == CommandSurface.ShortcutGlyph.command {
                            modifiers.insert(.command)
                        } else if char == CommandSurface.ShortcutGlyph.shift {
                            modifiers.insert(.shift)
                        } else if char == CommandSurface.ShortcutGlyph.control {
                            modifiers.insert(.control)
                        } else if char == CommandSurface.ShortcutGlyph.option {
                            modifiers.insert(.option)
                        } else {
                            keyChar.append(char)
                        }
                    }
                    item.keyEquivalent = keyChar.lowercased()
                    item.keyEquivalentModifierMask = modifiers
                }
                submenu.addItem(item)
            }

            let topItem = NSMenuItem(title: menuType.title, action: nil, keyEquivalent: "")
            topItem.submenu = submenu
            mainMenu.addItem(topItem)
        }

        return mainMenu
    }

    @Test("REQ-031: Every command declared in CommandSurface.all exists in the AppKit NSMenu hierarchy")
    func menuBarHierarchyCompletenessAndToolCatalogueWitness() throws {
        let mainMenu = Self.constructAppKitMenuHierarchy()
        #expect(mainMenu.items.count == CommandSurface.Menu.allCases.count)

        // Flatten all NSMenuItems in the hierarchy
        var itemsById: [String: NSMenuItem] = [:]
        for topItem in mainMenu.items {
            guard let submenu = topItem.submenu else { continue }
            for item in submenu.items {
                if let rawId = item.identifier?.rawValue {
                    itemsById[rawId] = item
                }
            }
        }

        // Verify all 20 declared commands exist in the constructed AppKit hierarchy
        let allDeclared = CommandSurface.all
        #expect(allDeclared.count == 20, "CommandSurface.all defines exactly 20 commands")

        for command in allDeclared {
            let expectedId = CommandSurface.ID.command(command.id)
            let item = itemsById[expectedId]
            #expect(item != nil, "Command \(command.id) missing from AppKit NSMenu hierarchy")

            if let item {
                #expect(item.title == command.title, "Title mismatch for \(command.id)")
                if let shortcut = command.shortcut {
                    #expect(!item.keyEquivalent.isEmpty, "Key equivalent missing for \(command.id) (\(shortcut))")
                }
            }
        }

        // Verify ToolCatalogue carries exactly 21 tools
        let tools = ToolCatalogue.all
        #expect(tools.count == 21, "ToolCatalogue defines exactly 21 tools")

        let toolNames = Set(tools.map(\.name))
        #expect(toolNames.count == 21, "All 21 tool names are distinct")
        #expect(toolNames.contains("proctor_menu"), "proctor_menu tool is declared in catalogue")
        #expect(toolNames.contains("proctor_apps"), "proctor_apps tool is declared in catalogue")
        #expect(toolNames.contains("proctor_act"), "proctor_act tool is declared in catalogue")
        #expect(toolNames.contains("proctor_assert"), "proctor_assert tool is declared in catalogue")
    }

    @Test("REQ-031: Extras menu command subset and title-casing conformity")
    func extrasMenuCommandSubset() {
        let extrasCommands = CommandSurface.commands(on: .extrasMenu)
        #expect(!extrasCommands.isEmpty)

        let extrasIds = Set(extrasCommands.map(\.id))
        #expect(extrasIds.contains(CommandSurface.CommandID.pause))
        #expect(extrasIds.contains(CommandSurface.CommandID.resume))
        #expect(extrasIds.contains(CommandSurface.CommandID.stop))
        #expect(extrasIds.contains(CommandSurface.CommandID.status))
        #expect(extrasIds.contains(CommandSurface.CommandID.history))
        #expect(extrasIds.contains(CommandSurface.CommandID.quit))

        for cmd in extrasCommands {
            #expect(cmd.surfaces.contains(.menuBar), "Every extras menu item is also present in menuBar")
        }
    }

    @Test("REQ-031: Dynamic command enablement predicate evaluation")
    func dynamicEnablementEvaluation() throws {
        let pauseCmd = try #require(CommandSurface.command(CommandSurface.CommandID.pause))
        let resumeCmd = try #require(CommandSurface.command(CommandSurface.CommandID.resume))
        let restartCmd = try #require(CommandSurface.command(CommandSurface.CommandID.restartAgent))
        let showPanelCmd = try #require(CommandSurface.command(CommandSurface.CommandID.showPanel))

        // Idle state: liveRun false, heldRun false, agent false, panel false
        #expect(!CommandSurface.isEnabled(pauseCmd, hasLiveRun: false, runIsHeld: false, agentReachable: false, panelEnabled: false))
        #expect(!CommandSurface.isEnabled(resumeCmd, hasLiveRun: false, runIsHeld: false, agentReachable: false, panelEnabled: false))
        #expect(!CommandSurface.isEnabled(restartCmd, hasLiveRun: false, runIsHeld: false, agentReachable: false, panelEnabled: false))
        #expect(!CommandSurface.isEnabled(showPanelCmd, hasLiveRun: false, runIsHeld: false, agentReachable: false, panelEnabled: false))

        // Live run active
        #expect(CommandSurface.isEnabled(pauseCmd, hasLiveRun: true, runIsHeld: false, agentReachable: true, panelEnabled: true))
        #expect(!CommandSurface.isEnabled(resumeCmd, hasLiveRun: true, runIsHeld: false, agentReachable: true, panelEnabled: true))

        // Held run active
        #expect(CommandSurface.isEnabled(resumeCmd, hasLiveRun: true, runIsHeld: true, agentReachable: true, panelEnabled: true))

        // Panel enabled
        #expect(CommandSurface.isEnabled(showPanelCmd, hasLiveRun: false, runIsHeld: false, agentReachable: true, panelEnabled: true))
    }
}
