import Foundation
import Carbon.HIToolbox
import CoreGraphics

// Named keys to virtual keycodes. The names are what a model will write, so
// aliases matter more than completeness: "esc", "escape", "arrowleft" and
// "left" all have to land on the same key.

enum KeyCodes {

    static let table: [String: CGKeyCode] = {
        var t: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
            "8": 28, "0": 29,
            "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
            "n": 45, "m": 46,

            "equal": 24, "=": 24,
            "minus": 27, "-": 27,
            "rightbracket": 30, "]": 30,
            "leftbracket": 33, "[": 33,
            "quote": 39, "'": 39,
            "semicolon": 41, ";": 41,
            "backslash": 42, "\\": 42,
            "comma": 43, ",": 43,
            "slash": 44, "/": 44,
            "period": 47, ".": 47,
            "grave": 50, "`": 50, "backtick": 50,

            "return": 36, "enter": 76, "keypadenter": 76,
            "tab": 48,
            "space": 49, "spacebar": 49, " ": 49,
            "delete": 51, "backspace": 51,
            "forwarddelete": 117, "del": 117,
            "escape": 53, "esc": 53,

            "left": 123, "arrowleft": 123,
            "right": 124, "arrowright": 124,
            "down": 125, "arrowdown": 125,
            "up": 126, "arrowup": 126,

            "home": 115, "end": 119,
            "pageup": 116, "pgup": 116,
            "pagedown": 121, "pgdn": 121,
            "help": 114, "insert": 114,

            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64,
            "f18": 79, "f19": 80, "f20": 90,

            "keypad0": 82, "keypad1": 83, "keypad2": 84, "keypad3": 85, "keypad4": 86,
            "keypad5": 87, "keypad6": 88, "keypad7": 89, "keypad8": 91, "keypad9": 92,
            "keypaddecimal": 65, "keypadmultiply": 67, "keypadplus": 69,
            "keypadclear": 71, "keypaddivide": 75, "keypadminus": 78, "keypadequals": 81,
        ]
        // Digits and letters also arrive spelled out often enough to be worth mapping.
        t["numpadenter"] = 76
        return t
    }()

    static func keyCode(for name: String) -> CGKeyCode? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let code = table[key] { return code }
        // A single character not in the table has no fixed keycode on a non-ANSI
        // layout; the caller falls back to posting it as a unicode string.
        return nil
    }

    static func modifiers(_ names: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for raw in names {
            switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
            case "cmd", "command", "meta", "super": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn", "function": flags.insert(.maskSecondaryFn)
            case "caps", "capslock": flags.insert(.maskAlphaShift)
            default: continue
            }
        }
        return flags
    }
}
