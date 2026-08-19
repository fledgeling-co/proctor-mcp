import Foundation
import Darwin
import ProctorCore

// PRO-0074. The terminal itself: raw mode, the alternate screen, and painting a
// frame atomically.
//
// It holds no TCC grants and needs no window server, which is the whole point:
// this is the supervision surface for an operator over SSH, where the panel and
// the status window cannot be reached at all.

enum Terminal {

    /// The terminal settings as they were found, so they can be put back
    /// exactly. Behind a lock because `restore` runs from a signal-driven exit
    /// path as well as from the render loop, and a half-restored terminal is
    /// worse than an unrestored one.
    private final class Saved: @unchecked Sendable {
        private let lock = NSLock()
        private var value: termios?
        func store(_ t: termios) { lock.lock(); value = t; lock.unlock() }
        func takeIfPresent() -> termios? {
            lock.lock(); defer { lock.unlock() }
            let out = value; value = nil; return out
        }
    }
    private static let saved = Saved()

    /// The size the terminal reports, or the design size when it will not say —
    /// a pipe has no size, and a supervision surface that refused to draw into
    /// one would be unusable in exactly the places people put it.
    static func size() -> (cols: Int, rows: Int) {
        var window = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &window) == 0,
           window.ws_col > 0, window.ws_row > 0 {
            return (Int(window.ws_col), Int(window.ws_row))
        }
        return (100, 30)
    }

    static var isInteractive: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 }

    /// Raw mode: one keystroke at a time, no echo, and no line discipline
    /// swallowing the key that stops a run.
    static func enterRawMode() {
        guard isInteractive else { return }
        var current = termios()
        tcgetattr(STDIN_FILENO, &current)
        saved.store(current)
        var raw = current
        raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~UInt(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~UInt(OPOST)
        withUnsafeMutablePointer(to: &raw.c_cc) { cc in
            cc.withMemoryRebound(to: UInt8.self, capacity: Int(NCCS)) { slots in
                slots[Int(VMIN)] = 0
                slots[Int(VTIME)] = 1
            }
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    /// Put the terminal back exactly as it was found, whatever happened.
    ///
    /// A TUI that exits without restoring leaves the operator with a shell that
    /// does not echo — and the operator is over SSH, so the fix is another
    /// session rather than a click.
    static func restore() {
        write("\u{1B}[?2026l\u{1B}[?25h\u{1B}[?1049l")
        guard var previous = saved.takeIfPresent() else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &previous)
    }

    static func enterAltScreen() { write("\u{1B}[?1049h\u{1B}[?25l") }

    static func write(_ text: String) {
        var bytes = Array(text.utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes {
                Darwin.write(STDOUT_FILENO, $0.baseAddress!.advanced(by: sent), bytes.count - sent)
            }
            if n <= 0 { break }
            sent += n
        }
    }

    /// Paint one frame, wrapped in DEC mode 2026.
    ///
    /// Synchronised output, because this surface exists to be used over SSH: a
    /// frame painted a row at a time down a slow link is visibly torn, and the
    /// tear looks like the layout bug this whole feature was built to prevent.
    static func paint(_ canvas: TUICanvas, theme: TUITheme) {
        var out = "\u{1B}[?2026h\u{1B}[H"
        for (y, row) in canvas.cells.enumerated() {
            out += "\u{1B}[\(y + 1);1H\u{1B}[K"
            var role = ""
            for cell in row {
                if cell.width == 0 { continue }
                if cell.role != role {
                    out += theme.escape(for: cell.role)
                    role = cell.role
                }
                out += cell.ch
            }
            out += "\u{1B}[0m"
        }
        out += "\u{1B}[?2026l"
        write(out)
    }

    /// Read one keystroke, or nil when the poll expired. Bounded so the render
    /// loop can also act on a pushed frame.
    static func key(timeout: TimeInterval) -> String? {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, Int32(timeout * 1000)) > 0 else { return nil }
        var byte: UInt8 = 0
        guard read(STDIN_FILENO, &byte, 1) == 1 else { return nil }
        switch byte {
        case 0x09: return "tab"
        case 0x03, 0x04: return "q"          // Ctrl-C and Ctrl-D still leave.
        case 0x1B: return "esc"
        default: return String(UnicodeScalar(byte))
        }
    }
}

/// Roles resolved to escape sequences.
///
/// Colour is negotiated, never assumed. `NO_COLOR` set to any non-empty value
/// means no colour and is checked first; without `COLORTERM` naming truecolour
/// the palette falls back to the terminal's own sixteen, whose RGB mapping is
/// undefined — which is exactly why selection is reverse video rather than a
/// coloured fill, and why the state a row is in is never carried by colour
/// alone.
public struct TUITheme: Sendable {
    public let colour: Bool
    public let truecolour: Bool

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let noColour = environment["NO_COLOR"].map { !$0.isEmpty } ?? false
        self.colour = !noColour
        let term = environment["COLORTERM"] ?? ""
        self.truecolour = !noColour && (term == "truecolor" || term == "24bit")
    }

    /// The role ladder, as the compiled frames declare it. Every role that
    /// carries information clears 3:1 against the surface, and the roles a
    /// reader must read clear 4.5:1.
    static let hex: [String: String] = [
        "text": "#E9EAED", "text-strong": "#FFFFFF", "text-dim": "#9AA1AF",
        "border": "#6E7686", "border-focus": "#D2A059", "accent": "#D2A059",
        "ok": "#74C79B", "warn": "#E3B76A", "danger": "#F1897F",
    ]

    /// The sixteen-colour fallback, by role. Named rather than computed: a
    /// downsample from hex would put two roles on one ANSI colour and silently
    /// flatten the ladder.
    static let ansi: [String: Int] = [
        "text": 7, "text-strong": 15, "text-dim": 8,
        "border": 8, "border-focus": 3, "accent": 3,
        "ok": 2, "warn": 3, "danger": 1,
    ]

    /// Weight for every role, alongside colour rather than instead of it.
    ///
    /// Measured on a capture of the running program: with weight applied only on
    /// the `NO_COLOR` path, `tui_gates.py` reported "no bold and no dim anywhere
    /// in the frame — every glyph carries the same weight, so the screen has no
    /// hierarchy that survives a monochrome terminal". A ladder carried by one
    /// channel is a ladder that disappears when that channel does, and the
    /// 16-colour palette has no defined RGB mapping anyway, so on a great many
    /// terminals colour is the channel that cannot be relied on.
    static func weight(for role: String) -> String {
        switch role {
        case "text-strong", "border-focus": return "\u{1B}[1m"
        case "text-dim", "border": return "\u{1B}[2m"
        case "selected": return "\u{1B}[7m"
        default: return ""
        }
    }

    public func escape(for role: String) -> String {
        let weight = Self.weight(for: role)
        guard colour else { return "\u{1B}[0m" + weight }
        if role == "selected" { return "\u{1B}[0m\u{1B}[7m" }
        if truecolour, let hex = Self.hex[role], let rgb = Self.rgb(hex) {
            return "\u{1B}[0m" + weight + "\u{1B}[38;2;\(rgb.0);\(rgb.1);\(rgb.2)m"
        }
        guard let code = Self.ansi[role] else { return "\u{1B}[0m" + weight }
        let colourCode = code >= 8 ? "\u{1B}[9\(code - 8)m" : "\u{1B}[3\(code)m"
        return "\u{1B}[0m" + weight + colourCode
    }

    static func rgb(_ hex: String) -> (Int, Int, Int)? {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }
}
