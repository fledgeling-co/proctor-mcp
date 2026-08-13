import Foundation
import ProctorCore

// PRO-0010: composite a marker at a step's target point onto a per-step capture.
//
// The checkable geometry — which point a step acted on, and where it lands in the
// frame — lives in ProctorCore.PointerMarker; the drawing lives in
// MarkRenderer.renderPointer. This bridges them: it resolves the acted element's
// frame from the AX tree when the step targets a node, runs the placement, and
// draws. It is best-effort — the overlay is a cosmetic annotation, so a step whose
// target cannot be resolved or drawn yields no overlay rather than failing the
// capture. It marks where the step acted, never a live cursor: Proctor drives
// through AX / Apple Events and does not move the system pointer.

extension Session {

    func pointerOverlay(for step: ActionStep, window: WindowHandle,
                        capture result: CaptureResult) -> PointerOverlay? {
        // Resolve the acted element's screen frame only when the step needs it —
        // an explicit point is used as-is, matching how the actuator resolves a
        // gesture (point wins, else the element centre).
        let elementFrame: Rect?
        if step.point == nil, let node = step.node {
            elementFrame = (try? ax.node(id: node))?.frame
        } else {
            elementFrame = nil
        }

        guard let target = PointerMarker.targetPoint(for: step, elementFrame: elementFrame),
              let placement = PointerMarker.place(x: target.x, y: target.y,
                                                  window: window.frame,
                                                  imageWidth: result.width,
                                                  imageHeight: result.height,
                                                  scale: result.scale) else {
            return nil
        }

        guard let markedPath = try? MarkRenderer.renderPointer(
            basePath: result.path, width: result.width, height: result.height,
            scale: result.scale, placement: placement) else {
            return nil
        }

        return PointerOverlay(annotatedPath: markedPath,
                              pixelX: placement.pixelX, pixelY: placement.pixelY,
                              source: target.source.rawValue,
                              node: target.source == .element ? step.node : nil,
                              onFrame: placement.onFrame)
    }
}
