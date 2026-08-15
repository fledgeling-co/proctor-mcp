import Foundation
import ProctorCore

// Where the run panel is, readable from off the main actor.
//
// TWO READERS THAT CANNOT ASK APPKIT. The session actor decides before each step
// whether the panel is standing where the step is about to post, and the event
// tap's callback decides whether a click landed on Stop. Neither may touch
// `NSWindow`: one is an actor off the main thread, and the other is a
// `.defaultTap` callback that macOS disables if it does not answer promptly —
// hopping to main from there would freeze the deadline timer and the release
// chord, which is PRO-0026's one way for both its invariants to fail without the
// process dying.
//
// So the panel pushes its geometry here whenever it moves, and both readers copy
// a value out under a lock and return. Nothing is held across any work and this
// lock is shared with nothing that hops to main.
//
// EVERYTHING IS PUBLISHED IN QUARTZ SCREEN SPACE, y down from the top of the
// primary display, converted once here by the only party that has an `NSScreen`
// to convert against. That is the space the actuator posts in and the space
// `CGEvent.location` reports, so neither reader converts anything and there is
// no second flip to get wrong.
final class RunHUDGeometry: @unchecked Sendable {

    static let shared = RunHUDGeometry()

    private let lock = NSLock()
    private var panel: Rect?
    private var stop: Rect?

    /// The panel moved, was placed, or changed height.
    func publish(panel: Rect, stop: Rect?) {
        lock.lock(); defer { lock.unlock() }
        self.panel = panel
        self.stop = stop
    }

    /// The panel is off screen — hidden, taken down after a drawing fault, or the
    /// run ended. Cleared rather than left stale: a stale Stop rectangle is a
    /// click on empty screen stopping a run, which is the one way this fails
    /// badly.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        panel = nil
        stop = nil
    }

    /// The panel's whole frame, for the mouse gate.
    var panelFrame: Rect? {
        lock.lock(); defer { lock.unlock() }
        return panel
    }

    /// The Stop control's rectangle, for the tap.
    var stopRect: Rect? {
        lock.lock(); defer { lock.unlock() }
        return stop
    }
}

// MARK: - The declaration

/// Proctor is about to put an event into the stream, said before it posts rather
/// than reported when `perform` returns.
///
/// PRO-0019 logged this as the reason a `type` or `scroll` that falls back
/// cannot be announced in the present tense: the actuator reported its plane
/// only on return, so nothing before that moment knew the step had gone to the
/// event stream. The grace window, the takeover statement and the input block
/// all had to guess from the step's kind, and all three were wrong about a
/// fallback.
///
/// The declaration is made at ONE choke point —
/// `Actuator.requireEventPlaneAvailable()` — which every synthetic route passes
/// immediately before it posts, after `activate(pid)` and after every
/// accessibility route has been tried and refused. Two properties follow, and
/// both matter:
///
///   * A declaration cannot precede an accessibility success, because the
///     accessibility routes are already behind it. So the declaration and the
///     measured plane cannot disagree in the direction that would leave the
///     panel stepped aside for a step that never posted.
///   * A future synthetic route cannot forget it, because forgetting it would
///     also forget the Secure Event Input check that lives in the same guard.
///     The two travel together or neither does.
///
/// `inFlight` is what makes "Proctor's own click can never press Stop"
/// structural rather than an identity check: our click happens inside our own
/// declared post, so the tap declines to read the Stop rectangle at all while
/// one is open.
final class SyntheticPost: @unchecked Sendable {

    static let shared = SyntheticPost()

    private let lock = NSLock()
    private var declaredAt: Double?
    private var declared = false
    private var handler: (@Sendable () -> Void)?

    var now: @Sendable () -> Double = { Date().timeIntervalSince1970 }

    /// Installed by the session at run start, cleared at run end. It must not
    /// wait on anything: it is called on the actuation thread with a post about
    /// to happen.
    func onDeclare(_ handler: (@Sendable () -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }

    /// Called from the actuator's choke point. Opens the window and runs the
    /// handler outside the lock.
    func declare() {
        lock.lock()
        declaredAt = now()
        declared = true
        let handler = self.handler
        lock.unlock()
        handler?()
    }

    /// A step is starting: forget the last one's declaration.
    func beginStep() {
        lock.lock(); defer { lock.unlock() }
        declaredAt = nil
        declared = false
    }

    /// The step is over, however it ended. Closed unconditionally rather than
    /// counted down, because a window held open by an accounting mistake — a
    /// throw between the declaration and the release — would leave the tap
    /// unable to read a Stop press for the rest of the run, which is this
    /// feature failing in exactly the way it exists to prevent.
    func endStep() {
        lock.lock(); defer { lock.unlock() }
        declaredAt = nil
    }

    /// Whether the step that just ran actually entered the event stream. What
    /// makes the run's account of having taken the machine true for a `type` or
    /// `scroll` that fell back, which nothing knew before the step returned.
    var declaredThisStep: Bool {
        lock.lock(); defer { lock.unlock() }
        return declared
    }

    /// Whether Proctor put something into the stream in the last moment.
    ///
    /// BOUNDED IN TIME, NOT TO THE STEP, and the difference is a defect the
    /// completeness gate caught. While this is true the tap declines to read the
    /// run panel's Stop rectangle, which is what makes "our own click can never
    /// press Stop" structural. Held for the whole of a step, a `dragPath` — which
    /// the actuator clamps at thirty seconds — would leave Stop unreadable by
    /// mouse for half a minute, and a long gesture is exactly the step PRO-0026
    /// says must stay stoppable throughout.
    ///
    /// So it is the same quarter second `PersonInput` already uses to keep an
    /// application's echo of our own click from reading as a person. It covers
    /// the instant our event is actually delivered, which is the only instant
    /// the structural rule is protecting; everything outside it is covered by
    /// `InputBlock.isOurs`, which is tested first in any case.
    var inFlight: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let declaredAt else { return false }
        return now() - declaredAt < PersonInput.graceSeconds
    }
}
