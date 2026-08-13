import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import ProctorCore

// Burns a set-of-marks plan into the pixels. This is the mechanical half of the
// feature: SetOfMarks decided which elements get which number and where the box
// lands, and this draws them. It reads the un-annotated PNG already written to
// disk — the same hand-off PixelProbe uses — composites into a bitmap context of
// the same size, and writes the marked PNG alongside. CaptureEngineImpl is never
// touched, so the capture path and its freshness metadata stay exactly as they were.
//
// The context is kept y-up (CoreGraphics' native space) and every top-left pixel
// coordinate from the plan is converted with `height - y`. Text then draws upright
// with no text-matrix flip, which is the usual source of upside-down glyphs.

enum MarkRenderer {

    /// Distinct accents cycled by mark index, so two marks that land next to each
    /// other are told apart at a glance. High-chroma on purpose: these sit on top
    /// of arbitrary UI and have to stay legible.
    private static let palette: [(Double, Double, Double)] = [
        (0.95, 0.15, 0.30),   // red
        (0.10, 0.55, 0.95),   // blue
        (0.15, 0.70, 0.35),   // green
        (0.60, 0.25, 0.85),   // purple
        (0.95, 0.55, 0.10),   // orange
        (0.05, 0.65, 0.65),   // teal
    ]

    /// Draw the plan onto the PNG at `basePath` and write the result. Returns the
    /// path of the marked PNG. Throws captureFailed with a remedy if the base
    /// image cannot be read or the result cannot be written, so annotation never
    /// fails silently into an un-marked file.
    static func render(basePath: String, width: Int, height: Int, scale: Double,
                       plan: SetOfMarks.Plan) throws -> String {
        guard width > 0, height > 0 else {
            throw AgentError(code: .captureFailed,
                             message: "Cannot annotate a capture with no pixel dimensions "
                                    + "(\(width)x\(height)).")
        }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: basePath) as CFURL, nil),
              let base = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AgentError(code: .captureFailed,
                             message: "Could not read the captured PNG at \(basePath) to annotate it.",
                             remedy: "Confirm the capture wrote a file before annotating.")
        }

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                       | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bitmapInfo) else {
            throw AgentError(code: .captureFailed,
                             message: "Could not create a drawing context to annotate the capture.")
        }

        // The captured frame, upright. In a y-up context drawing at (0,0,w,h)
        // reproduces the source orientation, matching how PixelProbe reads it back.
        ctx.interpolationQuality = .none
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))

        let s = scale > 0 ? scale : 1
        if let grid = plan.grid {
            drawGrid(grid, in: ctx, width: width, height: height, scale: s)
        }
        for mark in plan.marks {
            draw(mark: mark, in: ctx, height: height, scale: s)
        }

        guard let image = ctx.makeImage() else {
            throw AgentError(code: .captureFailed,
                             message: "The annotated frame could not be turned into an image.")
        }
        let outPath = annotatedPath(for: basePath)
        try writePNG(image, to: outPath)
        return outPath
    }

    // MARK: - Grid

    private static func drawGrid(_ grid: GridOverlay, in ctx: CGContext,
                                 width: Int, height: Int, scale: Double) {
        let line = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                           components: [0.10, 0.80, 0.85, 0.45])!
        ctx.setStrokeColor(line)
        ctx.setLineWidth(max(1, scale * 0.5))
        let h = CGFloat(height)

        for x in grid.verticals {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: h))
        }
        for yTop in grid.horizontals {
            let y = h - CGFloat(yTop)
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: CGFloat(width), y: y))
        }
        ctx.strokePath()

        // Label each interior line with the point coordinate a caller reads off it.
        let labelColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                 components: [0.03, 0.35, 0.40, 1.0])!
        let fontSize = max(8, 6 * scale)
        for x in grid.verticals {
            let points = Int((x / scale).rounded())
            drawText("\(points)", at: CGPoint(x: x + 2, y: h - fontSize - 2),
                     fontSize: fontSize, color: labelColor, in: ctx)
        }
        for yTop in grid.horizontals {
            let points = Int((yTop / scale).rounded())
            drawText("\(points)", at: CGPoint(x: 2, y: h - CGFloat(yTop) + 2),
                     fontSize: fontSize, color: labelColor, in: ctx)
        }
    }

    // MARK: - Marks

    private static func draw(mark: Mark, in ctx: CGContext, height: Int, scale: Double) {
        let (r, g, b) = palette[(mark.id - 1) % palette.count]
        let accent = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                             components: [r, g, b, 1.0])!
        let h = CGFloat(height)

        // The element box, in y-up space.
        let box = CGRect(x: mark.pixelRect.x,
                         y: h - mark.pixelRect.y - mark.pixelRect.h,
                         width: mark.pixelRect.w,
                         height: mark.pixelRect.h)
        ctx.setStrokeColor(accent)
        ctx.setLineWidth(max(2, scale))
        ctx.stroke(box)

        // A solid badge pinned to the box's top-left corner, holding the number.
        let fontSize = max(10, 8 * scale)
        let label = "\(mark.id)"
        let textWidth = measure(label, fontSize: fontSize)
        let padX = max(3, scale * 2), padY = max(2, scale)
        let badgeW = textWidth + padX * 2
        let badgeH = fontSize + padY * 2
        // Top-left of the box in top-left coords is (pixelRect.x, pixelRect.y);
        // in y-up the badge sits just above that edge.
        let badgeYUp = h - mark.pixelRect.y
        let badge = CGRect(x: box.minX, y: badgeYUp - badgeH, width: badgeW, height: badgeH)
        ctx.setFillColor(accent)
        ctx.fill(badge)

        let white = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                            components: [1, 1, 1, 1])!
        drawText(label, at: CGPoint(x: badge.minX + padX, y: badge.minY + padY),
                 fontSize: fontSize, color: white, in: ctx)
    }

    // MARK: - Text

    private static func font(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
    }

    private static func measure(_ string: String, fontSize: CGFloat) -> CGFloat {
        let line = ctLine(string, fontSize: fontSize,
                          color: CGColor(gray: 0, alpha: 1))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        return CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    }

    /// Draw a string with its lower-left corner at `origin`, in y-up space.
    private static func drawText(_ string: String, at origin: CGPoint,
                                 fontSize: CGFloat, color: CGColor, in ctx: CGContext) {
        let line = ctLine(string, fontSize: fontSize, color: color)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: origin.x, y: origin.y + descent)
        CTLineDraw(line, ctx)
    }

    private static func ctLine(_ string: String, fontSize: CGFloat, color: CGColor) -> CTLine {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font(fontSize),
            kCTForegroundColorAttributeName: color,
        ]
        let attributed = CFAttributedStringCreate(nil, string as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(attributed)
    }

    // MARK: - Output

    /// `/dir/foo.png` -> `/dir/foo.marked.png`, so the marked file sits beside the
    /// original and never overwrites it.
    static func annotatedPath(for basePath: String) -> String {
        let url = URL(fileURLWithPath: basePath)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        let name = ext.isEmpty ? "\(stem).marked.png" : "\(stem).marked.\(ext)"
        return dir.appendingPathComponent(name).path
    }

    private static func writePNG(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AgentError(code: .captureFailed,
                             message: "Could not open \(path) for writing the annotated PNG.",
                             remedy: "Check the directory exists and is writable.")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw AgentError(code: .captureFailed,
                             message: "Writing the annotated PNG to \(path) failed.")
        }
    }
}
