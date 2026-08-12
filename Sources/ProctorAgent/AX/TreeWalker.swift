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
        var includeInvisible: Bool
    }

    let windowId: String
    let budget: Budget
    let log = UnsupportedLog()

    private(set) var refs: [String: NodeRef] = [:]
    private(set) var truncatedAtDepth: Int?
    private(set) var truncatedAtCount: Int?
    private var emitted = 0

    init(windowId: String, budget: Budget) {
        self.windowId = windowId
        self.budget = budget
    }

    static func nodeId(window: String, path: String) -> String {
        "nd:" + Canonical.hash("\(window)|\(path)").prefix(16)
    }

    func walk(root: AXUIElement, rootPath: String? = nil) -> AXNode {
        let role = AXRead.string(root, kAXRoleAttribute, log: log) ?? "AXUnknown"
        let path = rootPath ?? role
        return build(root, path: path, depth: 0, forcedRole: role)
    }

    private func build(_ element: AXUIElement, path: String, depth: Int,
                       forcedRole: String? = nil) -> AXNode {
        AXUIElementSetMessagingTimeout(element, AXTimeout.walk)

        let role = forcedRole ?? AXRead.string(element, kAXRoleAttribute, log: log) ?? "AXUnknown"
        let id = Self.nodeId(window: windowId, path: path)
        refs[id] = NodeRef(element: element, window: windowId, path: path)
        emitted += 1

        let attributeNames = AXRead.attributeNames(element)
        let actions = AXRead.actions(element)

        var node = AXNode(
            id: id,
            role: role,
            subrole: AXRead.string(element, kAXSubroleAttribute, log: log),
            roleDescription: AXRead.string(element, kAXRoleDescriptionAttribute, log: log),
            title: AXRead.string(element, kAXTitleAttribute, log: log),
            label: AXRead.string(element, kAXDescriptionAttribute, log: log),
            value: AXRead.value(element, log: log),
            help: AXRead.string(element, kAXHelpAttribute, log: log),
            identifier: AXRead.string(element, kAXIdentifierAttribute, log: log),
            frame: AXRead.frame(element, log: log),
            enabled: AXRead.bool(element, kAXEnabledAttribute, log: log),
            focused: AXRead.bool(element, kAXFocusedAttribute, log: log),
            selected: AXRead.bool(element, kAXSelectedAttribute, log: log),
            actions: actions,
            writableAttributes: AXRead.settableAttributes(element, from: attributeNames),
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
