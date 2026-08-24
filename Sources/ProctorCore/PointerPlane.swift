import Foundation

// Where the drawn pointer belongs in the stack.
//
// The pointer is an annotation of one window's activity, not a thing sitting on
// top of the machine. Drawn at a high window level it appears above whatever a
// person is actually looking at, which reads as Proctor clicking their
// foreground app while it is in fact driving something else entirely — the one
// picture the overlay must never paint, because it is a lie about what the
// agent is doing to somebody's computer.
//
// The truthful position is the target window's own plane: immediately above it,
// below everything stacked over it, so a window covering the target covers the
// pointer too. macOS gives a panel a *level*, not a position in another
// application's stacking order, so this is reached by ordering the panel
// relative to a `CGWindowID` belonging to another process — measured working on
// macOS 26.6 and verified per use rather than assumed, because it is not a
// documented capability. The measurement is recorded in `CursorOverlay`.
//
// Three outcomes, and the two that are not the happy path both refuse to
// overstate: a target nobody can see gets no pointer at all, and a target whose
// plane cannot be established gets a pointer that is visibly marked as not
// vouching for its position.
//
// **"Nobody can see it" includes covered, and that was reported rather than
// reasoned.** From real use: "sometimes I'll see the fake cursor moving during
// testing, but the app it's working on is in the background and not visible,
// which makes the fake cursor's operation confusing." The window list called
// that target on screen, so the plane was attempted; when the restack did not
// hold, the pointer fell back to floating above everything — which is precisely
// the picture the paragraph above says must never be painted, with the dimming
// standing in for not painting it. Dimming marks uncertainty about a POSITION.
// It cannot mark a pointer that is in the wrong plane entirely, because there is
// no honest place on screen for an annotation of a window the person cannot see.
//
// So the fallback is split by whether anything covers the target. Uncovered and
// unverified is still `floatingDimmed`: the pointer is where it would be anyway,
// and the dimming says the exact ordering is unconfirmed. Covered is `hidden`.

/// Where the pointer should be drawn for one step.
public enum PointerPlane: Equatable, Sendable {
    /// Restack the panel immediately above this window and draw normally.
    case inPlane(above: UInt32)
    /// The plane could not be established. Draw at the floating level, dimmed
    /// and marked, so the pointer does not claim a position it does not hold.
    case floatingDimmed
    /// Nothing to annotate: the target is not on screen. Draw nothing.
    case hidden
}

public enum PointerPlanePolicy {

    /// How much of the pointer's opacity survives when its plane is unverified.
    /// Low enough to read as a different state at a glance, high enough that the
    /// glyph is still legible — it is marking uncertainty, not hiding.
    public static let dimmedOpacity: Float = 0.32

    /// The plane for a step, from what is known about its target window.
    ///
    /// `targetIsOnScreen` is the window list's answer, not accessibility's: a
    /// window minimised, hidden, or on another Space is absent from the
    /// on-screen list, and all three mean the same thing here — there is nothing
    /// on the screen in front of somebody for this pointer to annotate.
    /// `targetIsCovered` is whether another window sits over the target. A
    /// covered target has no honest pointer: drawn in plane it would be hidden
    /// by the covering window, and drawn floating it would appear over the
    /// window the person is actually looking at.
    public static func decide(targetWindowID: UInt32?, targetIsOnScreen: Bool,
                              targetIsCovered: Bool = false) -> PointerPlane {
        guard targetIsOnScreen else { return .hidden }
        guard let id = targetWindowID, id != 0 else {
            return targetIsCovered ? .hidden : .floatingDimmed
        }
        return .inPlane(above: id)
    }

    /// What to do when a restack did not hold.
    ///
    /// The same split, at the other end: the ordering call has already been made
    /// and read back, so this is asked with the window order in hand rather than
    /// with a flag somebody computed earlier.
    public static func fallback(target: UInt32, order: [UInt32],
                                ours: Set<UInt32> = []) -> PointerPlane {
        isCovered(target: target, order: order, ignoring: ours) ? .hidden : .floatingDimmed
    }

    /// Whether anything is drawn over the target, from the on-screen window
    /// list, front to back.
    ///
    /// Panels belonging to this process are not counted: the pointer's own
    /// surfaces and the run panel sit above the target by design, and treating
    /// Proctor's own annotations as "something covering it" would hide the
    /// pointer from every target it ever annotates.
    public static func isCovered(target: UInt32, order: [UInt32],
                                 ignoring ours: Set<UInt32> = []) -> Bool {
        guard let index = order.firstIndex(of: target) else { return true }
        return order[..<index].contains { !ours.contains($0) }
    }

    /// Did the restack actually hold? `order` is the on-screen window list,
    /// front to back, read back after the ordering call.
    ///
    /// Immediately above, not merely somewhere above. A window sitting between
    /// the panel and its target would be drawn *under* the pointer while being
    /// *over* the target, which is a smaller version of the same misstatement.
    /// Being strict costs an occasional demotion to the dimmed treatment, which
    /// is the safe direction to be wrong in.
    public static func held(panel: UInt32, above target: UInt32, order: [UInt32]) -> Bool {
        guard let p = order.firstIndex(of: panel), let t = order.firstIndex(of: target) else {
            return false
        }
        return t == p + 1
    }
}


// MARK: - Window Occlusion Detection (PRO-0118 / DEF-325 / REQ-043 / REQ-200)

/// An individual window entry in the WindowServer display hierarchy.
public struct WindowOcclusionEntry: Equatable, Sendable {
    public var windowID: UInt32
    public var pid: Int32
    public var bounds: Rect
    public var layer: Int
    public var alpha: Double
    public var isOnScreen: Bool

    public init(windowID: UInt32, pid: Int32, bounds: Rect, layer: Int = 0,
                alpha: Double = 1.0, isOnScreen: Bool = true) {
        self.windowID = windowID
        self.pid = pid
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
        self.isOnScreen = isOnScreen
    }
}

/// The result of evaluating occlusion for a target window or point.
public enum WindowOcclusionState: Equatable, Sendable {
    /// Target is completely visible / unoccluded at the target coordinate.
    case clear
    /// Target coordinate is covered by one or more overlapping windows.
    case pointOccluded(by: [UInt32])
    /// Entire target window is fully covered by overlapping windows.
    case fullyCovered(by: [UInt32])
    /// Target window is not present on screen.
    case notOnScreen

    public var isOccluded: Bool {
        switch self {
        case .pointOccluded, .fullyCovered, .notOnScreen:
            return true
        case .clear:
            return false
        }
    }
}

public enum WindowOcclusionDetector {

    /// Correlates window bounds, layers, and pointer coordinates to determine occlusion.
    ///
    /// `windows` is the ordered list of on-screen windows (front to back as returned by WindowServer).
    /// `targetID` is the CGWindowID of the window being actuated.
    /// `targetPoint` is the coordinate (in screen points) where the action / cursor is directed.
    /// `ignoring` is the set of window IDs belonging to Proctor itself (overlays, HUD) that must not
    /// be counted as covering the target.
    public static func evaluate(
        targetID: UInt32,
        targetPoint: Point? = nil,
        windows: [WindowOcclusionEntry],
        ignoring: Set<UInt32> = []
    ) -> WindowOcclusionState {
        guard let targetIndex = windows.firstIndex(where: { $0.windowID == targetID && $0.isOnScreen }) else {
            return .notOnScreen
        }
        let target = windows[targetIndex]

        var coveringWindows: [UInt32] = []
        var pointCoveringWindows: [UInt32] = []

        // 1. Windows stacked in front of target in Z-order
        for window in windows[..<targetIndex] {
            guard !ignoring.contains(window.windowID) else { continue }
            guard window.isOnScreen && window.alpha > 0.05 else { continue }
            guard window.layer >= target.layer else { continue }

            if rectsIntersect(target.bounds, window.bounds) {
                coveringWindows.append(window.windowID)
            }

            if let pt = targetPoint, pointInside(pt, rect: window.bounds) {
                pointCoveringWindows.append(window.windowID)
            }
        }

        if !pointCoveringWindows.isEmpty {
            return .pointOccluded(by: pointCoveringWindows)
        }

        // 2. Higher layer windows (e.g. modal panels, system alerts) even if later in list
        for window in windows[targetIndex...] {
            guard !ignoring.contains(window.windowID) else { continue }
            guard window.isOnScreen && window.alpha > 0.05 else { continue }
            if window.layer > target.layer {
                if let pt = targetPoint, pointInside(pt, rect: window.bounds) {
                    return .pointOccluded(by: [window.windowID])
                }
                if rectsIntersect(target.bounds, window.bounds) {
                    coveringWindows.append(window.windowID)
                }
            }
        }

        if !coveringWindows.isEmpty {
            for cid in coveringWindows {
                if let cw = windows.first(where: { $0.windowID == cid }),
                   rectEncloses(container: cw.bounds, enclosed: target.bounds) {
                    return .fullyCovered(by: [cid])
                }
            }
        }

        return .clear
    }

    public static func rectsIntersect(_ r1: Rect, _ r2: Rect) -> Bool {
        !(r1.x + r1.w <= r2.x || r2.x + r2.w <= r1.x ||
          r1.y + r1.h <= r2.y || r2.y + r2.h <= r1.y)
    }

    public static func pointInside(_ p: Point, rect r: Rect) -> Bool {
        p.x >= r.x && p.x <= r.x + r.w &&
        p.y >= r.y && p.y <= r.y + r.h
    }

    public static func rectEncloses(container: Rect, enclosed: Rect) -> Bool {
        container.x <= enclosed.x &&
        container.y <= enclosed.y &&
        container.x + container.w >= enclosed.x + enclosed.w &&
        container.y + container.h >= enclosed.y + enclosed.h
    }
}
