import AppKit
import QuartzCore
import ProctorCore

// The character in the panel's bay, and the glow on the progress rail.
//
// Both are here rather than in `RunHUDContentView.draw(_:)` for the reason the
// cursor overlay's header sets out: every animation this process shows is
// committed to the render server in one pass, so it plays at full rate while the
// agent is busy settling and walking trees. An overlay that needed servicing
// would stutter exactly when it was most worth watching, and the agent's job is
// to notice an application going quiet — not to draw frames.
//
// What moves and what a person's Reduce Motion setting does to it is decided in
// `RunHUDMotion`, in Core, so the rule is checkable without a display. These
// views only obey it.

/// The shipped sprite frames, decoded once.
///
/// A missing or unreadable picture leaves the bay empty and the run carries on,
/// which is the panel's own rule: a drawing failure never stops a run. The
/// pictures ship inside the bundle and are never fetched — an agent holding
/// these permissions has no business reaching the network to draw itself.
@MainActor
enum RunHUDSprites {

    private static var cache: [Int: [String: CGImage]] = [:]

    /// Every frame at one density, or nil if the set is not there. All-or-
    /// nothing on purpose: half a character is worse than none, because a state
    /// that silently drew the previous state's picture would be a panel telling
    /// somebody the wrong thing about a run they are supervising.
    static func images(scale: Int) -> [String: CGImage]? {
        if let ready = cache[scale] { return ready }
        var loaded: [String: CGImage] = [:]
        for asset in RunHUDCharacter.assets {
            guard let image = decode(asset: asset, scale: scale) else { return nil }
            loaded[asset] = image
        }
        cache[scale] = loaded
        return loaded
    }

    /// The best set at or below the display's density, so an unexpected scale
    /// draws a coarser character rather than an empty bay.
    static func images(forBackingScale backing: CGFloat) -> (images: [String: CGImage], scale: Int)? {
        let wanted = max(1, min(RunHUDCharacter.densities.max() ?? 1, Int(backing.rounded())))
        for scale in stride(from: wanted, through: 1, by: -1) {
            if let images = images(scale: scale) { return (images, scale) }
        }
        return nil
    }

    private static func decode(asset: String, scale: Int) -> CGImage? {
        let name = scale == 1 ? asset : "\(asset)@\(scale)x"
        guard let url = Bundle.module.url(forResource: name, withExtension: "png",
                                          subdirectory: "character"),
              let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.cgImage
    }
}

/// The bay's occupant. Hard pixels in both directions: a smoothed sprite is not
/// pixel art, and pixel art is the one thing about this character that makes it
/// gain legibility as it shrinks.
@MainActor
final class RunHUDCharacterView: NSView {

    /// The sprite is a sublayer, never the view's own backing layer. AppKit owns
    /// a layer-backed view's root layer and rewrites its `contents` on a display
    /// pass, which would quietly stamp on the animation. A hosted sublayer is
    /// mine, and because it fills the view's bounds exactly its frame carries no
    /// question about whether AppKit flipped the layer's geometry.
    private let sprite = CALayer()
    private var shown: (phase: RunHUDPhase, reduceMotion: Bool, scale: Int)?
    private var pendingPhase: RunHUDPhase?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 9
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.contentsGravity = .resize
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// The bay swallows nothing: hit testing is decided at the content view,
    /// which ignores subviews entirely, so this can never take a click meant for
    /// a control or for the application underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        shown = nil
        if let pendingPhase { show(pendingPhase) }
    }

    func show(_ phase: RunHUDPhase) {
        pendingPhase = phase
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let backing = window?.backingScaleFactor ?? 2
        guard let set = RunHUDSprites.images(forBackingScale: backing) else {
            isHidden = true
            return
        }
        isHidden = false
        // Reapplying the same loop would restart it on every 1 Hz clock tick,
        // which is a character that twitches once a second rather than moving.
        let wanted = (phase: phase, reduceMotion: reduceMotion, scale: set.scale)
        if let shown, shown == wanted { return }
        shown = wanted

        let frames = RunHUDMotion.sprite(for: phase, reduceMotion: reduceMotion)
        let images = frames.compactMap { set.images[$0.asset] }
        guard let first = images.first, images.count == frames.count else {
            isHidden = true
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.removeAnimation(forKey: "sprite")
        sprite.contentsScale = CGFloat(set.scale)
        sprite.frame = bounds
        // A state change cuts straight to the new picture. Hard-edged pixel art
        // blended into another frame goes soft, which is the one thing this
        // character cannot afford at 38pt.
        sprite.contents = first
        CATransaction.commit()

        guard frames.count > 1 else {
            CATransaction.flush()
            return
        }

        // Discrete keyframes take one more key time than they take values: the
        // last entry is when the final frame ends, not when it starts. Without
        // it the closing frame of every loop would be held for no time at all.
        let total = frames.reduce(0) { $0 + max(1, $1.durationMs) }
        var elapsed = 0
        var keyTimes: [NSNumber] = []
        for frame in frames {
            keyTimes.append(NSNumber(value: Double(elapsed) / Double(total)))
            elapsed += max(1, frame.durationMs)
        }
        keyTimes.append(1)

        let loop = CAKeyframeAnimation(keyPath: "contents")
        // Discrete: a pixel sprite cuts between frames, it does not cross-fade.
        loop.calculationMode = .discrete
        loop.values = images
        loop.keyTimes = keyTimes
        loop.duration = Double(total) / 1000
        loop.repeatCount = .infinity
        loop.isRemovedOnCompletion = false
        // One key, and the old animation is removed above, so a run that changes
        // state twenty times does not end up with twenty loops on one layer.
        sprite.add(loop, forKey: "sprite")
        // Handed over once. Nothing in this process draws a frame of it after
        // this line.
        CATransaction.flush()
    }
}

/// The filled part of the progress rail, so its pulse is the render server's
/// work rather than a timer's. The track underneath stays in `draw(_:)`: it does
/// not move, and a thing that does not move does not need a layer.
@MainActor
final class RunHUDRailView: NSView {

    /// A sublayer for the same reason the sprite uses one — the view's own
    /// backing layer belongs to AppKit.
    private let fill = CALayer()
    private var glowing: RunHUDMotion.RailGlow?
    private var applied = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        CATransaction.commit()
    }

    func apply(colour: NSColor, glow: RunHUDMotion.RailGlow?) {
        // No implicit animation on the fill's width, its colour, or the opacity
        // reset below. The reference transitions the width; a width that never
        // animates cannot violate a reduced-motion setting, and a rail that
        // jumps a step at a time is honest about what it is counting.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        fill.backgroundColor = colour.cgColor
        CATransaction.commit()

        guard glow != glowing || !applied else { return }
        glowing = glow
        applied = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Leaving travelling, or somebody turning Reduce Motion on, has to put
        // the rail back to full opacity as well as stop the pulse — otherwise it
        // sticks wherever the animation was when it was pulled.
        fill.removeAnimation(forKey: "glow")
        fill.opacity = 1
        CATransaction.commit()
        guard let glow else {
            CATransaction.flush()
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = glow.minimumOpacity
        pulse.duration = glow.periodSeconds / 2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        fill.add(pulse, forKey: "glow")
        CATransaction.flush()
    }
}
