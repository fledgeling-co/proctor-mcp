import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Region comparison for the regionMatches assertion. Deliberately small: a
/// mean absolute channel difference over a rectangle, which is what a tolerance
/// in an assertion means. Anything a caller cannot reason about the units of
/// would be a worse instrument than no instrument.
enum PixelCompare {

    struct Failure: Error {
        let reason: String
    }

    /// Mean absolute per-channel difference, 0..1, over the given region of
    /// both images. The region is in image pixels.
    static func meanDifference(_ pathA: String, _ pathB: String, region: CGRect?) throws -> Double {
        let a = try load(pathA)
        let b = try load(pathB)

        let cropA = try crop(a, to: region, label: pathA)
        let cropB = try crop(b, to: region, label: pathB)

        guard cropA.width == cropB.width, cropA.height == cropB.height else {
            throw Failure(reason: "the compared regions differ in size — \(cropA.width)x\(cropA.height) "
                                + "against \(cropB.width)x\(cropB.height); a scaled reference cannot be "
                                + "compared pixelwise")
        }

        let bytesA = try rgba(cropA)
        let bytesB = try rgba(cropB)
        guard bytesA.count == bytesB.count, !bytesA.isEmpty else {
            throw Failure(reason: "the region is empty")
        }

        var total = 0.0
        for i in stride(from: 0, to: bytesA.count, by: 4) {
            total += Double(abs(Int(bytesA[i]) - Int(bytesB[i])))
            total += Double(abs(Int(bytesA[i + 1]) - Int(bytesB[i + 1])))
            total += Double(abs(Int(bytesA[i + 2]) - Int(bytesB[i + 2])))
        }
        let samples = Double(bytesA.count / 4) * 3.0
        return total / (samples * 255.0)
    }

    /// Fraction of pixels that differ by more than `channelTolerance` on any
    /// channel, 0..1, over the given region of both images.
    ///
    /// A companion to `meanDifference` rather than a replacement, because they
    /// answer different questions. A mean is the right instrument for "how close
    /// is this to the reference", which is what an assertion tolerance means. It
    /// is the wrong one for "did anything happen": a small element moving on a
    /// large screen barely shifts a mean, while the count of pixels that changed
    /// at all separates it cleanly. Measured on an iOS simulator: an idle device
    /// scored 0.00000 here and a modest navigation 0.00204, against means of
    /// 0.000000 and 0.000838.
    static func changedFraction(_ pathA: String, _ pathB: String, region: CGRect?,
                                channelTolerance: Int) throws -> Double {
        let a = try load(pathA)
        let b = try load(pathB)
        let cropA = try crop(a, to: region, label: pathA)
        let cropB = try crop(b, to: region, label: pathB)

        guard cropA.width == cropB.width, cropA.height == cropB.height else {
            throw Failure(reason: "the compared regions differ in size — \(cropA.width)x\(cropA.height) "
                                + "against \(cropB.width)x\(cropB.height); a device that rotated or "
                                + "changed scale between the two frames cannot be compared pixelwise")
        }

        let bytesA = try rgba(cropA)
        let bytesB = try rgba(cropB)
        guard bytesA.count == bytesB.count, !bytesA.isEmpty else {
            throw Failure(reason: "the region is empty")
        }

        var changed = 0
        for i in stride(from: 0, to: bytesA.count, by: 4) {
            if abs(Int(bytesA[i]) - Int(bytesB[i])) > channelTolerance
                || abs(Int(bytesA[i + 1]) - Int(bytesB[i + 1])) > channelTolerance
                || abs(Int(bytesA[i + 2]) - Int(bytesB[i + 2])) > channelTolerance {
                changed += 1
            }
        }
        return Double(changed) / Double(bytesA.count / 4)
    }

    private static func load(_ path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw Failure(reason: "no image at \(path)")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(reason: "\(path) could not be decoded as an image")
        }
        return image
    }

    private static func crop(_ image: CGImage, to region: CGRect?, label: String) throws -> CGImage {
        guard let region else { return image }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = region.integral.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else {
            throw Failure(reason: "the region \(region) lies outside \(label), which is "
                                + "\(image.width)x\(image.height)")
        }
        guard let cropped = image.cropping(to: clamped) else {
            throw Failure(reason: "the region \(region) could not be cropped from \(label)")
        }
        return cropped
    }

    /// Both images are redrawn into the same 8-bit premultiplied RGBA layout,
    /// so a difference in the source colour space or bit depth does not read as
    /// a difference in the pixels.
    private static func rgba(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress,
                                      width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: info) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw Failure(reason: "could not rasterise the image for comparison") }
        return buffer
    }
}
