import Foundation
import ProctorCore

// Tree-to-tree comparison keyed by node id. This is what makes repeated reads
// during a flow cost tokens proportional to what changed rather than to the
// size of the window.

enum SnapshotDiffer {

    /// Sub-point geometry drift is not a state change. Treating it as one makes
    /// every view that animates or rounds differently look unstable.
    static let frameEpsilon: Double = 1.0

    static func diff(from old: AXNode?, to new: AXNode, fromRevision: Int) -> SnapshotDiff {
        var oldMap: [String: AXNode] = [:]
        if let old { flatten(old, into: &oldMap) }
        var newMap: [String: AXNode] = [:]
        flatten(new, into: &newMap)

        var added: [AXNode] = []
        var changed: [NodeChange] = []
        var unchanged = 0

        for (id, node) in newMap {
            guard let before = oldMap[id] else {
                added.append(node)
                continue
            }
            let fields = changedFields(before: before, after: node)
            if fields.isEmpty {
                unchanged += 1
            } else {
                changed.append(NodeChange(id: id, fields: fields))
            }
        }

        let removed = oldMap.keys.filter { newMap[$0] == nil }

        // Dictionary iteration order is not stable between runs. An unstable
        // diff would make two identical transitions compare unequal, which is
        // the thing the determinism instrument is meant to detect for real.
        added.sort { $0.id < $1.id }
        changed.sort { $0.id < $1.id }

        return SnapshotDiff(fromRevision: fromRevision,
                            added: added,
                            removed: removed.sorted(),
                            changed: changed,
                            unchangedCount: unchanged)
    }

    /// Nodes are flattened with their children detached. When a whole panel
    /// appears, every descendant is reported once on its own terms rather than
    /// once nested inside its parent and again as itself.
    private static func flatten(_ node: AXNode, into map: inout [String: AXNode]) {
        var shallow = node
        shallow.children = nil
        map[node.id] = shallow
        for child in node.children ?? [] {
            flatten(child, into: &map)
        }
    }

    private static func changedFields(before: AXNode, after: AXNode) -> [String: FieldDelta] {
        var out: [String: FieldDelta] = [:]

        if before.role != after.role {
            out["role"] = FieldDelta(before: .string(before.role), after: .string(after.role))
        }
        addString("title", before.title, after.title, &out)
        addString("label", before.label, after.label, &out)

        if before.value != after.value {
            out["value"] = FieldDelta(before: before.value, after: after.value)
        }
        if frameChanged(before.frame, after.frame) {
            out["frame"] = FieldDelta(before: before.frame.map(rectValue),
                                      after: after.frame.map(rectValue))
        }
        addBool("enabled", before.enabled, after.enabled, &out)
        addBool("focused", before.focused, after.focused, &out)
        addBool("selected", before.selected, after.selected, &out)

        return out
    }

    private static func addString(_ key: String, _ before: String?, _ after: String?,
                                  _ out: inout [String: FieldDelta]) {
        guard before != after else { return }
        out[key] = FieldDelta(before: before.map(JSONValue.string),
                              after: after.map(JSONValue.string))
    }

    private static func addBool(_ key: String, _ before: Bool?, _ after: Bool?,
                                _ out: inout [String: FieldDelta]) {
        guard before != after else { return }
        out[key] = FieldDelta(before: before.map(JSONValue.bool),
                              after: after.map(JSONValue.bool))
    }

    static func frameChanged(_ before: Rect?, _ after: Rect?) -> Bool {
        switch (before, after) {
        case (nil, nil): return false
        case (nil, _), (_, nil): return true
        case let (a?, b?):
            return abs(a.x - b.x) >= frameEpsilon
                || abs(a.y - b.y) >= frameEpsilon
                || abs(a.w - b.w) >= frameEpsilon
                || abs(a.h - b.h) >= frameEpsilon
        }
    }

    static func rectValue(_ r: Rect) -> JSONValue {
        .object(["x": .number(r.x), "y": .number(r.y), "w": .number(r.w), "h": .number(r.h)])
    }
}
