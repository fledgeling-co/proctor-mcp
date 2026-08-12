#if DEBUG || PROCTOR_REFLECTOR

import AppKit
import QuartzCore

// The view walk. Every line of this runs on the main thread.

@MainActor
enum Walker {

    struct Options {
        var maxDepth = 64
        var maxNodes = 4000
        var constraints = false
        var presentation = true
    }

    /// Two values are treated as the same when they agree to within this. A
    /// presentation layer that is a hundredth of a point from its model value is
    /// arithmetic noise, not an animation in flight.
    static let epsilon = 0.001

    // MARK: - Entry points

    static func hierarchy(windowNumber: Int?, options: Options) throws -> JSONValue {
        let windows = NSApplication.shared.windows.filter {
            windowNumber == nil || $0.windowNumber == windowNumber!
        }
        if let windowNumber, windows.isEmpty {
            throw ReflectorError.notFound("no NSWindow with window number \(windowNumber)")
        }

        var trackedLayers: [CALayer] = []
        var budget = options.maxNodes
        var truncated = false

        let encoded: [JSONValue] = windows.map { window in
            var root = JSONValue.null
            if let content = window.contentView {
                let prefix = "w\(window.windowNumber)"
                var ids: [ObjectIdentifier: String] = [:]
                mapIDs(content, path: prefix, depth: 0, maxDepth: options.maxDepth, into: &ids)
                root = node(content, path: prefix, depth: 0, options: options,
                            ids: ids, budget: &budget, truncated: &truncated,
                            layers: &trackedLayers)
            }
            return .object([
                "windowNumber": JSONValue.num(window.windowNumber),
                "title": .string(window.title),
                "frame": JSONValue.rect(window.frame),
                "isKey": .bool(window.isKeyWindow),
                "isVisible": .bool(window.isVisible),
                "appearance": JSONValue.str(window.appearance?.name.rawValue),
                "effectiveAppearance": .string(window.effectiveAppearance.name.rawValue),
                "backingScaleFactor": JSONValue.num(window.backingScaleFactor),
                "root": root
            ])
        }

        MainState.shared.track(layers: trackedLayers)

        return .object([
            "revision": JSONValue.num(Runtime.shared.revision),
            "idle": .bool(MainState.shared.idleNow()),
            "truncated": .bool(truncated),
            "windows": .array(encoded)
        ])
    }

    /// One node by its structural id, with its subtree to `maxDepth`.
    static func node(id: String, options: Options) throws -> JSONValue {
        guard let (window, view) = resolve(id: id) else {
            throw ReflectorError.notFound("no view with id \"\(id)\"; the hierarchy may have changed since the walk that produced it")
        }
        var ids: [ObjectIdentifier: String] = [:]
        mapIDs(view, path: id, depth: 0, maxDepth: options.maxDepth, into: &ids)
        var budget = options.maxNodes
        var truncated = false
        var layers: [CALayer] = []
        let encoded = node(view, path: id, depth: 0, options: options, ids: ids,
                           budget: &budget, truncated: &truncated, layers: &layers)
        MainState.shared.track(layers: layers)
        return .object([
            "revision": JSONValue.num(Runtime.shared.revision),
            "windowNumber": JSONValue.num(window.windowNumber),
            "truncated": .bool(truncated),
            "node": encoded
        ])
    }

    /// Ids are structural paths, so resolution is index arithmetic rather than a
    /// search: the same view gets the same id on every walk as long as the tree
    /// keeps its shape.
    static func resolve(id: String) -> (NSWindow, NSView)? {
        var parts = id.split(separator: "/").map(String.init)
        guard let head = parts.first, head.hasPrefix("w"),
              let number = Int(head.dropFirst()),
              let window = NSApplication.shared.windows.first(where: { $0.windowNumber == number }),
              var view = window.contentView
        else { return nil }
        parts.removeFirst()
        for part in parts {
            guard let index = Int(part), index >= 0, index < view.subviews.count else { return nil }
            view = view.subviews[index]
        }
        return (window, view)
    }

    // MARK: - Walk

    private static func mapIDs(_ view: NSView, path: String, depth: Int, maxDepth: Int,
                               into ids: inout [ObjectIdentifier: String]) {
        ids[ObjectIdentifier(view)] = path
        guard depth < maxDepth else { return }
        for (i, sub) in view.subviews.enumerated() {
            mapIDs(sub, path: "\(path)/\(i)", depth: depth + 1, maxDepth: maxDepth, into: &ids)
        }
    }

    private static func node(_ view: NSView, path: String, depth: Int, options: Options,
                             ids: [ObjectIdentifier: String], budget: inout Int,
                             truncated: inout Bool, layers: inout [CALayer]) -> JSONValue {
        budget -= 1
        if budget < 0 { truncated = true }

        var fields: [String: JSONValue] = [
            "id": .string(path),
            "class": .string(String(describing: type(of: view))),
            "identifier": JSONValue.str(view.identifier?.rawValue),
            "frame": JSONValue.rect(view.frame),
            "frameInWindow": JSONValue.rect(view.convert(view.bounds, to: nil)),
            "hidden": .bool(view.isHidden),
            "alphaValue": JSONValue.num(view.alphaValue),
            "isFlipped": .bool(view.isFlipped),
            "appearance": JSONValue.str(view.appearance?.name.rawValue),
            "effectiveAppearance": .string(view.effectiveAppearance.name.rawValue)
        ]

        if let layer = view.layer {
            layers.append(layer)
            fields["layer"] = describe(layer: layer, includePresentation: options.presentation)
        }

        if let text = describeText(view) {
            fields["text"] = text
        }

        if options.constraints {
            fields["constraints"] = describeConstraints(view, ids: ids)
        }

        if depth >= options.maxDepth || budget < 0 {
            fields["childCount"] = JSONValue.num(view.subviews.count)
            if !view.subviews.isEmpty { truncated = true }
            fields["children"] = .null
        } else {
            var children: [JSONValue] = []
            children.reserveCapacity(view.subviews.count)
            for (i, sub) in view.subviews.enumerated() {
                children.append(node(sub, path: "\(path)/\(i)", depth: depth + 1,
                                     options: options, ids: ids, budget: &budget,
                                     truncated: &truncated, layers: &layers))
            }
            fields["childCount"] = JSONValue.num(view.subviews.count)
            fields["children"] = .array(children)
        }

        return .object(fields)
    }

    // MARK: - Layer

    /// Model and presentation are both emitted because they are different
    /// questions. The model value is where the property will end up; the
    /// presentation value is where it is on this frame. They diverge exactly
    /// while something is animating, which makes their disagreement the app's
    /// own answer to "are you still moving" — better than any outside heuristic.
    private static func describe(layer: CALayer, includePresentation: Bool) -> JSONValue {
        let model = properties(of: layer)
        var fields: [String: JSONValue] = [
            "model": model,
            "animationKeys": .array((layer.animationKeys() ?? []).map { JSONValue.string($0) })
        ]

        // A layer that has never been committed to a render tree has no
        // presentation copy at all. That is not an error and not "not animating".
        if includePresentation, let presented = layer.presentation() {
            let live = properties(of: presented)
            fields["presentation"] = live
            fields["animating"] = .bool(!nearlyEqual(model, live))
        } else {
            fields["presentation"] = .null
            fields["animating"] = .bool(!(layer.animationKeys() ?? []).isEmpty)
        }
        return .object(fields)
    }

    private static func properties(of layer: CALayer) -> JSONValue {
        .object([
            "backgroundColor": Style.color(layer.backgroundColor),
            "borderColor": Style.color(layer.borderColor),
            "borderWidth": JSONValue.num(layer.borderWidth),
            "cornerRadius": JSONValue.num(layer.cornerRadius),
            "maskedCorners": Style.cornerMask(layer.maskedCorners),
            "opacity": JSONValue.num(Double(layer.opacity)),
            "shadowColor": Style.color(layer.shadowColor),
            "shadowOpacity": JSONValue.num(Double(layer.shadowOpacity)),
            "shadowRadius": JSONValue.num(layer.shadowRadius),
            "shadowOffset": .object(["w": JSONValue.num(layer.shadowOffset.width),
                                     "h": JSONValue.num(layer.shadowOffset.height)]),
            "masksToBounds": .bool(layer.masksToBounds),
            "contentsScale": JSONValue.num(layer.contentsScale),
            "transform": Style.transform(layer.transform)
        ])
    }

    static func nearlyEqual(_ a: JSONValue, _ b: JSONValue) -> Bool {
        switch (a, b) {
        case (.number(let x), .number(let y)):
            return abs(x - y) <= epsilon
        case (.array(let x), .array(let y)):
            return x.count == y.count && zip(x, y).allSatisfy { nearlyEqual($0, $1) }
        case (.object(let x), .object(let y)):
            guard x.count == y.count else { return false }
            return x.allSatisfy { key, value in
                guard let other = y[key] else { return false }
                return nearlyEqual(value, other)
            }
        default:
            return a == b
        }
    }

    // MARK: - Text

    private static func describeText(_ view: NSView) -> JSONValue? {
        let appearance = view.effectiveAppearance

        if let field = view as? NSTextField {
            return .object([
                "string": .string(field.stringValue),
                "placeholder": JSONValue.str(field.placeholderString),
                "font": Style.font(field.font),
                "color": Style.color(field.textColor, in: appearance),
                "alignment": .string(Style.alignment(field.alignment)),
                "lineBreakMode": .string(Style.lineBreak(field.lineBreakMode)),
                "editable": .bool(field.isEditable)
            ])
        }

        if let button = view as? NSButton {
            var color: NSColor? = button.contentTintColor
            let attributed = button.attributedTitle
            if attributed.length > 0,
               let attributedColor = attributed.attribute(.foregroundColor, at: 0,
                                                          effectiveRange: nil) as? NSColor {
                color = attributedColor
            }
            return .object([
                "string": .string(button.title),
                "font": Style.font(button.font),
                "color": Style.color(color, in: appearance),
                "alignment": .string(Style.alignment(button.alignment)),
                "lineBreakMode": .string(Style.lineBreak(button.lineBreakMode)),
                "state": JSONValue.num(button.state.rawValue),
                "bezelStyle": JSONValue.num(Int(button.bezelStyle.rawValue))
            ])
        }

        if let text = view as? NSText {
            return .object([
                "string": .string(text.string),
                "font": Style.font(text.font),
                "color": Style.color(text.textColor, in: appearance),
                "alignment": .string(Style.alignment(text.alignment)),
                "lineBreakMode": .null,
                "editable": .bool(text.isEditable)
            ])
        }

        return nil
    }

    // MARK: - Constraints

    private static func describeConstraints(_ view: NSView,
                                            ids: [ObjectIdentifier: String]) -> JSONValue {
        .array(view.constraints.map { c in
            .object([
                "firstItem": itemID(c.firstItem, ids: ids),
                "firstAttribute": .string(Style.attribute(c.firstAttribute)),
                "secondItem": itemID(c.secondItem, ids: ids),
                "secondAttribute": .string(Style.attribute(c.secondAttribute)),
                "relation": .string(Style.relation(c.relation)),
                "multiplier": JSONValue.num(c.multiplier),
                "constant": JSONValue.num(c.constant),
                "priority": JSONValue.num(Double(c.priority.rawValue)),
                "active": .bool(c.isActive),
                "identifier": JSONValue.str(c.identifier)
            ])
        })
    }

    private static func itemID(_ item: AnyObject?, ids: [ObjectIdentifier: String]) -> JSONValue {
        guard let item else { return .null }
        if let view = item as? NSView, let id = ids[ObjectIdentifier(view)] {
            return .string(id)
        }
        if let guide = item as? NSLayoutGuide {
            return .string("guide:\(guide.identifier.rawValue)")
        }
        return .string("\(type(of: item)):\(UInt(bitPattern: ObjectIdentifier(item).hashValue))")
    }
}

#endif
