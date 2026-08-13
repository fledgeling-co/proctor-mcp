import Foundation

// Reconstructing a menu item's keyboard shortcut from the raw accessibility
// attributes, and flattening a menu-bar tree into addressable rows. This is the
// load-bearing, testable half of proctor_menu: a wrong modifier decode or an
// unstable key mapping makes every shortcut it reports wrong, so it lives here in
// ProctorCore (pure, no AX) and is where the red→green tests land. The agent-side
// AXMenuBar walk (MenuBarReader) only fills in the RawMenuItem tree these
// functions consume — the same split as SetOfMarks / MarkRenderer.

public enum MenuKeyEquivalent {

    // MARK: - Carbon menu modifier mask

    // AXMenuItemCmdModifiers is the Carbon menu modifier bitmask, whose defining
    // quirk is that Command is IMPLIED: a menu key equivalent carries ⌘ unless the
    // no-command bit is set. Getting this backwards inverts every shortcut, so the
    // bits are named and the "command implied" rule is explicit.
    public enum CarbonMask {
        public static let shift = 0x01
        public static let option = 0x02
        public static let control = 0x04
        public static let noCommand = 0x08
    }

    /// Decode the Carbon modifier mask into normalised modifier names, in the
    /// canonical order `cmd, ctrl, opt, shift`. Command is present unless the
    /// no-command bit is set, so mask `0` is `["cmd"]` and mask `0x08` is `[]`.
    public static func modifiers(fromCarbonMask mask: Int) -> [String] {
        var out: [String] = []
        if (mask & CarbonMask.noCommand) == 0 { out.append("cmd") }
        if (mask & CarbonMask.control) != 0 { out.append("ctrl") }
        if (mask & CarbonMask.option) != 0 { out.append("opt") }
        if (mask & CarbonMask.shift) != 0 { out.append("shift") }
        return out
    }

    // MARK: - Key resolution

    /// The key half of a shortcut, as a name the `act` `key` step accepts, or nil
    /// when the item exposes no key equivalent. A usable printable `cmdChar` wins;
    /// otherwise a non-zero virtual keycode (arrows, function keys), then a menu
    /// glyph. Function-key and control-range characters are not usable as a
    /// printable and fall through to the virtual key, which is where the special
    /// keys actually live.
    public static func keyName(char: String?, virtualKey: Int?, glyph: Int?) -> String? {
        if let char, let name = normalisedChar(char) { return name }
        if let virtualKey, let name = virtualKeyNames[virtualKey] { return name }
        if let glyph, let name = glyphNames[glyph] { return name }
        return nil
    }

    /// A printable command character reduced to a `key`-step name. Space is named
    /// rather than passed through as a literal blank; the private-use function-key
    /// scalars (0xF700+) and control characters are rejected so a special-key
    /// equivalent resolves through its virtual key instead of a garbage glyph char.
    public static func normalisedChar(_ s: String) -> String? {
        guard let scalar = s.unicodeScalars.first else { return nil }
        let v = scalar.value
        if v == 0x20 { return "space" }
        guard v >= 0x21, v <= 0x7E else { return nil }
        return String(scalar).lowercased()
    }

    // MARK: - Shortcut string

    /// The normalised shortcut, cmd-first and `+`-joined, e.g. `cmd+shift+n`, or
    /// nil when no key resolves. Modifiers with no key are not a shortcut.
    public static func shortcut(char: String?, virtualKey: Int?, glyph: Int?,
                                carbonMask: Int) -> String? {
        guard let key = keyName(char: char, virtualKey: virtualKey, glyph: glyph) else { return nil }
        return shortcutString(modifiers: modifiers(fromCarbonMask: carbonMask), key: key)
    }

    public static func shortcutString(modifiers: [String], key: String) -> String {
        (modifiers + [key]).joined(separator: "+")
    }

    // MARK: - Flatten

    /// Flatten a menu-bar tree into one addressable row per non-separator item,
    /// depth-first in menu order. Every row carries its full menu path, enabled
    /// state, and — for leaves with an equivalent — the normalised shortcut plus
    /// the `key`+`modifiers` decomposition the `act` `key` step consumes.
    ///
    /// A submenu that had not populated at read time (macOS builds some lazily on
    /// open) is reported as a single row with `submenuPopulated == false` and is
    /// NOT descended into, so the enumeration never fabricates items it could not
    /// actually see.
    public static func flatten(bar items: [RawMenuItem]) -> [MenuItem] {
        var out: [MenuItem] = []
        func visit(_ item: RawMenuItem, path: [String]) {
            guard !item.isSeparator else { return }
            let title = item.title ?? ""
            let itemPath = path + [title]
            let key = keyName(char: item.cmdChar, virtualKey: item.cmdVirtualKey, glyph: item.cmdGlyph)
            let mods = key != nil ? modifiers(fromCarbonMask: item.cmdModifiers ?? 0) : nil
            let shortcut = key.map { shortcutString(modifiers: mods ?? [], key: $0) }
            let populated = item.hasSubmenu ? item.submenuPopulated : true
            out.append(MenuItem(path: itemPath, title: title, enabled: item.enabled,
                                shortcut: shortcut, key: key, modifiers: mods,
                                hasSubmenu: item.hasSubmenu, submenuPopulated: populated))
            if item.hasSubmenu, item.submenuPopulated {
                for child in item.children { visit(child, path: itemPath) }
            }
        }
        for item in items { visit(item, path: []) }
        return out
    }

    // MARK: - Tables

    /// Virtual keycode → the `key`-step name for keys that have no printable
    /// character. Keyed on the same virtual codes the actuator's KeyCodes table
    /// uses, so a name that comes back here drives `act` unchanged. Keycode 0 ('a')
    /// is intentionally absent: a letter equivalent always arrives as a cmdChar, so
    /// the reader treats a zero virtual key as "no virtual key" and never lands here.
    static let virtualKeyNames: [Int: String] = [
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7",
        100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12", 105: "f13",
        107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20",
        123: "left", 124: "right", 125: "down", 126: "up",
        115: "home", 119: "end", 116: "pageup", 121: "pagedown", 114: "help",
        51: "delete", 117: "forwarddelete", 36: "return", 76: "enter",
        48: "tab", 49: "space", 53: "escape",
    ]

    /// Menu glyph constant (kMenuXXXGlyph) → key name, for equivalents expressed as
    /// a glyph rather than a character or virtual key. Both the solid and the older
    /// dashed arrow encodings are covered; the null glyph (0) is absent so an item
    /// with no glyph never resolves here.
    static let glyphNames: [Int: String] = [
        0x02: "tab", 0x03: "tab", 0x04: "enter", 0x09: "space",
        0x0A: "forwarddelete", 0x0B: "return", 0x0C: "return", 0x0D: "return",
        0x17: "delete", 0x18: "left", 0x19: "up", 0x1A: "right", 0x1B: "escape",
        0x62: "pageup", 0x64: "left", 0x65: "right", 0x66: "home",
        0x67: "help", 0x68: "up", 0x69: "end", 0x6A: "down", 0x6B: "pagedown",
    ]
}

// MARK: - Wire types

/// One row of an enumerated menu bar. `key` and `modifiers` are the exact shape
/// the `act` `key` step reads, so an agent can invoke a command by its shortcut
/// straight from this row; `path` is what the background-safe `menu` step actuates
/// through the accessibility plane. `submenuPopulated == false` marks a submenu
/// that macOS had not built yet at read time — open it (a `menu`/`press` step on
/// this item) and re-read to see its contents.
public struct MenuItem: Codable, Sendable, Equatable {
    public var path: [String]
    public var title: String
    public var enabled: Bool
    public var shortcut: String?
    public var key: String?
    public var modifiers: [String]?
    public var hasSubmenu: Bool
    public var submenuPopulated: Bool
    public init(path: [String], title: String, enabled: Bool, shortcut: String?,
                key: String?, modifiers: [String]?, hasSubmenu: Bool, submenuPopulated: Bool) {
        self.path = path; self.title = title; self.enabled = enabled
        self.shortcut = shortcut; self.key = key; self.modifiers = modifiers
        self.hasSubmenu = hasSubmenu; self.submenuPopulated = submenuPopulated
    }
}

/// The raw menu node the agent-side AXMenuBar walk produces and `flatten` consumes.
/// It holds the accessibility attributes verbatim — the character, virtual key,
/// glyph and Carbon modifier mask — so the reconstruction rules stay in one
/// testable place rather than smeared through the AX reader.
public struct RawMenuItem: Sendable {
    public var title: String?
    public var enabled: Bool
    public var isSeparator: Bool
    public var cmdChar: String?
    public var cmdVirtualKey: Int?
    public var cmdGlyph: Int?
    public var cmdModifiers: Int?
    public var hasSubmenu: Bool
    public var submenuPopulated: Bool
    public var children: [RawMenuItem]
    public init(title: String?, enabled: Bool, isSeparator: Bool = false,
                cmdChar: String? = nil, cmdVirtualKey: Int? = nil, cmdGlyph: Int? = nil,
                cmdModifiers: Int? = nil, hasSubmenu: Bool = false,
                submenuPopulated: Bool = true, children: [RawMenuItem] = []) {
        self.title = title; self.enabled = enabled; self.isSeparator = isSeparator
        self.cmdChar = cmdChar; self.cmdVirtualKey = cmdVirtualKey; self.cmdGlyph = cmdGlyph
        self.cmdModifiers = cmdModifiers; self.hasSubmenu = hasSubmenu
        self.submenuPopulated = submenuPopulated; self.children = children
    }
}
