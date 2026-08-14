import Foundation
import ProctorCore

// The run's side of the HUD: what the panel is told, and where the run asks
// whether a person has stopped it.
//
// Everything here is a no-op when the panel is switched off, and every call is
// best-effort — the HUD is an annotation and a control, not a dependency. A run
// whose panel could not be drawn still runs; what it must not do is run while
// somebody believes they are holding a stop button that is not there, which is
// why `proctor_doctor` reports the panel's absence.
//
// The events all go through `runSteps`, which is the one code path a batch, a
// replayed flow, a stability sweep and the CUA façade all share. Showing the
// panel for one of them and not the others would make a stop control that is
// sometimes absent.

extension Session {

    /// Off switch, the drawn pointer's shape exactly and separate from it, so
    /// either can be left on alone.
    nonisolated static var hudEnabledByDefault: Bool {
        OverlaySwitch.isOn("PROCTOR_HUD", in: ProcessInfo.processInfo.environment)
    }

    /// Whether this step travels through the event stream, which is the one
    /// thing the panel ever says about a plane.
    static func isSynthetic(_ step: ActionStep) -> Bool {
        syntheticKinds.contains(step.kind)
    }

    /// The element a step names, for the description's object. Resolved once per
    /// step and handed to every line about it, so the live line, the trail row
    /// and the refusal all name the same thing.
    func hudNode(for step: ActionStep) -> AXNode? {
        guard let id = step.node else { return nil }
        return try? ax.node(id: id)
    }

    func hud(_ event: RunHUDEvent) async {
        guard drawsHUD else { return }
        await RunHUDPanel.shared.apply(event)
    }

    /// Show the panel for a batch about to run, on the screen holding the driven
    /// window.
    func hudRunBegan(total: Int, window: WindowHandle) async {
        guard drawsHUD else { return }
        let app = appHandle(forWindow: window)?.name
        await RunHUDPanel.shared.begin(total: total, app: app, window: window.frame)
    }

    /// A whole run is starting, so nobody's hand is on it yet. Deliberately not
    /// in `runSteps`: a stability sweep runs `runSteps` once per pass, and
    /// resetting there would let a sweep sail on past the Stop somebody pressed
    /// during pass two. Pause and Stop act on the run the panel is showing, and
    /// a sweep is one run.
    func hudRunControlBegin() {
        // Not gated on the panel. The panel is one way to set the latch, not the
        // latch itself, and a stale decision from a finished run must not carry
        // into the next one whether or not anything is on screen.
        runControl.begin()
    }

    /// What `proctor_doctor` says about the panel.
    func hudStatus() -> JSONValue {
        guard drawsHUD else {
            return .object([
                "enabled": .bool(false),
                "available": .bool(false),
                "note": .string("The run HUD is switched off by PROCTOR_HUD, so a run shows no "
                              + "panel and there is no Pause or Stop control on screen. Runs are "
                              + "unaffected. Unset PROCTOR_HUD to bring it back.")
            ])
        }
        let status = RunHUDAvailability.shared.status
        var out: [String: JSONValue] = [
            "enabled": .bool(true),
            "onScreen": .bool(status.available),
            "available": .bool(status.reason == nil),
            "pauseLimitSeconds": .number(runControl.pauseLimit)
        ]
        if let reason = status.reason {
            out["note"] = .string("The run HUD could not be drawn (\(reason)). Runs still proceed, "
                                + "but there is no Pause or Stop control on screen.")
        }
        return .object(out)
    }

    /// Ask whether a person has halted the run. Nil means carry on.
    func haltCheckpoint() async -> RunControl.Halt? {
        await runControl.checkpoint()
    }
}
