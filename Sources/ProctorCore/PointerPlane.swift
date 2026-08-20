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
//
// **"Nobody can see it" includes covered, and that was reported rather than
// reasoned.** From real use: "sometimes I'll see the fake cursor moving during
// testing, but the app it's working on is in the background and not visible,
// which makes the fake cursor's operation confusing." The window list called
// that target on screen, so the plane was attempted; when the restack did not
// hold, the pointer fell back to floating above everything — which is precisely
// the picture the paragraph above says must never be painted, with the dimming
// standing in for not painting it. Dimming marks uncertainty about a POSITION.
// It cannot mark a pointer that is in the wrong plane entirely, because there is
// no honest place on screen for an annotation of a window the person cannot see.
//
// So the fallback is split by whether anything covers the target. Uncovered and
// unverified is still `floatingDimmed`: the pointer is where it would be anyway,
// and the dimming says the exact ordering is unconfirmed. Covered is `hidden`.

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
    /// `targetIsCovered` is whether another window sits over the target. A
    /// covered target has no honest pointer: drawn in plane it would be hidden
    /// by the covering window, and drawn floating it would appear over the
    /// window the person is actually looking at.
    public static func decide(targetWindowID: UInt32?, targetIsOnScreen: Bool,
                              targetIsCovered: Bool = false) -> PointerPlane {
        guard targetIsOnScreen else { return .hidden }
        guard let id = targetWindowID, id != 0 else {
            return targetIsCovered ? .hidden : .floatingDimmed
        }
        return .inPlane(above: id)
    }

    /// What to do when a restack did not hold.
    ///
    /// The same split, at the other end: the ordering call has already been made
    /// and read back, so this is asked with the window order in hand rather than
    /// with a flag somebody computed earlier.
    public static func fallback(target: UInt32, order: [UInt32],
                                ours: Set<UInt32> = []) -> PointerPlane {
        isCovered(target: target, order: order, ignoring: ours) ? .hidden : .floatingDimmed
    }

    /// Whether anything is drawn over the target, from the on-screen window
    /// list, front to back.
    ///
    /// Panels belonging to this process are not counted: the pointer's own
    /// surfaces and the run panel sit above the target by design, and treating
    /// Proctor's own annotations as "something covering it" would hide the
    /// pointer from every target it ever annotates.
    public static func isCovered(target: UInt32, order: [UInt32],
                                 ignoring ours: Set<UInt32> = []) -> Bool {
        guard let index = order.firstIndex(of: target) else { return true }
        return order[..<index].contains { !ours.contains($0) }
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
