import Foundation
import CoreGraphics
import CoreText
import Testing
import ProctorCore
@testable import ProctorAgent

// Tests for Native OCR and High-DPI Visual Region Inspector for Zoom Assertions
// (PRO-0116 / REQ-190 / SURF-037 / DEF-315 / CASE-0730..CASE-0734).

@Suite("Native Vision OCR & High-DPI Zoom Inspector")
struct NativeOCRZoomTests {

    private static func createRenderedTextImage(
        text: String,
        width: Int = 400,
        height: Int = 120,
        bgRGB: (r: CGFloat, g: CGFloat, b: CGFloat) = (1, 1, 1),
        fgRGB: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0),
        fontSize: CGFloat = 28
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Background
        ctx.setFillColor(CGColor(red: bgRGB.r, green: bgRGB.g, blue: bgRGB.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Text
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attr = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: fgRGB.r, green: fgRGB.g, blue: fgRGB.b, alpha: 1)
        ] as CFDictionary
        let attrStr = CFAttributedStringCreate(nil, text as CFString, attr)!
        let line = CTLineCreateWithAttributedString(attrStr)
        ctx.textPosition = CGPoint(x: 20, y: 40)
        CTLineDraw(line, ctx)

        return ctx.makeImage()
    }

    /// Warm up the Apple Vision framework's internal CoreML model loading
    private static func warmUpVisionIfNeeded() {
        if let warmupImg = createRenderedTextImage(text: "Warmup", width: 100, height: 40) {
            _ = VisionOCR.recognize(in: warmupImg, scale: 1.0, timeoutMs: 10000)
        }
    }

    @Test("CASE-0730: Native Apple Vision OCR extracts text strings and bounding boxes")
    func nativeVisionOCRTextRecognition() throws {
        Self.warmUpVisionIfNeeded()
        let text = "Proctor Native Inspector"
        guard let image = Self.createRenderedTextImage(text: text, width: 500, height: 140) else {
            Issue.record("Failed to generate test text image")
            return
        }

        let result = VisionOCR.recognize(in: image, scale: 1.0, timeoutMs: 2000)
        #expect(result.count >= 1)
        #expect(result.text.contains("Proctor") || result.text.contains("Inspector"))
        #expect(!result.items.isEmpty)

        if let first = result.items.first {
            #expect(first.confidence > 0.5)
            #expect(first.boundingBox.w > 0)
            #expect(first.boundingBox.h > 0)
            #expect(first.pointBox.w > 0)
            #expect(first.pointBox.h > 0)
        }
    }

    @Test("CASE-0731: High-DPI Retina scale factor is preserved in geometry transformations")
    func highDPIRetinaScalePreservation() throws {
        Self.warmUpVisionIfNeeded()
        let text = "Retina Scale Test"
        guard let image = Self.createRenderedTextImage(text: text, width: 400, height: 100) else {
            Issue.record("Failed to generate test text image")
            return
        }

        let retinaScale = 2.0
        let result = VisionOCR.recognize(in: image, scale: retinaScale, timeoutMs: 2000)
        #expect(result.scale == 2.0)
        #expect(result.count >= 1)

        for item in result.items {
            let expectedPointW = item.boundingBox.w / retinaScale
            let expectedPointH = item.boundingBox.h / retinaScale
            #expect(abs(item.pointBox.w - expectedPointW) < 0.01)
            #expect(abs(item.pointBox.h - expectedPointH) < 0.01)
        }
    }

    @Test("CASE-0732: High-DPI text contrast verification and WCAG ratio calculation")
    func textContrastVerification() throws {
        Self.warmUpVisionIfNeeded()
        // High contrast dark-on-light
        let highContrastImg = Self.createRenderedTextImage(
            text: "High Contrast",
            bgRGB: (1, 1, 1),
            fgRGB: (0, 0, 0)
        )
        guard let highContrastImg else {
            Issue.record("Failed to generate high contrast image")
            return
        }
        let highResult = VisionOCR.recognize(in: highContrastImg, scale: 2.0, timeoutMs: 2000)
        #expect(highResult.count >= 1)
        if let item = highResult.items.first {
            #expect(item.contrastRatio != nil)
            if let ratio = item.contrastRatio {
                #expect(ratio >= 4.5, "Expected WCAG AA pass for black on white, got \(ratio)")
            }
            #expect(item.contrastPass == true)
            #expect(item.foreground != nil)
            #expect(item.background != nil)
        }

        // Dark theme: white on dark background
        let darkThemeImg = Self.createRenderedTextImage(
            text: "Dark Theme",
            bgRGB: (0.1, 0.1, 0.1),
            fgRGB: (1, 1, 1)
        )
        guard let darkThemeImg else {
            Issue.record("Failed to generate dark theme image")
            return
        }
        let darkResult = VisionOCR.recognize(in: darkThemeImg, scale: 2.0, timeoutMs: 2000)
        #expect(darkResult.count >= 1)
        if let item = darkResult.items.first {
            #expect(item.contrastPass == true)
        }
    }

    @Test("CASE-0733: Bounded execution duration and timeout enforcement")
    func boundedExecutionTimeout() throws {
        Self.warmUpVisionIfNeeded()
        let text = "Fast OCR Execution"
        guard let image = Self.createRenderedTextImage(text: text, width: 300, height: 80) else {
            Issue.record("Failed to generate image")
            return
        }

        // Warm request executes well within 500ms bound
        let result = VisionOCR.recognize(in: image, scale: 2.0, timeoutMs: 500)
        #expect(result.executionMs < 500.0)
        #expect(result.timedOut == false)

        // Strict sub-millisecond timeout triggers timeout flag
        let timedOutResult = VisionOCR.recognize(in: image, scale: 2.0, timeoutMs: 0)
        #expect(timedOutResult.timedOut == true)
    }

    @Test("CASE-0734: Zoom tool dispatch, recognize_text option, and graceful degradation")
    func zoomToolDispatchAndGracefulDegradation() async throws {
        let ax = FakeAX(bundleId: "com.fledgeling.testapp")
        let capture = SuccessFakeCapture()
        let session = Session(
            ax: ax, capture: capture, tri: nil,
            tools: ToolProbes(
                obscura: ToolProbe(probe: { ToolPresence(tool: "obscura", available: true) }),
                simctl: ToolProbe(probe: { ToolPresence(tool: "simctl", available: false) }),
                cuaDriver: ToolProbe(probe: { ToolPresence(tool: "cua-driver", available: false) }),
                maestro: ToolProbe(probe: { ToolPresence(tool: "maestro", available: false) }),
                lume: ToolProbe(probe: { ToolPresence(tool: "lume", available: false) }),
                prlctl: ToolProbe(probe: { ToolPresence(tool: "prlctl", available: false) }),
                environment: [:]
            ),
            secureInputProbe: { false }
        )
        _ = try await session.attachResolved(bundleId: "com.fledgeling.testapp", pid: nil, name: nil)

        // 1. recognizeText: false -> ocr is nil (zero overhead)
        let unaugmented = try await session.zoom(
            window: ax.window.id,
            region: [10, 10, 100, 50],
            node: nil,
            padding: 0,
            path: nil,
            waitForComplete: true,
            timeoutMs: 1000,
            scale: 2.0,
            includeCursor: false,
            recognizeText: false,
            encoding: ImageEncodingOptions(format: .png)
        )
        #expect(unaugmented["ocr"] == nil)

        // 2. recognizeText: true -> ocr field is present
        let augmented = try await session.zoom(
            window: ax.window.id,
            region: [10, 10, 100, 50],
            node: nil,
            padding: 0,
            path: nil,
            waitForComplete: true,
            timeoutMs: 1000,
            scale: 2.0,
            includeCursor: false,
            recognizeText: true,
            encoding: ImageEncodingOptions(format: .png)
        )
        #expect(augmented["ocr"] != nil)
        #expect(augmented["scale"]?.doubleValue == 2.0)
    }

    @Test("Graceful handling of empty or blank images")
    func emptyImageGracefulHandling() throws {
        Self.warmUpVisionIfNeeded()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8,
            bytesPerRow: 100 * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let blankImage = ctx.makeImage() else {
            Issue.record("Failed to create blank image")
            return
        }

        let result = VisionOCR.recognize(in: blankImage, scale: 1.0, timeoutMs: 2000)
        #expect(result.count == 0)
        #expect(result.items.isEmpty)
        #expect(result.text.isEmpty)
        #expect(result.timedOut == false)
    }
}
