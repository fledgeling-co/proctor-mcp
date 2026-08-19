import Foundation

// PRO-0074. The layout tree, and the widgets that paint into it.
//
// The vocabulary is deliberately the one the compiled frames were written in —
// panel, text, pairs, table, keybar, and containers that divide along an axis —
// so the mock and the build are two renderings of the same description rather
// than two descriptions that have to be kept in step by hand.
//
// **No column numbers appear anywhere in a caller's description.** A caller says
// what a pane contains and how it divides; every cell position is solved here.
// That is what makes the 80-column floor provable rather than hoped for: a
// column narrower than its own content is a recorded finding, not a torn border
// somebody notices in a screenshot.

/// One node of the tree.
public indirect enum TUINode: Sendable {
    /// Children stacked down the region.
    case column([TUIChild])
    /// Children laid across the region.
    case row([TUIChild])
    case panel(TUIPanel)
    case text(TUIText)
    case pairs(TUIPairs)
    case table(TUITable)
    case keybar(TUIKeybar)
    case gauge(TUIGauge)
    case blank
}

/// A child and how much room it asks for. `size` is fixed cells; `flex` shares
/// what is left. A child that names neither takes a flex of 1.
public struct TUIChild: Sendable {
    public let node: TUINode
    public let size: Int?
    public let flex: Double

    public init(_ node: TUINode, size: Int? = nil, flex: Double = 1) {
        self.node = node; self.size = size; self.flex = flex
    }
}

/// A bordered box whose border carries metadata.
///
/// The border is a shelf, not a fence: a title on the left of the top rule, a
/// state in the centre, a count on the right, a page indicator on the bottom.
/// It buys a row of vertical space per panel over putting the same text inside,
/// and puts the metadata where the eye already is.
public struct TUIPanel: Sendable {
    public var title: String?
    public var border: TUIBorder = .round
    public var focus: Bool = false
    public var focusMarker: String? = "▸"
    public var shelfCentre: String?
    public var shelfRight: String?
    public var shelfBottomLeft: String?
    public var shelfBottomRight: String?
    public var pad: Int = 1
    /// Overrides the border's role. Used for the one panel that is an error: the
    /// border carries the state as well as the shelf, so the pane reads as wrong
    /// before a word of it is read.
    public var borderRole: String?
    public var child: TUINode?

    public init(title: String? = nil, border: TUIBorder = .round, focus: Bool = false,
                focusMarker: String? = "▸", shelfCentre: String? = nil,
                shelfRight: String? = nil, shelfBottomLeft: String? = nil,
                shelfBottomRight: String? = nil, pad: Int = 1,
                borderRole: String? = nil, child: TUINode? = nil) {
        self.title = title; self.border = border; self.focus = focus
        self.focusMarker = focusMarker; self.shelfCentre = shelfCentre
        self.shelfRight = shelfRight; self.shelfBottomLeft = shelfBottomLeft
        self.shelfBottomRight = shelfBottomRight; self.pad = pad
        self.borderRole = borderRole; self.child = child
    }
}

public enum TUIBorder: String, Sendable {
    case round, single, double, heavy, none

    /// Top-left, top-right, bottom-left, bottom-right, horizontal, vertical.
    var glyphs: (String, String, String, String, String, String)? {
        switch self {
        case .round: return ("╭", "╮", "╰", "╯", "─", "│")
        case .single: return ("┌", "┐", "└", "┘", "─", "│")
        case .double: return ("╔", "╗", "╚", "╝", "═", "║")
        case .heavy: return ("┏", "┓", "┗", "┛", "━", "┃")
        case .none: return nil
        }
    }
}

public enum TUIAlign: String, Sendable { case left, right, centre }

public struct TUIText: Sendable {
    public var lines: [String]
    public var role: String = "text"
    public var align: TUIAlign = .left

    public init(_ lines: [String], role: String = "text", align: TUIAlign = .left) {
        self.lines = lines; self.role = role; self.align = align
    }
}

/// Label/value rows on two rails.
///
/// The value rail is computed from the widest label rather than declared, so the
/// values line up by construction. Labels are dim and values are the emphasis:
/// the label is the part the reader already knows.
public struct TUIPairs: Sendable {
    public var items: [(String, String)]
    public var gap: Int = 2
    public var labelRole: String = "text-dim"
    public var valueRole: String = "text-strong"

    public init(_ items: [(String, String)], gap: Int = 2,
                labelRole: String = "text-dim", valueRole: String = "text-strong") {
        self.items = items; self.gap = gap
        self.labelRole = labelRole; self.valueRole = valueRole
    }
}

public struct TUIColumn: Sendable {
    public var name: String
    public var width: Int?
    public var flex: Double = 1
    public var align: TUIAlign = .left
    public var role: String = "text"

    public init(_ name: String, width: Int? = nil, flex: Double = 1,
                align: TUIAlign = .left, role: String = "text") {
        self.name = name; self.width = width; self.flex = flex
        self.align = align; self.role = role
    }
}

/// A column table whose widths are solved, not declared.
public struct TUITable: Sendable {
    public var columns: [TUIColumn]
    public var rows: [[String]]
    public var gap: Int = 2
    public var header: Bool = true
    public var headerRule: Bool = true
    /// Reverse video rather than a coloured fill. The 16-colour palette has no
    /// defined RGB mapping, so an app naming `red` cannot know its own contrast
    /// ratio; reverse is an attribute the terminal applies, so it survives
    /// `NO_COLOR`, a pipe and a reader's unhelpful theme.
    public var selected: Int?
    public var selectedRole: String = "selected"
    /// Drawn in a gutter to the left of every row, so selection is carried by a
    /// glyph as well as by reverse video. A row distinguished from its siblings
    /// must stay distinguished when colour is removed.
    public var selectedMarker: String?

    public init(columns: [TUIColumn], rows: [[String]], gap: Int = 2,
                header: Bool = true, headerRule: Bool = true,
                selected: Int? = nil, selectedMarker: String? = nil) {
        self.columns = columns; self.rows = rows; self.gap = gap
        self.header = header; self.headerRule = headerRule
        self.selected = selected; self.selectedMarker = selectedMarker
    }
}

/// The footer, as a live surface rather than a static legend. The key is always
/// visually distinct from the word it operates, because a footer where both are
/// one colour reads as prose.
public struct TUIKeybar: Sendable {
    public var items: [(String, String)]
    public var separator: String = "  "
    public var keyRole: String = "accent"
    public var labelRole: String = "text-dim"

    public init(_ items: [(String, String)], separator: String = "  ") {
        self.items = items; self.separator = separator
    }
}

/// A labelled bar whose number is written as text as well as drawn.
///
/// A bar alone encodes its value in length only, which a screen reader cannot
/// linearise and a reader cannot read off precisely.
public struct TUIGauge: Sendable {
    public var label: String
    public var value: Double
    public var max: Double = 100
    public var readout: String
    public var role: String = "accent"
    public var glyph: String = "█"
    public var track: String = "░"

    public init(label: String, value: Double, max: Double = 100,
                readout: String, role: String = "accent") {
        self.label = label; self.value = value; self.max = max
        self.readout = readout; self.role = role
    }
}

public struct TUIRegion: Sendable, Equatable {
    public var x: Int, y: Int, w: Int, h: Int
    public init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

public enum TUILayout {

    /// Render a tree into a grid.
    public static func render(_ node: TUINode, cols: Int, rows: Int) -> TUICanvas {
        var canvas = TUICanvas(cols: cols, rows: rows)
        paint(TUIRegion(0, 0, cols, rows), node, into: &canvas)
        return canvas
    }

    /// Divide a region among children along one axis.
    ///
    /// Fixed sizes are honoured first, the remainder is shared by weight, and the
    /// rounding remainder goes to the last flexible child so the children always
    /// sum to exactly the parent. A layout whose children sum to one cell less
    /// than their parent is how a one-column gap appears down the middle of a
    /// screen for no reason anybody can find later.
    static func split(_ region: TUIRegion, _ children: [TUIChild],
                      horizontal: Bool) -> [(TUIRegion, TUIChild)] {
        guard !children.isEmpty else { return [] }
        let total = horizontal ? region.w : region.h
        var sizes: [Int?] = children.map(\.size)
        let fixedSum = sizes.compactMap { $0 }.reduce(0, +)
        let free = max(0, total - fixedSum)
        let flexible = sizes.indices.filter { sizes[$0] == nil }
        if !flexible.isEmpty {
            let weightSum = flexible.reduce(0.0) { $0 + children[$1].flex }
            for i in flexible {
                sizes[i] = weightSum > 0 ? Int(Double(free) * children[i].flex / weightSum) : 0
            }
            let drift = free - flexible.reduce(0) { $0 + (sizes[$1] ?? 0) }
            sizes[flexible[flexible.count - 1]]! += drift
        }
        var out: [(TUIRegion, TUIChild)] = []
        var cursor = horizontal ? region.x : region.y
        for (child, size) in zip(children, sizes) {
            let s = max(0, size ?? 0)
            let r = horizontal ? TUIRegion(cursor, region.y, s, region.h)
                               : TUIRegion(region.x, cursor, region.w, s)
            out.append((r, child))
            cursor += s
        }
        return out
    }

    static func paint(_ region: TUIRegion, _ node: TUINode, into canvas: inout TUICanvas) {
        switch node {
        case .blank:
            break
        case .column(let children):
            for (r, c) in split(region, children, horizontal: false) {
                paint(r, c.node, into: &canvas)
            }
        case .row(let children):
            for (r, c) in split(region, children, horizontal: true) {
                paint(r, c.node, into: &canvas)
            }
        case .panel(let p):
            paintPanel(region, p, into: &canvas)
        case .text(let t):
            paintText(region, t, into: &canvas)
        case .pairs(let p):
            paintPairs(region, p, into: &canvas)
        case .table(let t):
            paintTable(region, t, into: &canvas)
        case .keybar(let k):
            paintKeybar(region, k, into: &canvas)
        case .gauge(let g):
            paintGauge(region, g, into: &canvas)
        }
    }

    static func paintPanel(_ region: TUIRegion, _ p: TUIPanel, into canvas: inout TUICanvas) {
        let role = p.borderRole ?? (p.focus ? "border-focus" : "border")
        var inner = region
        if let (tl, tr, bl, br, hz, vt) = p.border.glyphs {
            guard region.w >= 2, region.h >= 2 else {
                canvas.note("panel-too-small", where_: p.title ?? "panel",
                            detail: "\(region.w)x\(region.h)")
                return
            }
            let x0 = region.x, y0 = region.y
            let x1 = region.x + region.w - 1, y1 = region.y + region.h - 1
            canvas.hline(x0 + 1, y0, region.w - 2, hz, role: role)
            canvas.hline(x0 + 1, y1, region.w - 2, hz, role: role)
            canvas.vline(x0, y0 + 1, region.h - 2, vt, role: role)
            canvas.vline(x1, y0 + 1, region.h - 2, vt, role: role)
            canvas.put(x0, y0, tl, role: role)
            canvas.put(x1, y0, tr, role: role)
            canvas.put(x0, y1, bl, role: role)
            canvas.put(x1, y1, br, role: role)
            paintShelf(region, p, into: &canvas)
            inner = TUIRegion(x0 + 1, y0 + 1, region.w - 2, region.h - 2)
        }
        if p.pad > 0 {
            inner = TUIRegion(inner.x + p.pad, inner.y + p.pad,
                              max(0, inner.w - 2 * p.pad), max(0, inner.h - 2 * p.pad))
        }
        if let child = p.child { paint(inner, child, into: &canvas) }
    }

    /// Write the metadata slots into the border rules.
    ///
    /// Each slot is padded with a space either side so it reads as sitting in a
    /// gap in the rule rather than colliding with it. Left, then right, then
    /// centre in what is left; a slot that does not fit is dropped and recorded,
    /// because overlapping shelf text is worse than a missing count.
    static func paintShelf(_ region: TUIRegion, _ p: TUIPanel, into canvas: inout TUICanvas) {
        let topY = region.y, bottomY = region.y + region.h - 1
        let avail = region.w - 2
        guard avail > 2 else { return }
        var title = p.title
        if let t = title, let marker = p.focusMarker, p.focus { title = "\(marker) \(t)" }
        let shelfRole = "text-dim"
        let slots: [(TUIAlign, Int, String?, String)] = [
            (.left, topY, title, p.focus ? "border-focus" : "text-strong"),
            (.right, topY, p.shelfRight, shelfRole),
            (.centre, topY, p.shelfCentre, shelfRole),
            (.left, bottomY, p.shelfBottomLeft, shelfRole),
            (.right, bottomY, p.shelfBottomRight, shelfRole),
        ]
        var used: [Int: [(Int, Int)]] = [topY: [], bottomY: []]
        for (align, y, text, role) in slots {
            guard let text, !text.isEmpty else { continue }
            let label = " \(text) "
            let w = TUIWidth.cells(of: label)
            if w > avail {
                canvas.note("shelf-too-wide", where_: text, detail: "row \(y)")
                continue
            }
            let x: Int
            switch align {
            case .left: x = region.x + 1
            case .right: x = region.x + region.w - 1 - w
            case .centre: x = region.x + 1 + (avail - w) / 2
            }
            if (used[y] ?? []).contains(where: { !(x + w <= $0.0 || x >= $0.1) }) {
                canvas.note("shelf-collision", where_: text, detail: "row \(y)")
                continue
            }
            used[y, default: []].append((x, x + w))
            canvas.put(x, y, label, role: role, limit: w, where_: "shelf")
        }
    }

    static func paintText(_ region: TUIRegion, _ t: TUIText, into canvas: inout TUICanvas) {
        for (i, line) in t.lines.enumerated() {
            if i >= region.h {
                canvas.note("text-overflow-rows", where_: "text",
                            detail: "\(t.lines.count) lines in \(region.h) rows")
                break
            }
            let x = region.x + offset(line, in: region.w, align: t.align)
            canvas.put(x, region.y + i, line, role: t.role,
                       limit: region.w - (x - region.x), where_: "text")
        }
    }

    static func paintPairs(_ region: TUIRegion, _ p: TUIPairs, into canvas: inout TUICanvas) {
        let widest = p.items.map { TUIWidth.cells(of: $0.0) }.max() ?? 0
        let rail = widest + p.gap
        if rail + 1 > region.w {
            canvas.note("pairs-rail-overflow", where_: "pairs",
                        detail: "rail \(rail) in \(region.w)")
        }
        for (i, item) in p.items.enumerated() {
            if i >= region.h {
                canvas.note("pairs-overflow-rows", where_: "pairs",
                            detail: "\(p.items.count) in \(region.h)")
                break
            }
            let y = region.y + i
            canvas.put(region.x, y, item.0, role: p.labelRole, limit: rail,
                       where_: "pairs:label")
            canvas.put(region.x + rail, y, item.1, role: p.valueRole,
                       limit: region.w - rail, where_: "pairs:value")
        }
    }

    static func paintTable(_ region: TUIRegion, _ t: TUITable, into canvas: inout TUICanvas) {
        guard !t.columns.isEmpty else { return }
        let marker = t.selectedMarker ?? ""
        let gutter = marker.isEmpty ? 0 : TUIWidth.cells(of: marker) + 1
        let avail = region.w - t.gap * (t.columns.count - 1) - gutter
        var widths: [Int?] = t.columns.map(\.width)
        var natural: [Int] = []
        for (i, column) in t.columns.enumerated() {
            let body = t.rows.compactMap { i < $0.count ? TUIWidth.cells(of: $0[i]) : nil }
                .max() ?? 0
            natural.append(max(body, TUIWidth.cells(of: column.name)))
        }
        let fixed = widths.compactMap { $0 }.reduce(0, +)
        let flexible = widths.indices.filter { widths[$0] == nil }
        let free = avail - fixed
        if !flexible.isEmpty {
            let weightSum = flexible.reduce(0.0) { $0 + t.columns[$1].flex }
            for i in flexible {
                widths[i] = max(1, Int(Double(free) * t.columns[i].flex / weightSum))
            }
            widths[flexible[flexible.count - 1]]! += free - flexible.reduce(0) { $0 + (widths[$1] ?? 0) }
        }
        for (i, width) in widths.enumerated() where natural[i] > (width ?? 0) {
            // The 80-column floor is proven here rather than hoped for: a column
            // narrower than its own content says so instead of clipping quietly.
            canvas.note("column-too-narrow", where_: t.columns[i].name,
                        detail: "wanted \(natural[i]), had \(width ?? 0)")
        }
        var xs: [Int] = []
        var cursor = region.x + gutter
        for width in widths {
            xs.append(cursor)
            cursor += (width ?? 0) + t.gap
        }
        var y = region.y
        if t.header {
            for (i, column) in t.columns.enumerated() {
                let w = widths[i] ?? 0
                canvas.put(xs[i] + offset(column.name, in: w, align: column.align), y,
                           column.name, role: "text-strong", limit: w, where_: "table:header")
            }
            y += 1
            if t.headerRule {
                canvas.hline(region.x, y, region.w, "─", role: "border")
                y += 1
            }
        }
        for (ri, row) in t.rows.enumerated() {
            if y >= region.y + region.h {
                canvas.note("table-overflow-rows", where_: "table",
                            detail: "\(t.rows.count) rows in \(region.h)")
                break
            }
            let isSelected = t.selected == ri
            for (ci, x) in xs.enumerated() where ci < row.count {
                let w = widths[ci] ?? 0
                // A selected row overrides its cells' semantic colour. Keeping
                // both makes the row unreadable and makes the category colour
                // mean two things.
                let role = isSelected ? t.selectedRole : t.columns[ci].role
                canvas.put(x + offset(row[ci], in: w, align: t.columns[ci].align), y,
                           row[ci], role: role, limit: w, where_: "table:cell")
            }
            if isSelected, !marker.isEmpty {
                canvas.put(region.x, y, marker, role: "accent", limit: gutter,
                           where_: "table:marker")
            }
            y += 1
        }
    }

    static func paintKeybar(_ region: TUIRegion, _ k: TUIKeybar, into canvas: inout TUICanvas) {
        var x = region.x
        for (i, item) in k.items.enumerated() {
            let cap = "[\(item.0)]"
            let textWidth = TUIWidth.cells(of: cap) + 1 + TUIWidth.cells(of: item.1)
            let sepWidth = i > 0 ? TUIWidth.cells(of: k.separator) : 0
            if x + sepWidth + textWidth > region.x + region.w {
                canvas.note("keybar-overflow", where_: item.1,
                            detail: "showed \(i) of \(k.items.count)")
                break
            }
            if i > 0 {
                x += canvas.put(x, region.y, k.separator, role: "text-dim", limit: sepWidth)
            }
            x += canvas.put(x, region.y, cap, role: k.keyRole,
                            limit: region.x + region.w - x, where_: "keybar")
            x += canvas.put(x, region.y, " " + item.1, role: k.labelRole,
                            limit: region.x + region.w - x, where_: "keybar")
        }
    }

    static func paintGauge(_ region: TUIRegion, _ g: TUIGauge, into canvas: inout TUICanvas) {
        let fraction = Swift.max(0, Swift.min(1, g.value / (g.max == 0 ? 100 : g.max)))
        let labelWidth = TUIWidth.cells(of: g.label) + (g.label.isEmpty ? 0 : 1)
        let readoutWidth = TUIWidth.cells(of: g.readout) + 1
        var barWidth = region.w - labelWidth - readoutWidth
        if barWidth < 3 {
            canvas.note("gauge-too-narrow", where_: g.label,
                        detail: "had \(region.w), wanted \(labelWidth + readoutWidth + 3)")
            barWidth = Swift.max(0, barWidth)
        }
        var x = region.x
        if !g.label.isEmpty {
            x += canvas.put(x, region.y, g.label + " ", role: "text-dim",
                            limit: labelWidth, where_: "gauge:label")
        }
        let filled = Int((Double(barWidth) * fraction).rounded())
        canvas.put(x, region.y, String(repeating: g.glyph, count: filled),
                   role: g.role, limit: barWidth, where_: "gauge:bar")
        canvas.put(x + filled, region.y,
                   String(repeating: g.track, count: Swift.max(0, barWidth - filled)),
                   role: "border", limit: barWidth - filled, where_: "gauge:track")
        canvas.put(x + barWidth + 1, region.y, g.readout, role: "text",
                   limit: readoutWidth, where_: "gauge:readout")
    }

    static func offset(_ text: String, in width: Int, align: TUIAlign) -> Int {
        let w = TUIWidth.cells(of: text)
        switch align {
        case .right: return max(0, width - w)
        case .centre: return max(0, (width - w) / 2)
        case .left: return 0
        }
    }
}
