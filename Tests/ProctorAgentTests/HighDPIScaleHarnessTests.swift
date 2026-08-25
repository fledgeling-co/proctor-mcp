import CoreGraphics
import CoreText
import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

/// A backing scale, injected and then put back.
///
/// PRO-0131 asks for display density to be a thing a test sets rather than a
/// thing the machine happens to have. This Mac's displays are 2x, so every
/// geometry test written against "the scale" has been written against 2 and a
/// 1x display — an external monitor, a screen-shared session, a CI runner — has
/// never been exercised. A harness that sets a scale and restores it on the way
/// out is the difference between covering that and assuming it.
///
/// The restore is the part that needs a type. A test that sets an environment
/// value and throws leaves it set for every test after it, and Swift Testing
/// runs suites in parallel, so the failure lands somewhere else entirely — which
/// is the worst shape a fixture fault can take.
final class ScaleHarness: @unchecked Sendable {

    static let variable = "PROCTOR_FORCE_BACKING_SCALE"

    private let previous: String?
    private var restored = false

    init(_ scale: Double) {
        previous = ProcessInfo.processInfo.environment[Self.variable]
        setenv(Self.variable, String(scale), 1)
    }

    /// Idempotent, and safe from a `defer` on any path including a throw.
    func restore() {
        guard !restored else { return }
        restored = true
        if let previous { setenv(Self.variable, previous, 1) } else { unsetenv(Self.variable) }
    }

    deinit { restore() }

    static var active: Double? {
        ProcessInfo.processInfo.environment[variable].flatMap(Double.init)
    }
}

@Suite("High-DPI: a scale a test sets, and puts back")
struct HighDPIScaleHarnessTests {

    // ── The harness itself ───────────────────────────────────────────────────

    @Test("a scale is set for the duration and restored afterwards, including on a throw")
    func harnessRestores() {
        let before = ScaleHarness.active
        do {
            let h = ScaleHarness(3.0)
            #expect(ScaleHarness.active == 3.0)
            h.restore()
            #expect(ScaleHarness.active == before,
                    "the harness left a scale set for every test that runs after it")
        }
        // And on the throwing path, which is the one a `defer` exists for.
        func throwing() throws {
            let h = ScaleHarness(1.0)
            defer { h.restore() }
            #expect(ScaleHarness.active == 1.0)
            throw ScaleHarness.Thrown()
        }
        #expect(throws: (any Error).self) { try throwing() }
        #expect(ScaleHarness.active == before, "a throw left the scale set")
    }

    @Test("restoring twice is a no-op, so a defer and an explicit call cannot fight")
    func restoreIsIdempotent() {
        let before = ScaleHarness.active
        let h = ScaleHarness(2.0)
        h.restore()
        h.restore()
        #expect(ScaleHarness.active == before)
    }

    // ── What the scale actually changes ──────────────────────────────────────

    @Test("a region places into a frame at 1x and 2x, and the pixel rect scales with it")
    func regionPlacementFollowsScale() throws {
        // The same window-point region, cut from the same window, at two
        // densities. The failure this catches is a transform that hard-codes 2
        // because every display the author had was Retina.
        let region = Rect(x: 10, y: 20, w: 100, h: 50)

        let one = try RegionCrop.place(regionPoints: region, imageWidth: 400, imageHeight: 300,
                                       scale: 1).get()
        #expect(one.pixelRect == Rect(x: 10, y: 20, w: 100, h: 50))
        #expect(!one.clamped)

        let two = try RegionCrop.place(regionPoints: region, imageWidth: 800, imageHeight: 600,
                                       scale: 2).get()
        #expect(two.pixelRect == Rect(x: 20, y: 40, w: 200, h: 100))
        #expect(!two.clamped)

        // A non-integer scale is the one that exposes rounding. The origin
        // floors and the far edge ceils, so the WHOLE of the requested region is
        // inside the crop rather than shaved — a region read back one pixel
        // short is a caption with its descender cut off.
        let onePointFive = try RegionCrop.place(regionPoints: Rect(x: 10, y: 20, w: 33, h: 17),
                                                imageWidth: 800, imageHeight: 600,
                                                scale: 1.5).get()
        #expect(onePointFive.pixelRect.x == 15)
        #expect(onePointFive.pixelRect.y == 30)
        #expect(onePointFive.pixelRect.w >= 33 * 1.5,
                "the crop is narrower than the region it was asked for")
        #expect(onePointFive.pixelRect.h >= 17 * 1.5)
    }

    @Test("a region past the frame's edge is clamped and says so, at either scale")
    func clampingIsReported() throws {
        for scale in [1.0, 2.0, 3.0] {
            let placed = try RegionCrop.place(
                regionPoints: Rect(x: 350, y: 250, w: 200, h: 200),
                imageWidth: Int(400 * scale), imageHeight: Int(300 * scale),
                scale: scale).get()
            #expect(placed.clamped,
                    "a region running off the frame at scale \(scale) reported a clean crop")
            #expect(placed.pixelRect.x + placed.pixelRect.w <= 400 * scale)
            #expect(placed.pixelRect.y + placed.pixelRect.h <= 300 * scale)
        }
        // Entirely outside is a named failure, not an empty image — a crop of
        // pixels that were never captured has no honest empty result.
        let outside = RegionCrop.place(regionPoints: Rect(x: 900, y: 900, w: 10, h: 10),
                                       imageWidth: 400, imageHeight: 300, scale: 1)
        #expect(outside == .failure(.outsideFrame))
    }

    @Test("point and pixel transforms round-trip at every scale this lane sees")
    func transformsRoundTrip() {
        // The direction matters and a first draft of this test had it backwards.
        // `toNative` takes a coordinate the MODEL returned — in the normalised
        // image it was handed — back to native pixels, so it DIVIDES. Asserting
        // it multiplied is the mistake a caller makes when reading a box off a
        // downscaled capture, and it puts every assertion at scale× the right
        // place on a Retina display.
        for scale in [1.0, 1.5, 2.0, 3.0] {
            for value in [0.0, 1.0, 33.0, 100.5, 1920.0] {
                let native = VisionCapture.toNative(value, scale: scale)
                let back = VisionCapture.toNormalized(native, scale: scale)
                #expect(abs(back - value) < 0.0001,
                        "a point at scale \(scale) did not survive the round trip")
                #expect(abs(native * scale - value) < 0.0001,
                        "toNative did not divide by \(scale)")
            }
            let r = Rect(x: 10, y: 20, w: 30, h: 40)
            let n = VisionCapture.toNative(r, scale: scale)
            #expect(abs(n.w - 30 / scale) < 0.0001)
            #expect(abs(n.h - 40 / scale) < 0.0001)
            #expect(abs(n.x - 10 / scale) < 0.0001, "the origin was not transformed with the size")
        }
    }

    // ── OCR across the two densities, as a relation rather than a threshold ──

    private static func render(_ text: String, scale: Double) -> CGImage? {
        let w = Int(500 * scale), h = Int(140 * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 28 * scale, nil)
        let attr = [kCTFontAttributeName: font,
                    kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1)]
                   as CFDictionary
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, text as CFString, attr)!)
        ctx.textPosition = CGPoint(x: 20 * scale, y: 50 * scale)
        CTLineDraw(line, ctx)
        return ctx.makeImage()
    }

    @Test("the same words read the same at 1x and 2x, and the boxes land in the same place")
    func ocrIsScaleInvariant() throws {
        // Metamorphic rather than a threshold: what matters is not that OCR
        // scores well, it is that DOUBLING the density does not move the answer.
        // A bounding box reported in pixels rather than normalized points would
        // come back twice as far along at 2x, and every assertion built on it
        // would be right on this Mac and wrong on an external display.
        let words = "Proctor High DPI Inspector"
        guard let one = Self.render(words, scale: 1), let two = Self.render(words, scale: 2) else {
            Issue.record("could not render the fixture images")
            return
        }
        _ = VisionOCR.recognize(in: one, scale: 1, timeoutMs: 10_000)   // warm the model

        let a = VisionOCR.recognize(in: one, scale: 1, timeoutMs: 15_000)
        let b = VisionOCR.recognize(in: two, scale: 2, timeoutMs: 15_000)

        #expect(!a.items.isEmpty, "1x read nothing at all")
        #expect(!b.items.isEmpty, "2x read nothing at all")

        let textA = a.items.map(\.text).joined(separator: " ").lowercased()
        let textB = b.items.map(\.text).joined(separator: " ").lowercased()
        #expect(textA.contains("proctor"), "1x did not read the first word: \(textA)")
        #expect(textB.contains("proctor"), "2x did not read the first word: \(textB)")
        #expect(textA.contains("inspector") == textB.contains("inspector"),
                "the two densities disagreed about the last word — 1x \(textA), 2x \(textB)")

        // The clause is about POINTS, and the item carries both. `boundingBox`
        // is crop PIXELS and doubles with the density; `pointBox` is divided by
        // the capture scale and does not. A first draft asserted invariance on
        // boundingBox and read 22 against 376 — which is the field working
        // exactly as documented, and the test reaching for the wrong one. That
        // is the mistake a caller makes, so it is the one worth pinning.
        guard let firstA = a.items.first, let firstB = b.items.first else { return }
        #expect(firstA.boundingBox.w > 0 && firstB.boundingBox.w > 0)
        #expect(firstB.boundingBox.w > firstA.boundingBox.w * 1.5,
                "boundingBox is documented as crop pixels and did not grow with the density: \(firstA.boundingBox.w) then \(firstB.boundingBox.w)")

        let pointDelta = abs(firstA.pointBox.x - firstB.pointBox.x)
        #expect(pointDelta < 12,
                "pointBox moved \(pointDelta)pt when only the density changed, so an assertion written against it is right on one display and wrong on another")
        #expect(abs(firstA.pointBox.w - firstB.pointBox.w) < 24)
    }

    @Test("a blank frame reads as nothing found, not as a failure and not as text")
    func blankFrameIsNotAFailure() {
        let w = 200, h = 80
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let blank = { ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                            return ctx.makeImage() }() else {
            Issue.record("could not render a blank frame")
            return
        }
        let result = VisionOCR.recognize(in: blank, scale: 1, timeoutMs: 8000)
        // Not looking, looking and finding nothing, and failing are three
        // different answers. A blank page is the second.
        #expect(result.items.isEmpty, "OCR read text off a blank white frame")
        #expect(result.executionMs >= 0)
    }
}

extension ScaleHarness {
    struct Thrown: Error {}
}
