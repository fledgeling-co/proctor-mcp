import Foundation
import ProctorCore

// The run's side of the takeover: what raises the statement, what arms the
// block, and what makes sure both are down when the run is.
//
// Everything here is a no-op when the overlay is switched off, and the block is
// a further no-op unless an operator set `PROCTOR_TAKEOVER_INPUT`. A run whose
// overlay could not be drawn still runs; what must not happen is a run whose
// block could not be released.

/// What the session needs from the takeover, so a test can drive it without a
/// window server or an event tap.
protocol TakeoverDriving: Sendable {
    /// Somebody pressed the release chord, and somebody used the machine. Bound
    /// once per run so the block reaches this run's latch rather than a stale
    /// one.
    func bind(onStop: @escaping @Sendable () -> Void,
              onPersonInput: @escaping @Sendable () -> Void)
    func show(app: String?)
    func hide()
    func arm(seconds: Double)
    func release(_ reason: TakeoverRelease)
    func stopAll(_ reason: TakeoverRelease)
    func report(shown: Bool) -> TakeoverReport
    var isHolding: Bool { get }
    var unavailableReason: String? { get }
}

/// The real one: the panels on the main actor, the tap on its own thread.
struct LiveTakeover: TakeoverDriving {

    func bind(onStop: @escaping @Sendable () -> Void,
              onPersonInput: @escaping @Sendable () -> Void) {
        InputBlocker.shared.onStop = onStop
        InputBlocker.shared.onPersonInput = onPersonInput
    }

    // The panels are main-actor work and the run is not on the main actor, so
    // every raise and lower is handed over rather than waited on. A run must
    // never be slowed, let alone blocked, by an annotation.
    func show(app: String?) {
        Task { @MainActor in TakeoverOverlay.shared.show(app: app) }
    }

    func hide() {
        Task { @MainActor in TakeoverOverlay.shared.hide() }
    }

    func arm(seconds: Double) {
        InputBlocker.shared.arm(seconds: seconds)
        Task { @MainActor in TakeoverOverlay.shared.refresh() }
    }

    func release(_ reason: TakeoverRelease) {
        InputBlocker.shared.release(reason)
        Task { @MainActor in TakeoverOverlay.shared.refresh() }
    }

    func stopAll(_ reason: TakeoverRelease) { InputBlocker.shared.stopAll(reason) }

    func report(shown: Bool) -> TakeoverReport { InputBlocker.shared.takeReport(shown: shown) }

    var isHolding: Bool { InputBlocker.shared.isHolding }
    var unavailableReason: String? { InputBlocker.shared.unavailableReason }
}

extension Session {

    /// Whether this run has raised the statement yet. Per batch rather than per
    /// step: a full-screen tint flashing on and off between ten clicks is
    /// strobing, and strobing is worse than the thing it announces.
    func takeoverShow(app: String?) {
        guard !takeoverShown else { return }
        takeoverShown = true
        takeover.show(app: app)
    }

    /// Hold input for this step, if an operator asked for that. The deadline
    /// goes with it and is enforced by the block's own thread, so a step that
    /// throws between here and its release cannot leave input held.
    func takeoverArm(for step: ActionStep) {
        guard takeoverShown else { return }
        takeover.arm(seconds: Takeover.armSeconds(stepDurationMs: step.durationMs))
    }

    func takeoverRelease(_ reason: TakeoverRelease) {
        guard takeoverShown else { return }
        takeover.release(reason)
    }

    /// The run is over. Both halves come down, whatever the step-level
    /// accounting says, and the counters are read once.
    func takeoverEnd(stopped: Bool) -> TakeoverReport? {
        guard takeoverShown else { return nil }
        takeoverShown = false
        takeover.stopAll(stopped ? .stopped : .runEnded)
        takeover.hide()
        let report = takeover.report(shown: true)
        return report.shown ? report : nil
    }

    /// Wire the block to this run's latch. `RunControl.stop()` and the
    /// contention monitor's timestamp are both lock-and-return, which is what
    /// makes them safe to call from the tap's callback: anything that waited
    /// there would freeze the deadline timer and the release chord with it.
    func takeoverBind() {
        let control = runControl
        let monitor = contentionMonitor
        takeover.bind(onStop: { control.stop() },
                      onPersonInput: { monitor.noteUserInput() })
    }
}

extension Session {

    /// What `proctor_doctor` says about the takeover. Three facts a person
    /// deciding whether to trust an unattended run needs, and they are not the
    /// same fact: whether the statement is drawn, whether the block was asked
    /// for, and whether it is actually available.
    func takeoverStatus() -> JSONValue {
        var out: [String: JSONValue] = [
            "overlay": .bool(TakeoverOverlay.isEnabled),
            "inputBlockRequested": .bool(InputBlocker.isEnabled),
            "inputMonitoring": .string(Grants.inputMonitoringState())
        ]
        if let reason = takeover.unavailableReason {
            out["inputBlockAvailable"] = .bool(false)
            out["note"] = .string(reason)
        } else {
            out["inputBlockAvailable"] = .bool(InputBlocker.isEnabled)
            if !InputBlocker.isEnabled {
                out["note"] = .string("A foreground step says so on every display and leaves input "
                                    + "alone. Set PROCTOR_TAKEOVER_INPUT=1 to have Proctor also hold "
                                    + "the keyboard and mouse for the moments it is posting events; "
                                    + "Esc stops a run while it does.")
            }
        }
        return .object(out)
    }
}
