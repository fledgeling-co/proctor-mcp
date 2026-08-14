import Foundation

// The container a capture is written in. Pure enough to test without a grant or
// a frame: the format decision, the quality clamp and the filename it implies
// live here, and the agent does the ImageIO write.
//
// PNG is the default and should stay it. Proctor returns a *path*, never bytes,
// so file size never reaches the model's context — a vision model is billed on
// the pixel dimensions of what it is shown, not on how many bytes the file took
// to store. That makes lossy encoding a trade with no upside on the token
// budget, and a measurable downside on text: on a 3456x2234 macOS capture
// normalised to the vision ceiling, Vision OCR recovered 94.0% of the
// native-resolution words from PNG and 92.7% from JPEG q95, and the count of
// garbled tokens — text read as a *different* real word, which is worse for a
// model than text it cannot read at all — climbed from 11 to 12 at q95, 20 at
// q85, 30 at q75 and 66 at q50 as ringing hit the hard glyph edges UI text is
// made of.
//
// JPEG is offered for the cases where bytes genuinely are the constraint: a CI
// job archiving thousands of frames, or the HTTP transport over a slow link.
// It is opt-in, and the quality floor is deliberately high.
public enum ImageFormat: String, Sendable, CaseIterable {
    case png
    case jpeg

    /// The UTI ImageIO writes through. Both are in
    /// `CGImageDestinationCopyTypeIdentifiers()` on every macOS Proctor supports.
    /// WebP is deliberately absent: macOS can *decode* it but ships no encoder,
    /// so offering it would mean bundling libwebp into a notarised build to save
    /// bytes that do not cost tokens.
    public var utType: String {
        switch self {
        case .png:  return "public.png"
        case .jpeg: return "public.jpeg"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpeg: return "jpg"
        }
    }

    public var isLossy: Bool { self != .png }

    /// Parse a caller's `format` argument. Accepts the common spellings rather
    /// than only the canonical one, since "jpg" is what most callers type.
    public static func parse(_ raw: String?) -> ImageFormat? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "png":            return .png
        case "jpeg", "jpg":    return .jpeg
        default:               return nil
        }
    }

    /// The container a capture is written in unless a caller says otherwise.
    /// Lossless, for the reason in this file's header: bytes are not what the
    /// model is billed for, so trading text fidelity for them is a bad trade
    /// made by default.
    public static let defaultFormat: ImageFormat = .png

    /// The default quality for a lossy write, and the floor it is clamped to.
    /// The floor is 60 rather than 0 because below roughly q75 the failure mode
    /// stops being "blurry" and becomes "confidently wrong": OCR recall fell to
    /// 82.0% at q65 and 77.7% at q50 on the measurement above, while garbled
    /// tokens rose to 50 and 66. A caller who wants a thumbnail should ask for
    /// fewer pixels, not fewer bits per pixel.
    public static let defaultQuality = 90
    public static let minimumQuality = 60

    public static func clampQuality(_ q: Int?) -> Double {
        let value = q ?? defaultQuality
        return Double(max(minimumQuality, min(100, value))) / 100.0
    }

    /// Swap a path's extension so the file on disk matches what was written into
    /// it. A caller who passes `shot.png` and asks for JPEG gets `shot.jpg`; a
    /// path with no extension, or one already correct, is left with the right
    /// suffix either way. Returning the path rather than mutating it keeps the
    /// caller's own default-path logic in one place.
    public func retarget(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let current = url.pathExtension.lowercased()
        guard current != fileExtension else { return path }
        // Only replace an extension that looks like an image container; a path
        // ending in something else keeps it and gains ours, so a caller's
        // deliberate filename is never silently truncated.
        let known = Set(ImageFormat.allCases.flatMap { [$0.fileExtension, $0.rawValue] })
        if known.contains(current) {
            return url.deletingPathExtension().appendingPathExtension(fileExtension).path
        }
        return url.appendingPathExtension(fileExtension).path
    }
}
