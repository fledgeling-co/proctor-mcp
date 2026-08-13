import Foundation

// Pointer-overlay placement. This is the checkable half of PRO-0010: given the
// point a step acted on and the pixel dimensions of the frame that was captured,
// it decides where a marker lands in the image. The pixel compositing that
// follows (MarkRenderer.renderPointer) is mechanical; getting the target choice
// or the transform wrong is what would draw the marker in the wrong place, so
// that arithmetic lives here, away from any window or grant, where it can be
// tested directly. It mirrors how SetOfMarks and RegionCrop keep the placement
// maths in Core rather than in the agent.
//
// Honesty note carried through the whole feature: Proctor drives via AX / Apple
// Events and does not move the system cursor, so this marks *where the step
// acted*, a pixel-plane annotation of the intended target — never a picture of a
// live cursor.

public enum PointerMarker {

    /// Which resolution produced the target point, for the map back and for a
    /// human reading the artifact.
    public enum Source: String, Sendable, Equatable {
        case point      // the step carried an explicit [x, y]
        case element    // the target was the centre of the acted element's frame
    }

    /// The point a step acted on, in screen points, and how it was resolved.
    public struct Target: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var source: Source
        public init(x: Double, y: Double, source: Source) {
            self.x = x; self.y = y; self.source = source
        }
    }

    /// Where the marker is drawn, in frame pixels, plus whether the target fell
    /// inside the captured frame. When it did not, the pixel is clamped to the
    /// nearest edge and `onFrame` is false: an action just off the captured frame
    /// stays visible at the edge and is flagged, rather than vanishing.
    public struct Placement: Sendable, Equatable {
        public var pixelX: Double
        public var pixelY: Double
        public var onFrame: Bool
        public init(pixelX: Double, pixelY: Double, onFrame: Bool) {
            self.pixelX = pixelX; self.pixelY = pixelY; self.onFrame = onFrame
        }
    }

    /// The point a step acted on, mirroring how the actuator resolves a synthetic
    /// gesture: an explicit `point` wins, otherwise the acted element's frame
    /// centre. Both are screen points — `step.point` is posted straight to
    /// CGEventPost and an AX frame is in screen points — so the two agree with the
    /// space `place` expects. A step that carries neither a point nor a framed
    /// element (a bare `type` or `key`) has no place that was acted on, so it
    /// marks nothing and returns nil.
    public static func targetPoint(for step: ActionStep, elementFrame: Rect?) -> Target? {
        if let p = step.point, p.count >= 2 {
            return Target(x: p[0], y: p[1], source: .point)
        }
        if let frame = elementFrame, frame.w > 0, frame.h > 0 {
            return Target(x: frame.x + frame.w / 2, y: frame.y + frame.h / 2, source: .element)
        }
        return nil
    }

    /// Screen point to frame pixel, the one transform the overlay turns on:
    /// subtract the window origin, scale. Identical to `SetOfMarks.toPixels` so a
    /// pointer marker and a set-of-marks box place the same coordinate in the same
    /// spot. A frame with no pixels has nowhere to draw and returns nil; a target
    /// outside the frame is clamped to the nearest edge with `onFrame` false.
    public static func place(x: Double, y: Double, window: Rect,
                             imageWidth: Int, imageHeight: Int, scale: Double) -> Placement? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let s = scale > 0 ? scale : 1
        let px = (x - window.x) * s
        let py = (y - window.y) * s

        let maxX = Double(imageWidth) - 1
        let maxY = Double(imageHeight) - 1
        let clampedX = min(max(px, 0), maxX)
        let clampedY = min(max(py, 0), maxY)
        let onFrame = px >= 0 && px <= maxX && py >= 0 && py <= maxY
        return Placement(pixelX: clampedX, pixelY: clampedY, onFrame: onFrame)
    }
}
