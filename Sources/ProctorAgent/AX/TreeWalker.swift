import Foundation
import ApplicationServices
import ProctorCore

/// Depth-first walk of one window's subtree.
///
/// Node ids come from a structural path — role plus the element's index among
/// its same-role siblings — so the same element gets the same id on a second
/// walk even though the underlying AXUIElementRef is a fresh object each time.
/// The refs the walk retains are kept by the caller, because a retained ref
/// resolves after its window moves to another Space and a fresh enumeration
/// of that Space's windows does not find it.
final class TreeWalker {

    struct Budget {
        var maxDepth: Int
        var maxNodes: Int
        /// Wall-clock ceiling. A node budget alone does not bound a walk: some
        /// applications answer each element more slowly the deeper into a large
        /// list you go, so a budget that returns in a moment on one window takes
        /// half a minute on another. The deadline makes a walk always return,
        /// and the truncation is reported rather than passed off as a whole tree.
        var maxMs: Int = 6000
        var includeInvisible: Bool
    }

    let windowId: String
    let budget: Budget
    let log = UnsupportedLog()

    private(set) var refs: [String: NodeRef] = [:]
    private(set) var truncatedAtDepth: Int?
    private(set) var truncatedAtCount: Int?
    private(set) var truncatedByDeadline = false
    private var emitted = 0
    private var deadline = Date.distantFuture

    init(windowId: String, budget: Budget) {
        self.windowId = windowId
        self.budget = budget
    }

    /// Read in a single batch per node. Order is irrelevant; membership is not —
    /// an attribute missing here is a field that will always come back nil.
    static let nodeAttributes: [String] = [
        kAXSubroleAttribute, kAXRoleDescriptionAttribute, kAXTitleAttribute,
        kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute,
        kAXIdentifierAttribute, kAXPositionAttribute, kAXSizeAttribute,
        kAXEnabledAttribute, kAXFocusedAttribute, kAXSelectedAttribute,
    ]

    static func nodeId(window: String, path: String) -> String {
        "nd:" + Canonical.hash("\(window)|\(path)").prefix(16)
    }

    func walk(root: AXUIElement, rootPath: String? = nil) -> AXNode {
        let role = AXRead.string(root, kAXRoleAttribute, log: log) ?? "AXUnknown"
        let path = rootPath ?? role
        deadline = Date().addingTimeInterval(Double(max(budget.maxMs, 250)) / 1000)
        return build(root, path: path, depth: 0, forcedRole: role)
    }

    private func build(_ element: AXUIElement, path: String, depth: Int,
                       forcedRole: String? = nil) -> AXNode {
        AXUIElementSetMessagingTimeout(element, AXTimeout.walk)

        let role = forcedRole ?? AXRead.string(element, kAXRoleAttribute, log: log) ?? "AXUnknown"
        let id = Self.nodeId(window: windowId, path: path)
        refs[id] = NodeRef(element: element, window: windowId, path: path)
        emitted += 1

        let actions = AXRead.actions(element)

        // One round trip for the whole node instead of twelve. A walk is
        // dominated by IPC, and a target whose accessibility implementation
        // degrades under load makes per-attribute reads worse than linear.
        let box = AXRead.multiple(element, Self.nodeAttributes)

        var node = AXNode(
            id: id,
            role: role,
            subrole: AXRead.string(box, kAXSubroleAttribute),
            roleDescription: AXRead.string(box, kAXRoleDescriptionAttribute),
            title: AXRead.string(box, kAXTitleAttribute),
            label: AXRead.string(box, kAXDescriptionAttribute),
            value: box[kAXValueAttribute].map { AXRead.json($0) },
            help: AXRead.string(box, kAXHelpAttribute),
            identifier: AXRead.string(box, kAXIdentifierAttribute),
            frame: AXRead.rect(box, position: kAXPositionAttribute, size: kAXSizeAttribute),
            enabled: AXRead.bool(box, kAXEnabledAttribute),
            focused: AXRead.bool(box, kAXFocusedAttribute),
            selected: AXRead.bool(box, kAXSelectedAttribute),
            actions: actions,
            writableAttributes: AXRead.shouldProbeSettability(role: role, hasActions: !actions.isEmpty)
                ? AXRead.settableAttributes(element, from: AXRead.attributeNames(element))
                : [],
            children: nil,
            childCount: 0
        )

        let children = AXRead.elements(element, kAXChildrenAttribute, log: log)
        node.childCount = children.count
        guard !children.isEmpty else { return node }

        if depth + 1 > budget.maxDepth {
            truncatedAtDepth = min(truncatedAtDepth ?? Int.max, depth + 1)
            return node
        }

        var counts: [String: Int] = [:]
        var kids: [AXNode] = []
        for child in children {
            if Date() >= deadline {
                truncatedByDeadline = true
                truncatedAtCount = emitted
                break
            }
            if emitted >= budget.maxNodes {
                truncatedAtCount = budget.maxNodes
                break
            }
            let childRole = AXRead.string(child, kAXRoleAttribute, log: log) ?? "AXUnknown"
            let index = counts[childRole, default: 0]
            counts[childRole] = index + 1
            let childPath = "\(path)/\(childRole)[\(index)]"

            if !budget.includeInvisible, isInvisible(child) { continue }

            kids.append(build(child, path: childPath, depth: depth + 1, forcedRole: childRole))
        }
        node.children = kids
        return node
    }

    /// Zero-area and offering no actions is the pair that means "not there".
    /// Either alone is common and legitimate: an off-screen but actionable
    /// control is real, and a zero-area label may still be read by VoiceOver.
    private func isInvisible(_ element: AXUIElement) -> Bool {
        guard let frame = AXRead.frame(element, log: log) else { return false }
        guard frame.w == 0 || frame.h == 0 else { return false }
        return AXRead.actions(element).isEmpty
    }
}

extension AXNode {
    func flattened() -> [AXNode] {
        var out: [AXNode] = [self]
        for child in children ?? [] { out.append(contentsOf: child.flattened()) }
        return out
    }

    var withoutChildren: AXNode {
        var copy = self
        copy.children = nil
        return copy
    }
}

extension FindPredicate {

    func matches(_ node: AXNode) -> Bool {
        if let role, !compare(node.role, role) { return false }
        if let subrole, !compare(node.subrole, subrole) { return false }
        if let title, !compare(node.title, title) { return false }
        if let label, !compare(node.label, label) { return false }
        if let identifier, !compare(node.identifier, identifier) { return false }
        if let valueContains {
            guard let value = node.value, compare(describe(value), valueContains) else { return false }
        }
        if let enabled, node.enabled != enabled { return false }
        if let focused, node.focused != focused { return false }
        if let hasAction, !node.actions.contains(where: { compare($0, hasAction) }) { return false }
        return true
    }

    private func compare(_ candidate: String?, _ wanted: String) -> Bool {
        guard let candidate else { return false }
        switch match {
        case .exact:
            return candidate == wanted
        case .substring:
            return candidate.range(of: wanted, options: .caseInsensitive) != nil
        case .regex:
            guard let re = try? NSRegularExpression(pattern: wanted, options: [.caseInsensitive])
            else { return false }
            let range = NSRange(candidate.startIndex..., in: candidate)
            return re.firstMatch(in: candidate, range: range) != nil
        }
    }

    private func describe(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        case .array, .object:
            return (try? String(data: JSONEncoder().encode(value), encoding: .utf8) ?? "") ?? ""
        }
    }
}
