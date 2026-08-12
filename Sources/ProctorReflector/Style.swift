#if DEBUG || PROCTOR_REFLECTOR

import AppKit
import QuartzCore

// Colour and font resolution. Everything here runs on the main thread.

@MainActor
enum Style {

    // MARK: - Colour

    /// An `NSColor` resolved for a specific appearance.
    ///
    /// The catalog and semantic name are kept alongside the numbers because the
    /// name is what a designer actually specified. `NSColor.labelColor` reduced
    /// to `#000000E5` has lost the only part of it a review can argue about.
    static func color(_ color: NSColor?, in appearance: NSAppearance?) -> JSONValue {
        guard let color else { return .null }

        var catalog: String?
        var name: String?
        if color.type == .catalog {
            catalog = color.catalogNameComponent
            name = color.colorNameComponent
        }

        var resolved: NSColor?
        let resolve = { resolved = color.usingColorSpace(.sRGB) }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(resolve)
        } else {
            resolve()
        }

        guard let rgb = resolved else {
            return .object([
                "hex": .null,
                "alpha": .null,
                "catalog": JSONValue.str(catalog),
                "name": JSONValue.str(name),
                "unresolvable": .bool(true),
                "colorSpace": .string(color.colorSpace.localizedName ?? "unknown")
            ])
        }
        return describe(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent,
                        a: rgb.alphaComponent, catalog: catalog, name: name)
    }

    /// A `CGColor` from a layer. A layer stores the resolved component values, so
    /// any semantic origin is already gone by the time it arrives here — the
    /// catalog fields are null for layer colours and that is a fact about
    /// CoreAnimation rather than a gap in this walk.
    static func color(_ cg: CGColor?) -> JSONValue {
        guard let cg else { return .null }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cg.converted(to: srgb, intent: .defaultIntent, options: nil),
              let comps = converted.components, comps.count >= 3
        else {
            return .object(["hex": .null, "alpha": JSONValue.num(cg.alpha),
                            "catalog": .null, "name": .null, "unresolvable": .bool(true)])
        }
        let alpha = comps.count >= 4 ? comps[3] : converted.alpha
        return describe(r: comps[0], g: comps[1], b: comps[2], a: alpha, catalog: nil, name: nil)
    }

    private static func describe(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat,
                                 catalog: String?, name: String?) -> JSONValue {
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let hex = String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        return .object([
            "hex": .string(hex),
            "alpha": JSONValue.num(Double(a)),
            "catalog": JSONValue.str(catalog),
            "name": JSONValue.str(name)
        ])
    }

    // MARK: - Font

    static func font(_ font: NSFont?) -> JSONValue {
        guard let font else { return .null }
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weightValue = (traits?[.weight] as? NSNumber)?.doubleValue ?? 0
        return .object([
            "family": JSONValue.str(font.familyName),
            "postScriptName": .string(font.fontName),
            "size": JSONValue.num(font.pointSize),
            "weight": JSONValue.num(weightValue),
            "weightName": .string(weightName(weightValue)),
            "italic": .bool(font.fontDescriptor.symbolicTraits.contains(.italic)),
            "monospace": .bool(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        ])
    }

    /// Maps the `NSFont.Weight` scale onto the names a designer uses.
    private static func weightName(_ w: Double) -> String {
        switch w {
        case ..<(-0.7): return "ultraLight"
        case ..<(-0.5): return "thin"
        case ..<(-0.2): return "light"
        case ..<0.1: return "regular"
        case ..<0.3: return "medium"
        case ..<0.4: return "semibold"
        case ..<0.55: return "bold"
        case ..<0.6: return "heavy"
        default: return "black"
        }
    }

    // MARK: - Enum spellings

    static func alignment(_ a: NSTextAlignment) -> String {
        switch a {
        case .left: return "left"
        case .right: return "right"
        case .center: return "center"
        case .justified: return "justified"
        case .natural: return "natural"
        @unknown default: return "unknown"
        }
    }

    static func lineBreak(_ m: NSLineBreakMode) -> String {
        switch m {
        case .byWordWrapping: return "byWordWrapping"
        case .byCharWrapping: return "byCharWrapping"
        case .byClipping: return "byClipping"
        case .byTruncatingHead: return "byTruncatingHead"
        case .byTruncatingTail: return "byTruncatingTail"
        case .byTruncatingMiddle: return "byTruncatingMiddle"
        @unknown default: return "unknown"
        }
    }

    static func cornerMask(_ m: CACornerMask) -> JSONValue {
        var names: [JSONValue] = []
        if m.contains(.layerMinXMinYCorner) { names.append(.string("minXMinY")) }
        if m.contains(.layerMaxXMinYCorner) { names.append(.string("maxXMinY")) }
        if m.contains(.layerMinXMaxYCorner) { names.append(.string("minXMaxY")) }
        if m.contains(.layerMaxXMaxYCorner) { names.append(.string("maxXMaxY")) }
        return .array(names)
    }

    static func transform(_ t: CATransform3D) -> JSONValue {
        guard !CATransform3DIsIdentity(t) else { return .null }
        return .array([t.m11, t.m12, t.m13, t.m14,
                       t.m21, t.m22, t.m23, t.m24,
                       t.m31, t.m32, t.m33, t.m34,
                       t.m41, t.m42, t.m43, t.m44].map { JSONValue.num(Double($0)) })
    }

    static func attribute(_ a: NSLayoutConstraint.Attribute) -> String {
        switch a {
        case .left: return "left"
        case .right: return "right"
        case .top: return "top"
        case .bottom: return "bottom"
        case .leading: return "leading"
        case .trailing: return "trailing"
        case .width: return "width"
        case .height: return "height"
        case .centerX: return "centerX"
        case .centerY: return "centerY"
        case .lastBaseline: return "lastBaseline"
        case .firstBaseline: return "firstBaseline"
        case .notAnAttribute: return "notAnAttribute"
        // Autoresizing-derived constraints use private attribute values. The raw
        // number is kept because "unknown" on its own is not usable evidence.
        @unknown default: return "unknown(\(a.rawValue))"
        }
    }

    static func relation(_ r: NSLayoutConstraint.Relation) -> String {
        switch r {
        case .lessThanOrEqual: return "<="
        case .equal: return "=="
        case .greaterThanOrEqual: return ">="
        @unknown default: return "unknown"
        }
    }
}

#endif
