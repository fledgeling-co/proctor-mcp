import Foundation

// Vision-capture normalisation, the checkable half of the feature. A frame handed
// to a vision model that exceeds the API's ceiling is *silently* downsampled by
// the API, and any coordinate the model then returns is in a different space from
// the pixels Proctor measured — drift that quietly corrupts pixel-plane
// assertions and tri-observer geometry. Doing the scaling ourselves, and
// reporting the exact factor, keeps the coordinate round-trip honest.
//
// The decision (which ceiling binds, what scale that implies) and the coordinate
// round-trip live here, away from ScreenCaptureKit and any grant, so they can be
// tested directly — the same reason SetOfMarks, PointerPath and RegionDirt keep
// their arithmetic in Core rather than in the agent. The pixel resample that
// follows in the agent is mechanical; getting *this* wrong is what would make a
// model's coordinate land on the wrong element.

public enum VisionCapture {

    /// The long-edge ceiling most vision APIs enforce before they downsample.
    /// A frame whose longer side is under this is passed through untouched.
    public static let defaultMaxLongEdge = 1568

    /// The total-pixel ceiling (~1.15 megapixels). Area scales with the square of
    /// a linear factor, so this binds independently of the long edge — a large
    /// near-square frame can be under 1568 on each side and still over budget.
    public static let defaultMaxPixels = 1_150_000

    /// WHAT THE FRAME IS FOR, which is the only thing that decides how many
    /// pixels it needs.
    ///
    /// The ceilings above are the vision API's limit, and Proctor used to send
    /// every capture at them. That is the wrong default, because the limit is
    /// what the API *tolerates* rather than what the task *needs*, and a model is
    /// billed on pixel dimensions — Anthropic prices an image at roughly
    /// `width × height / 750` tokens, so a frame at the ceiling costs about
    /// 1,530 tokens whether or not anything in it needed resolving.
    ///
    /// The three tiers are the measured design rather than round numbers:
    ///
    ///   `targeting` at 768 is where a frame is only being used to decide WHAT to
    ///   press and WHERE. Nothing is being read, so glyph legibility is not the
    ///   constraint. 768 is also exactly Gemini's tile boundary — it charges
    ///   `ceil(w/768) × ceil(h/768) × 258`, so 769 pixels costs double what 768
    ///   does — and it is the cheapest tier that still resolves a numbered mark.
    ///
    ///   `verify` at 1024 is XGA, which is what Anthropic's own computer-use
    ///   reference implementation targets for reliability rather than the API
    ///   ceiling it also publishes. This is the default: it reads most UI text
    ///   and costs a little over half of what the ceiling does.
    ///
    ///   `detail` is the old default, the API ceiling itself, for a frame
    ///   somebody is going to read dense text out of.
    ///
    /// The escalation is the point, and it is evidence-backed rather than
    /// tidy: returning a low-resolution overview and letting a caller ask for a
    /// native-resolution crop on demand is measured to lift grounding accuracy on
    /// dense professional interfaces from under 20% to over 70%. Proctor already
    /// has the second half of that pattern in `proctor_zoom`; this supplies the
    /// first half instead of sending the ceiling every time.
    public enum Purpose: String, Sendable, CaseIterable, Codable {
        case targeting
        case verify
        case detail

        public var maxLongEdge: Int {
            switch self {
            case .targeting: return 768
            case .verify:    return 1024
            case .detail:    return VisionCapture.defaultMaxLongEdge
            }
        }

        /// Kept in proportion to the long edge rather than fixed, for the reason
        /// `defaultMaxPixels` exists: a near-square frame can sit under the long
        /// edge on both sides and still be over budget.
        public var maxPixels: Int {
            switch self {
            case .targeting: return 400_000
            case .verify:    return 750_000
            case .detail:    return VisionCapture.defaultMaxPixels
            }
        }

        public static let `default`: Purpose = .verify

        public static func parse(_ raw: String?) -> Purpose? {
            guard let raw else { return nil }
            return Purpose(rawValue:
                raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    /// Roughly what a frame of this size costs a vision model, so the saving is
    /// legible in the result rather than something a caller has to work out.
    ///
    /// Anthropic's published approximation, and deliberately only that: it is one
    /// family's pricing and the other two tokenise differently, so this is
    /// reported as an estimate and never used to decide anything.
    public static func estimatedVisionTokens(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 0 }
        return Int((Double(width) * Double(height) / 750.0).rounded())
    }

    /// The outcome of fitting a frame under the ceilings: the uniform scale
    /// actually applied (`out/in`, always ≤ 1), the resulting pixel dimensions,
    /// and whether any downscale happened at all.
    public struct Fit: Equatable, Sendable {
        public var scale: Double     // out/in, ≤ 1; 1 when nothing was scaled
        public var width: Int        // normalised pixel width
        public var height: Int       // normalised pixel height
        public var applied: Bool     // whether a downscale was needed
        public init(scale: Double, width: Int, height: Int, applied: Bool) {
            self.scale = scale; self.width = width; self.height = height; self.applied = applied
        }
    }

    /// Decide the scale that brings a frame under both ceilings, preserving
    /// aspect ratio. Normalisation only ever shrinks: a frame already within
    /// both ceilings is returned unchanged with `scale == 1` and
    /// `applied == false`, so opting in never degrades an image that did not
    /// need it. The binding ceiling is whichever demands the smaller scale — the
    /// long edge, or the pixel count via `sqrt(maxPixels / pixels)` because area
    /// falls with the square of the linear factor.
    public static func fit(width: Int, height: Int,
                           maxLongEdge: Int = defaultMaxLongEdge,
                           maxPixels: Int = defaultMaxPixels) -> Fit {
        guard width > 0, height > 0 else {
            return Fit(scale: 1, width: width, height: height, applied: false)
        }
        let longEdge = max(width, height)
        let pixels = Double(width) * Double(height)

        let edgeScale = (maxLongEdge > 0 && longEdge > maxLongEdge)
            ? Double(maxLongEdge) / Double(longEdge) : 1.0
        let pixelScale = (maxPixels > 0 && pixels > Double(maxPixels))
            ? (Double(maxPixels) / pixels).squareRoot() : 1.0

        let scale = min(edgeScale, pixelScale)
        guard scale < 1.0 else {
            return Fit(scale: 1, width: width, height: height, applied: false)
        }

        // Round to the nearest whole pixel, never below 1. The reported `scale`
        // is the uniform factor the round-trip inverts; sub-pixel rounding of the
        // dimensions is bounded to under a pixel and does not change the factor.
        let outW = max(1, Int((Double(width) * scale).rounded()))
        let outH = max(1, Int((Double(height) * scale).rounded()))
        return Fit(scale: scale, width: outW, height: outH, applied: true)
    }

    /// Map a coordinate the model returned in the *normalised* image back to
    /// native pixel space. This is the inverse a caller applies before asserting
    /// against Proctor's native geometry: the model saw a frame scaled by
    /// `scale`, so its coordinate is `scale`× the native one, and dividing undoes
    /// it. A `scale` of 0 or below is treated as 1 (no normalisation applied).
    public static func toNative(_ value: Double, scale: Double) -> Double {
        scale > 0 ? value / scale : value
    }

    /// Map a native-space coordinate forward into the normalised image the model
    /// sees. The exact inverse of `toNative`, so a round-trip returns the input.
    public static func toNormalized(_ value: Double, scale: Double) -> Double {
        scale > 0 ? value * scale : value
    }

    /// Map a whole rectangle from normalised image space back to native pixels.
    public static func toNative(_ rect: Rect, scale: Double) -> Rect {
        let s = scale > 0 ? scale : 1
        return Rect(x: rect.x / s, y: rect.y / s, w: rect.w / s, h: rect.h / s)
    }
}
