import Foundation
import CoreGraphics
import ProctorCore

// Where the drawn pointer goes for a given step.
//
// The resolution deliberately mirrors PointerMarker, which mirrors the
// actuator: an explicit point wins, otherwise the acted element's frame centre.
// Three different answers to "which point did this step act on" would be three
// things to keep in step, and the one drawn live has to agree with the one
// composited into a capture, or the overlay and the evidence disagree about the
// same action.
//
// A step with neither a point nor a framed element — a bare `type`, a `key`, a
// menu path — has no place on screen that it acted on, so nothing moves and the
// pointer stays where the last step left it.

extension Session {

    /// Step kinds that actuate something at a point, and so earn a pulse.
    static let pulsingKinds: Set<ActionStep.Kind> = [
        .press, .click, .pick, .confirm, .cancel, .increment, .decrement
    ]

    /// Draw the step before it runs. Best-effort throughout: the overlay is an
    /// annotation, so a target that cannot be resolved yields no movement rather
    /// than a failed step.
    ///
    /// The window is passed in because where the pointer belongs is a fact about
    /// the window being driven, not about the step: it is drawn in that window's
    /// own plane, so a window stacked above the target covers it, and it is not
    /// drawn at all when the target is not on screen.
    func showCursor(for step: ActionStep, window: WindowHandle) async {
        guard CursorOverlay.isEnabled else { return }
        let plane = cursorPlane(for: window)

        if step.kind == .dragPath {
            let route = cursorRoute(for: step)
            if route.count >= 2 {
                await CursorOverlay.shared.drag(along: route,
                                                durationMs: step.durationMs ?? 300,
                                                plane: plane)
                return
            }
        }

        guard let target = cursorTarget(for: step) else { return }
        await CursorOverlay.shared.travel(to: target, plane: plane)
        if Self.pulsingKinds.contains(step.kind) {
            await CursorOverlay.shared.click()
        }
    }

    /// Where this window's pointer belongs, from the window list rather than
    /// from accessibility. A window that is minimised, hidden, or on another
    /// Space is absent from the on-screen list, and all three mean the same
    /// thing: there is nothing in front of anybody for this pointer to annotate.
    /// `WindowHandle.isMinimized` and `isOnActiveSpace` are beliefs recorded
    /// when the handle was made; the list is the instrument.
    func cursorPlane(for window: WindowHandle) -> PointerPlane {
        let onScreen = CGWindowIndex.records(option: .optionOnScreenOnly)
            .contains { $0.number == window.cgWindowID }
        return PointerPlanePolicy.decide(targetWindowID: window.cgWindowID,
                                         targetIsOnScreen: onScreen)
    }

    /// The point a step acts on, in screen points.
    func cursorTarget(for step: ActionStep) -> CGPoint? {
        let elementFrame: Rect?
        if step.point == nil, let node = step.node {
            elementFrame = (try? ax.node(id: node))?.frame
        } else {
            elementFrame = nil
        }
        guard let target = PointerMarker.targetPoint(for: step, elementFrame: elementFrame) else {
            return nil
        }
        return CGPoint(x: target.x, y: target.y)
    }

    /// The screen points this step is about to post at, for the panel's mouse
    /// gate. The same points the drawn pointer travels to, and — because the
    /// actuator posts `step.point` raw and aims at an element's centre otherwise
    /// — the same points the actuator will post at. Reusing the pointer's own
    /// resolution rather than writing a second one is what keeps the gate's
    /// arithmetic and the actuation aimed at the same place; two resolutions
    /// that drifted apart would leave the panel stepping aside for somewhere the
    /// step was not going.
    ///
    /// A step whose target cannot be resolved contributes nothing, and the gate
    /// reads that as "do not step aside" — the safe direction, because the cost
    /// is a swallowed synthetic event rather than a dead Stop.
    func gatePoints(for step: ActionStep) -> [RunHUDPlacement.Point] {
        let route = cursorRoute(for: step)
        if route.count >= 2 {
            return route.map { RunHUDPlacement.Point(x: Double($0.x), y: Double($0.y)) }
        }
        guard let target = cursorTarget(for: step) else { return [] }
        return [RunHUDPlacement.Point(x: Double(target.x), y: Double(target.y))]
    }

    /// The route a drag will follow, resolved the way the actuator resolves it:
    /// an explicit path, otherwise the start point plus its delta.
    func cursorRoute(for step: ActionStep) -> [CGPoint] {
        if let path = step.path {
            let points = path.filter { $0.count >= 2 }.map { CGPoint(x: $0[0], y: $0[1]) }
            if points.count >= 2 { return points }
        }
        guard let start = cursorTarget(for: step), let delta = step.delta, delta.count >= 2 else {
            return []
        }
        return [start, CGPoint(x: start.x + delta[0], y: start.y + delta[1])]
    }

    /// Let the pointer fade, now that a batch of steps has finished.
    func restCursor() async {
        guard CursorOverlay.isEnabled else { return }
        await CursorOverlay.shared.idle()
    }
}
