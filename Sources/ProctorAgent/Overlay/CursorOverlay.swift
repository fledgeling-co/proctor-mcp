import AppKit
import QuartzCore
import ProctorCore

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
// pointer or takes focus. The panels are non-activating, click-through and join
// every Space, so they draw over what is being driven without touching it — and
// they sit in that window's own plane rather than above the machine, for the
// reason recorded further down.
//
// Two properties make this safe to leave on by default. The panels belong to
// this process, and every capture is window-scoped to the app under test, so
// the overlay never appears in a frame, never moves a state hash, and never
// changes a pixel assertion. And every animation is committed to the render
// server in one transaction, so it plays at full frame rate without this
// process drawing a frame — the agent is busy settling and walking trees, and
// an overlay that needed servicing would stutter exactly when it was most
// worth watching.
//
// ONE PANEL PER SCREEN, and that is not a stylistic choice. The first version
// used a single panel sized to the union of every display, which on a
// 1728x1117 laptop beside a 2560x1440 display is 2560x2557pt — a 5120x5114
// backing store, about 26 megapixels. The window server accepts such a window
// and reports it perfectly healthy: CGWindowListCopyWindowInfo returns it at
// the requested level with `onscreen = 1` and `alpha = 1`. It simply never
// presents. Sixty full-screen captures across a six-step run were
// byte-identical, and no amount of explicit CATransaction flushing changed
// that, because nothing was wrong with the transactions. Measured on macOS
// 26.6: a panel matching either screen individually (7Mpx and 14Mpx backing)
// presents immediately; the union panel never does, whether its origin is
// negative or zero. So each screen gets its own panel, and the pointer lives
// on the one containing its target.
//
// THE POINTER SITS IN THE TARGET WINDOW'S PLANE, and that is also measured
// rather than reasoned. A panel's level is not a position in another
// application's stacking order, so the panel is ordered relative to the target
// window's CGWindowID — a window belonging to another process, which is not a
// documented use of `order(_:relativeTo:)`. Measured on macOS 26.6, 2026-08-15,
// against real Chrome and Ghostty windows, by capturing the screen and sampling
// the pixel at the drawn point rather than by asking the window server what it
// believed:
//
//   at level .screenSaver, over a target fully covered by another app
//                                         → pointer VISIBLE (the misstatement)
//   at level .normal + order(.above, relativeTo: <foreign id>), same target
//                                         → pointer ABSENT: the covering
//                                           window's own pixels, which is the
//                                           truthful picture
//   same restack, target frontmost        → pointer VISIBLE
//
// The panel landed at window-list index 28 with the target at 29 and the app
// above it at 27 — genuinely sandwiched between two windows of another process
// — and was still immediately above the target after three seconds idle. The
// level is what makes it work: at .screenSaver the ordering call is accepted
// and inert, because level dominates.
//
// It is verified per use anyway. `PointerPlanePolicy.held` re-reads the window
// list after the ordering call, and a placement that did not hold demotes to a
// dimmed pointer at the old floating level. An undocumented ordering that stops
// working on some future macOS then degrades to a pointer that admits it cannot
// vouch for its position, rather than to one that quietly lies about it.
@MainActor
final class CursorOverlay {

    static let shared = CursorOverlay()

    /// Off switch for a run that should leave the screen alone — an unattended
    /// suite, or a machine where somebody is working. `nonisolated` because the
    /// call sites check it before hopping to the main actor, so a disabled
    /// overlay costs nothing at all.
    nonisolated private static let switchedOn: Bool =
        OverlaySwitch.isOn("PROCTOR_CURSOR", in: ProctorEnvironment.current)

    /// On when the variable is absent, which is right for the agent and wrong
    /// for every other process that links this target. `AgentProcess` is the
    /// term that tells them apart.
    nonisolated static var isEnabled: Bool {
        OverlaySwitch.mayRaise(isAgent: AgentProcess.isAgent, switchedOn: switchedOn)
    }

    private static let pointerSize = CGSize(width: 19, height: 32)
    private static let ringDiameter: CGFloat = 46
    /// The band the pointer joins to sit in a target window's plane. It has to
    /// share a band with ordinary application windows, because a level always
    /// beats an ordering.
    private static let inPlaneLevel: NSWindow.Level = .normal
    /// Where the pointer goes when its plane could not be established: back
    /// above everything, dimmed and marked, which is the honest way to say "I
    /// cannot vouch for where this belongs".
    private static let floatingLevel: NSWindow.Level = .screenSaver
    /// How long the pointer stays on screen after a batch of steps finishes.
    private static let idleTimeout: TimeInterval = 2.5
    /// The backstop: how long it may stay if nobody ever says the batch ended,
    /// because a run that dies mid-flight should not leave a pointer on the
    /// screen forever. Long enough to outlive any single settling step.
    private static let abandonedTimeout: TimeInterval = 45

    /// One screen's worth of overlay. The frame is the screen's AppKit frame,
    /// kept here so a screen point can be turned into a layer point without
    /// asking the window or the screen list again.
    private struct Surface {
        let panel: NSPanel
        let pointer: CAShapeLayer
        let ring: CAShapeLayer
        let frame: CGRect
    }

    private var surfaces: [Surface] = []
    /// The arrangement the current surfaces were built for. Displays come and
    /// go — a laptop lid, a dock, a resolution change — and surfaces built for
    /// yesterday's arrangement leave the pointer on a screen that is not there.
    private var builtFor: [CGRect] = []
    /// Which surface the pointer is currently living on.
    private var activeIndex: Int?
    /// The last target, in screen points as the actuator and the AX tree state
    /// them: y down from the top of the primary display.
    private var lastTarget: CGPoint?
    /// The opacity the pointer is currently entitled to, from the last plane
    /// that was applied. Full when the panel is genuinely in the target's plane,
    /// dimmed when it is floating above everything without being able to say it
    /// belongs there.
    private var activeOpacity: Float = 1
    private var fadeOut: DispatchWorkItem?

    // MARK: - Public surface

    /// Travel to a target and wait for the animation to land, so the step that
    /// follows fires with the pointer already there. A caller that did not wait
    /// would draw a click arriving before the pointer did, which reads as the
    /// overlay being decorative rather than as a record of what happened.
    func travel(to target: CGPoint, plane: PointerPlane = .floatingDimmed) async {
        ensureSurfaces()
        guard let index = surfaceIndex(containing: target) else { return }
        guard applyPlane(plane, on: surfaces[index]) else { return }

        // Crossing to another display is a jump, not a flight: there is no
        // continuous surface between two panels to animate across, and a
        // pointer that slid through the gap would be describing a path the
        // actuator never took.
        let crossed = activeIndex != index
        if crossed, let previous = activeIndex, surfaces.indices.contains(previous) {
            let old = surfaces[previous]
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            old.pointer.opacity = 0
            old.ring.opacity = 0
            CATransaction.commit()
        }
        activeIndex = index

        let duration = beginTravel(to: target, on: surfaces[index], landing: crossed)
        Self.flush()
        if duration > 0.01 {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    }

    /// A pulse where the pointer is standing, for a step that actuates.
    func click() async {
        guard let surface = activeSurface else { return }
        let pointer = surface.pointer, ring = surface.ring
        ring.position = pointer.position
        armFade()

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.0
        let vanish = CABasicAnimation(keyPath: "opacity")
        // The pulse is as qualified as the pointer that made it: a dimmed
        // pointer that punched a full-strength ring would undo the marking.
        vanish.fromValue = 0.75 * Double(activeOpacity)
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
    func drag(along route: [CGPoint], durationMs: Int,
              plane: PointerPlane = .floatingDimmed) async {
        guard route.count >= 2, let start = route.first else { return }
        await travel(to: start, plane: plane)
        guard let surface = activeSurface else { return }
        let pointer = surface.pointer, ring = surface.ring

        let seconds = min(6.0, max(0.15, Double(durationMs) / 1000))
        let path = CGMutablePath()
        path.move(to: layerPoint(for: start, on: surface))
        for point in route.dropFirst() { path.addLine(to: layerPoint(for: point, on: surface)) }

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
        pointer.position = layerPoint(for: destination, on: surface)
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
        guard !surfaces.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for surface in surfaces {
            surface.pointer.opacity = 0
            surface.ring.opacity = 0
        }
        CATransaction.commit()
        Self.flush()
    }

    // MARK: - Placement

    /// Put this surface's panel where the plane says, and set the opacity the
    /// pointer has earned. Returns whether there is anything to draw at all.
    ///
    /// The in-plane placement is attempted and then *checked*: ordering a panel
    /// relative to another process's window is measured behaviour rather than a
    /// documented capability, so a placement that did not hold falls back to the
    /// floating level with the pointer dimmed and its ring dashed. That is the
    /// same treatment an uncorrelated window gets, and it means the pointer
    /// never occupies a position it cannot justify.
    private func applyPlane(_ plane: PointerPlane, on surface: Surface) -> Bool {
        switch plane {
        case .hidden:
            hide()
            return false

        case .floatingDimmed:
            float(surface)
            return true

        case .inPlane(let target):
            // Every other display's panel goes back to the floating band first.
            // They hold a pointer at zero opacity so they are invisible either
            // way, but a sibling left in the normal band from an earlier step
            // can land between this panel and its target and fail the read-back
            // below for a placement that was actually correct.
            for other in surfaces where other.panel !== surface.panel {
                Self.place(other.panel, at: Self.floatingLevel)
            }
            Self.place(surface.panel, at: Self.inPlaneLevel)
            surface.panel.orderFrontRegardless()
            surface.panel.order(.above, relativeTo: Int(target))
            let panelNumber = surface.panel.windowNumber
            if panelNumber > 0,
               PointerPlanePolicy.held(panel: UInt32(panelNumber), above: target,
                                       order: Self.onScreenOrder()) {
                mark(surface, opacity: 1, dashed: false)
                return true
            }
            // The ordering did not hold — a target on a level this panel cannot
            // reach, a macOS that no longer honours the call, or simply a window
            // sitting over the target. `orderFront` above left the panel at the
            // head of the normal band, which is not a position it can justify.
            //
            // Where it goes instead depends on whether anything covers the
            // target, and the two are different pictures rather than degrees of
            // the same one. Uncovered: float and mark it, because the pointer is
            // where it would be anyway and only the exact ordering is
            // unconfirmed. Covered: draw nothing. A pointer floating over a
            // window the person cannot see reads as Proctor clicking the app
            // they ARE looking at, which is the misstatement this whole file
            // exists to prevent, and dimming it does not stop it being that.
            let order = Self.onScreenOrder()
            switch PointerPlanePolicy.fallback(target: target,
                                               order: order,
                                               ours: Set(self.panelNumbers())) {
            case .hidden:
                hide()
                return false
            default:
                float(surface)
                return true
            }
        }
    }

    /// The window numbers of this process's own overlay panels.
    ///
    /// The pointer's surfaces sit above their target by construction, so
    /// counting them as "something covering it" would hide the pointer from
    /// every target it ever annotates.
    private func panelNumbers() -> [UInt32] {
        surfaces.compactMap { $0.panel.windowNumber > 0 ? UInt32($0.panel.windowNumber) : nil }
    }

    /// Move a panel between bands, and re-apply the capture exclusion.
    ///
    /// PRO-0088. Measured 2026-08-20 against agent pid 86732: this panel
    /// reported `sharingState 1` on the window server while the run panel
    /// (window 121489, layer 25) and the takeover statement (window 121490,
    /// layer 24) both reported 0 — evidence/witness/a2-hud-11.json. Those two
    /// set `sharingType` once at construction and never move; this is the only
    /// overlay that changes level at runtime, and the sharing type does not
    /// survive the change. So the two are set together here, and `level` is
    /// assigned nowhere else in this file.
    ///
    /// Unconditional `.none`, matching `RunHUDPanel` and `TakeoverOverlay`:
    /// evidence must not change because somebody was watching, and the surface
    /// whose whole job is to be drawn over somebody else's window is the last
    /// one that should be photographable.
    private static func place(_ panel: NSPanel, at level: NSWindow.Level) {
        panel.level = level
        panel.sharingType = .none
    }

    private func float(_ surface: Surface) {
        Self.place(surface.panel, at: Self.floatingLevel)
        surface.panel.orderFrontRegardless()
        mark(surface, opacity: PointerPlanePolicy.dimmedOpacity, dashed: true)
    }

    /// Dimmed *and* marked, not dimmed alone: a faint pointer could be read as a
    /// pointer fading out, where a dashed ring says the drawing is qualified.
    private func mark(_ surface: Surface, opacity: Float, dashed: Bool) {
        activeOpacity = opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.ring.lineDashPattern = dashed ? [4, 3] : nil
        CATransaction.commit()
    }

    /// Every window on screen, front to back. The window list is the instrument
    /// that works here — a panel's own belief that it was ordered in is not
    /// evidence of where it landed.
    private static func onScreenOrder() -> [UInt32] {
        CGWindowIndex.records(option: .optionOnScreenOnly).map(\.number)
    }

    // MARK: - Travel

    /// Commit the move and report how long it will take. Split out from
    /// `travel` so the animation is committed in one synchronous pass and only
    /// the waiting is asynchronous.
    ///
    /// `landing` forces the no-flight case: a first appearance and a crossing
    /// to another display both have nowhere to travel from.
    private func beginTravel(to target: CGPoint, on surface: Surface,
                             landing: Bool) -> TimeInterval {
        let pointer = surface.pointer
        let from = landing ? nil : lastTarget
        let destination = layerPoint(for: target, on: surface)
        let origin = from.map { layerPoint(for: $0, on: surface) } ?? destination

        let distance = from == nil ? 0 : hypot(destination.x - origin.x, destination.y - origin.y)
        let duration = distance < 2 ? 0 : min(0.62, 0.16 + distance / 1400)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pointer.position = destination
        surface.ring.position = destination
        pointer.opacity = activeOpacity
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

    /// The batch is over: fade on the short timer. Called once when a run of
    /// steps finishes, which is the only moment that actually knows the pointer
    /// has nothing left to point at.
    ///
    /// This exists because arming the short fade at draw time was wrong in a way
    /// that hid the overlay for a whole debugging session: `beginTravel` runs
    /// BEFORE the step it is drawing for, and a step that settles for a second
    /// and a half spends most of the 2.5s timeout still executing. The pointer
    /// was being drawn correctly and then fading while the step it belonged to
    /// was still running.
    func idle() {
        armFade(after: Self.idleTimeout)
    }

    private func armFade(after seconds: TimeInterval = CursorOverlay.abandonedTimeout) {
        fadeOut?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let surface = self.activeSurface else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = surface.pointer.opacity
            fade.toValue = 0
            fade.duration = 0.45
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            surface.pointer.opacity = 0
            surface.ring.opacity = 0
            surface.pointer.add(fade, forKey: "fade")
            Self.flush()
        }
        fadeOut = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Committing

    /// Push the layer tree to the render server now.
    ///
    /// The agent owns main with a bare `CFRunLoopRun` — see `main.swift` — and
    /// never runs an NSApplication event loop. Flushing at the end of each
    /// entry point makes the crossing to the render server explicit rather than
    /// dependent on a loop this process does not run. It is called once per
    /// step rather than per frame, and the animations still play on the render
    /// server without this process drawing.
    ///
    /// Never call this from inside a `begin`/`commit` pair — every call site
    /// above is outside one.
    private static func flush() {
        CATransaction.flush()
    }

    // MARK: - Coordinates

    private var activeSurface: Surface? {
        guard let index = activeIndex, surfaces.indices.contains(index) else { return nil }
        return surfaces[index]
    }

    /// A screen point stated y-down from the top of the primary display, as the
    /// actuator posts it through CGEventPost and as an AX frame states it,
    /// converted to AppKit's y-up-from-the-bottom space.
    private func appKitPoint(for screenPoint: CGPoint) -> CGPoint {
        let flip = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: screenPoint.x, y: flip - screenPoint.y)
    }

    /// Screen points to one surface's layer points.
    private func layerPoint(for screenPoint: CGPoint, on surface: Surface) -> CGPoint {
        let appKit = appKitPoint(for: screenPoint)
        return CGPoint(x: appKit.x - surface.frame.minX,
                       y: appKit.y - surface.frame.minY)
    }

    /// Which screen a target belongs on. A point in the dead space between two
    /// unaligned displays belongs to no screen, and rather than dropping the
    /// step's drawing entirely it goes to the nearest surface, which is where
    /// somebody looking for it would look.
    private func surfaceIndex(containing screenPoint: CGPoint) -> Int? {
        guard !surfaces.isEmpty else { return nil }
        let appKit = appKitPoint(for: screenPoint)
        if let hit = surfaces.firstIndex(where: { $0.frame.contains(appKit) }) { return hit }
        return surfaces.indices.min { a, b in
            distance(from: appKit, to: surfaces[a].frame) < distance(from: appKit, to: surfaces[b].frame)
        }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    // MARK: - The panels

    /// Build one panel per screen, and rebuild when the arrangement changes.
    private func ensureSurfaces() {
        let arrangement = NSScreen.screens.map(\.frame)
        guard arrangement != builtFor else {
            for surface in surfaces { surface.panel.orderFrontRegardless() }
            Self.flush()
            return
        }

        for surface in surfaces { surface.panel.orderOut(nil) }
        surfaces = arrangement.map(build(for:))
        builtFor = arrangement
        activeIndex = nil
        lastTarget = nil
        Self.flush()
    }

    private func build(for frame: CGRect) -> Surface {
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
        // Click-through is the whole safety story: the panels cover every
        // display, so anything less would put a sheet of glass over the machine.
        panel.ignoresMouseEvents = true
        Self.place(panel, at: Self.floatingLevel)
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

        panel.orderFrontRegardless()
        return Surface(panel: panel, pointer: pointer, ring: ring, frame: frame)
    }

    /// The arrow glyph, in a unit-ish outline scaled to `pointerSize`.
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
