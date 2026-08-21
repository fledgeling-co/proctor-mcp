import Foundation
import Testing
@testable import ProctorCore

// PRO-0088 — the decision between "a frame arrived" and "a frame has something
// in it". CASE-0120..CASE-0123.
//
// This is the production decision rather than a copy of it: `CaptureEngineImpl`
// calls exactly these two functions, which is what CASE-0126 checks. The gate
// lives in Core with no I/O so it can be driven here, on a machine with no
// display and no ScreenCaptureKit.

@Suite("Frame content gate")
struct FrameContentGateTests {

    private func summary(alpha: Int, colours: Int = 1, sampled: Int = 2_942_720)
    -> FrameContentSummary {
        FrameContentSummary(pixelsSampled: sampled, maxAlpha: alpha,
                            distinctColours: colours, allTransparent: alpha == 0)
    }

    // CASE-0120
    @Test("an empty frame over a Proctor-owned window states the exclusion")
    func excludedTargetNamesTheMechanism() {
        let empty = summary(alpha: 0)
        let verdict = CaptureContentGate.verdict(summary: empty, targetIsProctorOwned: true)
        #expect(verdict == .excludedTarget)

        let caveat = CaptureContentGate.caveat(for: verdict, summary: empty, window: "win:1:0")
        #expect(caveat?.contains("belongs to Proctor") == true)
        #expect(caveat?.contains("nothing was going to be in it") == true)

        // Armed: the same pixels over a window Proctor does not own are a
        // different verdict with a different sentence. If ownership stopped
        // being consulted, both legs would return the same thing and this fails.
        let foreign = CaptureContentGate.verdict(summary: empty, targetIsProctorOwned: false)
        #expect(foreign == .emptyFrame)
        #expect(CaptureContentGate.caveat(for: foreign, summary: empty, window: "win:1:0")
                != caveat)
    }

    // CASE-0121
    @Test("an empty frame over a foreign window reports what was measured")
    func emptyFrameCarriesItsPopulation() {
        let empty = summary(alpha: 0, sampled: 65_536)
        let verdict = CaptureContentGate.verdict(summary: empty, targetIsProctorOwned: false)
        #expect(verdict == .emptyFrame)

        // The count is in the sentence, because "empty" without a denominator is
        // the claim this whole item exists to stop being made.
        let caveat = CaptureContentGate.caveat(for: verdict, summary: empty, window: "win:2:0")
        #expect(caveat?.contains("65536 pixel(s) sampled") == true)

        // Armed: one pixel with any alpha at all moves the verdict, so the check
        // is measuring alpha rather than agreeing with `allTransparent` by
        // construction.
        let oneLitPixel = FrameContentSummary(pixelsSampled: 65_536, maxAlpha: 1,
                                              distinctColours: 2, allTransparent: false)
        #expect(CaptureContentGate.verdict(summary: oneLitPixel,
                                           targetIsProctorOwned: false) == .content)
        #expect(CaptureContentGate.caveat(for: .content, summary: oneLitPixel,
                                          window: "win:2:0") == nil)
    }

    // CASE-0122
    @Test("an opaque single-colour frame is content, not a defect")
    func aBlankWindowIsNotAFault() {
        // The honest edge. A legitimately blank window exists — a fresh
        // document, a loading pane, a solid fill — and downgrading it would be
        // this item's own false positive. `distinctColours` is published so a
        // caller can make that call; no branch in the gate keys off it.
        let flat = FrameContentSummary(pixelsSampled: 65_536, maxAlpha: 255,
                                       distinctColours: 1, allTransparent: false)
        #expect(CaptureContentGate.verdict(summary: flat, targetIsProctorOwned: false) == .content)
        #expect(CaptureContentGate.verdict(summary: flat, targetIsProctorOwned: true) == .content)
        #expect(CaptureContentGate.caveat(for: .content, summary: flat, window: "win:3:0") == nil)

        // Armed against the opposite mistake: the same one colour with no alpha
        // is empty, so this test would not pass a gate that had stopped looking
        // at alpha entirely.
        let flatAndTransparent = FrameContentSummary(pixelsSampled: 65_536, maxAlpha: 0,
                                                     distinctColours: 1, allTransparent: true)
        #expect(CaptureContentGate.verdict(summary: flatAndTransparent,
                                           targetIsProctorOwned: false) == .emptyFrame)
    }

    // CASE-0123
    @Test("not looking and finding nothing are different answers")
    func anUnmeasuredFrameClaimsNothing() {
        #expect(CaptureContentGate.verdict(summary: nil, targetIsProctorOwned: false)
                == .notMeasured)
        #expect(CaptureContentGate.verdict(summary: nil, targetIsProctorOwned: true)
                == .notMeasured)

        // A sample of zero pixels is also not a measurement: an instrument that
        // looked at nothing must not be able to say a frame is empty.
        let nothingLookedAt = FrameContentSummary(pixelsSampled: 0, maxAlpha: 0,
                                                  distinctColours: 0, allTransparent: false)
        #expect(CaptureContentGate.verdict(summary: nothingLookedAt,
                                           targetIsProctorOwned: false) == .notMeasured)

        // Armed: hand it a real sample and the verdict leaves .notMeasured.
        #expect(CaptureContentGate.verdict(summary: summary(alpha: 0),
                                           targetIsProctorOwned: false) != .notMeasured)
    }

    // CASE-0199 — a verdict that makes a frame untrustworthy must say why.
    @Test("an unmeasured frame is untrustworthy with a reason, not untrustworthy in silence")
    func anUnmeasuredFrameCarriesItsReason() {
        // `CaptureEngineImpl` conjoins `contentVerdict == .content` into
        // `trustworthy`, so .notMeasured returns false, and its caveat ladder
        // reaches this function in the final `else`. Returning nil there hands a
        // caller `trustworthy: false` with nothing beside it.
        let nothingLookedAt = FrameContentSummary(pixelsSampled: 0, maxAlpha: 0,
                                                  distinctColours: 0, allTransparent: false)
        let caveat = CaptureContentGate.caveat(for: .notMeasured, summary: nothingLookedAt,
                                               window: "win:4:0")
        #expect(caveat != nil)
        #expect(caveat?.contains("win:4:0") == true)
        #expect(caveat?.contains("not measured") == true)

        // And it does not say the window was empty, which is the claim a
        // measurement that never ran has no standing to make. `.emptyFrame` is
        // the verdict that says that, and it says it in different words.
        #expect(caveat?.contains("no content") == false)
        #expect(caveat?.contains("fully transparent") == false)
        #expect(caveat != CaptureContentGate.caveat(for: .emptyFrame, summary: nothingLookedAt,
                                                    window: "win:4:0"))

        // Armed against the opposite over-correction: `.content` is still the
        // one verdict with nothing to say, so this is not a function that has
        // started returning a sentence for everything.
        #expect(CaptureContentGate.caveat(for: .content, summary: summary(alpha: 255),
                                          window: "win:4:0") == nil)
    }

    // CASE-0123b — ownership is decided by the bundle identifier the window
    // server reports, not by a name match.
    @Test("both of Proctor's bundle identifiers count as Proctor-owned")
    func ownershipIsTheBundleIdentifier() {
        // Two, and the second is the one that matters: every overlay is drawn by
        // the agent, which carries its own embedded Info.plist. Measured
        // 2026-08-21 — `proctor_apps list` reports it as
        // app.fledgeling.procter.agent, not as the UI app's identifier.
        #expect(CaptureContentGate.isProctorOwned(bundleIdentifier: Wire.bundleIdentifier))
        #expect(CaptureContentGate.isProctorOwned(bundleIdentifier: Wire.agentLabel))
        #expect(CaptureContentGate.proctorBundleIdentifiers.count == 2)

        #expect(!CaptureContentGate.isProctorOwned(bundleIdentifier: "com.apple.calculator"))
        #expect(!CaptureContentGate.isProctorOwned(bundleIdentifier: nil))
        // The identifier is `procter`, not `proctor`. A test that spelled it the
        // obvious way would pass an implementation that did too.
        #expect(!CaptureContentGate.isProctorOwned(bundleIdentifier: "app.fledgeling.proctor"))
        // Exact, not a prefix: a neighbouring identifier is not Proctor.
        #expect(!CaptureContentGate.isProctorOwned(bundleIdentifier: "app.fledgeling.procter.guest"))
    }
}
