import Foundation

// Set-of-marks placement. This is the load-bearing, checkable half of the
// annotated-capture feature: given accessibility element frames in screen points
// and the pixel dimensions of the frame that was captured, it decides which
// elements get a numbered mark, what number each gets, and where the box lands in
// the image. The pixel compositing that follows is mechanical; getting the
// numbering or the transform wrong is what would make a mark map point at the
// wrong element, so that arithmetic lives here, away from any window or grant,
// where it can be tested directly. It mirrors how PointerPath and RegionDirt keep
// the gesture and region maths in Core rather than in the agent.

public enum SetOfMarks {

    /// One accessibility element eligible for a mark, in the coordinates the tree
    /// reports it in — screen points, top-left origin.
    public struct Element: Sendable, Equatable {
        public var node: String      // AX node id; the thing "click mark 7" resolves to
        public var role: String
        public var label: String?
        public var frame: Rect       // screen points
        public init(node: String, role: String, label: String? = nil, frame: Rect) {
            self.node = node; self.role = role; self.label = label; self.frame = frame
        }
    }

    public struct GridOptions: Sendable, Equatable {
        public var enabled: Bool
        public var spacingPoints: Double
        public init(enabled: Bool, spacingPoints: Double) {
            self.enabled = enabled; self.spacingPoints = spacingPoints
        }
        public static let off = GridOptions(enabled: false, spacingPoints: 100)
    }

    public struct Plan: Sendable {
        public var marks: [Mark]
        public var grid: GridOverlay?
        /// How many candidate elements were handed in, before culling. Reported so
        /// a truncated dense window says what it left out rather than looking empty.
        public var elementsConsidered: Int
        public var markedCount: Int
        public var truncated: Bool
        public init(marks: [Mark], grid: GridOverlay?, elementsConsidered: Int,
                    markedCount: Int, truncated: Bool) {
            self.marks = marks; self.grid = grid
            self.elementsConsidered = elementsConsidered
            self.markedCount = markedCount; self.truncated = truncated
        }
    }

    /// The default ceiling on marks. A dense window can expose hundreds of
    /// interactables; past this the numbers stop being legible and the point of
    /// grounding by id is lost, so the overflow is dropped and reported rather
    /// than drawn illegibly.
    public static let defaultMaxMarks = 150

    /// Screen points to frame pixels, the one transform the whole feature turns
    /// on. Identical to TriObserver.imageRect so a mark and a tri-observer finding
    /// place the same element in the same spot: subtract the window origin, scale.
    public static func toPixels(_ frame: Rect, window: Rect, scale: Double) -> Rect {
        let s = scale > 0 ? scale : 1
        return Rect(x: (frame.x - window.x) * s,
                    y: (frame.y - window.y) * s,
                    w: frame.w * s,
                    h: frame.h * s)
    }

    /// Number the visible elements in reading order and place their boxes.
    ///
    /// Ordering is by rounded y, then rounded x, then node id. Rounding to whole
    /// points matches the grain Canonical hashes at, so the same tree revision
    /// produces the same order and therefore the same ids every time — which is
    /// what lets a caller trust "mark 7" to mean the same element across two
    /// captures of one state. An element whose box does not intersect the captured
    /// frame is culled: a mark you cannot see grounds nothing.
    public static func plan(elements: [Element],
                            window: Rect,
                            imageWidth: Int,
                            imageHeight: Int,
                            scale: Double,
                            grid: GridOptions = .off,
                            maxMarks: Int = defaultMaxMarks) -> Plan {

        let imageBounds = Rect(x: 0, y: 0, w: Double(max(0, imageWidth)),
                               h: Double(max(0, imageHeight)))

        // Cull first, so numbering runs over exactly what will be drawn.
        var visible: [(element: Element, pixels: Rect)] = []
        for element in elements {
            guard element.frame.w > 0, element.frame.h > 0 else { continue }
            let px = toPixels(element.frame, window: window, scale: scale)
            guard let clipped = RegionDirt.intersection(px, imageBounds),
                  clipped.w > 0, clipped.h > 0 else { continue }
            visible.append((element, clipped))
        }

        visible.sort { a, b in
            let ay = a.element.frame.y.rounded(), by = b.element.frame.y.rounded()
            if ay != by { return ay < by }
            let ax = a.element.frame.x.rounded(), bx = b.element.frame.x.rounded()
            if ax != bx { return ax < bx }
            return a.element.node < b.element.node
        }

        let cap = max(0, maxMarks)
        let truncated = visible.count > cap
        let kept = Array(visible.prefix(cap))

        let marks = kept.enumerated().map { index, item in
            Mark(id: index + 1,
                 node: item.element.node,
                 role: item.element.role,
                 label: item.element.label,
                 frame: item.element.frame,
                 pixelRect: item.pixels)
        }

        return Plan(marks: marks,
                    grid: gridOverlay(grid, imageWidth: imageWidth, imageHeight: imageHeight,
                                      scale: scale),
                    elementsConsidered: elements.count,
                    markedCount: marks.count,
                    truncated: truncated)
    }

    /// Reference lines every `spacingPoints` points, given in frame pixels so the
    /// renderer draws without re-deriving the scale. The window edges (0 and the
    /// far side) are left undrawn; the lines that matter are the interior ones a
    /// caller reads a coordinate off.
    public static func gridOverlay(_ options: GridOptions,
                                   imageWidth: Int, imageHeight: Int,
                                   scale: Double) -> GridOverlay? {
        guard options.enabled, options.spacingPoints > 0, scale > 0,
              imageWidth > 0, imageHeight > 0 else { return nil }
        let step = options.spacingPoints * scale
        guard step >= 1 else { return nil }   // sub-pixel spacing would be a solid fill

        var verticals: [Double] = []
        var x = step
        while x < Double(imageWidth) { verticals.append(x); x += step }

        var horizontals: [Double] = []
        var y = step
        while y < Double(imageHeight) { horizontals.append(y); y += step }

        return GridOverlay(spacingPoints: options.spacingPoints, scale: scale,
                           verticals: verticals, horizontals: horizontals)
    }
}
