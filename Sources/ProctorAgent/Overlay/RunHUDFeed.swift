import Foundation
import ProctorCore

// Where the run HUD's state actually lives.
//
// It used to live on `RunHUDPanel`, on the main actor, which made the view the
// source of truth. That was wrong in the one case that matters most: with
// `PROCTOR_HUD=0` no panel is ever built, and that is precisely the launch with
// no Pause and no Stop anywhere on screen — the launch whose state the menu bar
// most needs to be able to report. A reducer that only runs when something is
// drawing cannot serve a surface in another process.
//
// So the reduction happens here, behind a lock, readable from any thread and
// from any process that can reach the agent's socket. Two things consume it and
// neither derives a second one:
//
//   the panel, which renders this model and owns nothing but pixels; and
//   `proctor_recent_activity`, which projects the phase onto the socket the menu
//   bar already polls.
//
// The lock is held for a reduction or a field read and never across an await, in
// the same shape `RunControl` and `RunHUDAvailability` use, for the same reason:
// a person's click arrives on the main thread while the run reads from inside an
// actor, and neither may block the other.
final class RunHUDFeed: @unchecked Sendable {

    static let shared = RunHUDFeed()

    /// What the menu bar is told. Everything a second surface needs and nothing
    /// that only means something to a panel.
    struct Snapshot: Sendable, Equatable {
        /// The phase to draw. Rested to `idle` once the run's linger is over, so
        /// a finished run's tick is held exactly as long as the panel holds it
        /// and no longer.
        var phase: RunHUDPhase
        /// Whether a run is actually in flight, which is what makes Pause and
        /// Stop mean anything.
        var running: Bool
        /// Whether the panel is currently allowed on screen.
        var drawing: Bool
        /// Whether it *could* be, if somebody asked. False on an agent that was
        /// launched with the HUD off, because that launch runs a bare run loop
        /// and a panel drawn under it has buttons nobody can press.
        var canShow: Bool
    }

    private let lock = NSLock()
    private var state = RunHUDState()
    private var drawingFlag: Bool
    private var canShowFlag = false
    /// The driven window the panel was last placed against, so a panel brought
    /// back mid-run lands where it would have been rather than in a corner.
    private var lastWindow: Rect?

    init(drawing: Bool = OverlaySwitch.isOn("PROCTOR_HUD",
                                            in: ProctorEnvironment.current)) {
        self.drawingFlag = drawing
    }

    // MARK: - Reducing

    /// Reduce an event and hand back the resulting model. Always runs, whether
    /// or not anything is drawn.
    @discardableResult
    func apply(_ event: RunHUDEvent) -> RunHUDModel {
        lock.lock(); defer { lock.unlock() }
        state.apply(event)
        return state.model
    }

    @discardableResult
    func setQueue(_ queue: RunQueueModel) -> RunHUDModel {
        lock.lock(); defer { lock.unlock() }
        state.setQueue(queue)
        return state.model
    }

    var model: RunHUDModel {
        lock.lock(); defer { lock.unlock() }
        return state.model
    }

    // MARK: - The switch

    /// Whether the panel may be on screen. Seeded from `PROCTOR_HUD` and moved
    /// by the menu bar, which is what makes the two the same switch rather than
    /// two switches a person has to remember the difference between.
    var drawing: Bool {
        lock.lock(); defer { lock.unlock() }
        return drawingFlag
    }

    func setDrawing(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        drawingFlag = on
    }

    /// Set once, when the agent enters AppKit's event loop.
    func setCanShow(_ can: Bool) {
        lock.lock(); defer { lock.unlock() }
        canShowFlag = can
    }

    var canShow: Bool {
        lock.lock(); defer { lock.unlock() }
        return canShowFlag
    }

    func rememberWindow(_ rect: Rect) {
        lock.lock(); defer { lock.unlock() }
        lastWindow = rect
    }

    var window: Rect? {
        lock.lock(); defer { lock.unlock() }
        return lastWindow
    }

    // MARK: - What leaves the process

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(phase: state.model.menuBarPhase,
                        running: state.model.visible,
                        drawing: drawingFlag,
                        canShow: canShowFlag)
    }

    /// The snapshot as the socket carries it. One shape, written once, so the
    /// menu bar and any later reader are reading the same words.
    var wire: JSONValue {
        let now = snapshot
        return .object([
            AgentVerbs.HUD.phase: .string(now.phase.rawValue),
            AgentVerbs.HUD.running: .bool(now.running),
            AgentVerbs.HUD.drawing: .bool(now.drawing),
            AgentVerbs.HUD.canShow: .bool(now.canShow)
        ])
    }

    /// Why Show is unavailable. Nil when it is available.
    ///
    /// It names what is actually true — no application event loop — rather than
    /// only the setting that causes it in practice, because the two are not the
    /// same claim and a report should not assert a cause it has not checked.
    var showRefusal: String? {
        guard !canShow else { return nil }
        return "this agent is not running an application event loop, so a panel drawn now would "
             + "have Pause and Stop that cannot receive a click. That is what starting with "
             + "PROCTOR_HUD off does; unset it and restart the agent to bring the panel back."
    }

    /// Reset, for a test that wants a clean reducer.
    func reset(drawing: Bool) {
        lock.lock(); defer { lock.unlock() }
        state = RunHUDState()
        drawingFlag = drawing
        canShowFlag = false
        lastWindow = nil
    }
}

/// A holder so the session's feed can be swapped without the session having to
/// be isolated to read it. One reference, set once at start-up in a test and
/// never at all in production, where it is already the shared feed.
final class HUDFeedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: RunHUDFeed = .shared

    var feed: RunHUDFeed {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); defer { lock.unlock() }; current = newValue }
    }
}
