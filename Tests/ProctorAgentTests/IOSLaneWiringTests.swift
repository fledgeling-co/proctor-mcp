import Foundation
import Testing
import ProctorCore
import CoreGraphics
import ImageIO
@testable import ProctorAgent

// PRO-0048 — the wiring half of the iOS Simulator lane.
//
// The verdict ladder, the failure decoding, the scheme resolution and the gate
// are pure and tested in ProctorCoreTests. What is tested here is what reaches
// the agent: that a device handle is refused by every window-taking path rather
// than reported as a missing window, that the pixel instrument the verdict rests
// on measures what it claims, that a device frame never inherits a window
// capture's credibility, and that the promise never to shut a simulator down is
// enforced by something other than an intention.
//
// Not testable here: anything that needs a booted simulator. Those paths were
// verified by hand against a real device and reported rather than committed as a
// gate, because a fleet runner on a machine with no Xcode must not go red for
// the absence of Xcode.

@Suite("iOS lane wiring")
struct IOSLaneWiringTests {

    // MARK: - AC2 · the refusal reaches every window-taking tool

    @Test("a device handle is refused by name wherever a window handle is expected")
    func deviceHandleIsRefusedAtTheWindowSeam() async throws {
        let session = Session(ax: FakeAX(bundleId: "com.example.fake"), capture: FakeCapture())

        do {
            _ = try await session.snapshot(window: "dev-29fea02e",
                                           options: Session.SnapshotOptions(),
                                           sinceRevision: Int?.none)
            Issue.record("a device handle must not resolve as a window")
        } catch let error as AgentError {
            // Not "no window with handle dev-…": a caller holding a device handle
            // has a category error, and telling it the window was not found sends
            // it round a retry loop looking for one that will never exist.
            #expect(error.message.contains("iOS device handle"))
            #expect(!error.message.contains("no window with handle"))
            let remedy = try #require(error.remedy)
            #expect(remedy.contains("accessibility API does not cross"))
            #expect(remedy.contains("proctor_ios"))
        }
    }

    @Test("an ordinary unknown window still reports as an unknown window")
    func ordinaryHandlesAreUnaffected() async throws {
        let session = Session(ax: FakeAX(bundleId: "com.example.fake"), capture: FakeCapture())
        do {
            _ = try await session.snapshot(window: "w-nope",
                                           options: Session.SnapshotOptions(),
                                           sinceRevision: Int?.none)
            Issue.record("an unknown window must still fail")
        } catch let error as AgentError {
            #expect(error.code == .windowNotFound)
            #expect(!error.message.contains("iOS device handle"))
        }
    }

    // MARK: - AC10 · a device frame declares that its freshness is unknown

    @Test("the device-frame caveat names the missing frame status")
    func deviceFramesAreNeverTrustworthy() {
        let caveat = Session.deviceFrameCaveat
        #expect(caveat.contains("simctl"))
        // The same standard this wave applies to Cua's screenshots has to apply to
        // Proctor's own device frames, or it is a standard about the vendor rather
        // than about the evidence.
        #expect(caveat.contains("SCFrameStatus"))
        #expect(caveat.lowercased().contains("cannot be established"))

        // The listing says the same thing, because a model that reads a device
        // handle and reaches for a snapshot has stopped reading descriptions.
        let capabilities = Session.iosCapabilities
        let unavailable = capabilities["unavailable"]?.arrayValue?
            .compactMap(\.stringValue).joined(separator: " ") ?? ""
        #expect(unavailable.contains("accessibility tree"))
        #expect(unavailable.contains("frontmost"))
        let note = capabilities["note"]?.stringValue ?? ""
        #expect(note.contains("ScreenCaptureKit frame status"))

        // The tension an out-of-family review found and this states rather than
        // ships silently: the channel that mints an attributive verdict is built
        // from the same frames reported as untrustworthy, so every verdict
        // resting on it carries that limit with it.
        #expect(IOSPixel.channelCaveat.contains("SCFrameStatus"))
        #expect(IOSPixel.channelCaveat.contains("inherits that limit"))
    }

    // MARK: - AC9 · Proctor never shuts a simulator down

    @Test("no code path in the iOS lane constructs a shutdown or erase argument")
    func theLaneCannotShutADeviceDown() throws {
        // A promise in a comment is worth what enforces it. Every simctl argument
        // in this lane is a literal in one of these two files, so a destructive
        // subcommand appearing later is caught here rather than by a person who
        // lost a simulator they were using.
        //
        // The limit of this check, stated so nobody reads it as stronger than it
        // is: it catches a literal, not a computed string. Somebody who built the
        // argument at runtime would pass it. It is a tripwire on the obvious
        // regression, not a proof of the property.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ProctorAgentTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/ProctorAgent/Session")

        for file in ["SessionIOS.swift", "SessionIOSProcess.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(file),
                                    encoding: .utf8)
            for destructive in ["\"shutdown\"", "\"erase\"", "\"delete\"", "\"uninstall\""] {
                #expect(!source.contains(destructive),
                        "\(file) must not construct a \(destructive) argument")
            }
        }
    }

    // MARK: - The pixel instrument the verdict rests on

    @Test("the changed-pixel fraction separates an unchanged frame from a changed one")
    func changedFractionMeasuresWhatItClaims() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("proctor-ios-pixels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("a.png").path
        let same = directory.appendingPathComponent("b.png").path
        let quarter = directory.appendingPathComponent("c.png").path
        try Self.writeImage(width: 100, height: 100, changedRows: 0, to: plain)
        try Self.writeImage(width: 100, height: 100, changedRows: 0, to: same)
        try Self.writeImage(width: 100, height: 100, changedRows: 25, to: quarter)

        // Identical frames measure exactly zero, which is what makes "anything at
        // all" a usable signal rather than a threshold tuned against noise.
        let unchanged = try PixelCompare.changedFraction(
            plain, same, region: nil, channelTolerance: IOSPixel.channelTolerance)
        #expect(unchanged == 0)
        #expect(unchanged < IOSPixel.changeThreshold)

        // A quarter of the rows differing measures a quarter.
        let changed = try PixelCompare.changedFraction(
            plain, quarter, region: nil, channelTolerance: IOSPixel.channelTolerance)
        #expect(abs(changed - 0.25) < 0.01)
        #expect(changed > IOSPixel.changeThreshold)

        // The region argument is what excludes the status bar, so it has to
        // actually scope the measurement: the changed rows are at the top, and
        // cropping them out returns the frame to quiet.
        let belowTheChange = CGRect(x: 0, y: 30, width: 100, height: 70)
        let scoped = try PixelCompare.changedFraction(
            plain, quarter, region: belowTheChange,
            channelTolerance: IOSPixel.channelTolerance)
        #expect(scoped == 0)
    }

    @Test("the status-bar band is excluded from a device comparison")
    func comparisonRegionExcludesTheStatusBar() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("proctor-ios-region-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // An iPhone 16 Pro frame, as measured.
        let path = directory.appendingPathComponent("frame.png").path
        try Self.writeImage(width: 1206, height: 2622, changedRows: 0, to: path)

        let region = try #require(Session.comparisonRegion(forFramePath: path))
        // The clock lives in the excluded band. A digit changing at a minute
        // boundary is a change nobody caused, and it is the same order of
        // magnitude as the smallest real navigation — exactly the wrong noise to
        // leave in.
        #expect(region.minY > 0)
        #expect(region.width == 1206)
        #expect(region.maxY == 2622)
        #expect(region.minY < 2622 * 0.1)
    }

    /// A solid image whose first `changedRows` rows are a different colour.
    private static func writeImage(width: Int, height: Int, changedRows: Int,
                                   to path: String) throws {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let value: UInt8 = y < changedRows ? 250 : 10
                pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value
                pixels[i + 3] = 255
            }
        }
        let context = CGContext(data: &pixels, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = context?.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        else { throw PixelCompare.Failure(reason: "could not write the fixture image") }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
