import Foundation
import ApplicationServices
import ProctorCore

// Reading the accessibility API. Every read goes through here so that the two
// ordinary "failures" — kAXErrorAttributeUnsupported and kAXErrorNoValue — are
// recorded as provenance instead of ending a walk. Most elements answer only a
// handful of the attributes anyone might ask for, so treating either as an
// error would abort on the first ordinary element.

enum AXAttr {
    /// Not exported to Swift by the SDK; Chromium and Electron only build a tree
    /// once a client sets this on the application element.
    static let manualAccessibility = "AXManualAccessibility"
    static let enhancedUserInterface = "AXEnhancedUserInterface"

    static let scrollUpByPage = "AXScrollUpByPage"
    static let scrollDownByPage = "AXScrollDownByPage"
    static let scrollLeftByPage = "AXScrollLeftByPage"
    static let scrollRightByPage = "AXScrollRightByPage"
}

enum AXTimeout {
    /// A hung app must not wedge the agent. Walks give up sooner than actions,
    /// which may legitimately take a moment to return.
    static let walk: Float = 2.0
    static let action: Float = 5.0
}

/// Structural attributes are never settable and probing each one costs an IPC
/// round trip per node, which is the dominant cost of a large walk.
let axStructuralAttributes: Set<String> = [
    kAXRoleAttribute, kAXSubroleAttribute, kAXRoleDescriptionAttribute,
    kAXChildrenAttribute, kAXParentAttribute, kAXWindowAttribute,
    kAXTopLevelUIElementAttribute, kAXIdentifierAttribute, kAXHelpAttribute,
    "AXChildrenInNavigationOrder", "AXFrame",
]

/// Collects the attribute names an app declined, shared across one walk.
final class UnsupportedLog {
    private(set) var names: Set<String> = []
    func record(_ name: String) { names.insert(name) }
    var sorted: [String] { names.sorted() }
}

enum AXRead {

    static func raw(_ element: AXUIElement, _ attribute: String,
                    log: UnsupportedLog? = nil) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        switch err {
        case .success:
            return value
        case .attributeUnsupported, .noValue:
            log?.record(attribute)
            return nil
        default:
            return nil
        }
    }

    static func string(_ element: AXUIElement, _ attribute: String,
                       log: UnsupportedLog? = nil) -> String? {
        guard let v = raw(element, attribute, log: log) else { return nil }
        if CFGetTypeID(v) == CFStringGetTypeID() { return (v as! CFString) as String }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func bool(_ element: AXUIElement, _ attribute: String,
                     log: UnsupportedLog? = nil) -> Bool? {
        guard let v = raw(element, attribute, log: log) else { return nil }
        if CFGetTypeID(v) == CFBooleanGetTypeID() { return CFBooleanGetValue((v as! CFBoolean)) }
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }

    static func element(_ element: AXUIElement, _ attribute: String,
                        log: UnsupportedLog? = nil) -> AXUIElement? {
        guard let v = raw(element, attribute, log: log) else { return nil }
        guard CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String,
                         log: UnsupportedLog? = nil) -> [AXUIElement] {
        guard let v = raw(element, attribute, log: log) else { return [] }
        guard CFGetTypeID(v) == CFArrayGetTypeID() else { return [] }
        let array = v as! CFArray
        let count = CFArrayGetCount(array)
        var out: [AXUIElement] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            guard let ptr = CFArrayGetValueAtIndex(array, i) else { continue }
            let obj = unsafeBitCast(ptr, to: CFTypeRef.self)
            guard CFGetTypeID(obj) == AXUIElementGetTypeID() else { continue }
            out.append(obj as! AXUIElement)
        }
        return out
    }

    static func point(_ element: AXUIElement, _ attribute: String,
                      log: UnsupportedLog? = nil) -> CGPoint? {
        guard let v = raw(element, attribute, log: log),
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var out = CGPoint.zero
        guard AXValueGetValue((v as! AXValue), .cgPoint, &out) else { return nil }
        return out
    }

    static func size(_ element: AXUIElement, _ attribute: String,
                     log: UnsupportedLog? = nil) -> CGSize? {
        guard let v = raw(element, attribute, log: log),
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var out = CGSize.zero
        guard AXValueGetValue((v as! AXValue), .cgSize, &out) else { return nil }
        return out
    }

    static func frame(_ element: AXUIElement, log: UnsupportedLog? = nil) -> Rect? {
        let p = point(element, kAXPositionAttribute, log: log)
        let s = size(element, kAXSizeAttribute, log: log)
        guard p != nil || s != nil else { return nil }
        let origin = p ?? .zero
        let extent = s ?? .zero
        return Rect(x: Double(origin.x), y: Double(origin.y),
                    w: Double(extent.width), h: Double(extent.height))
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    static func attributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    /// Roles that can plausibly hold a writable value. Probing settability costs
    /// one IPC round trip per attribute per element, so probing every node in a
    /// 2000-node tree is tens of thousands of round trips and takes tens of
    /// seconds. Restricting it to the roles a test would ever write to, plus any
    /// node that offers an action, keeps a full walk to a handful of probes.
    static let valueBearingRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXStaticText", "AXComboBox", "AXSlider",
        "AXIncrementor", "AXStepper", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXMenuButton", "AXScrollBar", "AXValueIndicator", "AXProgressIndicator",
        "AXSearchField", "AXSecureTextField", "AXDisclosureTriangle", "AXSwitch",
        "AXWindow", "AXCell", "AXRow", "AXOutline", "AXTable", "AXList",
    ]

    static func shouldProbeSettability(role: String, hasActions: Bool) -> Bool {
        hasActions || valueBearingRoles.contains(role)
    }

    static func settableAttributes(_ element: AXUIElement, from names: [String]) -> [String] {
        var out: [String] = []
        for name in names where !axStructuralAttributes.contains(name) {
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
            else { continue }
            if settable.boolValue { out.append(name) }
        }
        return out
    }

    /// AX values are genuinely heterogeneous, so anything that is not a scalar,
    /// an array or a geometry box is reduced to its description rather than dropped.
    static func json(_ value: CFTypeRef) -> JSONValue {
        let type = CFGetTypeID(value)
        if type == CFStringGetTypeID() { return .string((value as! CFString) as String) }
        if type == CFBooleanGetTypeID() {
            return .bool(CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self)))
        }
        if type == CFNumberGetTypeID() {
            return .number((value as! NSNumber).doubleValue)
        }
        if type == CFArrayGetTypeID() {
            let array = value as! CFArray
            var out: [JSONValue] = []
            for i in 0..<CFArrayGetCount(array) {
                guard let ptr = CFArrayGetValueAtIndex(array, i) else { continue }
                out.append(json(unsafeBitCast(ptr, to: CFTypeRef.self)))
            }
            return .array(out)
        }
        if type == AXValueGetTypeID() {
            let v = value as! AXValue
            switch AXValueGetType(v) {
            case .cgPoint:
                var p = CGPoint.zero
                AXValueGetValue(v, .cgPoint, &p)
                return .object(["x": .number(Double(p.x)), "y": .number(Double(p.y))])
            case .cgSize:
                var s = CGSize.zero
                AXValueGetValue(v, .cgSize, &s)
                return .object(["w": .number(Double(s.width)), "h": .number(Double(s.height))])
            case .cgRect:
                var r = CGRect.zero
                AXValueGetValue(v, .cgRect, &r)
                return .object(["x": .number(Double(r.origin.x)), "y": .number(Double(r.origin.y)),
                                "w": .number(Double(r.width)), "h": .number(Double(r.height))])
            case .cfRange:
                var r = CFRange(location: 0, length: 0)
                AXValueGetValue(v, .cfRange, &r)
                return .object(["location": .number(Double(r.location)),
                                "length": .number(Double(r.length))])
            default:
                return .string(String(describing: v))
            }
        }
        if type == AXUIElementGetTypeID() { return .string("<AXUIElement>") }
        if CFGetTypeID(value) == CFNullGetTypeID() { return .null }
        return .string(String(describing: value))
    }

    static func value(_ element: AXUIElement, log: UnsupportedLog? = nil) -> JSONValue? {
        guard let v = raw(element, kAXValueAttribute, log: log) else { return nil }
        return json(v)
    }
}

enum AXWrite {

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }

    static func cfValue(from json: JSONValue) -> CFTypeRef {
        switch json {
        case .null: return kCFNull
        case .bool(let b): return b ? kCFBooleanTrue : kCFBooleanFalse
        case .number(let n): return NSNumber(value: n)
        case .string(let s): return s as CFString
        case .array, .object:
            let text = (try? String(data: JSONEncoder().encode(json), encoding: .utf8)) ?? nil
            return (text ?? "") as CFString
        }
    }
}

extension AXError {
    var isSuccess: Bool { self == .success }

    var shortName: String {
        switch self {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown(\(rawValue))"
        }
    }

    func asAgentError(_ context: String) -> AgentError {
        switch self {
        case .apiDisabled:
            return AgentError(code: .permissionAccessibility,
                              message: "\(context): the accessibility API is disabled for this process",
                              remedy: Grants.accessibilityFixText(osMajor: 26))
        case .invalidUIElement:
            return AgentError(code: .nodeStale,
                              message: "\(context): the element has been invalidated",
                              remedy: "Re-snapshot the window and use the fresh node id.")
        case .actionUnsupported, .notificationUnsupported:
            return AgentError(code: .actionUnsupported, message: "\(context): \(shortName)")
        default:
            return AgentError(code: .actionFailed, message: "\(context): \(shortName)")
        }
    }
}

// MARK: - Batched reads

extension AXRead {
    /// One round trip for many attributes instead of one per attribute.
    ///
    /// A tree walk is dominated by IPC, not by parsing: reading fifteen
    /// attributes on two thousand nodes one at a time is thirty thousand
    /// synchronous round trips to the target process, and a target whose own
    /// accessibility implementation slows down under load makes that worse than
    /// linear. `AXUIElementCopyMultipleAttributeValues` asks once.
    ///
    /// `.stopOnError` is deliberately not passed: an element that does not
    /// support one attribute in the list still answers for the rest, and the
    /// unsupported ones come back as AXValue error placeholders.
    static func multiple(_ element: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
        var values: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(
            element, names as CFArray, AXCopyMultipleAttributeOptions(), &values)
        guard err == .success, let array = values as? [CFTypeRef],
              array.count == names.count else { return [:] }

        var out: [String: CFTypeRef] = [:]
        out.reserveCapacity(names.count)
        for (name, value) in zip(names, array) {
            // An unsupported attribute arrives as an AXValue wrapping an
            // AXError. Keeping it would turn "this element has no title" into a
            // title, so it is dropped rather than stored.
            if CFGetTypeID(value) == AXValueGetTypeID(),
               AXValueGetType(value as! AXValue) == .axError { continue }
            if CFGetTypeID(value) == CFNullGetTypeID() { continue }
            out[name] = value
        }
        return out
    }

    static func string(_ box: [String: CFTypeRef], _ name: String) -> String? {
        guard let v = box[name], CFGetTypeID(v) == CFStringGetTypeID() else { return nil }
        let s = v as! String
        return s.isEmpty ? nil : s
    }

    static func bool(_ box: [String: CFTypeRef], _ name: String) -> Bool? {
        guard let v = box[name], CFGetTypeID(v) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((v as! CFBoolean))
    }

    static func rect(_ box: [String: CFTypeRef],
                     position: String, size: String) -> Rect? {
        guard let p = box[position], CFGetTypeID(p) == AXValueGetTypeID(),
              let s = box[size], CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
              AXValueGetValue(s as! AXValue, .cgSize, &extent) else { return nil }
        return Rect(x: origin.x, y: origin.y, w: extent.width, h: extent.height)
    }
}
