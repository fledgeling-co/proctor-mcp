import Foundation
import CoreGraphics

// The arithmetic behind a drag gesture and behind a region-scoped dirty-area
// query. It lives here, away from both callers, because it is the part of each
// that can be checked without a window, a display or a grant.

// MARK: - Pointer paths

public enum PointerPath {

    /// Points closer together than this are indistinguishable to a tracking app,
    /// and further apart than this start to read as a jump.
    public static let defaultSpacing: Double = 10

    /// A ceiling on how many events one gesture may post.
    public static let defaultMaxPoints = 240

    /// Expand a sparse path into one an application can actually follow.
    ///
    /// An app that tracks a drag reads the movement between the press and the
    /// release; a press and a release at two positions with nothing in between
    /// is a click however far apart they are. Every supplied vertex is kept and
    /// points are inserted until consecutive ones are no more than `maxSpacing`
    /// apart.
    ///
    /// `maxPoints` wins over `maxSpacing` when the two conflict: a path dragged
    /// across a large display would otherwise post thousands of events, so the
    /// spacing widens rather than the count growing.
    public static func interpolate(_ points: [CGPoint],
                                   maxSpacing: Double = defaultSpacing,
                                   maxPoints: Int = defaultMaxPoints) -> [CGPoint] {
        let cap = max(2, maxPoints)
        guard points.count >= 2 else { return points }

        var total = 0.0
        for i in 1..<points.count { total += distance(points[i - 1], points[i]) }
        guard total > 0 else {
            // A path that never moves has nothing to fill in. The endpoints are
            // still both returned, so the gesture is a press and a release in
            // one place rather than an empty event list.
            return points.count <= cap ? points : decimate(points, to: cap)
        }

        let spacing = max(max(maxSpacing, .ulpOfOne), total / Double(cap - 1))
        var out: [CGPoint] = [points[0]]
        out.reserveCapacity(cap)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let steps = max(1, Int((distance(a, b) / spacing).rounded(.up)))
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out.count <= cap ? out : decimate(out, to: cap)
    }

    /// Thin a path to at most `count` points, keeping the first and the last so
    /// the gesture still starts and ends where the caller asked.
    public static func decimate(_ points: [CGPoint], to count: Int) -> [CGPoint] {
        let cap = max(2, count)
        guard points.count > cap else { return points }
        let last = Double(points.count - 1)
        return (0..<cap).map { i in
            let index = Int((Double(i) * last / Double(cap - 1)).rounded())
            return points[min(points.count - 1, max(0, index))]
        }
    }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Dirty regions

public enum RegionDirt {

    /// The overlap of two rectangles, or nil when they do not overlap.
    public static func intersection(_ a: Rect, _ b: Rect) -> Rect? {
        let x0 = max(a.x, b.x), x1 = min(a.x + a.w, b.x + b.w)
        let y0 = max(a.y, b.y), y1 = min(a.y + a.h, b.y + b.h)
        guard x1 > x0, y1 > y0 else { return nil }
        return Rect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }

    /// The area of that overlap. A dirty rect that covers part of a region
    /// contributes that part, not its whole area.
    public static func intersectionArea(_ a: Rect, _ b: Rect) -> Double {
        guard let overlap = intersection(a, b) else { return 0 }
        return overlap.w * overlap.h
    }

    /// Overlapping rects would double-count, so the area is a true union: split
    /// into vertical strips at every distinct x edge, union the y intervals
    /// inside each strip. A frame carries a handful of rects, so O(n^2) is free.
    public static func unionArea(_ rects: [Rect]) -> Double {
        let boxes = rects.filter { $0.w > 0 && $0.h > 0 }
        guard !boxes.isEmpty else { return 0 }
        var xs = Set<Double>()
        for r in boxes { xs.insert(r.x); xs.insert(r.x + r.w) }
        let edges = xs.sorted()
        var total = 0.0
        for i in 0..<(edges.count - 1) {
            let x0 = edges[i], x1 = edges[i + 1]
            let width = x1 - x0
            if width <= 0 { continue }
            var spans: [(Double, Double)] = []
            for r in boxes where r.x <= x0 && r.x + r.w >= x1 {
                spans.append((r.y, r.y + r.h))
            }
            if spans.isEmpty { continue }
            spans.sort { $0.0 < $1.0 }
            var covered = 0.0
            var curLo = spans[0].0, curHi = spans[0].1
            for s in spans.dropFirst() {
                if s.0 > curHi { covered += curHi - curLo; curLo = s.0; curHi = s.1 }
                else { curHi = max(curHi, s.1) }
            }
            covered += curHi - curLo
            total += covered * width
        }
        return total
    }

    /// How much of `region` the dirty rects cover, as a fraction of the region.
    /// Nil for a region with no area: a rectangle that cannot be measured is not
    /// a rectangle that was quiet, and returning 0 would say the opposite.
    public static func dirtyFraction(_ dirty: [Rect], in region: Rect) -> Double? {
        let area = region.w * region.h
        guard area > 0 else { return nil }
        let clipped = dirty.compactMap { intersection($0, region) }
        return min(1, max(0, unionArea(clipped) / area))
    }
}
