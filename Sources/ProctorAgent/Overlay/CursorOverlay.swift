import AppKit
import QuartzCore

// The pointer Proctor draws while it drives an application.
//
// Most of what the agent does is invisible. An accessibility press actuates a
// button without anything moving on screen, which is the property that makes it
// work on a background window — and also the property that makes a run
// impossible to follow. Somebody watching sees text appear and menus open with
// no cause. This draws the cause: a pointer that travels to each step's target
// before the step fires, leans into the direction it is travelling, and pulses
// where it acts.
//
// It is an annotation, not the system cursor. Nothing here moves the real
// pointer or takes focus. The panel is non-activating, click-through and joins
// every Space, so it floats over whatever is being driven without touching it.
//
// Two properties make this safe to leave on by default. The panel belongs to
// this process, and every capture is window-scoped to the app under test, so
// the overlay never appears in a frame, never moves a state hash, and never
// changes a pixel assertion. And every animation is committed to the render
// server in one transaction, so it plays at full frame rate without this
// process drawing a frame — the agent is busy settling and walking trees, and
// an overlay that needed servicing would stutter exactly when it was most
// worth watching.
@MainActor
final class CursorOverlay {

    static let shared = CursorOverlay()

    /// Off switch for a run that should leave the screen alone — an unattended
    /// suite, or a machine where somebody is working. `nonisolated` because the
    /// call sites check it before hopping to the main actor, so a disabled
    /// overlay costs nothing at all.
    nonisolated static let isEnabled: Bool = {
        let raw = ProcessInfo.processInfo.environment["PROCTOR_CURSOR"]?.lowercased()
        return !["0", "off", "false", "no"].contains(raw ?? "")
    }()

    private static let pointerSize = CGSize(width: 19, height: 32)
    private static let ringDiameter: CGFloat = 46
    /// How long the pointer stays on screen after the last step before it fades.
    private static let idleTimeout: TimeInterval = 2.5

    private var panel: NSPanel?
    private var pointer: CAShapeLayer?
    private var ring: CAShapeLayer?
    /// The panel's origin in AppKit screen coordinates, so a screen point can be
    /// turned into a layer point without asking the window each time.
    private var panelOrigin: CGPoint = .zero
    /// The last target, in screen points as the actuator and the AX tree state
    /// them: y down from the top of the primary display.
    private var lastTarget: CGPoint?
    private var fadeOut: DispatchWorkItem?

    // MARK: - Public surface

    /// Travel to a target and wait for the animation to land, so the step that
    /// follows fires with the pointer already there. A caller that did not wait
    /// would draw a click arriving before the pointer did, which reads as the
    /// overlay being decorative rather than as a record of what happened.
    func travel(to target: CGPoint) async {
        guard ensureShown(), let pointer else { return }
        let duration = beginTravel(to: target, pointer: pointer)
        Self.flush()
        if duration > 0.01 {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    }

    /// A pulse where the pointer is standing, for a step that actuates.
    func click() async {
        guard let pointer, let ring else { return }
        ring.position = pointer.position
        armFade()

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.0
        let vanish = CABasicAnimation(keyPath: "opacity")
        vanish.fromValue = 0.75
        vanish.toValue = 0.0
        let pulse = CAAnimationGroup()
        pulse.animations = [grow, vanish]
        pulse.duration = 0.42
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(pulse, forKey: "pulse")

        // The pointer dips the way a hand does when it presses something.
        let dip = CAKeyframeAnimation(keyPath: "transform.scale")
        dip.values = [1.0, 0.8, 1.0]
        dip.keyTimes = [0, 0.35, 1]
        dip.duration = 0.26
        dip.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pointer.add(dip, forKey: "dip")
        Self.flush()

        try? await Task.sleep(nanoseconds: 120_000_000)
    }

    /// Follow a drag route, pressed, at the pace the gesture itself will run at
    /// so the drawing and the posted events describe the same movement.
    func drag(along route: [CGPoint], durationMs: Int) async {
        guard route.count >= 2, let start = route.first else { return }
        await travel(to: start)
        guard let pointer, let ring else { return }

        let seconds = min(6.0, max(0.15, Double(durationMs) / 1000))
        let path = CGMutablePath()
        path.move(to: layerPoint(for: start))
        for point in route.dropFirst() { path.addLine(to: layerPoint(for: point)) }

        let follow = CAKeyframeAnimation(keyPath: "position")
        follow.path = path
        follow.duration = seconds
        follow.calculationMode = .paced
        follow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Held down for the length of the drag, which is what distinguishes it
        // on screen from the pointer merely moving between two places.
        let held = CABasicAnimation(keyPath: "transform.scale")
        held.fromValue = 0.86
        held.toValue = 0.86
        held.duration = seconds

        let destination = route[route.count - 1]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pointer.position = layerPoint(for: destination)
        ring.position = pointer.position
        CATransaction.commit()
        lastTarget = destination

        pointer.add(follow, forKey: "drag")
        pointer.add(held, forKey: "held")
        armFade()
        Self.flush()

        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        await click()
    }

    /// Take the pointer off screen now, rather than on the idle timer.
    func hide() {
        fadeOut?.cancel()
        fadeOut = nil
        guard let pointer, let ring else { return }
        pointer.opacity = 0
        ring.opacity = 0
        Self.flush()
    }

    // MARK: - Travel

    /// Commit the move and report how long it will take. Split out from
    /// `travel` so the animation is committed in one synchronous pass and only
    /// the waiting is asynchronous.
    private func beginTravel(to target: CGPoint, pointer: CAShapeLayer) -> TimeInterval {
        let from = lastTarget
        let destination = layerPoint(for: target)
        let origin = from.map(layerPoint(for:)) ?? destination

        // A first appearance has nowhere to travel from, so it lands rather
        // than flying in from a corner it was never at.
        let distance = from == nil ? 0 : hypot(destination.x - origin.x, destination.y - origin.y)
        let duration = distance < 2 ? 0 : min(0.62, 0.16 + distance / 1400)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pointer.position = destination
        ring?.position = destination
        pointer.opacity = 1
        CATransaction.commit()
        lastTarget = target

        if duration > 0 {
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: origin)
            move.toValue = NSValue(point: destination)
            move.duration = duration
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pointer.add(move, forKey: "travel")

            // The lean. A pointer that slides across the screen at a fixed
            // angle reads as a sprite; one that tips into the direction it is
            // going and rights itself on arrival reads as something holding it.
            // The tilt is taken against a vertical bias so a mostly-vertical
            // move barely leans, and it is capped well short of anything that
            // would make the glyph ambiguous.
            let dx = destination.x - origin.x
            let dy = destination.y - origin.y
            let lean = atan2(dx, abs(dy) + 90)
            let tilt = -max(-0.38, min(0.38, lean))
            let spin = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            spin.values = [0, tilt, tilt * 0.35, 0]
            spin.keyTimes = [0, 0.22, 0.78, 1]
            spin.duration = duration
            spin.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pointer.add(spin, forKey: "lean")
        }

        armFade()
        return duration
    }

    private func armFade() {
        fadeOut?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let pointer = self.pointer, let ring = self.ring else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = pointer.opacity
            fade.toValue = 0
            fade.duration = 0.45
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            pointer.opacity = 0
            ring.opacity = 0
            pointer.add(fade, forKey: "fade")
            Self.flush()
        }
        fadeOut = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleTimeout, execute: work)
    }

    // MARK: - Committing

    /// Push the layer tree to the render server now.
    ///
    /// The agent owns main with a bare `CFRunLoopRun`, deliberately — see
    /// `main.swift`. It never runs an NSApplication event loop, and without one
    /// the implicit transaction that would normally carry these mutations across
    /// is not reliably drained: the panel arrives in the window server at the
    /// right level, the right size and fully opaque, and stays empty. Measured
    /// on this machine, that is exactly what happened — 60 full-screen frames
    /// captured across a six-step run were byte-identical over the region the
    /// pointer was travelling through.
    ///
    /// Flushing at the end of each entry point makes the crossing explicit
    /// rather than dependent on a loop this process does not run. It is cheap,
    /// it is called once per step rather than per frame, and the animations
    /// themselves still play on the render server without this process drawing.
    ///
    /// Never call this from inside a `begin`/`commit` pair — every call site
    /// below is outside one.
    private static func flush() {
        CATransaction.flush()
    }

    // MARK: - Coordinates

    /// Screen points to layer points. The actuator posts a step's point through
    /// CGEventPost and an AX frame is stated the same way — y down from the top
    /// of the primary display — while AppKit measures y up from its bottom. The
    /// flip is against the primary screen specifically, which is the one that
    /// defines the origin both spaces are stated against.
    private func layerPoint(for screenPoint: CGPoint) -> CGPoint {
        let flip = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: screenPoint.x - panelOrigin.x,
                       y: (flip - screenPoint.y) - panelOrigin.y)
    }

    // MARK: - The panel

    /// Build the panel on first use and keep it fitted to the current display
    /// arrangement. False means there is no screen to draw on.
    @discardableResult
    private func ensureShown() -> Bool {
        if pointer == nil { build() }
        guard let panel else { return false }
        // Displays come and go — a laptop lid, a dock, a resolution change —
        // and a panel sized to yesterday's arrangement leaves the pointer
        // clipped or invisible on the display that was added.
        let wanted = Self.desktopBounds()
        if panel.frame != wanted {
            panel.setFrame(wanted, display: false)
            panel.contentView?.frame = CGRect(origin: .zero, size: wanted.size)
            panel.contentView?.layer?.frame = CGRect(origin: .zero, size: wanted.size)
            panelOrigin = wanted.origin
        }
        panel.orderFrontRegardless()
        Self.flush()
        return true
    }

    private func build() {
        let frame = Self.desktopBounds()
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Click-through is the whole safety story: the panel covers every
        // display, so anything less would put a sheet of glass over the machine.
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .ignoresCycle, .fullScreenAuxiliary]

        // Layer-hosting rather than layer-backed: assigning the layer before
        // wantsLayer leaves the tree ours, so AppKit does not redraw over it.
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let root = CALayer()
        root.frame = view.bounds
        view.layer = root
        view.wantsLayer = true
        panel.contentView = view

        let ring = CAShapeLayer()
        let ringRect = CGRect(x: 0, y: 0, width: Self.ringDiameter, height: Self.ringDiameter)
        ring.path = CGPath(ellipseIn: ringRect, transform: nil)
        ring.bounds = ringRect
        ring.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        ring.fillColor = NSColor(calibratedRed: 0.29, green: 0.55, blue: 1.0, alpha: 0.22).cgColor
        ring.strokeColor = NSColor(calibratedRed: 0.29, green: 0.55, blue: 1.0, alpha: 0.9).cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        root.addSublayer(ring)

        let pointer = CAShapeLayer()
        pointer.path = Self.arrowPath()
        pointer.bounds = CGRect(origin: .zero, size: Self.pointerSize)
        // The tip, so the glyph rotates about the point it is indicating rather
        // than about its own middle, and the point it indicates is the point the
        // step acts on.
        pointer.anchorPoint = CGPoint(x: 0, y: 1)
        pointer.fillColor = NSColor.white.cgColor
        pointer.strokeColor = NSColor.black.withAlphaComponent(0.8).cgColor
        pointer.lineWidth = 1.25
        pointer.lineJoin = .round
        pointer.shadowColor = NSColor.black.cgColor
        pointer.shadowOpacity = 0.4
        pointer.shadowRadius = 3
        pointer.shadowOffset = CGSize(width: 0, height: -1.5)
        pointer.opacity = 0
        root.addSublayer(pointer)

        self.panel = panel
        self.pointer = pointer
        self.ring = ring
        self.panelOrigin = frame.origin
        panel.orderFrontRegardless()
    }

    /// Every display as one rectangle, so a single panel and a single layer
    /// tree cover a move that crosses from one screen to another.
    private static func desktopBounds() -> CGRect {
        let screens = NSScreen.screens
        guard var union = screens.first?.frame else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        for screen in screens.dropFirst() { union = union.union(screen.frame) }
        return union
    }

    /// The classic pointer outline, stated as fractions of the bounds with the
    /// tip at the top-left corner, which is where the anchor sits.
    private static func arrowPath() -> CGPath {
        let w = pointerSize.width, h = pointerSize.height
        let outline: [(CGFloat, CGFloat)] = [
            (0.00, 1.00),   // tip
            (0.00, 0.12),   // down the leading edge
            (0.35, 0.33),   // into the notch beside the tail
            (0.55, 0.02),   // tail, outer corner
            (0.76, 0.07),   // tail, inner corner
            (0.57, 0.37),   // back out of the tail
            (1.00, 0.39)    // the barb
        ]
        let path = CGMutablePath()
        for (index, point) in outline.enumerated() {
            let p = CGPoint(x: point.0 * w, y: point.1 * h)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
