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

    // CASE-0127
    @Test("the drawn pointer assigns sharingType everywhere it assigns level")
    func thePointerKeepsItsExclusionAcrossBands() throws {
        let text = try source("Sources/ProctorAgent/Overlay/CursorOverlay.swift")

        // Every band change goes through one helper, and that helper sets both.
        #expect(text.contains("private static func place(_ panel: NSPanel, at level: NSWindow.Level)"))
        #expect(text.contains("panel.sharingType = .none"))

        // Count the direct level assignments left outside it. Written as a count
        // rather than a `contains`, because "no direct assignment" is a claim
        // about a population and a printed line is not a population.
        let direct = text.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return false }
            return t.contains(".level = ") && !t.hasPrefix("panel.level = ")
        }
        #expect(direct.isEmpty,
                "every level assignment must go through place(_:at:); found \(direct)")

        // The instrument's control: it does find the one assignment that is
        // supposed to be there, inside the helper. A filter that matched nothing
        // at all would pass the check above while measuring nothing.
        let insideHelper = text.components(separatedBy: .newlines).filter {
            $0.trimmingCharacters(in: .whitespaces) == "panel.level = level"
        }
        #expect(insideHelper.count == 1)
    }

    // The two siblings are unchanged and stay that way: the exclusion on the run
    // HUD and the takeover statement is correct, and this item does not weaken it.
    @Test("the run HUD and the takeover statement still exclude themselves")
    func theSiblingExclusionsAreIntact() throws {
        #expect(try source("Sources/ProctorAgent/Overlay/RunHUDPanel.swift")
            .contains("sharingType = .none"))
        #expect(try source("Sources/ProctorAgent/Overlay/TakeoverOverlay.swift")
            .contains("panel.sharingType = .none"))
    }
}
