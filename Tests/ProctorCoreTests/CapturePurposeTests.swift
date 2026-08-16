import Foundation
import Testing
import ProctorCore

// PRO-0063 — a capture is sized by what it is for.
//
// Proctor used to send every capture at the vision API's ceiling. That is the
// wrong default: the ceiling is what the API tolerates, not what a task needs,
// and a model is billed on pixel dimensions rather than on file size — which is
// also why the answer here is fewer pixels and not a smaller container. Proctor
// returns a path and never bytes, so a lossy encoding would trade text fidelity
// for something that costs nothing.
//
// What is proved here is the arithmetic behind the three tiers, the rule that
// annotating implies the cheapest one, and that none of it can accidentally
// enlarge a frame.
@Suite("PRO-0063 · a capture is sized by what it is for")
struct CapturePurposeTests {

    // MARK: - The tiers, and why these numbers

    @Test("the default tier is verify, not the API ceiling")
    func defaultIsVerify() {
        #expect(VisionCapture.Purpose.default == .verify)
        #expect(VisionCapture.Purpose.verify.maxLongEdge == 1024)
        // The old default, kept reachable rather than deleted.
        #expect(VisionCapture.Purpose.detail.maxLongEdge == VisionCapture.defaultMaxLongEdge)
    }

    @Test("targeting sits exactly on Gemini's tile boundary")
    func targetingIsOnTheTileBoundary() {
        // Gemini charges ceil(w/768) x ceil(h/768) x 258. One pixel over doubles
        // the column, so the tier is 768 rather than a round 800.
        #expect(VisionCapture.Purpose.targeting.maxLongEdge == 768)
        func tiles(_ edge: Int) -> Int { Int((Double(edge) / 768.0).rounded(.up)) }
        #expect(tiles(768) == 1)
        #expect(tiles(769) == 2)
    }

    @Test("each tier is strictly cheaper than the one above it")
    func tiersAreOrdered() {
        let ordered: [VisionCapture.Purpose] = [.targeting, .verify, .detail]
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            #expect(lower.maxLongEdge < higher.maxLongEdge)
            #expect(lower.maxPixels < higher.maxPixels)
        }
    }

    @Test("the saving over the old default is worth the change")
    func theSavingIsReal() {
        // A 16in Retina window, 3456x2018, through each tier. The point of the
        // item is this table: the old default cost about 1,530 tokens for every
        // frame whether or not anything in it needed resolving.
        let w = 3456, h = 2018
        func tokens(_ p: VisionCapture.Purpose) -> Int {
            let fit = VisionCapture.fit(width: w, height: h,
                                        maxLongEdge: p.maxLongEdge, maxPixels: p.maxPixels)
            return VisionCapture.estimatedVisionTokens(width: fit.width, height: fit.height)
        }
        let detail = tokens(.detail)
        let verify = tokens(.verify)
        let targeting = tokens(.targeting)

        #expect(detail > 1_400)
        // The default now costs a little over half the ceiling.
        #expect(Double(verify) < Double(detail) * 0.60)
        // And a targeting frame costs under a third of it.
        #expect(Double(targeting) < Double(detail) * 0.34)
    }

    // MARK: - The estimate

    @Test("the token estimate follows the published approximation")
    func tokenEstimate() {
        #expect(VisionCapture.estimatedVisionTokens(width: 1024, height: 768) == 1049)
        #expect(VisionCapture.estimatedVisionTokens(width: 0, height: 768) == 0)
        #expect(VisionCapture.estimatedVisionTokens(width: -5, height: 10) == 0)
    }

    // MARK: - Normalisation only ever shrinks

    @Test("a frame already smaller than the tier is passed through untouched")
    func aSmallFrameIsNotEnlarged() {
        // The tiers are ceilings, never targets. A 400x300 window must not be
        // scaled *up* to fill a budget.
        let fit = VisionCapture.fit(width: 400, height: 300,
                                    maxLongEdge: VisionCapture.Purpose.targeting.maxLongEdge,
                                    maxPixels: VisionCapture.Purpose.targeting.maxPixels)
        #expect(fit.applied == false)
        #expect(fit.scale == 1)
        #expect(fit.width == 400)
        #expect(fit.height == 300)
    }

    @Test("every tier preserves the aspect ratio it was given")
    func aspectRatioSurvives() {
        for purpose in VisionCapture.Purpose.allCases {
            let fit = VisionCapture.fit(width: 3456, height: 2018,
                                        maxLongEdge: purpose.maxLongEdge,
                                        maxPixels: purpose.maxPixels)
            let before = 3456.0 / 2018.0
            let after = Double(fit.width) / Double(fit.height)
            #expect(abs(before - after) < 0.01, "aspect drifted on \(purpose.rawValue)")
        }
    }

    @Test("a near-square frame is bound by the pixel ceiling, not the long edge")
    func thePixelCeilingStillBinds() {
        // The reason each tier carries both numbers: 1000x1000 is under verify's
        // 1024 long edge on both sides and still over its pixel budget.
        let purpose = VisionCapture.Purpose.verify
        #expect(1000 < purpose.maxLongEdge)
        let fit = VisionCapture.fit(width: 1000, height: 1000,
                                    maxLongEdge: purpose.maxLongEdge,
                                    maxPixels: purpose.maxPixels)
        #expect(fit.applied == true)
        #expect(fit.width * fit.height <= purpose.maxPixels)
    }

    // MARK: - Parsing

    @Test("a purpose is parsed by name, and an unknown one is refused rather than guessed")
    func parsing() {
        #expect(VisionCapture.Purpose.parse("targeting") == .targeting)
        #expect(VisionCapture.Purpose.parse("  Verify ") == .verify)
        #expect(VisionCapture.Purpose.parse("DETAIL") == .detail)
        #expect(VisionCapture.Purpose.parse("small") == nil)
        #expect(VisionCapture.Purpose.parse(nil) == nil)
    }

    // MARK: - The report

    @Test("a normalisation with no tier still decodes, so an older record is not lost")
    func absentPurposeDecodes() throws {
        let json = """
        {"scale":0.4,"applied":true,"originalWidth":3456,"originalHeight":2018,\
        "width":1382,"height":807,"maxLongEdge":1568,"maxPixels":1150000}
        """
        let decoded = try JSONDecoder().decode(CaptureNormalization.self, from: Data(json.utf8))
        #expect(decoded.purpose == nil)
        #expect(decoded.estimatedVisionTokens == nil)
        #expect(decoded.maxLongEdge == 1568)
    }
}
