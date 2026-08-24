import Foundation
import CoreGraphics
import ImageIO
import Vision
import ProctorCore

// Native Apple Vision-framework text recognition (OCR) and high-DPI contrast
// inspector for zoom assertions (PRO-0116 / REQ-190).
//
// Extends visual inspection beyond the accessibility tree: custom canvas views,
// non-standard AppKit controls, and graphic text renders where AX is unpopulated
// can be visually inspected and verified at native Retina resolution.

enum VisionOCR {

    /// Default bounded timeout for zoom region OCR (< 500ms).
    static let defaultTimeoutMs: Int = 500

    /// Run text recognition and contrast inspection on a CGImage.
    static func recognize(in image: CGImage,
                          scale: Double = 1.0,
                          timeoutMs: Int = defaultTimeoutMs,
                          probe: PixelProbe? = nil) -> ZoomOCRResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let effectiveScale = scale > 0 ? scale : 1.0
        let width = Double(image.width)
        let height = Double(image.height)

        guard width > 0, height > 0 else {
            return ZoomOCRResult(items: [], text: "", count: 0,
                                 executionMs: 0, scale: effectiveScale, timedOut: false)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        var timedOut = false
        var items: [RecognizedTextItem] = []

        do {
            try handler.perform([request])
            let elapsedAfterOCR = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            if elapsedAfterOCR > Double(timeoutMs) {
                timedOut = true
            }

            if let observations = request.results {
                let pixelProbe = probe ?? PixelProbe(image: image)
                for obs in observations {
                    guard let top = obs.topCandidates(1).first else { continue }
                    let box = obs.boundingBox
                    // Vision boundingBox has bottom-left origin in normalized 0..1 coordinates.
                    // Convert to top-left origin in image pixel space:
                    let px = (box.origin.x * width).rounded()
                    let py = ((1.0 - box.origin.y - box.size.height) * height).rounded()
                    let pw = max(1.0, (box.size.width * width).rounded())
                    let ph = max(1.0, (box.size.height * height).rounded())

                    let pixelRect = Rect(x: px, y: py, w: pw, h: ph)
                    let pointRect = Rect(x: px / effectiveScale,
                                         y: py / effectiveScale,
                                         w: pw / effectiveScale,
                                         h: ph / effectiveScale)

                    // Measure WCAG contrast within the text bounding box if probe is available
                    var contrastRatio: Double? = nil
                    var fgHex: String? = nil
                    var bgHex: String? = nil
                    var contrastPass: Bool? = nil

                    if let pixelProbe {
                        let cgRect = CGRect(x: px, y: py, width: pw, height: ph)
                        if let stats = pixelProbe.stats(in: cgRect), let fg = stats.contrastingColour {
                            let ratio = RGB.contrastRatio(fg, stats.dominant)
                            contrastRatio = (ratio * 100).rounded() / 100.0
                            fgHex = fg.hex
                            bgHex = stats.dominant.hex
                            // WCAG standard body text threshold is 4.5:1
                            contrastPass = ratio >= 4.5
                        }
                    }

                    let item = RecognizedTextItem(
                        text: top.string,
                        confidence: Double(top.confidence),
                        boundingBox: pixelRect,
                        pointBox: pointRect,
                        contrastRatio: contrastRatio,
                        foreground: fgHex,
                        background: bgHex,
                        contrastPass: contrastPass
                    )
                    items.append(item)
                }
            }
        } catch {
            // Degrades gracefully on recognition error
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        if elapsedMs > Double(timeoutMs) {
            timedOut = true
        }
        let fullText = items.map(\.text).joined(separator: "\n")
        return ZoomOCRResult(items: items, text: fullText, count: items.count,
                             executionMs: elapsedMs, scale: effectiveScale, timedOut: timedOut)
    }

    /// Run text recognition and contrast inspection on an image file on disk.
    static func recognize(from pngPath: String,
                          scale: Double = 1.0,
                          timeoutMs: Int = defaultTimeoutMs) -> ZoomOCRResult {
        let url = URL(fileURLWithPath: pngPath)
        guard FileManager.default.fileExists(atPath: pngPath),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return ZoomOCRResult(items: [], text: "", count: 0,
                                 executionMs: 0, scale: scale, timedOut: false)
        }
        let probe = PixelProbe(image: image)
        return recognize(in: image, scale: scale, timeoutMs: timeoutMs, probe: probe)
    }
}
