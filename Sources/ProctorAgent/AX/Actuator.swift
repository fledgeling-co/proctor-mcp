import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import ProctorCore

// Actuation. Everything here that can go through AXUIElementPerformAction or
// AXUIElementSetAttributeValue does, because that plane reaches a window that
// is not frontmost, is occluded, or is on another Space, without stealing
// focus, and Secure Event Input does not block it. The synthetic-event kinds
// are the exception and say so in the plane they return.
//
// Two kinds have more than one accessibility route, and they try all of them
// before conceding the foreground. `type` writes the value, and if that is
// refused — or accepted and quietly ignored, which is what a web input usually
// does — writes into a full-value selection instead. `scroll` moves the
// element's own scroll bar, then its by-page action, then the scroll bar of the
// scroll area that encloses it. Every one of those keeps the run in the
// background, and which one was taken is reported rather than left to be
// inferred from a plane that cannot tell them apart.
//
// A write is judged by reading it back, never by its return code. AX reports
// success for a set that the application then discards, and a step that reports
// a background success while having done nothing is worse than one that falls
// back honestly: it is indistinguishable, from outside, from the case this
// whole file exists to produce.

struct ActuationTarget {
    var pid: pid_t
    var appElement: AXUIElement
    var windowElement: AXUIElement?
    var node: AXUIElement?
    var nodeId: String?
}

enum Actuator {

    static let shortcutTimeout: TimeInterval = 10

    /// How far up the parent chain to look for the scroll area enclosing an
    /// element. Deep enough to clear the handful of groups a scrollable list is
    /// usually wrapped in, shallow enough that a miss costs a bounded number of
    /// round trips rather than a walk to the application element.
    static let scrollAncestorLimit = 12

    static func perform(_ step: ActionStep, target: ActuationTarget,
                        foreground: Bool) throws -> Actuation {
        if let node = target.node { AXUIElementSetMessagingTimeout(node, AXTimeout.action) }
        if let window = target.windowElement {
            AXUIElementSetMessagingTimeout(window, AXTimeout.action)
        }

        switch step.kind {
        case .press:    return try act(step, target, kAXPressAction)
        case .confirm:  return try act(step, target, kAXConfirmAction)
        case .cancel:   return try act(step, target, kAXCancelAction)
        case .raise:    return try act(step, target, kAXRaiseAction, preferWindow: true)
        case .increment: return try act(step, target, kAXIncrementAction)
        case .decrement: return try act(step, target, kAXDecrementAction)

        case .pick:
            let element = try element(step, target)
            let available = AXRead.actions(element)
            let action = available.contains(kAXPickAction) ? kAXPickAction : kAXPressAction
            return try act(step, target, action)

        case .close:
            return try close(step, target)

        case .focus:
            let element = try element(step, target)
            let err = AXWrite.set(element, kAXFocusedAttribute, kCFBooleanTrue)
            guard err.isSuccess else { throw err.asAgentError("focus") }
            return Actuation(.accessibility, .valueWrite)

        case .setValue:
            let element = try element(step, target)
            let value = step.value ?? (step.text.map { JSONValue.string($0) } ?? .null)
            let err = AXWrite.set(element, kAXValueAttribute, AXWrite.cfValue(from: value))
            guard err.isSuccess else { throw err.asAgentError("setValue") }
            return Actuation(.accessibility, .valueWrite)

        case .type:
            return try type(step, target, foreground: foreground)

        case .menu:
            return try menu(step, target)

        case .scroll:
            return try scroll(step, target, foreground: foreground)

        case .move, .resize:
            return try geometry(step, target)

        case .key:
            return try key(step, target)

        case .click, .hover:
            return try pointer(step, target)

        case .dragPath:
            return try drag(step, target, foreground: foreground)

        case .appleScript:
            return try appleScript(step)

        case .shortcut:
            return try shortcut(step)

        case .waitFor:
            // The session layer owns waiting; the step exists so a flow can
            // express the pause without the engine inventing a policy.
            return Actuation(.accessibility, .action)
        }
    }

    // MARK: - AX actions

    private static func element(_ step: ActionStep, _ target: ActuationTarget) throws -> AXUIElement {
        if let node = target.node { return node }
        if let window = target.windowElement { return window }
        throw AgentError(code: .nodeNotFound,
                         message: "step \(step.kind.rawValue) needs a node or a window",
                         remedy: "Supply a node id from snapshot or find.")
    }

    private static func act(_ step: ActionStep, _ target: ActuationTarget,
                            _ action: String, preferWindow: Bool = false) throws -> Actuation {
        let element: AXUIElement
        if preferWindow, target.node == nil, let window = target.windowElement {
            element = window
        } else {
            element = try self.element(step, target)
        }
        let available = AXRead.actions(element)
        guard available.contains(action) else {
            throw AgentError(
                code: .actionUnsupported,
                message: "\(action) is not offered by this element",
                remedy: available.isEmpty
                    ? "This element offers no actions; act on a descendant or use a synthetic event."
                    : "Available actions: \(available.joined(separator: ", "))",
                detail: .object([
                    "requested": .string(action),
                    "node": .string(target.nodeId ?? ""),
                    "available": .array(available.map { .string($0) }),
                ]))
        }
        let err = AXUIElementPerformAction(element, action as CFString)
        guard err.isSuccess else { throw err.asAgentError(action) }
        return Actuation(.accessibility, .action)
    }

    private static func close(_ step: ActionStep, _ target: ActuationTarget) throws -> Actuation {
        let window = target.node ?? target.windowElement
        guard let window else {
            throw AgentError(code: .windowNotFound, message: "close needs a window")
        }
        if let button = AXRead.element(window, kAXCloseButtonAttribute) {
            let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
            guard err.isSuccess else { throw err.asAgentError("close") }
            return Actuation(.accessibility, .action)
        }
        for child in AXRead.elements(window, kAXChildrenAttribute)
        where AXRead.string(child, kAXSubroleAttribute) == "AXCloseButton" {
            let err = AXUIElementPerformAction(child, kAXPressAction as CFString)
            guard err.isSuccess else { throw err.asAgentError("close") }
            return Actuation(.accessibility, .action)
        }
        throw AgentError(code: .actionUnsupported,
                         message: "no AXCloseButton on this window",
                         remedy: "Close it through the app's File menu instead.")
    }

    // MARK: - Typing

    /// Two accessibility routes before the one that costs the foreground.
    ///
    /// The value write is tried first and **read back**, because a web input or
    /// a custom text view commonly accepts the write and does nothing with it.
    /// Without the read-back that case reports a background success that never
    /// happened, and — worse for this step — it would stop the second route
    /// from ever being reached on exactly the fields that need it.
    ///
    /// The second route writes into a selection covering the whole value, which
    /// is what a text view that refuses `AXValue` usually does accept. It is
    /// only attempted when the value can be read (to know the length) and the
    /// existing selection can be read (to put it back), because `AXSelectedText`
    /// with no selection *inserts at the caret* — a different outcome from the
    /// replace this verb has always meant — and a field left selected end to end
    /// would be emptied by the first keystroke of the fallback below.
    private static func type(_ step: ActionStep, _ target: ActuationTarget,
                             foreground: Bool) throws -> Actuation {
        let element = try self.element(step, target)
        let text = step.text ?? step.value?.stringValue ?? ""

        if AXWrite.isSettable(element, kAXValueAttribute) {
            let err = AXWrite.set(element, kAXValueAttribute, text as CFString)
            if err.isSuccess, valueReads(element, as: text) {
                return Actuation(.accessibility, .valueWrite)
            }
        }

        if typeIntoSelection(element, text) {
            return Actuation(.accessibility, .selectedText)
        }

        // No accessibility route left: the field is a custom text view or a web
        // input that refuses both, and the only route remaining enters the
        // shared event stream, so the app has to be frontmost and the plane
        // reported is a different one. A caller who asked to stay in the
        // background gets told, rather than getting a foreground action wearing
        // a background result.
        guard foreground else {
            throw AgentError(
                code: .actionUnsupported,
                message: "this field's value is settable through neither an accessibility value "
                       + "write nor a write into its selection, and typing into it needs the app "
                       + "in the foreground",
                remedy: "Re-run this step with foreground true, or set the value on an "
                      + "ancestor or sibling element that does accept a value write.",
                detail: .object(["node": .string(target.nodeId ?? "")]))
        }
        _ = AXWrite.set(element, kAXFocusedAttribute, kCFBooleanTrue)
        try activate(target.pid)
        try requireEventPlaneAvailable()
        postUnicode(text)
        return Actuation(.syntheticEvent, .eventStream)
    }

    /// Replace the whole value by writing into a selection that covers it.
    /// Returns whether the text actually landed; on any failure the selection is
    /// put back where it was.
    private static func typeIntoSelection(_ element: AXUIElement, _ text: String) -> Bool {
        guard AXWrite.isSettable(element, kAXSelectedTextAttribute),
              let current = AXRead.string(element, kAXValueAttribute),
              let original = AXRead.raw(element, kAXSelectedTextRangeAttribute)
        else { return false }

        var whole = CFRange(location: 0, length: current.utf16.count)
        guard let range = AXValueCreate(.cfRange, &whole) else { return false }
        guard AXWrite.set(element, kAXSelectedTextRangeAttribute, range).isSuccess else {
            return false
        }
        let wrote = AXWrite.set(element, kAXSelectedTextAttribute, text as CFString)
        if wrote.isSuccess, valueReads(element, as: text) { return true }
        AXWrite.set(element, kAXSelectedTextRangeAttribute, original)
        return false
    }

    /// Did the write take? An unreadable value is treated as "took": a field
    /// that will not report its own value cannot be checked, and refusing to
    /// believe an accepted write on that ground would push every such field to
    /// the event stream, which is the cost this whole path exists to avoid.
    static func tookValue(read: String?, expected: String) -> Bool {
        guard let read else { return true }
        return read == expected
    }

    private static func valueReads(_ element: AXUIElement, as text: String) -> Bool {
        tookValue(read: AXRead.string(element, kAXValueAttribute), expected: text)
    }

    private static func geometry(_ step: ActionStep, _ target: ActuationTarget) throws -> Actuation {
        let element = target.node ?? target.windowElement
        guard let element else {
            throw AgentError(code: .windowNotFound, message: "\(step.kind.rawValue) needs a window")
        }
        let pair = step.point ?? step.delta ?? step.value?.arrayValue?.compactMap(\.doubleValue)
        guard let pair, pair.count >= 2 else {
            throw AgentError(code: .invalidArguments,
                             message: "\(step.kind.rawValue) needs point: [x, y]")
        }
        if step.kind == .move {
            var origin = CGPoint(x: pair[0], y: pair[1])
            guard let value = AXValueCreate(.cgPoint, &origin) else {
                throw AgentError(code: .internalError, message: "could not box a CGPoint")
            }
            let err = AXWrite.set(element, kAXPositionAttribute, value)
            guard err.isSuccess else { throw err.asAgentError("move") }
        } else {
            var size = CGSize(width: pair[0], height: pair[1])
            guard let value = AXValueCreate(.cgSize, &size) else {
                throw AgentError(code: .internalError, message: "could not box a CGSize")
            }
            let err = AXWrite.set(element, kAXSizeAttribute, value)
            guard err.isSuccess else { throw err.asAgentError("resize") }
        }
        return Actuation(.accessibility, .valueWrite)
    }

    // MARK: - Menus

    /// Driving the menu bar is the most reliable background-safe route into an
    /// app: the menu tree is process-directed, so it works while the app is
    /// behind other windows and needs no synthetic event.
    private static func menu(_ step: ActionStep, _ target: ActuationTarget) throws -> Actuation {
        guard let path = step.menuPath, !path.isEmpty else {
            throw AgentError(code: .invalidArguments, message: "menu needs menuPath")
        }
        guard let bar = AXRead.element(target.appElement, kAXMenuBarAttribute) else {
            throw AgentError(code: .actionUnsupported,
                             message: "this application exposes no menu bar",
                             remedy: "Agent-style apps have no menu bar; use an AX action instead.")
        }

        var container = bar
        var walked: [String] = []
        for (index, component) in path.enumerated() {
            guard let match = child(of: container, titled: component) else {
                throw AgentError(
                    code: .nodeNotFound,
                    message: "menu item \"\(component)\" not found under \(walked.joined(separator: " ▸ "))",
                    remedy: "Titles are localised; read them from a snapshot of the menu bar first.",
                    detail: .object([
                        "available": .array(titles(of: container).map { .string($0) }),
                    ]))
            }
            walked.append(component)

            if index == path.count - 1 {
                let err = AXUIElementPerformAction(match, kAXPressAction as CFString)
                guard err.isSuccess else { throw err.asAgentError("menu press") }
                return Actuation(.accessibility, .action)
            }
            container = descend(into: match)
        }
        throw AgentError(code: .actionFailed, message: "menu path exhausted without a target")
    }

    /// Menu items hold their submenu as a single AXMenu child. Some apps build
    /// that submenu lazily, so an empty item is pressed once to populate it.
    private static func descend(into item: AXUIElement) -> AXUIElement {
        var children = AXRead.elements(item, kAXChildrenAttribute)
        if children.isEmpty {
            _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
            usleep(150_000)
            children = AXRead.elements(item, kAXChildrenAttribute)
        }
        if let submenu = children.first(where: { AXRead.string($0, kAXRoleAttribute) == kAXMenuRole }) {
            return submenu
        }
        return item
    }

    private static func child(of container: AXUIElement, titled title: String) -> AXUIElement? {
        for child in AXRead.elements(container, kAXChildrenAttribute) {
            let role = AXRead.string(child, kAXRoleAttribute)
            if role == kAXMenuRole {
                if let nested = self.child(of: child, titled: title) { return nested }
                continue
            }
            let candidate = AXRead.string(child, kAXTitleAttribute)
                ?? AXRead.string(child, kAXDescriptionAttribute)
            if candidate?.caseInsensitiveCompare(title) == .orderedSame { return child }
        }
        return nil
    }

    private static func titles(of container: AXUIElement) -> [String] {
        var out: [String] = []
        for child in AXRead.elements(container, kAXChildrenAttribute) {
            if AXRead.string(child, kAXRoleAttribute) == kAXMenuRole {
                out.append(contentsOf: titles(of: child))
            } else if let title = AXRead.string(child, kAXTitleAttribute) {
                out.append(title)
            }
        }
        return out
    }

    // MARK: - Scrolling

    private static func scroll(_ step: ActionStep, _ target: ActuationTarget,
                               foreground: Bool) throws -> Actuation {
        let element = try self.element(step, target)
        let delta = step.delta ?? [0, -3]
        let dy = delta.count > 1 ? delta[1] : 0
        let dx = delta.first ?? 0

        if AXRead.string(element, kAXRoleAttribute) == kAXScrollBarRole,
           writeBar(element, by: dy != 0 ? dy : dx) {
            return Actuation(.accessibility, .scrollBar)
        }

        let available = AXRead.actions(element)
        let wanted: String? = if dy < 0 { AXAttr.scrollDownByPage }
            else if dy > 0 { AXAttr.scrollUpByPage }
            else if dx < 0 { AXAttr.scrollRightByPage }
            else if dx > 0 { AXAttr.scrollLeftByPage }
            else { nil }
        if let wanted, available.contains(wanted) {
            let err = AXUIElementPerformAction(element, wanted as CFString)
            if err.isSuccess { return Actuation(.accessibility, .scrollAction) }
        }

        // The element is inside something scrollable even when it offers nothing
        // itself — a cell in a list, a label in a document. The scroll area that
        // encloses it owns bars that do take a value, and driving those is still
        // the accessibility plane, so it is tried before conceding the front.
        if scrollEnclosingArea(of: element, dx: dx, dy: dy) {
            return Actuation(.accessibility, .scrollBar)
        }

        // Falling back to a scroll wheel event activates the app and enters the
        // system event stream, so it answers a narrower question than the caller
        // asked. Silently substituting it is how a background-safe result stops
        // being one, so the fallback is refused rather than taken quietly.
        guard foreground else {
            throw AgentError(
                code: .actionUnsupported,
                message: "the accessibility scroll action was not accepted by this element, no "
                       + "enclosing scroll area's bar would take the value, and the scroll-wheel "
                       + "fallback needs the app in the foreground",
                remedy: "Re-run this step with foreground true to allow a synthetic scroll, "
                      + "or scroll by setting the scroll bar's value, which stays on the "
                      + "accessibility plane.",
                detail: .object([
                    "available": .array(available.map { .string($0) }),
                    "attempted": .string(wanted ?? "none"),
                ]))
        }
        guard let centre = centre(of: element) else {
            throw AgentError(code: .actionUnsupported,
                             message: "no scroll action and no frame to aim a scroll wheel at",
                             detail: .object(["available": .array(available.map { .string($0) })]))
        }
        try activate(target.pid)
        try requireEventPlaneAvailable()
        warpCursor(to: centre)
        let source = eventSource()
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)
        event?.post(tap: .cghidEventTap)
        return Actuation(.syntheticEvent, .eventStream)
    }

    /// Walk up to the nearest enclosing scroll area whose bars will take the
    /// delta, and move every axis that was asked for. All-or-nothing per call:
    /// a diagonal scroll that only moved sideways is not the scroll that was
    /// asked for, so a partial result hands on to the next route rather than
    /// reporting a success the caller cannot act on.
    private static func scrollEnclosingArea(of element: AXUIElement,
                                            dx: Double, dy: Double) -> Bool {
        guard dx != 0 || dy != 0 else { return false }
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < scrollAncestorLimit {
            defer {
                current = AXRead.element(node, kAXParentAttribute)
                depth += 1
            }
            guard AXRead.string(node, kAXRoleAttribute) == kAXScrollAreaRole else { continue }

            var wanted = 0, moved = 0
            if dy != 0, let bar = AXRead.element(node, kAXVerticalScrollBarAttribute) {
                wanted += 1
                if writeBar(bar, by: dy) { moved += 1 }
            }
            if dx != 0, let bar = AXRead.element(node, kAXHorizontalScrollBarAttribute) {
                wanted += 1
                if writeBar(bar, by: dx) { moved += 1 }
            }
            // The first scroll area that answers at all is the one this element
            // sits in; a further ancestor is somebody else's scroller.
            if wanted > 0 { return moved == wanted }
        }
        return false
    }

    /// Move one scroll bar by a delta and confirm it moved.
    ///
    /// A bar's `AXValue` is its position in the document as a fraction, so the
    /// delta is mapped the way the scroll-bar branch has always mapped it —
    /// a hundredth of the document per unit. That mapping is crude, and it is
    /// deliberately unchanged here: correcting it would change what every
    /// already-working scroll does, which is a different item.
    ///
    /// A bar already at the end reads back unchanged and reports failure, which
    /// is right: nothing moved, and a caller told otherwise would believe the
    /// document had scrolled.
    private static func writeBar(_ bar: AXUIElement, by delta: Double) -> Bool {
        guard AXWrite.isSettable(bar, kAXValueAttribute) else { return false }
        let before = AXRead.value(bar)?.doubleValue ?? 0
        let next = scrollFraction(from: before, by: delta)
        guard AXWrite.set(bar, kAXValueAttribute, NSNumber(value: next)).isSuccess else {
            return false
        }
        guard let after = AXRead.value(bar)?.doubleValue else { return true }
        return moved(from: before, to: after)
    }

    /// Where a bar ends up after a delta. A hundredth of the document per unit,
    /// clamped to the ends, which is the mapping the scroll-bar branch has
    /// always used.
    static func scrollFraction(from current: Double, by delta: Double) -> Double {
        max(0, min(1, current + (delta / 100)))
    }

    /// Whether a bar actually moved. A bar already at the end reads back
    /// unchanged and counts as not moved, which is right: nothing scrolled, and
    /// a caller told otherwise would believe the document had.
    static func moved(from before: Double, to after: Double) -> Bool {
        abs(after - before) > 1e-9
    }

    // MARK: - Synthetic events

    /// The one place a synthetic event's source is built, so every event Proctor
    /// posts carries Proctor's tag.
    ///
    /// It exists for the yield watch (PRO-0018): an input monitor that could not
    /// tell Proctor's own events from a person's would pause every synthetic run
    /// on its own first step. The tag is one of three independent filters and
    /// costs a single assignment here. Routing every construction through this
    /// function is what makes "every post is tagged" a property of the code
    /// rather than of somebody remembering at the next post site.
    static func eventSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = ProctorEventTag.value
        return source
    }

    private static func key(_ step: ActionStep, _ target: ActuationTarget) throws -> Actuation {
        guard let name = step.key, !name.isEmpty else {
            throw AgentError(code: .invalidArguments, message: "key needs a key name")
        }
        try activate(target.pid)
        try requireEventPlaneAvailable()

        let flags = KeyCodes.modifiers(step.modifiers ?? [])
        guard let code = KeyCodes.keyCode(for: name) else {
            guard name.count == 1 else {
                throw AgentError(code: .invalidArguments,
                                 message: "unknown key name \"\(name)\"",
                                 remedy: "Use a name from the key table, or a single character.")
            }
            postUnicode(name)
            return Actuation(.syntheticEvent, .eventStream)
        }
        let source = eventSource()
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        return Actuation(.syntheticEvent, .eventStream)
    }

    private static func pointer(_ step: ActionStep, _ target: ActuationTarget) throws -> Actuation {
        let point: CGPoint
        if let p = step.point, p.count >= 2 {
            point = CGPoint(x: p[0], y: p[1])
        } else if let node = target.node, let c = centre(of: node) {
            point = c
        } else {
            throw AgentError(code: .invalidArguments,
                             message: "\(step.kind.rawValue) needs a node with a frame or an explicit point")
        }

        try activate(target.pid)
        try requireEventPlaneAvailable()
        warpCursor(to: point)
        guard step.kind == .click else { return Actuation(.syntheticEvent, .eventStream) }

        let source = eventSource()
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type,
                    mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        return Actuation(.syntheticEvent, .eventStream)
    }

    /// There is no accessibility expression for a drag, so this is a synthetic
    /// gesture and reports itself as one.
    private static func drag(_ step: ActionStep, _ target: ActuationTarget,
                             foreground: Bool) throws -> Actuation {
        let route = try dragRoute(step, target)

        // Activating the app to post the gesture answers a narrower question
        // than a background-safe caller asked, so the substitution is refused
        // rather than made quietly.
        guard foreground else {
            throw AgentError(
                code: .actionUnsupported,
                message: "a drag can only be expressed as synthetic events, which need the app "
                       + "in the foreground",
                remedy: "Re-run this step with foreground true, or reach the same end state "
                      + "through the accessibility plane — a value write on the control being "
                      + "dragged, or its increment and decrement actions, both stay in the "
                      + "background.",
                detail: .object(["node": .string(target.nodeId ?? "")]))
        }
        try activate(target.pid)
        try requireEventPlaneAvailable()

        let points = PointerPath.interpolate(route)
        // One event source for the whole gesture, so the WindowServer sees one
        // device pressing, moving and releasing rather than three unrelated ones.
        let source = eventSource()
        // Posting the sequence in a tight loop outruns what many apps process,
        // so the events are spread across the requested duration, with a floor
        // of 2ms an app can still see and a ceiling no gesture needs.
        let totalMs = min(max(step.durationMs ?? 300, 1), 30_000)
        let intervalUs = UInt32(max(2, totalMs / max(1, points.count)) * 1000)

        warpCursor(to: points[0])
        post(.leftMouseDown, at: points[0], source: source)
        // The movement between the press and the release is the drag. An app
        // that tracks dragging sees nothing without it, and reads a press and a
        // release at two positions as a click.
        for point in points.dropFirst() {
            usleep(intervalUs)
            post(.leftMouseDragged, at: point, source: source)
        }
        usleep(intervalUs)
        post(.leftMouseUp, at: points[points.count - 1], source: source)
        return Actuation(.syntheticEvent, .eventStream)
    }

    /// The route in window coordinates: the supplied path, or the two-point path
    /// a start and a delta describe.
    private static func dragRoute(_ step: ActionStep,
                                  _ target: ActuationTarget) throws -> [CGPoint] {
        if let path = step.path, !path.isEmpty {
            let points = path.filter { $0.count >= 2 }.map { CGPoint(x: $0[0], y: $0[1]) }
            guard points.count == path.count else {
                throw AgentError(code: .invalidArguments,
                                 message: "every entry in a dragPath path must be [x, y]")
            }
            guard points.count >= 2 else {
                throw AgentError(code: .invalidArguments,
                                 message: "a dragPath path needs at least two points",
                                 remedy: "Supply the end of the drag as a second point, or drop "
                                       + "path and give point plus delta.")
            }
            return points
        }

        let start: CGPoint
        if let p = step.point, p.count >= 2 {
            start = CGPoint(x: p[0], y: p[1])
        } else if let node = target.node, let centre = centre(of: node) {
            start = centre
        } else {
            throw AgentError(code: .invalidArguments,
                             message: "dragPath needs path, or point, or a node with a frame")
        }
        guard let delta = step.delta, delta.count >= 2 else {
            throw AgentError(code: .invalidArguments,
                             message: "dragPath with no path needs delta: [dx, dy]",
                             remedy: "Give path as [[x,y], ...] for a route with a shape.")
        }
        return [start, CGPoint(x: start.x + delta[0], y: start.y + delta[1])]
    }

    private static func post(_ type: CGEventType, at point: CGPoint, source: CGEventSource?) {
        // The button number travels on the drag events too; without it a
        // dragged event carries no button and reads as a bare mouse move.
        CGEvent(mouseEventSource: source, mouseType: type,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func warpCursor(to point: CGPoint) {
        let source = eventSource()
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func postUnicode(_ text: String) {
        guard !text.isEmpty else { return }
        let source = eventSource()
        for scalar in text.unicodeScalars {
            var units = Array(String(scalar).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                else { continue }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private static func centre(of element: AXUIElement) -> CGPoint? {
        guard let frame = AXRead.frame(element), frame.w > 0, frame.h > 0 else { return nil }
        return CGPoint(x: frame.x + frame.w / 2, y: frame.y + frame.h / 2)
    }

    /// The last thing between a step and the event stream, and therefore the one
    /// place a step declares that it is about to enter it.
    ///
    /// Every synthetic route reaches its post through this guard: `type`'s
    /// fallback, `scroll`'s fallback, `key`, `click`, `hover` and `dragPath`. It
    /// is called after `activate(pid)` and after every accessibility route has
    /// been tried and refused, so a declaration made here is the point of no
    /// return — it cannot precede an accessibility success, and a step refused
    /// for secure input throws above it and declares nothing.
    ///
    /// KEEP THE DECLARATION IN THIS GUARD rather than at the six post sites. A
    /// new synthetic route that forgot to declare would also have forgotten the
    /// secure-input check, which is the one nobody gets to forget; the two travel
    /// together or neither does. What reads the declaration — the grace window,
    /// the takeover statement, the input block and the panel's mouse gate — is in
    /// `SyntheticPost`.
    private static func requireEventPlaneAvailable() throws {
        guard !Grants.secureEventInputActive() else {
            throw AgentError(code: .secureInputActive,
                             message: "Secure Event Input is active; synthetic events are discarded",
                             remedy: "Dismiss the password field that enabled it, or use an AX action, "
                                   + "which is not affected.")
        }
        SyntheticPost.shared.declare()
    }

    private static func activate(_ pid: pid_t) throws {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw AgentError(code: .appNotFound, message: "process \(pid) is no longer running")
        }
        if !app.isActive {
            _ = app.activate()
            usleep(120_000)
        }
    }

    // MARK: - Declared contracts

    private static func appleScript(_ step: ActionStep) throws -> Actuation {
        guard let source = step.text ?? step.value?.stringValue, !source.isEmpty else {
            throw AgentError(code: .invalidArguments, message: "appleScript needs text")
        }
        guard let script = NSAppleScript(source: source) else {
            throw AgentError(code: .invalidArguments, message: "the script could not be compiled")
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed"
            // -1743 is the Apple Events consent refusal, which no retry will fix.
            if number == -1743 {
                throw AgentError(code: .permissionAutomation, message: message,
                                 remedy: "System Settings ▸ Privacy & Security ▸ Automation, "
                                       + "allow Proctor to control this app.")
            }
            throw AgentError(code: .actionFailed, message: message,
                             detail: .object(["errorNumber": .number(Double(number))]))
        }
        return Actuation(.appleEvents, .appleEvent)
    }

    /// A shortcut that prompts waits for a person forever, so the timeout is
    /// part of the contract rather than a safety net.
    private static func shortcut(_ step: ActionStep) throws -> Actuation {
        guard let name = step.text ?? step.label ?? step.value?.stringValue, !name.isEmpty else {
            throw AgentError(code: .invalidArguments, message: "shortcut needs a name in text")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do { try process.run() } catch {
            throw AgentError(code: .actionFailed,
                             message: "could not launch /usr/bin/shortcuts: \(error.localizedDescription)",
                             remedy: "The shortcuts CLI ships with macOS 12 and later.")
        }

        let deadline = Date().addingTimeInterval(shortcutTimeout)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning {
            process.terminate()
            usleep(200_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw AgentError(code: .settleTimeout,
                             message: "shortcut \"\(name)\" did not finish within \(Int(shortcutTimeout))s",
                             remedy: "A shortcut that asks for input blocks forever when run headless; "
                                   + "remove the prompt or run it interactively.")
        }
        guard process.terminationStatus == 0 else {
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(),
                              encoding: .utf8) ?? ""
            throw AgentError(code: .actionFailed,
                             message: "shortcut \"\(name)\" exited \(process.terminationStatus)",
                             detail: .object(["output": .string(text)]))
        }
        return Actuation(.declared, .declared)
    }
}
