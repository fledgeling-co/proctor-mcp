import Foundation
import ApplicationServices
import ProctorCore

// Reading the menu bar. This is a pure accessibility read: it walks AXMenuBar and
// each item's command-key attributes into a RawMenuItem tree, and it NEVER presses
// an item to force a lazily-built submenu to populate. Pressing would be a side
// effect on a read-only tool, so an unpopulated submenu is reported as such and
// the pure reconstruction (MenuKeyEquivalent) turns the tree into shortcut rows.

/// The menu-item command attributes, read by their raw AX strings the same way
/// AXAttr.manualAccessibility is — these are the standard accessibility attribute
/// names for a menu item's key equivalent.
enum AXMenuAttr {
    static let cmdChar = "AXMenuItemCmdChar"
    static let cmdVirtualKey = "AXMenuItemCmdVirtualKey"
    static let cmdGlyph = "AXMenuItemCmdGlyph"
    static let cmdModifiers = "AXMenuItemCmdModifiers"
}

enum MenuBarReader {
    /// A menu deeper than this is almost certainly a cycle or a runaway, not a real
    /// hierarchy; the walk stops and reports the deepest submenu as unread.
    static let maxDepth = 12

    /// Walk the application's menu bar into a raw tree. Returns nil when the app
    /// exposes no menu bar at all (agent-style apps have none).
    static func read(appElement: AXUIElement) -> [RawMenuItem]? {
        guard let bar = AXRead.element(appElement, kAXMenuBarAttribute) else { return nil }
        return AXRead.elements(bar, kAXChildrenAttribute).map { item(from: $0, depth: 0) }
    }

    private static func item(from element: AXUIElement, depth: Int) -> RawMenuItem {
        let title = AXRead.string(element, kAXTitleAttribute)
            ?? AXRead.string(element, kAXDescriptionAttribute)

        // A menu item's submenu, when it has one, is its single AXMenu child.
        let submenu = AXRead.elements(element, kAXChildrenAttribute)
            .first { AXRead.string($0, kAXRoleAttribute) == kAXMenuRole }
        let hasSubmenu = submenu != nil

        var children: [RawMenuItem] = []
        var populated = true
        if let submenu, depth < maxDepth {
            let entries = AXRead.elements(submenu, kAXChildrenAttribute)
            populated = !entries.isEmpty          // empty here means macOS builds it lazily on open
            children = entries.map { item(from: $0, depth: depth + 1) }
        } else if hasSubmenu {
            populated = false                     // depth cap reached; report as present but unread
        }

        let cmdChar = AXRead.string(element, AXMenuAttr.cmdChar).flatMap { $0.isEmpty ? nil : $0 }
        let virtualKey = keyNumber(element, AXMenuAttr.cmdVirtualKey)
        let glyph = keyNumber(element, AXMenuAttr.cmdGlyph)
        let modifiers = number(element, AXMenuAttr.cmdModifiers)

        // A separator is a title-less item with nothing to invoke and no submenu.
        let isSeparator = !hasSubmenu && (title?.isEmpty ?? true)
            && cmdChar == nil && virtualKey == nil && glyph == nil

        return RawMenuItem(title: title,
                           enabled: AXRead.bool(element, kAXEnabledAttribute) ?? true,
                           isSeparator: isSeparator,
                           cmdChar: cmdChar, cmdVirtualKey: virtualKey, cmdGlyph: glyph,
                           cmdModifiers: modifiers, hasSubmenu: hasSubmenu,
                           submenuPopulated: populated, children: children)
    }

    private static func number(_ element: AXUIElement, _ attribute: String) -> Int? {
        guard let raw = AXRead.raw(element, attribute),
              CFGetTypeID(raw) == CFNumberGetTypeID() else { return nil }
        return (raw as! NSNumber).intValue
    }

    /// Virtual key and glyph both use 0 as their "no value" sentinel — a real
    /// keycode-0 ('a') or glyph equivalent always arrives as a character instead —
    /// and AppKit uses 0xFFFF for an unset virtual key, so both mean "none" here.
    private static func keyNumber(_ element: AXUIElement, _ attribute: String) -> Int? {
        guard let v = number(element, attribute), v != 0, v != 0xFFFF else { return nil }
        return v
    }
}
