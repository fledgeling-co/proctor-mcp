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
    ///
    /// `owner` is this run's answer to which of two pointers draws (PRO-0046).
    /// Standing down returns before the window-list read, so a delegated run that
    /// deferred costs exactly what `PROCTOR_CURSOR=0` costs: nothing.
    func showCursor(for step: ActionStep, window: WindowHandle,
                    owner: PointerOwner = .proctor) async {
        // THE CEILING WAVE 9'S COVERED-TARGET RULE STOPS AT (PRO-0084, REQ-072).
        //
        // Below this line every plane decision is about a panel THIS process
        // owns: `cursorPlane` reads the window list, `CursorOverlay.applyPlane`
        // restacks and reads back, and `PointerPlanePolicy.fallback` hides the
        // pointer when something covers the target. All three act by moving or
        // hiding Proctor's own panel.
        //
        // A driver's cursor is another process's drawing. Proctor can neither
        // place it in the target's plane nor hide it when the target is covered,
        // so the rule cannot be carried across this return — not because nobody
        // wired it, but because there is nothing here to place or hide. What
        // Proctor CAN still do is say so, and `RunHUDEvent.pointerDeferred` does
        // that at the run's one decision point.
        //
        // This is recorded as a ceiling rather than worked around. The two
        // workarounds both make things worse: drawing a Proctor pointer anyway
        // puts two cursors on one screen, which `PointerOwner` refuses on the
        // grounds that a reader then cannot tell which one the machine follows;
        // and drawing one only when the driver's is believed absent rests on a
        // belief about another process that Proctor never observes.
        guard owner == .proctor else { return }
        guard CursorOverlay.isEnabled else { return }
        let target = cursorTarget(for: step)
        let plane = cursorPlane(for: window, at: target)

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

    /// Where this window's pointer belongs, correlating CGWindowList bounds,
    /// layers, and pointer coordinates. An occluded window or target point
    /// resolves to `.hidden` so no pointer is drawn over a window the person
    /// cannot see.
    func cursorPlane(for window: WindowHandle, at point: CGPoint? = nil) -> PointerPlane {
        guard let windowID = window.cgWindowID else {
            return .hidden
        }
        let records = CGWindowIndex.records(option: .optionOnScreenOnly)
        let onScreen = records.contains { $0.number == windowID }
        guard onScreen else { return .hidden }

        let windowEntries = records.map {
            WindowOcclusionEntry(
                windowID: $0.number,
                pid: $0.pid,
                bounds: Rect(x: Double($0.bounds.origin.x),
                             y: Double($0.bounds.origin.y),
                             w: Double($0.bounds.size.width),
                             h: Double($0.bounds.size.height)),
                layer: $0.layer,
                alpha: 1.0,
                isOnScreen: true
            )
        }

        let occlusion = WindowOcclusionDetector.evaluate(
            targetID: windowID,
            targetPoint: point.map { Point(x: Double($0.x), y: Double($0.y)) },
            windows: windowEntries,
            ignoring: []
        )

        if occlusion.isOccluded {
            return .hidden
        }

        return PointerPlanePolicy.decide(targetWindowID: windowID,
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
