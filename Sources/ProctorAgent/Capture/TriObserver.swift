import Foundation
import CoreGraphics
import ProctorCore

// The third observer. The AX tree says what exists, the geometry source says
// where it is laid out, and the pixels say what a person can actually see.
// Where two of them disagree about the same instant, the delta is the finding:
// a ghost node, an invisible-but-focusable control, a stale frame, a hit target
// that misses itself. Smoothing those away would discard the only evidence this
// server has that the app is lying about its own state.

enum TriObserver {

    // MARK: - Tunables

    /// Two points is the tolerance AX geometry is worth; below that, layout
    /// rounding and backing-scale conversion account for the difference.
    static let frameTolerance: Double = 2

    /// Standard deviation below this, per channel on a 0..1 scale, reads as a
    /// flat fill rather than rendered content.
    static let uniformityEpsilon: Double = 0.01

    /// How close a region's dominant colour has to be to the window background
    /// before it counts as the same colour.
    static let backgroundMatchEpsilon: Double = 0.035

    /// WCAG 2.2 minimum target size.
    static let recommendedMinimumHitSize: Double = 24

    static let containerRoles: Set<String> = [
        "AXGroup", "AXSplitGroup", "AXSplitter", "AXScrollArea", "AXWindow", "AXApplication",
        "AXLayoutArea", "AXLayoutItem", "AXList", "AXOutline", "AXTable", "AXTabGroup",
        "AXToolbar", "AXUnknown", "AXScrollBar", "AXMatte", "AXDrawer", "AXSheet",
    ]

    static let actionRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXMenuButton", "AXCheckBox", "AXRadioButton",
        "AXTextField", "AXTextArea", "AXSlider", "AXStepper", "AXComboBox", "AXLink",
        "AXMenuItem", "AXTab", "AXDisclosureTriangle", "AXIncrementor", "AXSearchField",
    ]

    static let actionNames: Set<String> = [
        "AXPress", "AXIncrement", "AXDecrement", "AXConfirm", "AXPick", "AXShowMenu", "AXOpen",
    ]

    static func isActionable(_ node: AXNode) -> Bool {
        if node.actions.contains(where: { actionNames.contains($0) }) { return true }
        return actionRoles.contains(node.role)
    }

    // MARK: - Entry point

    /// `lastAXChangeAt` is seconds since epoch, from whatever observed the last
    /// AX notification on this window. Nil means nothing is tracking it, and the
    /// staleness check is skipped rather than guessed at.
    static func analyse(root: AXNode,
                        window: WindowHandle,
                        geometry: [String: Rect]?,
                        capture: CaptureResult,
                        lastAXChangeAt: Double?) -> [Disagreement] {

        var out: [Disagreement] = []

        if let changedAt = lastAXChangeAt, capture.capturedAt < changedAt {
            let lagMs = Int((changedAt - capture.capturedAt) * 1000)
            out.append(Disagreement(
                kind: .staleFrame,
                node: nil,
                detail: "The frame was captured \(lagMs)ms before the last accessibility change "
                      + "on this window, so every pixel assertion made against it describes an "
                      + "older state than the tree does.",
                axSays: .number(changedAt),
                layerSays: nil,
                pixelsSay: .number(capture.capturedAt),
                severity: .defect))
        }

        if !capture.trustworthy {
            out.append(Disagreement(
                kind: .staleFrame,
                node: nil,
                detail: "The capture is not trustworthy: status \(capture.status.rawValue). "
                      + (capture.caveat ?? "No caveat was recorded."),
                axSays: nil,
                layerSays: nil,
                pixelsSay: .string(capture.status.rawValue),
                severity: .warning))
        }

        let probe = PixelProbe(pngPath: capture.path)
        // The window's modal background colour, which the ghost-node check
        // compares node regions against.
        let background = probe.flatMap { $0.stats(in: $0.bounds)?.dominant }
        let contentPixels = probe.flatMap {
            contentRectInPixels(capture.contentRect, image: $0, scale: capture.scale)
        }

        walk(node: root, parent: nil) { node, parent in
            out.append(contentsOf: nodeFindings(node: node,
                                                parent: parent,
                                                window: window,
                                                geometry: geometry,
                                                capture: capture,
                                                probe: probe,
                                                background: background,
                                                contentPixels: contentPixels))
        }

        return out
    }

    // MARK: - Per-node checks

    private static func nodeFindings(node: AXNode,
                                     parent: AXNode?,
                                     window: WindowHandle,
                                     geometry: [String: Rect]?,
                                     capture: CaptureResult,
                                     probe: PixelProbe?,
                                     background: RGB?,
                                     contentPixels: CGRect?) -> [Disagreement] {
        var out: [Disagreement] = []
        guard let frame = node.frame else { return out }
        let rect = cg(frame)
        let actionable = isActionable(node)

        // invisibleButFocusable — zero area
        if rect.width <= 0 || rect.height <= 0 {
            if node.focused == true {
                out.append(Disagreement(
                    kind: .invisibleButFocusable,
                    node: node.id,
                    detail: "\(node.role) holds keyboard focus with a zero-area frame, so the "
                          + "focused element is not visible anywhere on screen.",
                    axSays: rectValue(frame),
                    layerSays: nil,
                    pixelsSay: nil,
                    severity: .defect))
            } else if actionable {
                out.append(Disagreement(
                    kind: .invisibleButFocusable,
                    node: node.id,
                    detail: "\(node.role) exposes \(node.actions.joined(separator: ", ")) with a "
                          + "zero-area frame: it can be actuated through accessibility but a "
                          + "person has nothing to click.",
                    axSays: rectValue(frame),
                    layerSays: nil,
                    pixelsSay: nil,
                    severity: .defect))
            }
            return out
        }

        // invisibleButFocusable — outside the captured content
        if let content = contentPixels {
            let inImage = imageRect(frame, window: window, scale: capture.scale)
            if !inImage.intersects(content) && (actionable || node.focused == true) {
                out.append(Disagreement(
                    kind: .invisibleButFocusable,
                    node: node.id,
                    detail: "\(node.role) sits entirely outside the frame's content rect, so it "
                          + "is reachable through accessibility but absent from the rendered "
                          + "window. It may be scrolled out of view, or laid out off-window.",
                    axSays: rectValue(frame),
                    layerSays: nil,
                    pixelsSay: .string(describe(content)),
                    severity: node.focused == true ? .defect : .warning))
                return out
            }
        }

        // hitTargetMismatch
        if let parent, let pf = parent.frame {
            let clipped = rect.intersection(cg(pf))
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            if clipped.isNull || !clipped.contains(centre) {
                out.append(Disagreement(
                    kind: .hitTargetMismatch,
                    node: node.id,
                    detail: "The centre of \(node.role) falls outside its own frame once clipped "
                          + "to \(parent.role), so a click at the reported hit point lands on "
                          + "something else.",
                    axSays: rectValue(frame),
                    layerSays: rectValue(pf),
                    pixelsSay: nil,
                    severity: actionable ? .defect : .warning))
            }
        }

        // frameMismatch
        if let geometry, let layer = geometry[node.id] {
            // A geometry source may report window-relative or screen coordinates
            // and does not say which, so a mismatch counts only when both
            // readings disagree.
            let screenDelta = maxDelta(frame, layer)
            let relative = Rect(x: frame.x - window.frame.x, y: frame.y - window.frame.y,
                                w: frame.w, h: frame.h)
            let relativeDelta = maxDelta(relative, layer)
            let delta = min(screenDelta, relativeDelta)
            if delta > frameTolerance {
                out.append(Disagreement(
                    kind: .frameMismatch,
                    node: node.id,
                    detail: String(format: "The accessibility frame and the layer frame disagree "
                                 + "by %.1fpt under both screen and window-relative readings. "
                                 + "One of the two is describing geometry the other cannot see.",
                                   delta),
                    axSays: rectValue(frame),
                    layerSays: rectValue(layer),
                    pixelsSay: nil,
                    severity: .defect))
            }
        }

        // ghostNode
        if let probe, let background, !containerRoles.contains(node.role) {
            let region = imageRect(frame, window: window, scale: capture.scale)
            if region.width >= 2, region.height >= 2,
               let stats = probe.stats(in: region),
               stats.variance.squareRoot() < uniformityEpsilon,
               stats.dominant.distance(to: background) < backgroundMatchEpsilon {
                out.append(Disagreement(
                    kind: .ghostNode,
                    node: node.id,
                    detail: "\(node.role) claims \(describe(region)) in the frame, but that region "
                          + "is a flat fill of the window background colour \(background.hex). "
                          + "Either nothing is drawn there or the node is stale.",
                    axSays: rectValue(frame),
                    layerSays: nil,
                    pixelsSay: .object([
                        "dominant": .string(stats.dominant.hex),
                        "stddev": .number(stats.variance.squareRoot()),
                        "samples": .number(Double(stats.sampleCount)),
                    ]),
                    // A legitimately empty control — an unchecked checkbox on a
                    // matching background, a spacer — looks the same, so this
                    // heuristic reports rather than convicts.
                    severity: .warning))
            }
        }

        return out
    }

    // MARK: - Helpers for the assert layer

    /// The smallest dimension of a node's hit area, in points. Nil when the node
    /// has no frame at all, which is a different finding.
    static func hitSize(of node: AXNode) -> (w: Double, h: Double)? {
        guard let f = node.frame else { return nil }
        return (f.w, f.h)
    }

    /// Nodes whose actionable area is below `minimum` on either axis.
    static func hitSizeFindings(root: AXNode,
                                minimum: Double = recommendedMinimumHitSize) -> [Disagreement] {
        var out: [Disagreement] = []
        walk(node: root, parent: nil) { node, _ in
            guard isActionable(node), let size = hitSize(of: node) else { return }
            guard size.w > 0, size.h > 0 else { return }   // zero area is reported elsewhere
            guard size.w < minimum || size.h < minimum else { return }
            out.append(Disagreement(
                kind: .hitTargetMismatch,
                node: node.id,
                detail: String(format: "%@ is %.0fx%.0fpt, below the %.0fpt minimum target size.",
                               node.role, size.w, size.h, minimum),
                axSays: .object(["w": .number(size.w), "h": .number(size.h)]),
                layerSays: nil,
                pixelsSay: nil,
                severity: .warning))
        }
        return out
    }

    struct ContrastMeasurement: Sendable {
        var ratio: Double
        var foreground: RGB
        var background: RGB
        var foregroundShare: Double
    }

    /// WCAG contrast between a node region's dominant colour and the most
    /// luminance-distant colour holding a real share of that region. Sampled
    /// from the PNG, so it measures what was rendered rather than what was
    /// specified.
    static func contrast(of node: AXNode,
                         window: WindowHandle,
                         capture: CaptureResult,
                         probe: PixelProbe) -> ContrastMeasurement? {
        guard let frame = node.frame else { return nil }
        let region = imageRect(frame, window: window, scale: capture.scale)
        guard region.width >= 2, region.height >= 2,
              let stats = probe.stats(in: region),
              let fg = stats.contrastingColour else { return nil }
        return ContrastMeasurement(ratio: RGB.contrastRatio(fg, stats.dominant),
                                   foreground: fg,
                                   background: stats.dominant,
                                   foregroundShare: stats.contrastingShare)
    }

    /// Text-bearing nodes whose measured contrast falls below `threshold`
    /// (4.5 is the WCAG AA floor for body text).
    static func contrastFindings(root: AXNode,
                                 window: WindowHandle,
                                 capture: CaptureResult,
                                 threshold: Double = 4.5) -> [Disagreement] {
        guard let probe = PixelProbe(pngPath: capture.path) else { return [] }
        var out: [Disagreement] = []
        walk(node: root, parent: nil) { node, _ in
            let carriesText = !(node.title ?? "").isEmpty || !(node.label ?? "").isEmpty
                || node.role == "AXStaticText"
            guard carriesText, let m = contrast(of: node, window: window,
                                                capture: capture, probe: probe) else { return }
            guard m.ratio < threshold else { return }
            out.append(Disagreement(
                kind: .contrastBelowThreshold,
                node: node.id,
                detail: String(format: "Measured contrast %.2f:1 between %@ and %@, below the "
                             + "%.1f:1 threshold.", m.ratio, m.foreground.hex,
                               m.background.hex, threshold),
                axSays: .string(node.title ?? node.label ?? node.role),
                layerSays: nil,
                pixelsSay: .object([
                    "ratio": .number(m.ratio),
                    "foreground": .string(m.foreground.hex),
                    "background": .string(m.background.hex),
                    "foregroundShare": .number(m.foregroundShare),
                ]),
                // Sampled contrast can pick a border or an icon as foreground,
                // so it is evidence to look at rather than a proven failure.
                severity: m.ratio < threshold * 0.6 ? .defect : .warning))
        }
        return out
    }

    // MARK: - Geometry

    static func walk(node: AXNode, parent: AXNode?, _ body: (AXNode, AXNode?) -> Void) {
        body(node, parent)
        for child in node.children ?? [] { walk(node: child, parent: node, body) }
    }

    static func cg(_ r: Rect) -> CGRect { CGRect(x: r.x, y: r.y, width: r.w, height: r.h) }

    /// Screen points to frame pixels: subtract the window origin, then scale.
    static func imageRect(_ r: Rect, window: WindowHandle, scale: Double) -> CGRect {
        let s = scale > 0 ? scale : 1
        return CGRect(x: (r.x - window.frame.x) * s,
                      y: (r.y - window.frame.y) * s,
                      width: r.w * s,
                      height: r.h * s)
    }

    /// SCK reports contentRect in the surface's pixel space, but a caller may
    /// hand back one measured in points. Whichever it is, it is compared against
    /// the image, so it is normalised against the image's own dimensions.
    static func contentRectInPixels(_ rect: Rect?, image: PixelProbe, scale: Double) -> CGRect? {
        guard let rect, rect.w > 0, rect.h > 0 else { return nil }
        let asPixels = CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
        let tolerance = max(2.0, Double(image.width) * 0.02)
        if abs(rect.w - Double(image.width)) <= tolerance { return asPixels }
        let s = scale > 0 ? scale : 1
        if abs(rect.w * s - Double(image.width)) <= tolerance {
            return CGRect(x: rect.x * s, y: rect.y * s, width: rect.w * s, height: rect.h * s)
        }
        return asPixels
    }

    static func maxDelta(_ a: Rect, _ b: Rect) -> Double {
        max(abs(a.x - b.x), abs(a.y - b.y), abs(a.w - b.w), abs(a.h - b.h))
    }

    static func rectValue(_ r: Rect) -> JSONValue {
        .object(["x": .number(r.x), "y": .number(r.y), "w": .number(r.w), "h": .number(r.h)])
    }

    static func describe(_ r: CGRect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", r.origin.x, r.origin.y, r.width, r.height)
    }
}
