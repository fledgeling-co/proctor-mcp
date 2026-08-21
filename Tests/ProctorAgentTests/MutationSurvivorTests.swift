import Foundation
import Testing
import Carbon.HIToolbox
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ProctorAgent

// PRO-0080 — the survivors of the first mutation sample ever taken in
// `ProctorAgent`.
//
// 24 mutants over a pool of 3,189 sites under seed 20260821: 19 survived. A
// survivor is not a bug, it is a behaviour nothing was watching — the mutation
// ran, the product did something different, and 1,818 tests all still passed.
// These five are the ones this headless lane can reach. The other fourteen are
// recorded in REPORT.md with a reason typed `equivalent` or `uncovered-by-lane`,
// which are different claims and are kept apart on purpose.
//
// Each test below is armed: the mutant was re-applied by hand afterwards, the
// named test watched going red, and the mutant reverted. A test written to kill
// a mutant nobody watched fail is the defect this whole item is about.
//
// Where a constant is under test the oracle is deliberately NOT the constant in
// the source. `kVK_ANSI_N` comes from Carbon's own header, the RGBA stride is
// derived from the pixel count rather than read off the loop, and the id length
// is checked against the alphabet it is drawn from. Asserting a value the test
// itself supplied is how DEF-019 shipped.
@Suite("Mutation survivors, ProctorAgent")
struct MutationSurvivorTests {

    // Survivor 21 — `AX/KeyCodes.swift:18`, `"n": 45` became `"n": 46`.
    //
    // Nothing checked the table against anything. With the mutation `n` and `m`
    // both map to 46, so `proctor_act` typing "n" presses M, and the whole suite
    // stayed green. Carbon's `kVK_ANSI_*` are the oracle because they are the
    // platform's own definition of these codes rather than a second copy of the
    // table's.
    @Test("Every letter key maps to the virtual keycode Carbon names for it")
    func letterKeysAgreeWithCarbon() {
        let carbon: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        ]
        for (letter, expected) in carbon.sorted(by: { $0.key < $1.key }) {
            let actual = KeyCodes.table[letter]
            #expect(actual == CGKeyCode(expected),
                    "\(letter) maps to \(actual.map(String.init) ?? "nothing"), Carbon says \(expected)")
        }
        // The count floor exists because a lookup that returned nil for every
        // letter would satisfy nothing above if the loop were ever emptied.
        #expect(carbon.count == 26)

        // Distinctness, which is the property the mutation actually broke: two
        // letters sharing a code means one of them cannot be typed at all.
        let codes = carbon.keys.compactMap { KeyCodes.table[$0] }
        #expect(codes.count == 26)
        #expect(Set(codes).count == 26, "two letters share a virtual keycode")
    }

    // Survivor 2 — `RunIdentity.swift:30`, `prefix(12)` became `prefix(13)`.
    //
    // The run id is written into every record of every tool call and nothing
    // asserted its shape. The length is checked against the contract in the
    // doc comment ("short … it is kept small"), and the alphabet against the
    // source it is drawn from: a hyphen-stripped lowercased UUID is hex.
    @Test("A minted run id is twelve lowercase hex characters, and two differ")
    func mintedRunIdHasTheShapeEveryRecordCarries() {
        let id = RunIdentity.mint()
        #expect(id.count == 12, "minted \(id.count) characters: \(id)")
        #expect(id.allSatisfy { $0.isHexDigit && !$0.isUppercase },
                "\(id) is not lowercase hex")
        // Randomness, so a constant would not pass the two above.
        let minted = Set((0..<64).map { _ in RunIdentity.mint() })
        #expect(minted.count == 64, "64 mints produced \(minted.count) distinct ids")
    }

    // Survivor 18 — `Session/PixelCompare.swift:38`, `stride(… by: 4)` became
    // `by: 5`.
    //
    // `meanDifference` backs the `regionMatches` assertion, so this is the
    // instrument a caller's tolerance is measured in. At stride 5 it reads
    // misaligned channels and visits four fifths of the pixels, and every
    // existing test compared images that were either identical or wildly
    // different — both of which survive a broken stride.
    //
    // The expected mean is derived, not copied: two uniform images differing by
    // `delta` on all three colour channels have a mean absolute channel
    // difference of exactly `delta / 255`, whatever the pixel count.
    @Test("Mean difference reads all four bytes of every RGBA pixel")
    func meanDifferenceWalksThePixelsOnAStrideOfFour() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pro0080-pixelcompare-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.png").path
        let b = dir.appendingPathComponent("b.png").path
        let dark: UInt8 = 10, light: UInt8 = 30
        let delta = Double(light) - Double(dark)
        try Self.writeUniform(width: 4, height: 4, value: dark, to: a)
        try Self.writeUniform(width: 4, height: 4, value: light, to: b)

        let mean = try PixelCompare.meanDifference(a, b, region: nil)
        #expect(abs(mean - delta / 255.0) < 0.0005,
                "mean \(mean), expected \(delta / 255.0) for a uniform \(Int(delta))-per-channel gap")

        // An identical pair must read zero, so the assertion above cannot be
        // satisfied by an instrument that returns a constant.
        #expect(try PixelCompare.meanDifference(a, a, region: nil) == 0.0)
    }

    // Survivor 17 — `Unlock/UnlockBroker.swift:51`, `contactCount += 1` became
    // `+= 2`.
    //
    // `contactCount` is how `proctor_unlock status` proves the login-path
    // mechanism actually reached the broker — os_log from a launchd agent is not
    // reliably visible, so this counter is the evidence. A counter that
    // double-counts reports two handshakes where one happened, and nothing
    // watched it.
    //
    // A fresh `UnlockTurn` rather than `.shared`, so the count starts at a known
    // zero and no other test can move it.
    @Test("Each contact recorded on the unlock turn counts exactly once")
    func recordContactCountsOnePerContact() {
        let turn = UnlockTurn()
        #expect(turn.contactInfo().contactCount == 0)
        for i in 1...3 {
            turn.recordContact(peerVerified: true, reply: "ALLOW")
            #expect(turn.contactInfo().contactCount == i,
                    "after \(i) contacts the broker counted \(turn.contactInfo().contactCount)")
        }
        let info = turn.contactInfo()
        #expect(info.lastReply == "ALLOW")
        #expect(info.lastPeerVerified == true)
        #expect(info.lastContact != nil)
    }

    // Survivor 14 — `Overlay/RunHUDContentView.swift:830`, `ms < 1000` became
    // `ms <= 1000`.
    //
    // The HUD's duration form. At the boundary the mutation prints "1000ms"
    // where the mock's form is "1.0s", and the existing tests only ever passed
    // values well clear of the boundary — the shape of untested boundary that
    // `RunHUDGate.onSegment` is already on record for.
    @MainActor
    @Test("A duration switches from milliseconds to seconds at exactly one second")
    func durationBoundaryIsExclusiveAtOneSecond() {
        #expect(RunHUDContentView.duration(1) == "1ms")
        #expect(RunHUDContentView.duration(999) == "999ms")
        #expect(RunHUDContentView.duration(1000) == "1.0s")
        #expect(RunHUDContentView.duration(1001) == "1.0s")
        #expect(RunHUDContentView.duration(2400) == "2.4s")
    }

    /// A uniform opaque image, written as a real PNG so `meanDifference` goes
    /// through its own ImageIO load path rather than a byte array the test made.
    private static func writeUniform(width: Int, height: Int, value: UInt8,
                                     to path: String) throws {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value
            pixels[i + 3] = 255
        }
        let context = CGContext(data: &pixels, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = context?.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw PixelCompare.Failure(reason: "could not write the fixture image") }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
