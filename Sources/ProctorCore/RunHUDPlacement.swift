import Foundation

// Where the run HUD sits, as arithmetic rather than as AppKit.
//
// The panel is 352pt wide and sized to its own content, so unlike the pointer
// overlay it can never be a window spanning every display — the failure
// `CursorOverlay.swift`'s header measures, where a 26-megapixel union panel is
// accepted by the window server, reported `onscreen = 1, alpha = 1`, and never
// presented. What is left to decide is which screen it belongs on and where on
// that screen it sits, and both are a function of the arrangement and the driven
// window's frame. Keeping them here means the decision is testable without a
// display attached, which is the only way it gets tested at all.
//
// Everything in this file is AppKit space: y up from the bottom of the primary
// display, the space `NSScreen.frame` reports and `NSWindow.setFrameOrigin`
// takes. Accessibility frames arrive y-down from the top of the primary display,
// so `appKit(from:primaryMaxY:)` converts them, exactly as the pointer overlay
// converts its targets.
public enum RunHUDPlacement {

    /// The mock's inset from the screen's bottom-right corner.
    public static let defaultInset: Double = 34

    public struct Placement: Sendable, Equatable {
        /// Index into the screens given, so the caller keeps its own handles.
        public var screen: Int
        /// Bottom-left of the panel, in AppKit space.
        public var origin: Point
        public init(screen: Int, origin: Point) {
            self.screen = screen
            self.origin = origin
        }
    }

    public struct Point: Sendable, Equatable {
        public var x: Double, y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// Dock the panel bottom-right of the screen holding the driven window.
    ///
    /// A target that straddles two displays belongs to the one showing most of
    /// it, and one that belongs to no screen at all — a window on a display that
    /// has just been unplugged — goes to the nearest, rather than the panel
    /// silently not appearing. With no target at all it goes to the first screen,
    /// which the caller passes as the primary.
    public static func place(panel size: Size, in screens: [Rect], target: Rect?,
                             inset: Double = defaultInset) -> Placement? {
        guard let index = screenIndex(for: target, in: screens) else { return nil }
        let screen = screens[index]
        let x = screen.x + screen.w - inset - size.w
        let y = screen.y + inset
        return Placement(screen: index,
                         origin: clamp(Point(x: x, y: y), size: size, into: screen))
    }

    public struct Size: Sendable, Equatable {
        public var w: Double, h: Double
        public init(w: Double, h: Double) { self.w = w; self.h = h }
    }

    /// Which screen a driven window belongs to: most overlap wins, then nearest.
    public static func screenIndex(for target: Rect?, in screens: [Rect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        guard let target else { return 0 }

        var best: (index: Int, area: Double)?
        for (index, screen) in screens.enumerated() {
            let area = intersectionArea(target, screen)
            if area > 0, area > (best?.area ?? 0) { best = (index, area) }
        }
        if let best { return best.index }

        // Off every screen. The nearest one is where somebody looking for the
        // panel would look, and an absent panel is a stop button nobody has.
        return screens.indices.min {
            distance(from: centre(of: target), to: screens[$0])
                < distance(from: centre(of: target), to: screens[$1])
        }
    }

    /// Keep a panel wholly on its screen. A dragged position outlives the screen
    /// arrangement that produced it, so this runs on a remembered origin too.
    public static func clamp(_ origin: Point, size: Size, into screen: Rect) -> Point {
        // A screen narrower than the panel cannot hold it; pinning to the near
        // edge keeps the live line and the controls reachable, which is the half
        // that matters.
        let maxX = max(screen.x, screen.x + screen.w - size.w)
        let maxY = max(screen.y, screen.y + screen.h - size.h)
        return Point(x: min(max(origin.x, screen.x), maxX),
                     y: min(max(origin.y, screen.y), maxY))
    }

    /// An accessibility frame — y down from the top of the primary display — in
    /// AppKit's y-up space. `primaryMaxY` is the primary screen's `frame.maxY`.
    public static func appKit(from screenSpace: Rect, primaryMaxY: Double) -> Rect {
        Rect(x: screenSpace.x, y: primaryMaxY - screenSpace.y - screenSpace.h,
             w: screenSpace.w, h: screenSpace.h)
    }

    /// The way back: an AppKit frame — `NSWindow.frame`, `NSScreen.frame` — in
    /// the y-down screen space the actuator posts in and `CGEvent.location`
    /// reports. The transform is its own inverse, which is why the body is
    /// identical, and it is written out rather than aliased so a reader at
    /// either call site sees which direction they are going.
    ///
    /// `primaryMaxY` is the PRIMARY screen's `frame.maxY` for the whole
    /// arrangement, never the screen the panel happens to be on. Flipping
    /// per-screen puts a panel on a display above the menu bar, or left of the
    /// origin, at a rectangle nothing is drawn at — and a Stop rectangle in the
    /// wrong place is a click on empty screen stopping a run.
    public static func quartz(from appKitSpace: Rect, primaryMaxY: Double) -> Rect {
        Rect(x: appKitSpace.x, y: primaryMaxY - appKitSpace.y - appKitSpace.h,
             w: appKitSpace.w, h: appKitSpace.h)
    }

    // MARK: - Geometry

    private static func intersectionArea(_ a: Rect, _ b: Rect) -> Double {
        let w = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
        let h = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        return w > 0 && h > 0 ? w * h : 0
    }

    private static func centre(of rect: Rect) -> Point {
        Point(x: rect.x + rect.w / 2, y: rect.y + rect.h / 2)
    }

    private static func distance(from point: Point, to rect: Rect) -> Double {
        let dx = max(rect.x - point.x, 0, point.x - (rect.x + rect.w))
        let dy = max(rect.y - point.y, 0, point.y - (rect.y + rect.h))
        return (dx * dx + dy * dy).squareRoot()
    }
}
