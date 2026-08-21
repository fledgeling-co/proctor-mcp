// Does a captured frame contain anything?
//
// PRO-0078 published a capture whose reply read `status: complete, trustworthy:
// true` over 2,942,720 pixels of RGBA(0,0,0,0). Every gate in the campaign
// accepted it; what caught it was reading the picture. So this reads the picture,
// and it is deliberately a SEPARATE program from whatever produced the frame.
//
// It reports the numbers a blank frame and a drawn one differ on — distinct
// colours, the fraction of fully transparent pixels, and the mean and spread of
// luminance — and makes no judgement. A caller decides what counts as content;
// this only makes the decision possible.
//
//   swiftc -O frame_content.swift -o /tmp/frame_content
//   frame_content <in.png> <out.json>

import CoreGraphics
import Foundation
import ImageIO

let argv = CommandLine.arguments
guard argv.count >= 3 else {
    FileHandle.standardError.write(Data("usage: frame_content <in.png> <out.json>\n".utf8))
    exit(2)
}
let path = argv[1]

func emit(_ object: [String: Any]) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: object,
                                           options: [.prettyPrinted, .sortedKeys])
    try? data.write(to: URL(fileURLWithPath: argv[2]))
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    exit(0)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    emit(["ok": false, "path": path, "reason": "the file could not be decoded as an image"])
}

let width = image.width, height = image.height
let space = CGColorSpace(name: CGColorSpace.sRGB)!
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let context = CGContext(data: &pixels, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: width * 4,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    emit(["ok": false, "path": path, "reason": "no bitmap context"])
}
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

var colours = Set<UInt32>()
var transparent = 0
var luminanceSum = 0.0
var luminanceSquares = 0.0
let total = width * height
for index in stride(from: 0, to: pixels.count, by: 4) {
    let r = pixels[index], g = pixels[index + 1], b = pixels[index + 2], a = pixels[index + 3]
    if a == 0 { transparent += 1 }
    colours.insert(UInt32(r) << 24 | UInt32(g) << 16 | UInt32(b) << 8 | UInt32(a))
    let luminance = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    luminanceSum += luminance
    luminanceSquares += luminance * luminance
}
let mean = luminanceSum / Double(total)
let variance = max(0, luminanceSquares / Double(total) - mean * mean)

emit([
    "ok": true,
    "path": path,
    "width": width, "height": height, "pixels": total,
    "distinctColours": colours.count,
    "fullyTransparentPixels": transparent,
    "fullyTransparentFraction": Double(transparent) / Double(total),
    "luminanceMean": mean,
    "luminanceStdDev": variance.squareRoot(),
    "channel": "CGImageSource in a process that did not take the capture"
])
