import Foundation

// Where the drawn pointer belongs in the stack.
//
// The pointer is an annotation of one window's activity, not a thing sitting on
// top of the machine. Drawn at a high window level it appears above whatever a
// person is actually looking at, which reads as Proctor clicking their
// foreground app while it is in fact driving something else entirely — the one
// picture the overlay must never paint, because it is a lie about what the
// agent is doing to somebody's computer.
//
// The truthful position is the target window's own plane: immediately above it,
// below everything stacked over it, so a window covering the target covers the
// pointer too. macOS gives a panel a *level*, not a position in another
// application's stacking order, so this is reached by ordering the panel
// relative to a `CGWindowID` belonging to another process — measured working on
// macOS 26.6 and verified per use rather than assumed, because it is not a
// documented capability. The measurement is recorded in `CursorOverlay`.
//
// Three outcomes, and the two that are not the happy path both refuse to
// overstate: a target nobody can see gets no pointer at all, and a target whose
// plane cannot be established gets a pointer that is visibly marked as not
// vouching for its position.

/// Where the pointer should be drawn for one step.
public enum PointerPlane: Equatable, Sendable {
    /// Restack the panel immediately above this window and draw normally.
    case inPlane(above: UInt32)
    /// The plane could not be established. Draw at the floating level, dimmed
    /// and marked, so the pointer does not claim a position it does not hold.
    case floatingDimmed
    /// Nothing to annotate: the target is not on screen. Draw nothing.
    case hidden
}

public enum PointerPlanePolicy {

    /// How much of the pointer's opacity survives when its plane is unverified.
    /// Low enough to read as a different state at a glance, high enough that the
    /// glyph is still legible — it is marking uncertainty, not hiding.
    public static let dimmedOpacity: Float = 0.32

    /// The plane for a step, from what is known about its target window.
    ///
    /// `targetIsOnScreen` is the window list's answer, not accessibility's: a
    /// window minimised, hidden, or on another Space is absent from the
    /// on-screen list, and all three mean the same thing here — there is nothing
    /// on the screen in front of somebody for this pointer to annotate.
    public static func decide(targetWindowID: UInt32?, targetIsOnScreen: Bool) -> PointerPlane {
        guard targetIsOnScreen else { return .hidden }
        guard let id = targetWindowID, id != 0 else { return .floatingDimmed }
        return .inPlane(above: id)
    }

    /// Did the restack actually hold? `order` is the on-screen window list,
    /// front to back, read back after the ordering call.
    ///
    /// Immediately above, not merely somewhere above. A window sitting between
    /// the panel and its target would be drawn *under* the pointer while being
    /// *over* the target, which is a smaller version of the same misstatement.
    /// Being strict costs an occasional demotion to the dimmed treatment, which
    /// is the safe direction to be wrong in.
    public static func held(panel: UInt32, above target: UInt32, order: [UInt32]) -> Bool {
        guard let p = order.firstIndex(of: panel), let t = order.firstIndex(of: target) else {
            return false
        }
        return t == p + 1
    }
}
