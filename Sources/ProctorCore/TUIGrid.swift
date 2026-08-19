import Foundation

// PRO-0074. Cell arithmetic, and a canvas that clips loudly.
//
// A terminal is a grid of cells, and almost every real TUI defect is arithmetic
// on that grid going wrong. `"Deploy".count` is 6 and `"🚀 Deploy".count` is 8
// while it occupies 9 — one wide glyph puts every column after it off by one,
// the border does not close, and nothing in the source says so.
//
// **This is deliberately the same arithmetic the mock was compiled with.** The
// 22 frames under `design/surfaces/tui/` were measured by tui-craft's
// `char_width`, and `TUIRenderFidelityTests` asserts this renderer reproduces
// every one of them cell for cell. That is the whole fidelity claim for this
// surface: both sides were measured the same way, so a difference between them
// is a difference in the build rather than in the arithmetic.

public enum TUIWidth {

    /// Cells occupied by one scalar: 0, 1 or 2.
    ///
    /// East Asian Width alone is not sufficient — UAX #11 says so — so combining
    /// marks, enclosing marks and format characters are taken by category, and
    /// the emoji planes are taken by range because they render double-width in
    /// most terminals while sitting outside the EAW=W blocks.
    public static func cells(of scalar: Unicode.Scalar) -> Int {
        // ZWJ and the variation selectors, which join rather than occupy.
        if scalar.value == 0x200D || scalar.value == 0xFE0F || scalar.value == 0xFE0E { return 0 }
        if scalar.value == 0 { return 0 }
        if scalar.value < 32 || (0x7F..<0xA0).contains(scalar.value) { return 0 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format: return 0
        default: break
        }
        if isWideOrFullwidth(scalar) { return 2 }
        if (0x1F300...0x1FAFF).contains(scalar.value) { return 2 }
        if (0x1F000...0x1F0FF).contains(scalar.value) { return 2 }
        return 1
    }

    /// Cells a string occupies. This is what `count` gets wrong.
    public static func cells(of text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + cells(of: $1) }
    }

    /// East Asian Width W or F.
    ///
    /// Swift exposes no `east_asian_width` property, so the ranges are carried
    /// here. They are the ones a supervision surface can actually meet — CJK, the
    /// Hangul block, fullwidth forms — rather than the whole table, and anything
    /// outside them measures as one cell. A capture of the running program is
    /// what settles an exotic case; this is what lets the layout be computed at
    /// all.
    static func isWideOrFullwidth(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        switch v {
        case 0x1100...0x115F,          // Hangul Jamo initial
             0x2E80...0x303E,          // CJK radicals, Kangxi, CJK symbols
             0x3041...0x33FF,          // Hiragana through CJK compatibility
             0x3400...0x4DBF,          // CJK extension A
             0x4E00...0x9FFF,          // CJK unified
             0xA000...0xA4CF,          // Yi
             0xAC00...0xD7A3,          // Hangul syllables
             0xF900...0xFAFF,          // CJK compatibility ideographs
             0xFE10...0xFE19,          // vertical forms
             0xFE30...0xFE6F,          // CJK compatibility forms
             0xFF00...0xFF60,          // fullwidth forms
             0xFFE0...0xFFE6,          // fullwidth signs
             0x20000...0x2FFFD,        // CJK extension B and beyond
             0x30000...0x3FFFD:
            return true
        default:
            return false
        }
    }

    /// Split into printable units, keeping zero-width scalars attached to the
    /// scalar they modify.
    ///
    /// Not UAX #29 segmentation and not to be mistaken for it: it handles
    /// combining marks, ZWJ sequences and variation selectors, which is what
    /// terminal text actually throws at a layout. Where text is user-supplied
    /// and may carry arbitrary Unicode, capture the running program rather than
    /// trusting this.
    public static func clusters(of text: String) -> [String] {
        var out: [String] = []
        for scalar in text.unicodeScalars {
            if !out.isEmpty, cells(of: scalar) == 0 {
                out[out.count - 1].unicodeScalars.append(scalar)
            } else {
                out.append(String(scalar))
            }
        }
        return out
    }

    /// Cut to `width` cells, appending a marker when anything was lost.
    ///
    /// The marker is the point: text cut at the edge with nothing to say so
    /// reads as a short string, and the reader never learns there was more.
    public static func truncate(_ text: String, to width: Int,
                                marker: String = "…") -> (text: String, cut: Bool) {
        if cells(of: text) <= width { return (text, false) }
        if width <= 0 { return ("", true) }
        let markerWidth = cells(of: marker)
        let budget = width - markerWidth
        if budget < 0 { return (String(marker.prefix(width)), true) }
        var kept = "", used = 0
        for cluster in clusters(of: text) {
            let w = cells(of: cluster)
            if used + w > budget { break }
            kept += cluster
            used += w
        }
        return (kept + marker, true)
    }
}

/// One painted cell. `width == 0` marks the continuation of a wide cell.
public struct TUICell: Sendable, Equatable {
    public var ch: String
    public var width: Int
    public var role: String

    public init(ch: String = " ", width: Int = 1, role: String = "surface") {
        self.ch = ch; self.width = width; self.role = role
    }
}

/// What a widget could not fit, recorded rather than silently clipped.
///
/// Clipping quietly is what makes a hand-drawn mock lie. A column narrower than
/// its own content, a shelf label too wide for its rule and a table with more
/// rows than room all arrive here.
public struct TUIFitFinding: Sendable, Equatable {
    public let kind: String
    public let where_: String
    public let detail: String

    public init(kind: String, where_: String, detail: String = "") {
        self.kind = kind; self.where_ = where_; self.detail = detail
    }
}

/// A grid that clips at its own edges and records what it lost.
public struct TUICanvas: Sendable {
    public let cols: Int
    public let rows: Int
    public private(set) var cells: [[TUICell]]
    public private(set) var findings: [TUIFitFinding] = []

    public init(cols: Int, rows: Int) {
        self.cols = cols; self.rows = rows
        self.cells = Array(repeating: Array(repeating: TUICell(), count: cols), count: rows)
    }

    public mutating func note(_ kind: String, where_: String, detail: String = "") {
        findings.append(TUIFitFinding(kind: kind, where_: where_, detail: detail))
    }

    /// Write a string starting at (x, y). Returns the cells advanced.
    ///
    /// `limit` is what the caller has to spend. Text longer than that is
    /// truncated with a marker and recorded, because a widget that quietly eats
    /// its own label is the defect this whole file exists to make visible.
    @discardableResult
    public mutating func put(_ x: Int, _ y: Int, _ text: String,
                             role: String = "text", limit: Int? = nil,
                             where_: String = "") -> Int {
        guard y >= 0, y < rows else {
            note("row-off-frame", where_: where_, detail: "row \(y)")
            return 0
        }
        let room = limit.map { min($0, cols - x) } ?? (cols - x)
        guard room > 0 else {
            note("no-room", where_: where_, detail: "row \(y) col \(x)")
            return 0
        }
        let (fitted, cut) = TUIWidth.truncate(text, to: room)
        if cut { note("truncated", where_: where_, detail: "row \(y) col \(x): \(text)") }
        var cx = x
        for cluster in TUIWidth.clusters(of: fitted) {
            let w = TUIWidth.cells(of: cluster)
            if w == 0 { continue }
            if cx + w > cols { break }
            if cx >= 0 {
                cells[y][cx] = TUICell(ch: cluster, width: w, role: role)
                for k in 1..<max(1, w) where cx + k < cols {
                    cells[y][cx + k] = TUICell(ch: "", width: 0, role: role)
                }
            }
            cx += w
        }
        return cx - x
    }

    public mutating func hline(_ x: Int, _ y: Int, _ w: Int, _ ch: String, role: String) {
        guard y >= 0, y < rows else { return }
        for xx in max(0, x)..<min(cols, x + w) { put(xx, y, ch, role: role) }
    }

    public mutating func vline(_ x: Int, _ y: Int, _ h: Int, _ ch: String, role: String) {
        for yy in max(0, y)..<min(rows, y + h) { put(x, yy, ch, role: role) }
    }

    /// The grid as text, one string per row. Continuation cells contribute
    /// nothing, so a row's string is as many cells wide as the grid.
    public var lines: [String] {
        cells.map { row in row.map { $0.width == 0 ? "" : $0.ch }.joined() }
    }
}
