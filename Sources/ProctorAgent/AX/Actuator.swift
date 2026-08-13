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

struct ActuationTarget {
    var pid: pid_t
    var appElement: AXUIElement
    var windowElement: AXUIElement?
    var node: AXUIElement?
    var nodeId: String?
}

enum Actuator {

    static let shortcutTimeout: TimeInterval = 10

    static func perform(_ step: ActionStep, target: ActuationTarget,
                        foreground: Bool) throws -> ActuationPlane {
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
            return .accessibility

        case .setValue:
            let element = try element(step, target)
            let value = step.value ?? (step.text.map { JSONValue.string($0) } ?? .null)
            let err = AXWrite.set(element, kAXValueAttribute, AXWrite.cfValue(from: value))
            guard err.isSuccess else { throw err.asAgentError("setValue") }
            return .accessibility

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
            return .accessibility
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
                            _ action: String, preferWindow: Bool = false) throws -> ActuationPlane {
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
        return .accessibility
    }

    private static func close(_ step: ActionStep, _ target: ActuationTarget) throws -> ActuationPlane {
        let window = target.node ?? target.windowElement
        guard let window else {
            throw AgentError(code: .windowNotFound, message: "close needs a window")
        }
        if let button = AXRead.element(window, kAXCloseButtonAttribute) {
            let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
            guard err.isSuccess else { throw err.asAgentError("close") }
            return .accessibility
        }
        for child in AXRead.elements(window, kAXChildrenAttribute)
        where AXRead.string(child, kAXSubroleAttribute) == "AXCloseButton" {
            let err = AXUIElementPerformAction(child, kAXPressAction as CFString)
            guard err.isSuccess else { throw err.asAgentError("close") }
            return .accessibility
        }
        throw AgentError(code: .actionUnsupported,
                         message: "no AXCloseButton on this window",
                         remedy: "Close it through the app's File menu instead.")
    }

    private static func type(_ step: ActionStep, _ target: ActuationTarget,
                             foreground: Bool) throws -> ActuationPlane {
        let element = try self.element(step, target)
        let text = step.text ?? step.value?.stringValue ?? ""

        if AXWrite.isSettable(element, kAXValueAttribute) {
            let err = AXWrite.set(element, kAXValueAttribute, text as CFString)
            if err.isSuccess { return .accessibility }
        }

        // Not settable: the field is a custom text view or a web input, and the
        // only route left enters the shared event stream, so the app has to be
        // frontmost and the plane reported is a different one. A caller who asked
        // to stay in the background gets told, rather than getting a foreground
        // action wearing a background result.
        guard foreground else {
            throw AgentError(
                code: .actionUnsupported,
                message: "this field's value is not settable through the accessibility plane, "
                       + "and typing into it needs the app in the foreground",
                remedy: "Re-run this step with foreground true, or set the value on an "
                      + "ancestor or sibling element that does accept a value write.",
                detail: .object(["node": .string(target.nodeId ?? "")]))
        }
        _ = AXWrite.set(element, kAXFocusedAttribute, kCFBooleanTrue)
        try activate(target.pid)
        try requireEventPlaneAvailable()
        postUnicode(text)
        return .syntheticEvent
    }

    private static func geometry(_ step: ActionStep, _ target: ActuationTarget) throws -> ActuationPlane {
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
        return .accessibility
    }

    // MARK: - Menus

    /// Driving the menu bar is the most reliable background-safe route into an
    /// app: the menu tree is process-directed, so it works while the app is
    /// behind other windows and needs no synthetic event.
    private static func menu(_ step: ActionStep, _ target: ActuationTarget) throws -> ActuationPlane {
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
                return .accessibility
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
                               foreground: Bool) throws -> ActuationPlane {
        let element = try self.element(step, target)
        let delta = step.delta ?? [0, -3]
        let dy = delta.count > 1 ? delta[1] : 0
        let dx = delta.first ?? 0

        if AXRead.string(element, kAXRoleAttribute) == kAXScrollBarRole,
           AXWrite.isSettable(element, kAXValueAttribute) {
            let current = AXRead.value(element)?.doubleValue ?? 0
            let next = max(0, min(1, current + (dy / 100)))
            let err = AXWrite.set(element, kAXValueAttribute, NSNumber(value: next))
            if err.isSuccess { return .accessibility }
        }

        let available = AXRead.actions(element)
        let wanted: String? = if dy < 0 { AXAttr.scrollDownByPage }
            else if dy > 0 { AXAttr.scrollUpByPage }
            else if dx < 0 { AXAttr.scrollRightByPage }
            else if dx > 0 { AXAttr.scrollLeftByPage }
            else { nil }
        if let wanted, available.contains(wanted) {
            let err = AXUIElementPerformAction(element, wanted as CFString)
            if err.isSuccess { return .accessibility }
        }

        // Falling back to a scroll wheel event activates the app and enters the
        // system event stream, so it answers a narrower question than the caller
        // asked. Silently substituting it is how a background-safe result stops
        // being one, so the fallback is refused rather than taken quietly.
        guard foreground else {
            throw AgentError(
                code: .actionUnsupported,
                message: "the accessibility scroll action was not accepted by this element, "
                       + "and the scroll-wheel fallback needs the app in the foreground",
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
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)
        event?.post(tap: .cghidEventTap)
        return .syntheticEvent
    }

    // MARK: - Synthetic events

    private static func key(_ step: ActionStep, _ target: ActuationTarget) throws -> ActuationPlane {
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
            return .syntheticEvent
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        return .syntheticEvent
    }

    private static func pointer(_ step: ActionStep, _ target: ActuationTarget) throws -> ActuationPlane {
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
        guard step.kind == .click else { return .syntheticEvent }

        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type,
                    mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        return .syntheticEvent
    }

    /// There is no accessibility expression for a drag, so this is a synthetic
    /// gesture and reports itself as one.
    private static func drag(_ step: ActionStep, _ target: ActuationTarget,
                             foreground: Bool) throws -> ActuationPlane {
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
        let source = CGEventSource(stateID: .hidSystemState)
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
        return .syntheticEvent
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
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func postUnicode(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
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

    private static func requireEventPlaneAvailable() throws {
        guard !Grants.secureEventInputActive() else {
            throw AgentError(code: .secureInputActive,
                             message: "Secure Event Input is active; synthetic events are discarded",
                             remedy: "Dismiss the password field that enabled it, or use an AX action, "
                                   + "which is not affected.")
        }
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

    private static func appleScript(_ step: ActionStep) throws -> ActuationPlane {
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
        return .appleEvents
    }

    /// A shortcut that prompts waits for a person forever, so the timeout is
    /// part of the contract rather than a safety net.
    private static func shortcut(_ step: ActionStep) throws -> ActuationPlane {
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
        return .declared
    }
}
