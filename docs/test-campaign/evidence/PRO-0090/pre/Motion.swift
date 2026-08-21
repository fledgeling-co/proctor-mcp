import SwiftUI

/// The mock's motion system in one place, so every surface springs the same way.
///
/// Everything is `cubic-bezier(.32, .72, 0, 1)` — a soft spring that settles
/// without overshoot — at three durations, and every animated property is a
/// transform or an opacity so nothing triggers layout. Reduced-motion is honoured
/// at each call site by passing `nil` instead of one of these.
enum Motion {
    static let fast = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.15)
    static let med  = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.25)
    static let slow = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.40)
    /// Step-to-step slide, matching the mock's .34s content entrance.
    static let step = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.34)
}

/// A 15px directional slide + fade, the mock's `enter-fwd` / `enter-back`.
/// A full `.move(edge:)` travels the whole width, which is too far in a 620pt
/// window; this is the small nudge the mock actually uses.
extension AnyTransition {
    static func slideNudge(from edge: HorizontalEdge) -> AnyTransition {
        let dx: CGFloat = edge == .trailing ? 15 : -15
        return .asymmetric(
            insertion: .modifier(active: Nudge(dx: dx, opacity: 0),
                                 identity: Nudge(dx: 0, opacity: 1)),
            removal: .opacity)
    }
}

private struct Nudge: ViewModifier {
    let dx: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.offset(x: dx).opacity(opacity)
    }
}
