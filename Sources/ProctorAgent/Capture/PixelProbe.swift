import Foundation
import CoreGraphics
import ImageIO
import ProctorCore

// Pixel sampling for the third observer. The PNG on disk is the only pixel
// evidence the rest of the agent has, so it is read back rather than kept in
// memory: whatever is asserted against is exactly what a person would open.

struct RGB: Hashable, Sendable {
    var r: Double, g: Double, b: Double     // 0..1, sRGB

    var hex: String {
        String(format: "#%02x%02x%02x",
               Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    func distance(to other: RGB) -> Double {
        let dr = r - other.r, dg = g - other.g, db = b - other.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// WCAG 2.x relative luminance.
    var relativeLuminance: Double {
        func lin(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

struct RegionStats: Sendable {
    var mean: RGB
    /// Mean per-channel variance over the region, on a 0..1 channel scale.
    var variance: Double
    var dominant: RGB
    /// The colour furthest from `dominant` in luminance that still holds a
    /// meaningful share of the region — the foreground candidate.
    var contrastingColour: RGB?
    var contrastingShare: Double
    var sampleCount: Int
}

/// A decoded PNG held as tightly packed RGBA8.
struct PixelProbe: Sendable {
    let width: Int
    let height: Int
    private let rgba: [UInt8]

    init?(pngPath: String) {
        let url = URL(fileURLWithPath: pngPath) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(image: image)
    }

    init?(image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.width = w
        self.height = h
        self.rgba = buffer
    }

    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    func pixel(x: Int, y: Int) -> RGB? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return RGB(r: Double(rgba[i]) / 255, g: Double(rgba[i + 1]) / 255, b: Double(rgba[i + 2]) / 255)
    }

    /// Subsampled so a full-window region costs the same as a small one.
    func stats(in rect: CGRect, maxSamples: Int = 4096) -> RegionStats? {
        let clipped = rect.intersection(bounds).integral
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }
        let x0 = Int(clipped.minX), y0 = Int(clipped.minY)
        let x1 = min(width, Int(clipped.maxX)), y1 = min(height, Int(clipped.maxY))
        guard x1 > x0, y1 > y0 else { return nil }

        let cells = (x1 - x0) * (y1 - y0)
        let stride = max(1, Int((Double(cells) / Double(maxSamples)).squareRoot().rounded(.up)))

        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var sumSq = (r: 0.0, g: 0.0, b: 0.0)
        var histogram: [Int: Int] = [:]
        var count = 0

        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let i = (y * width + x) * 4
                let r = Double(rgba[i]) / 255, g = Double(rgba[i + 1]) / 255, b = Double(rgba[i + 2]) / 255
                sum.r += r; sum.g += g; sum.b += b
                sumSq.r += r * r; sumSq.g += g * g; sumSq.b += b * b
                // 5 bits per channel: fine enough to separate real UI colours,
                // coarse enough that antialiasing does not shatter the histogram.
                let key = (Int(rgba[i]) >> 3) << 10 | (Int(rgba[i + 1]) >> 3) << 5 | (Int(rgba[i + 2]) >> 3)
                histogram[key, default: 0] += 1
                count += 1
                x += stride
            }
            y += stride
        }
        guard count > 0 else { return nil }

        let n = Double(count)
        let mean = RGB(r: sum.r / n, g: sum.g / n, b: sum.b / n)
        let varR = max(0, sumSq.r / n - mean.r * mean.r)
        let varG = max(0, sumSq.g / n - mean.g * mean.g)
        let varB = max(0, sumSq.b / n - mean.b * mean.b)

        let ordered = histogram.sorted { $0.value > $1.value }
        let dominant = PixelProbe.unkey(ordered[0].key)
        let domLuma = dominant.relativeLuminance

        var contrasting: RGB?
        var contrastingShare = 0.0
        var bestDelta = 0.0
        for (key, weight) in ordered.prefix(32) {
            let share = Double(weight) / n
            guard share >= 0.01 else { continue }
            let colour = PixelProbe.unkey(key)
            let delta = abs(colour.relativeLuminance - domLuma)
            if delta > bestDelta {
                bestDelta = delta
                contrasting = colour
                contrastingShare = share
            }
        }

        return RegionStats(mean: mean,
                           variance: (varR + varG + varB) / 3,
                           dominant: dominant,
                           contrastingColour: contrasting,
                           contrastingShare: contrastingShare,
                           sampleCount: count)
    }

    private static func unkey(_ key: Int) -> RGB {
        // Recover the centre of the 5-bit bucket rather than its floor.
        let r = ((key >> 10) & 0x1f) << 3 | 0x4
        let g = ((key >> 5) & 0x1f) << 3 | 0x4
        let b = (key & 0x1f) << 3 | 0x4
        return RGB(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
    }
}
