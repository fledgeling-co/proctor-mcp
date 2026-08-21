import CoreVideo
import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0088 — the instrument that reads a frame's bytes, and the two production
// call sites that spend what it reports. CASE-0124..CASE-0127.
//
// What is NOT testable here, stated so nobody reads the pass as stronger than it
// is: `swift test` has no window server, so no panel is created and no capture
// is taken. The end-to-end verdict over a real ScreenCaptureKit frame is a glass
// -lane measurement — CASE-0128 and CASE-0129 — and the two source checks below
// are what tie this suite to the code those measurements run.

@Suite("Capture content instrument")
struct CaptureContentInstrumentTests {

    /// A tightly packed BGRA frame, the layout `FrameSink.copyPixels` produces.
    private func frame(width: Int, height: Int,
                       fill: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> FramePixels {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let (b, g, r, a) = fill(x, y)
                bytes[i] = b; bytes[i + 1] = g; bytes[i + 2] = r; bytes[i + 3] = a
            }
        }
        return FramePixels(data: Data(bytes), width: width, height: height,
                           bytesPerRow: width * 4)
    }

    // CASE-0124
    @Test("a fully transparent frame measures as fully transparent, and the instrument could say otherwise")
    func transparentFrameIsMeasuredNotAssumed() {
        let empty = frame(width: 320, height: 200) { _, _ in (0, 0, 0, 0) }
        let summary = empty.contentSummary()

        #expect(summary.pixelsSampled > 0)          // it actually looked
        #expect(summary.maxAlpha == 0)
        #expect(summary.allTransparent)
        #expect(summary.distinctColours == 1)

        // Before believing the zero, confirm the instrument could have reported
        // non-zero over the same buffer. One pixel, one channel.
        let almostEmpty = frame(width: 320, height: 200) { x, y in
            (x == 0 && y == 0) ? (0, 0, 0, 7) : (0, 0, 0, 0)
        }
        let lit = almostEmpty.contentSummary()
        #expect(lit.maxAlpha == 7)
        #expect(!lit.allTransparent)
    }

    // CASE-0125
    @Test("a frame with real content measures as content")
    func contentFrameIsNotEmpty() {
        let real = frame(width: 320, height: 200) { x, y in
            (UInt8(x % 256), UInt8(y % 256), 128, 255)
        }
        let summary = real.contentSummary()
        #expect(!summary.allTransparent)
        #expect(summary.maxAlpha == 255)
        #expect(summary.distinctColours > 1)

        // Armed the other way: zero the same geometry and both invert, so the
        // measurement is of the bytes rather than of the frame's size.
        let zeroed = frame(width: 320, height: 200) { _, _ in (0, 0, 0, 0) }
        let inverted = zeroed.contentSummary()
        #expect(inverted.allTransparent)
        #expect(inverted.distinctColours == 1)
    }

    @Test("a frame the instrument cannot read is not measured, rather than empty")
    func anUnreadableFrameClaimsNothing() {
        // A truncated buffer must not be reported as a transparent frame: that
        // would turn a plumbing fault into a claim about the target.
        let truncated = FramePixels(data: Data(repeating: 0, count: 16),
                                    width: 320, height: 200, bytesPerRow: 320 * 4)
        let summary = truncated.contentSummary()
        #expect(summary.pixelsSampled == 0)
        #expect(!summary.allTransparent)
        #expect(CaptureContentGate.verdict(summary: summary, targetIsProctorOwned: true)
                == .notMeasured)
    }

    // CASE-0124b — the finding the out-of-family spec review raised, kept as a
    // test rather than as a note. Strided alpha sampling on a 3-megapixel frame
    // steps 7-8 pixels, so a one-pixel hairline falls between every sample and a
    // window with something in it reports empty. Alpha is exhaustive now, and
    // this is what would catch a stride creeping back in.
    @Test("one lit pixel in three megapixels is not an empty frame")
    func aHairlineIsNotEmptiness() {
        let big = frame(width: 1520, height: 1936) { x, y in
            // A single one-pixel-wide vertical line, at an offset no square
            // stride over this frame would land on.
            x == 733 && y == 1019 ? (0, 0, 0, 255) : (0, 0, 0, 0)
        }
        let summary = big.contentSummary(maxColourSamples: 4_096)
        #expect(summary.maxAlpha == 255)
        #expect(!summary.allTransparent)
        #expect(CaptureContentGate.verdict(summary: summary, targetIsProctorOwned: false)
                == .content)

        // The population reported is every pixel, because the alpha claim is
        // about every pixel.
        #expect(summary.pixelsSampled == 1520 * 1936)

        // Armed: the same frame with that one pixel cleared is empty.
        let cleared = frame(width: 1520, height: 1936) { _, _ in (0, 0, 0, 0) }
        #expect(cleared.contentSummary(maxColourSamples: 4_096).allTransparent)
    }

    // The Medium finding from the same review: a buffer that did not arrive as
    // 32BGRA is declined rather than read as if it had.
    @Test("a frame in a layout this cannot read claims nothing")
    func anUnexpectedPixelFormatIsNotMeasured() {
        var wideGamut = frame(width: 64, height: 64) { _, _ in (0, 0, 0, 0) }
        wideGamut.pixelFormat = kCVPixelFormatType_64RGBAHalf
        let summary = wideGamut.contentSummary()
        #expect(summary.pixelsSampled == 0)
        #expect(!summary.allTransparent)
        #expect(CaptureContentGate.verdict(summary: summary, targetIsProctorOwned: true)
                == .notMeasured)

        // Armed: the identical bytes in the format the stream actually asks for
        // are measured, so the guard is on the format and not on the content.
        #expect(frame(width: 64, height: 64) { _, _ in (0, 0, 0, 0) }
            .contentSummary().allTransparent)
    }

    // MARK: - The two production call sites
    //
    // Source analysis. It establishes that the code above is the code that runs,
    // and nothing more: it buys no evidence that a real capture behaves this way.

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ProctorAgentTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    // CASE-0126
    @Test("the capture verdict conjoins the content gate")
    func trustworthyIsGatedOnContent() throws {
        let text = try source("Sources/ProctorAgent/Capture/CaptureEngineImpl.swift")

        #expect(text.contains("let contentSummary = pixels.contentSummary()"))
        #expect(text.contains("CaptureContentGate.isProctorOwned("))
        #expect(text.contains("scWindow.owningApplication?.bundleIdentifier"))
        #expect(text.contains("CaptureContentGate.verdict(summary: contentSummary,"))

        // The term itself. Removing it is the sabotage this asserts against.
        #expect(text.contains("&& contentVerdict == .content"),
                "trustworthy must be conjoined with the content verdict")

        // And the caveat is drawn from the gate rather than written twice.
        #expect(text.contains("CaptureContentGate.caveat(for: contentVerdict,"))
    }

    /// The body of `place(_:at:)`, as a line range, so a check can exclude the
    /// helper's own assignment without excluding anything that merely looks like
    /// it. Returns `nil` when the helper is not there at all, which is itself a
    /// failure the caller reports rather than swallows.
    private func placeHelperBody(in lines: [String]) -> Range<Int>? {
        let signature = "private static func place(_ panel: NSPanel, at level: NSWindow.Level)"
        guard let start = lines.firstIndex(where: { $0.contains(signature) }) else { return nil }
        // Closes at the first line that is the type's own one-level indent, which
        // is where a nested `private static func` body ends.
        guard let end = ((start + 1)..<lines.count).first(where: { lines[$0] == "    }" })
        else { return nil }
        return (start + 1)..<end
    }

    // CASE-0127
    @Test("the drawn pointer assigns sharingType everywhere it assigns level")
    func thePointerKeepsItsExclusionAcrossBands() throws {
        let text = try source("Sources/ProctorAgent/Overlay/CursorOverlay.swift")
        let lines = text.components(separatedBy: .newlines)

        // Every band change goes through one helper, and that helper sets both.
        let body = placeHelperBody(in: lines)
        #expect(body != nil, "place(_:at:) must exist for anything below to mean anything")
        guard let body else { return }

        // Count the direct level assignments left outside the helper's BODY,
        // located by line range rather than by what a line says.
        //
        // The predicate this replaces excluded every line beginning
        // `panel.level = `, meaning to skip the helper's own `panel.level =
        // level`. A direct assignment inside a band-change function is written
        // `panel.level = .floating` and begins the same way, so the check
        // excluded precisely the regression it exists to catch and could not go
        // red. Armed by putting that line back: see
        // docs/test-campaign/evidence/PRO-0088/case-0127-arming.txt.
        let direct = lines.enumerated().filter { index, line in
            guard !body.contains(index) else { return false }
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("//") else { return false }
            return t.contains(".level = ")
        }
        let reported = direct.map { "line \($0.offset + 1): \($0.element.trimmingCharacters(in: .whitespaces))" }
        #expect(direct.isEmpty,
                "every level assignment must go through place(_:at:); found \(reported)")

        // The instrument's control: inside the range it excluded, it does find
        // the one assignment that is supposed to be there. A range that had
        // drifted off the helper would pass the check above while measuring
        // nothing.
        let insideHelper = body.filter {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("panel.level = ")
        }
        #expect(insideHelper.count == 1)
    }

    /// Every line in a file that assigns `sharingType`, trimmed.
    private func sharingAssignments(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && $0.contains("sharingType = ") }
    }

    // All three overlays, and the property they now share.
    //
    // Rewritten against what shipped rather than against this branch's version.
    // These three expectations were `contains("sharingType = .none")`, written
    // when the exclusion was an unconditional literal. On `main` it is decided by
    // `OverlayCapture.excludedFromCapture()`, a capability switch that is off
    // unless somebody sets `PROCTOR_OVERLAY_CAPTURE`, so a campaign can
    // photograph the overlays deliberately. A literal `.none` no longer appears
    // in any of the three files and all three expectations went red on the merge.
    //
    // What is asserted instead is the property the literal used to carry: every
    // `sharingType` assignment in every overlay is decided by that switch, none
    // is hardcoded, and the switch's own default is exclusion. The last leg is a
    // behavioural call rather than a source read, so "excluded by default"
    // is measured rather than inferred from the text of an expression.
    @Test("every overlay takes its capture exclusion from the switch, which is off by default")
    func allThreeOverlaysAreExcludedByDefault() throws {
        let files = [
            "Sources/ProctorAgent/Overlay/CursorOverlay.swift",
            "Sources/ProctorAgent/Overlay/RunHUDPanel.swift",
            "Sources/ProctorAgent/Overlay/TakeoverOverlay.swift",
        ]
        var total = 0
        for file in files {
            let assignments = sharingAssignments(in: try source(file))
            // A file with no assignment at all would pass an `allSatisfy` over an
            // empty list, so the population is required before it is judged.
            #expect(assignments.count == 1, "\(file) assigns sharingType \(assignments.count) times")
            #expect(assignments.allSatisfy { $0.contains("excludedFromCapture") },
                    "\(file): \(assignments)")
            #expect(assignments.allSatisfy { $0.contains("? .none : .readOnly") },
                    "\(file): \(assignments)")
            total += assignments.count
        }
        #expect(total == 3)

        // And the switch is off unless asked, so the shipped default over all
        // three is the exclusion the literal used to state outright.
        #expect(OverlayCapture.excludedFromCapture(in: [:]))
        // Armed: it is a real switch and not a constant returning true.
        #expect(!OverlayCapture.excludedFromCapture(in: [OverlayCapture.variable: "1"]))
    }
}
