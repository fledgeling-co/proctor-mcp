import Foundation
import ProctorCore

extension FindPredicate {
    /// Build a predicate from the `find` object that several tools accept.
    /// Every supplied condition must hold, so an empty object matches nothing
    /// useful and is rejected by the callers that require a subject.
    init(json: JSONValue?) {
        self.init()
        guard let json else { return }
        role = json["role"]?.stringValue
        subrole = json["subrole"]?.stringValue
        title = json["title"]?.stringValue
        label = json["label"]?.stringValue
        identifier = json["identifier"]?.stringValue
        valueContains = json["valueContains"]?.stringValue
        enabled = json["enabled"]?.boolValue
        focused = json["focused"]?.boolValue
        hasAction = json["hasAction"]?.stringValue
        if let raw = json["match"]?.stringValue, let mode = MatchMode(rawValue: raw) {
            match = mode
        }
    }

    var isEmpty: Bool {
        role == nil && subrole == nil && title == nil && label == nil && identifier == nil
            && valueContains == nil && enabled == nil && focused == nil && hasAction == nil
    }

    var described: JSONValue {
        var out: [String: JSONValue] = ["match": .string(match.rawValue)]
        if let role { out["role"] = .string(role) }
        if let subrole { out["subrole"] = .string(subrole) }
        if let title { out["title"] = .string(title) }
        if let label { out["label"] = .string(label) }
        if let identifier { out["identifier"] = .string(identifier) }
        if let valueContains { out["valueContains"] = .string(valueContains) }
        if let enabled { out["enabled"] = .bool(enabled) }
        if let focused { out["focused"] = .bool(focused) }
        if let hasAction { out["hasAction"] = .string(hasAction) }
        return .object(out)
    }
}

/// Flat text for a JSONValue, used where a value has to be compared as a
/// substring or reported next to an expectation.
enum JSONText {
    static func describe(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .string(let s): return s
        case .array(let a): return a.map(describe).joined(separator: ",")
        case .object(let o): return o.keys.sorted().map { "\($0):\(describe(o[$0]))" }
                                          .joined(separator: ",")
        }
    }

    /// Loose equality, so `expected: 3` matches an AX value of `"3"`. AX values
    /// arrive as whatever type the app chose to expose and a test written
    /// against the visible text should not fail on that.
    static func equal(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
        if a == b { return true }
        guard let a, let b else { return false }
        if let x = a.doubleValue, let y = b.doubleValue { return x == y }
        return describe(a) == describe(b)
    }
}

extension Rect {
    static func from(_ value: JSONValue?) -> Rect? {
        guard let value else { return nil }
        if let a = value.arrayValue, a.count == 4 {
            let n = a.compactMap(\.doubleValue)
            guard n.count == 4 else { return nil }
            return Rect(x: n[0], y: n[1], w: n[2], h: n[3])
        }
        if let o = value.objectValue,
           let x = o["x"]?.doubleValue, let y = o["y"]?.doubleValue,
           let w = o["w"]?.doubleValue, let h = o["h"]?.doubleValue {
            return Rect(x: x, y: y, w: w, h: h)
        }
        return nil
    }

    var json: JSONValue { SnapshotDiffer.rectValue(self) }
    var maxX: Double { x + w }
    var maxY: Double { y + h }
    var centerX: Double { x + w / 2 }
    var centerY: Double { y + h / 2 }
}

extension AXNode {
    /// A compact node description for assertion and wait output, where the
    /// whole node would drown the verdict.
    var summary: JSONValue {
        var out: [String: JSONValue] = ["id": .string(id), "role": .string(role)]
        if let subrole { out["subrole"] = .string(subrole) }
        if let title { out["title"] = .string(title) }
        if let label { out["label"] = .string(label) }
        if let identifier { out["identifier"] = .string(identifier) }
        if let value { out["value"] = value }
        if let frame { out["frame"] = frame.json }
        if let enabled { out["enabled"] = .bool(enabled) }
        if let focused { out["focused"] = .bool(focused) }
        if let selected { out["selected"] = .bool(selected) }
        return .object(out)
    }

    var accessibleName: String? {
        for candidate in [label, title, help, identifier] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                return candidate
            }
        }
        return nil
    }

    // flattened() lives on the AX side, in TreeWalker.swift.

    /// Depth-first, children in tree order. AX order is the focus order, so it
    /// is the sequence a focus-order assertion is about.
    func inTreeOrder() -> [AXNode] {
        var out: [AXNode] = []
        func visit(_ node: AXNode) {
            out.append(node)
            for child in node.children ?? [] { visit(child) }
        }
        visit(self)
        return out
    }
}
