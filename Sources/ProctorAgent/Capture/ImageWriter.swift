import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ProctorCore

// The one place a captured frame reaches the filesystem. Both writers that used
// to exist — the capture engine's and the zoom crop's — hardcoded PNG through
// their own CGImageDestination, which meant two places to change a container and
// two sets of error messages for the same failure. The format decision itself is
// in ProctorCore.ImageFormat, which needs no grant to test.

enum ImageWriter {

    /// Write a CGImage to `path` in `format`. `quality` applies to lossy formats
    /// only and is clamped in ProctorCore; PNG ignores it. The directory is
    /// created if it does not exist, so a caller pointing at a fresh session
    /// directory does not have to.
    ///
    /// `what` names the artefact in any error — "capture", "crop", "annotated
    /// capture" — so a failure says which write failed rather than only that a
    /// write did.
    static func write(_ image: CGImage,
                      to path: String,
                      format: ImageFormat = .png,
                      quality: Int? = nil,
                      what: String = "capture") throws {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType as CFString, 1, nil) else {
            throw AgentError(
                code: .captureFailed,
                message: "Could not open \(path) for writing the \(what) as \(format.rawValue).",
                remedy: "Check the directory exists and is writable.")
        }

        var properties: [CFString: Any] = [:]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] =
                ImageFormat.clampQuality(quality)
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw AgentError(code: .captureFailed,
                             message: "Writing the \(what) to \(path) failed.")
        }
    }
}
