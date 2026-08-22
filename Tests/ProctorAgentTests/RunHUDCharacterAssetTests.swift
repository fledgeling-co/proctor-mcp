import Foundation
import CoreGraphics
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0017 — the pictures themselves, as they will actually be loaded.
//
// The frame table is checked in Core. What is checked here is the half a table
// cannot state: that every picture the table names is really in the bundle at
// every density, that the charcoal the sheet was drawn on was actually cut
// rather than baked in, and that the character holds one footprint across all
// seven states. That last one is the whole reason this item exists — the mock's
// slices were hand-estimated and the character drifted between them — and it is
// measurable from the bytes, so it is measured rather than eyeballed.
//
// What is NOT testable here: the sprite drawn in the bay, the loop playing, the
// rail glowing, and light against dark. `swift test` has no window server.

@MainActor
private func pixels(_ image: CGImage) throws -> (w: Int, h: Int, rgba: [UInt8]) {
    let w = image.width, h = image.height
    var buffer = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    // PRO-0098, DEF-136. `w` and `h` come off a real CGImage decoded from the
    // bundled asset. A zero-dimension image — the shape a missing or truncated
    // asset produces — makes this initializer return nil, which is precisely the
    // regression these tests exist to catch.
    let context = try #require(CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                         bytesPerRow: w * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                               "no CGContext for a \(w)x\(h) image")
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, buffer)
}

/// The opaque bounding box, in image rows and columns from the top-left.
@MainActor
private func inkBox(_ image: CGImage) throws -> (top: Int, bottom: Int, left: Int, right: Int)? {
    let (w, h, rgba) = try pixels(image)
    var top = h, bottom = -1, left = w, right = -1
    for y in 0..<h {
        for x in 0..<w where rgba[(y * w + x) * 4 + 3] > 8 {
            top = min(top, y); bottom = max(bottom, y)
            left = min(left, x); right = max(right, x)
        }
    }
    return bottom < 0 ? nil : (top, bottom, left, right)
}

@Suite("Run HUD character assets")
@MainActor
struct RunHUDCharacterAssetTests {

    @Test("every picture the table names is in the bundle at every density")
    func allDensitiesPresent() throws {
        for density in RunHUDCharacter.densities {
            let set = try #require(RunHUDSprites.images(scale: density),
                                   "no sprite set at @\(density)x")
            #expect(Set(set.keys) == Set(RunHUDCharacter.assets))
        }
    }

    @Test("every picture is the bay's size at its density, so nothing is rescaled to fit")
    func sizes() throws {
        for density in RunHUDCharacter.densities {
            let set = try #require(RunHUDSprites.images(scale: density))
            let side = RunHUDCharacter.bay * density
            for (name, image) in set {
                #expect(image.width == side && image.height == side,
                        "\(name)@\(density)x is \(image.width)x\(image.height), wanted \(side)")
            }
        }
    }

    @Test("the charcoal was cut, not baked in — real alpha, and no ground left behind")
    func realAlpha() throws {
        let set = try #require(RunHUDSprites.images(scale: 1))
        for (name, image) in set {
            let (w, h, rgba) = try pixels(image)
            var transparent = 0
            for index in stride(from: 0, to: w * h * 4, by: 4) {
                let alpha = rgba[index + 3]
                if alpha == 0 { transparent += 1; continue }
                guard alpha > 200 else { continue }
                let r = Int(rgba[index]), g = Int(rgba[index + 1]), b = Int(rgba[index + 2])
                // The sheet's ground. Anything this dark and this neutral left
                // opaque means the cut missed, and the character would be seated
                // on a charcoal card inside the bay rather than in it.
                let charcoal = r < 40 && g < 40 && b < 40
                    && abs(r - g) < 6 && abs(g - b) < 6 && !(r < 24 && g < 24 && b < 24)
                #expect(!charcoal, "\(name) keeps ground at rgb(\(r),\(g),\(b))")
            }
            #expect(transparent > w * h / 4,
                    "\(name) is \(transparent) transparent pixels — the cut did nothing")
        }
    }

    @Test("one footprint across all seven states, so the character never jumps")
    func evenFootprints() throws {
        let set = try #require(RunHUDSprites.images(scale: 1))
        var baselines: [String: Int] = [:]
        var tops: [String: Int] = [:]
        for phase in RunHUDPhase.allCases {
            let asset = RunHUDCharacter.frames(for: phase)[0].asset
            let image = try #require(set[asset], "\(asset) is not in the bundle")
            let box = try #require(try inkBox(image), "\(asset) is blank")
            baselines[asset] = box.bottom
            tops[asset] = box.top
        }
        // The feet land in the same place in every state. This is the anchor the
        // build script normalises on, and the one a person would notice.
        #expect(Set(baselines.values).count == 1,
                "feet drift between states: \(baselines.sorted { $0.key < $1.key })")
        // The top may vary a little: a leaning or tilted case genuinely measures
        // taller than an upright one, and sparkles and smoke are allowed to run
        // off the top of the well. A whole state's worth of drift is not.
        let spread = (tops.values.max() ?? 0) - (tops.values.min() ?? 0)
        #expect(spread <= 6, "case tops spread \(spread)px: \(tops.sorted { $0.key < $1.key })")
    }

    @Test("a loop's frames sit on the same footprint as each other, bar idle's one-pixel bob")
    func loopFramesAreSteady() throws {
        let set = try #require(RunHUDSprites.images(scale: 1))
        for phase in RunHUDCharacter.moving {
            let boxes = try RunHUDCharacter.frames(for: phase).map { frame -> (top: Int, bottom: Int, left: Int, right: Int) in
                let image = try #require(set[frame.asset], "\(frame.asset) is not in the bundle")
                return try #require(try inkBox(image), "\(frame.asset) is blank")
            }
            let bottoms = Set(boxes.map(\.bottom))
            let lift = phase == .idle ? 1 : 0
            #expect((bottoms.max() ?? 0) - (bottoms.min() ?? 0) <= lift,
                    "\(phase)'s frames drift vertically: \(bottoms.sorted())")
        }
    }

    @Test("idle's second frame is the first lifted exactly one pixel — the record's bob")
    func idleBob() throws {
        let set = try #require(RunHUDSprites.images(scale: 1))
        let downImage = try #require(set["idle-0"])
        let upImage = try #require(set["idle-1"])
        let down = try #require(try inkBox(downImage))
        let up = try #require(try inkBox(upImage))
        #expect(down.bottom - up.bottom == 1)
        #expect(down.left == up.left && down.right == up.right)
    }

    @Test("the densities are the same art, not three different drawings")
    func densitiesAgree() throws {
        let one = try #require(RunHUDSprites.images(scale: 1))
        for density in [2, 3] {
            let scaled = try #require(RunHUDSprites.images(scale: density))
            for asset in RunHUDCharacter.assets {
                let base = try #require(one[asset])
                let dense = try #require(scaled[asset])
                let a = try #require(try inkBox(base))
                let b = try #require(try inkBox(dense))
                #expect(b.bottom / density == a.bottom && b.left / density == a.left,
                        "\(asset)@\(density)x does not line up with @1x")
            }
        }
    }

    @Test("grey belongs to paused alone, so paused is readable without colour")
    func greyIsReservedForPaused() throws {
        let set = try #require(RunHUDSprites.images(scale: 1))
        for (name, image) in set {
            let (w, h, rgba) = try pixels(image)
            var grey = 0
            for index in stride(from: 0, to: w * h * 4, by: 4) where rgba[index + 3] > 200 {
                let r = Int(rgba[index]), g = Int(rgba[index + 1]), b = Int(rgba[index + 2])
                // Neutral, and neither the white body nor the black outline.
                if abs(r - g) < 12 && abs(g - b) < 12 && r > 90 && r < 200 { grey += 1 }
            }
            if name == "paused" {
                #expect(grey > 40, "the paused screen has lost its grey")
            } else {
                // Averaging a white/black edge is what invents grey, which is why
                // the slicer takes the most common palette colour instead. If this
                // fails the downsample has gone back to averaging and paused is no
                // longer the only grey screen.
                #expect(grey == 0, "\(name) has \(grey) grey pixels")
            }
        }
    }

    @Test("the bay's rounded clip never cuts the character, only what trails off it")
    func fitsTheWell() throws {
        let set = try #require(RunHUDSprites.images(scale: 1))
        let side = Double(RunHUDCharacter.bay)
        let radius = 9.0
        for (name, image) in set {
            let (w, h, rgba) = try pixels(image)
            var clippedLow = 0, clipped = 0
            for y in 0..<h {
                for x in 0..<w where rgba[(y * w + x) * 4 + 3] > 8 {
                    let px = Double(x) + 0.5, py = Double(y) + 0.5
                    let cx = px < radius ? radius : (px > side - radius ? side - radius : px)
                    let cy = py < radius ? radius : (py > side - radius ? side - radius : py)
                    guard hypot(px - cx, py - cy) > radius else { continue }
                    clipped += 1
                    if py > side / 2 { clippedLow += 1 }
                }
            }
            // The bottom corners are where the feet are, and the feet are the
            // anchor every frame is normalised on. Losing a pixel of one would
            // undo the whole point of the re-crop.
            #expect(clippedLow == 0, "\(name) loses \(clippedLow) pixels of its footing to the well")
            // Above the midline exactly one state reaches a corner: the error
            // state's puff of smoke. The reference's own well hides its
            // overflow and the design record says the extras are expected to go
            // at small sizes, so that is allowed — and pinned, so a regenerated
            // sheet that pushed a case top or a head into a corner fails here
            // rather than shipping a shorn character.
            #expect(clipped <= (name == "error" ? 8 : 0),
                    "\(name) loses \(clipped) pixels to the well")
        }
    }

    func densityChoice() throws {
        #expect(RunHUDSprites.images(forBackingScale: 2)?.scale == 2)
        #expect(RunHUDSprites.images(forBackingScale: 1)?.scale == 1)
        // A display denser than anything drawn gets the densest drawn set rather
        // than an empty bay.
        #expect(RunHUDSprites.images(forBackingScale: 4)?.scale == 3)
    }
}
