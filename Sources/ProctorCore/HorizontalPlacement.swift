import Foundation

// Which of left, centre or right describes where an element sits inside the
// thing that contains it. The arithmetic lives here, away from the assertion
// that calls it, for the reason `RegionCrop` and `RegionDirt` do: it needs no
// window, no display and no Accessibility grant, and every wrong answer it can
// give is indistinguishable from a right one.
//
// Two rules shape it, both argued in docs/specs/spec-PRO-0042.md.
//
// The terms are *physical*. This compares screen x coordinates and nothing here
// reads layout direction, so in a right-to-left app the element a developer
// calls leading sits at the larger x. Naming the measurement `left` says what
// was measured; naming it `leading` would claim a direction-awareness that is
// not here. The semantic words are accepted on the way in and resolved to the
// physical ones.
//
// And the nearest fit wins. In a container barely wider than the element more
// than one placement is inside the tolerance, and refusing to rank them would
// make an ordinary compact layout unassertable — a 28pt control in a 36pt cell
// has offsets of 0, 4 and 8, and it is plainly left-aligned. Only a genuine tie
// is undecidable, and an element that fills its container is exactly that.
public enum HorizontalPlacement: String, Sendable, Equatable, CaseIterable, Codable {
    case left, center, right

    /// Two offsets closer together than this are the same distance on screen, so
    /// they tie rather than rank. Half a point is one device pixel at 2x, which
    /// is the finest difference a layout can actually express.
    ///
    /// It is deliberately *not* the default tolerance. Setting the two equal
    /// makes every multi-candidate reading at the default a tie — the whole
    /// candidate band is one tolerance wide, so no two candidates can ever be
    /// further apart than that — which switches the ranking off exactly where
    /// most callers live. A 16pt element flush against an 18pt cell has offsets
    /// of 0, 1 and 2: plainly left-aligned, and unassertable under that rule.
    public static let tieWindow: Double = 0.5

    /// The tolerance every geometry kind on `proctor_assert` defaults to. One
    /// number across the tool: the distance at which two coordinates count as
    /// the same.
    public static let defaultTolerance: Double = 1.0

    /// Whether a rectangle can be measured horizontally at all. A frame read
    /// from AX can arrive with a non-finite or negative width, and every
    /// comparison against a NaN is false — which would otherwise make an
    /// unreadable frame come back as a confident `custom`, or, with a finite
    /// origin and a NaN width, as a confident `left`. Only the two fields the
    /// classification uses are checked, so a bad `y` does not throw away a
    /// horizontal answer that is perfectly good.
    public static func isMeasurable(_ rect: Rect) -> Bool {
        rect.x.isFinite && rect.w.isFinite && rect.w >= 0
    }

    /// The words a caller may write, case-insensitively. `leading` and
    /// `trailing` resolve to the physical term rather than being rejected, so an
    /// AppKit-shaped spec keeps working, and `centre` is accepted beside
    /// `center`.
    public static func parse(_ word: String) -> HorizontalPlacement? {
        switch word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left", "leading": return .left
        case "center", "centre": return .center
        case "right", "trailing": return .right
        default: return nil
        }
    }

    /// What a skip reason prints when it could not parse the caller's word.
    public static let acceptedWords =
        "left, center or right (leading, trailing and centre are also accepted)"

    /// What was measured, and what it does or does not decide.
    public struct Reading: Sendable, Equatable {

        /// `element.x - container.x`. Negative means the element starts outside
        /// the container's left edge.
        public var leftOffset: Double
        /// `element.maxX - container.maxX`. Negative means the element's right
        /// edge stops short of the container's, which is the usual case.
        public var rightOffset: Double
        /// `element.centerX - container.centerX`.
        public var centreOffset: Double
        /// The tolerance the reading was taken at, after clamping.
        public var tolerance: Double

        public init(leftOffset: Double, rightOffset: Double, centreOffset: Double,
                    tolerance: Double) {
            self.leftOffset = leftOffset
            self.rightOffset = rightOffset
            self.centreOffset = centreOffset
            self.tolerance = tolerance
        }

        public func offset(for placement: HorizontalPlacement) -> Double {
            switch placement {
            case .left: return leftOffset
            case .center: return centreOffset
            case .right: return rightOffset
            }
        }

        /// Every placement whose offset is inside the tolerance, in left,
        /// center, right order.
        public var candidates: [HorizontalPlacement] {
            HorizontalPlacement.allCases.filter { abs(offset(for: $0)) <= tolerance }
        }

        /// The candidates that share the smallest offset, within `tieWindow` of
        /// it. One element when the reading decides; more when it does not;
        /// none when nothing was in tolerance at all.
        public var nearest: [HorizontalPlacement] {
            let inTolerance = candidates
            guard let best = inTolerance.map({ abs(offset(for: $0)) }).min() else { return [] }
            return inTolerance.filter {
                abs(offset(for: $0)) - best <= HorizontalPlacement.tieWindow
            }
        }

        /// The placement this reading decides on, or nil when it decides
        /// nothing — either because no placement was in tolerance (`isCustom`)
        /// or because more than one is equally near (`isTied`).
        public var placement: HorizontalPlacement? {
            let near = nearest
            return near.count == 1 ? near[0] : nil
        }

        /// No placement was within tolerance: the element is positioned, but not
        /// against any of the container's three horizontal references.
        public var isCustom: Bool { candidates.isEmpty }

        /// More than one placement is equally near. The commonest cause is an
        /// element that fills its container, where all three offsets are zero
        /// and left, centre and right describe the same rectangle.
        public var isTied: Bool { nearest.count > 1 }

        /// The three measurements as a sentence fragment, so the reason a caller
        /// reads is built next to the arithmetic that produced it rather than
        /// re-derived at each call site.
        ///
        /// The three offsets do not share a sign convention — a positive left
        /// offset puts the element inside the container while a positive right
        /// offset puts it past the far edge — so each is worded on its own
        /// rather than through a shared rule that would silently invert one.
        public func describeOffsets() -> String {
            let left = leftOffset >= 0
                ? "\(points(leftOffset)) inside the container's"
                : "\(points(leftOffset)) outside the container's"
            let right = rightOffset <= 0
                ? "\(points(rightOffset)) inside it"
                : "\(points(rightOffset)) past it"
            let centre = centreOffset <= 0
                ? "\(points(centreOffset)) to its left"
                : "\(points(centreOffset)) to its right"
            return "the left edge is \(left), the right edge \(right), "
                 + "and the centre \(centre)"
        }

        private func points(_ value: Double) -> String {
            String(format: "%.1fpt", abs(value))
        }
    }

    /// Measure an element against its container. `tolerance` is one distance,
    /// applied identically to both edges and to the centre — the shipped code
    /// tripled it for the edges, which made a `left` pass three times weaker
    /// than the number the caller wrote.
    public static func read(element: Rect, container: Rect,
                            tolerance: Double = defaultTolerance) -> Reading {
        // A negative tolerance would otherwise match nothing, silently turning
        // every reading into `custom`; zero is the strictest thing it can mean.
        let epsilon = max(0, tolerance)
        return Reading(leftOffset: element.x - container.x,
                       rightOffset: (element.x + element.w) - (container.x + container.w),
                       centreOffset: (element.x + element.w / 2) - (container.x + container.w / 2),
                       tolerance: epsilon)
    }
}
