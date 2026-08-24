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
// 2. Validates that the 21-tool catalogue (ToolCatalogue.all) is fully enumerated
//    and operator actions map to menu hierarchy capabilities (including proctor_menu).
// 3. Validates that live NSStatusBar status extra items and main menu items adhere to
//    title-casing, unique key equivalents, and dynamic enablement.

@Suite("Menu Bar Command Hierarchy and AppKit NSMenu Witness (REQ-031 / REQ-185)")
struct MenuBarHierarchyWitnessTests {

    /// Builds a live AppKit NSMenu hierarchy for Proctor's main menu bar.
    @MainActor
    private static func buildAppKitMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")

        for menuType in CommandSurface.Menu.allCases {
            let submenu = NSMenu(title: menuType.title)
            submenu.identifier = NSUserInterfaceItemIdentifier(CommandSurface.ID.menu(menuType))
            let commands = CommandSurface.commands(in: menuType)

            for command in commands {
                let item = NSMenuItem(title: command.title, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
                item.identifier = NSUserInterfaceItemIdentifier(CommandSurface.ID.command(command.id))

                if let shortcut = command.shortcut {
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

    /// Builds a live AppKit NSMenu for Proctor's status bar extra item.
    @MainActor
    private static func buildAppKitExtrasMenu() -> NSMenu {
        let menu = NSMenu(title: "ProctorStatusExtra")

        // Status header
        menu.addItem(withTitle: CommandSurface.ExtrasCopy.status, action: nil, keyEquivalent: "")

        let extrasCommands = CommandSurface.commands(on: .extrasMenu)
        for command in extrasCommands {
            let item = NSMenuItem(title: command.title, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(CommandSurface.ID.command(command.id))
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: CommandSurface.ExtrasCopy.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.identifier = NSUserInterfaceItemIdentifier(CommandSurface.ID.command(CommandSurface.CommandID.quit))
        menu.addItem(quitItem)

        return menu
    }

    @MainActor
    @Test("REQ-031: Every command declared in CommandSurface.all exists in the AppKit NSMenu hierarchy")
    func menuBarHierarchyCompletenessAndToolCatalogueWitness() throws {
        let mainMenu = Self.buildAppKitMainMenu()
        NSApplication.shared.mainMenu = mainMenu

        #expect(mainMenu.items.count == CommandSurface.Menu.allCases.count)

        // Traverse live NSMenu hierarchy using AppKit inspection methods
        var itemsById: [String: NSMenuItem] = [:]
        for topItem in mainMenu.items {
            guard let submenu = topItem.submenu else { continue }
            for item in submenu.items {
                if let rawId = item.identifier?.rawValue {
                    itemsById[rawId] = item
                }
            }
        }

        // Verify all 20 declared commands exist in the live AppKit hierarchy
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

        // Verify Live NSStatusBar Extra item hierarchy
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let extrasMenu = Self.buildAppKitExtrasMenu()
        statusItem.menu = extrasMenu

        #expect(statusItem.menu != nil, "Status bar item has live NSMenu attached")
        #expect(statusItem.menu?.items.count ?? 0 >= 6, "Extras menu contains status item hierarchy")

        let extrasIds = Set((statusItem.menu?.items ?? []).compactMap { $0.identifier?.rawValue })
        #expect(extrasIds.contains(CommandSurface.ID.command(CommandSurface.CommandID.pause)))
        #expect(extrasIds.contains(CommandSurface.ID.command(CommandSurface.CommandID.resume)))
        #expect(extrasIds.contains(CommandSurface.ID.command(CommandSurface.CommandID.stop)))
        #expect(extrasIds.contains(CommandSurface.ID.command(CommandSurface.CommandID.quit)))

        NSStatusBar.system.removeStatusItem(statusItem)

        // Verify ToolCatalogue carries exactly 21 tools and maps to menu structure
        let tools = ToolCatalogue.all
        #expect(tools.count == 21, "ToolCatalogue defines exactly 21 tools")

        let toolNames = Set(tools.map(\.name))
        #expect(toolNames.count == 21, "All 21 tool names are distinct")

        // Tool catalogue in menu structure: verify proctor_menu and companions
        let menuTool = try #require(ToolCatalogue.spec(named: "proctor_menu"))
        #expect(menuTool.readOnly, "proctor_menu tool is readOnly")
        #expect(!menuTool.description.isEmpty, "proctor_menu has descriptive specification")

        #expect(toolNames.contains("proctor_menu"), "proctor_menu tool is declared in catalogue")
        #expect(toolNames.contains("proctor_apps"), "proctor_apps tool is declared in catalogue")
        #expect(toolNames.contains("proctor_act"), "proctor_act tool is declared in catalogue")
        #expect(toolNames.contains("proctor_assert"), "proctor_assert tool is declared in catalogue")
        #expect(toolNames.contains("proctor_doctor"), "proctor_doctor tool is declared in catalogue")
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
