import Foundation

// When the run panel has to step out of the way, as arithmetic.
//
// THE GATE ANSWERS ONE QUESTION AND IT IS NARROWER THAN IT LOOKS. A synthetic
// event is posted at a screen point and the window at that point wins, so a
// point under the run panel is routed to the run panel — which is how a click
// aimed at the application under test gets swallowed, or lands on Stop and halts
// the run that posted it. That is the whole reason the panel goes
// click-through, and it is a fact about GEOMETRY, not about the step's kind.
//
// Before PRO-0033 the panel stepped aside for the whole of any step whose kind
// was synthetic. That was wrong in both directions: it missed a `scroll` that
// fell back to a wheel event, whose kind is not synthetic, and it fired for
// every synthetic step whether or not that step went anywhere near the panel.
// The second error is the expensive one — while the panel is click-through a
// person's click on Stop passes through it into the application, so the kill
// switch is dead and the same gesture corrupts the run.
//
// EVERYTHING HERE IS QUARTZ SCREEN SPACE, y down from the top of the primary
// display. That is the space the actuator posts in — `Actuator.pointer` and the
// `dragPath` route use `step.point` raw, and an accessibility frame states the
// same space — and it is the space `CGEvent.location` reports inside the event
// tap. One space, converted once by whoever publishes the panel's frame, so
// there is no second flip to get wrong.
public enum RunHUDGate {

    /// Does anything this step is about to post land on the panel?
    ///
    /// `points` is the route the step will act along: one point for a click, a
    /// hover or a fallback scroll, the whole path for a drag. `panel` is the run
    /// panel's frame, or nil when it is not on screen.
    ///
    /// Nil panel, or no points, is false in both cases for the same reason: a
    /// panel that is not on screen cannot be in the way, and a step whose target
    /// could not be resolved posts nowhere this can reason about. False means
    /// "do not step aside", which keeps Stop clickable — the safe direction,
    /// because the cost of being wrong here is a swallowed synthetic event
    /// rather than a dead kill switch.
    public static func stepsAside(points: [RunHUDPlacement.Point], panel: Rect?) -> Bool {
        guard let panel, panel.w > 0, panel.h > 0, !points.isEmpty else { return false }
        if points.contains(where: { contains(panel, $0) }) { return true }
        // A route is tested along its segments rather than at its ends: a drag
        // from one side of the panel to the other has both endpoints outside it
        // and crosses it completely, and a gesture that crosses the panel is a
        // gesture the panel would intercept.
        guard points.count >= 2 else { return false }
        for index in 1..<points.count where crosses(panel, points[index - 1], points[index]) {
            return true
        }
        return false
    }

    static func contains(_ rect: Rect, _ point: RunHUDPlacement.Point) -> Bool {
        point.x >= rect.x && point.x <= rect.x + rect.w
            && point.y >= rect.y && point.y <= rect.y + rect.h
    }

    /// Whether a segment meets a rectangle whose corners it does not sit inside.
    /// Both endpoints are known to be outside by the time this is asked, so it is
    /// enough to test the segment against the four edges.
    private static func crosses(_ rect: Rect, _ a: RunHUDPlacement.Point,
                                _ b: RunHUDPlacement.Point) -> Bool {
        let corners = [
            RunHUDPlacement.Point(x: rect.x, y: rect.y),
            RunHUDPlacement.Point(x: rect.x + rect.w, y: rect.y),
            RunHUDPlacement.Point(x: rect.x + rect.w, y: rect.y + rect.h),
            RunHUDPlacement.Point(x: rect.x, y: rect.y + rect.h)
        ]
        for index in 0..<4 where meets(a, b, corners[index], corners[(index + 1) % 4]) {
            return true
        }
        return false
    }

    private static func meets(_ p1: RunHUDPlacement.Point, _ p2: RunHUDPlacement.Point,
                              _ p3: RunHUDPlacement.Point,
                              _ p4: RunHUDPlacement.Point) -> Bool {
        let d1 = direction(p3, p4, p1)
        let d2 = direction(p3, p4, p2)
        let d3 = direction(p1, p2, p3)
        let d4 = direction(p1, p2, p4)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0))
            && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) { return true }
        if d1 == 0, onSegment(p3, p4, p1) { return true }
        if d2 == 0, onSegment(p3, p4, p2) { return true }
        if d3 == 0, onSegment(p1, p2, p3) { return true }
        if d4 == 0, onSegment(p1, p2, p4) { return true }
        return false
    }

    private static func direction(_ a: RunHUDPlacement.Point, _ b: RunHUDPlacement.Point,
                                  _ c: RunHUDPlacement.Point) -> Double {
        (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)
    }

    private static func onSegment(_ a: RunHUDPlacement.Point, _ b: RunHUDPlacement.Point,
                                  _ c: RunHUDPlacement.Point) -> Bool {
        min(a.x, b.x) <= c.x && c.x <= max(a.x, b.x)
            && min(a.y, b.y) <= c.y && c.y <= max(a.y, b.y)
    }
}
