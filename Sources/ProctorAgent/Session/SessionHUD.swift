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
    ///
    /// Asked of the selected backend rather than of a table of kinds: since
    /// PRO-0044 a click is not inherently a foreground event, it is one on a
    /// backend that can only express it that way.
    func isSynthetic(_ step: ActionStep) -> Bool {
        actuator.backgroundCapability(for: step.kind) == .never
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
    func hudRunBegan(total: Int, window: WindowHandle,
                     demand: ForegroundDemand = ForegroundDemand(),
                     delegated: Bool = false) async {
        guard drawsHUD else { return }
        let app = appHandle(forWindow: window)?.name
        await RunHUDPanel.shared.begin(total: total, app: app, window: window.frame,
                                       foreground: demand, delegated: delegated)
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
        //
        // Keyed by this call's own ticket, so it clears this run's automatic
        // hold and nobody else's. `RunScheduler.acquire` does not consult the
        // latch, so a run on a free app lane starts while another is yielded —
        // and an unconditional reset here lifted that run's hold from under it.
        runControl.begin(run: RunScheduler.currentRun)
    }

    /// What `proctor_doctor` says about the panel.
    ///
    /// Three states, and a person deciding whether to trust an unattended run has
    /// to be able to tell them apart: drawn, hidden from the menu bar with the
    /// controls still reachable there, and switched off at launch with no panel
    /// this launch at all.
    func hudStatus() -> JSONValue {
        let feed = hudFeed
        let status = RunHUDAvailability.shared.status
        var out: [String: JSONValue] = [
            "enabled": .bool(feed.drawing),
            "onScreen": .bool(status.available),
            // Whether there is actually a working stop control on screen. Every
            // one of the four ways there is not — switched off at launch, hidden
            // from the menu bar, no event loop to deliver a click, a drawing
            // fault — answers false here, because a person reading this is asking
            // one question and it is that one.
            "available": .bool(feed.drawing && feed.canShow && status.reason == nil),
            "canShow": .bool(feed.canShow),
            "pauseLimitSeconds": .number(runControl.pauseLimit)
        ]
        // Four different absences, and a person deciding whether to trust an
        // unattended run has to be able to tell them apart. `drawing` is the
        // switch; `canShow` is whether this process could draw a panel whose
        // buttons work at all.
        switch (feed.drawing, feed.canShow) {
        case (false, false):
            out["note"] = .string("The run panel is switched off by PROCTOR_HUD, so this run shows "
                                + "no panel and there is no Pause or Stop control on screen. Runs "
                                + "are unaffected, and Proctor's menu bar still shows what the run "
                                + "is doing. Unset PROCTOR_HUD and restart the agent to bring the "
                                + "panel back.")
        case (false, true):
            out["note"] = .string("A person hid the run panel from Proctor's menu bar, so there is "
                                + "no Pause or Stop control on screen. Both are in Proctor's menu "
                                + "bar while a run is going, and Show Run Panel brings the panel "
                                + "back.")
        case (true, false):
            out["note"] = .string("This process is not running an application event loop, so a "
                                + "panel drawn now would have Pause and Stop that cannot receive a "
                                + "click, and none is drawn. Runs are unaffected.")
        case (true, true):
            if let reason = status.reason {
                out["note"] = .string("The run HUD could not be drawn (\(reason)). Runs still "
                                    + "proceed, but there is no Pause or Stop control on screen.")
            }
        }
        return .object(out)
    }

    /// The internal `proctor_hud` verb: the menu bar's side of the panel.
    ///
    /// Never in `ToolCatalogue`, so the public tool count is unchanged and the
    /// shim — which gates `tools/call` on the catalogue — cannot reach it. Only a
    /// local process of the same user can, which is the same boundary
    /// `proctor_recent_activity` already sits behind.
    ///
    /// Every action answers with the resulting state, so the menu updates on the
    /// reply rather than on the next poll.
    func hudControl(_ action: RunHUDControl?) async throws -> JSONValue {
        guard let action else {
            throw AgentError(
                code: .invalidArguments,
                message: "proctor_hud needs an action",
                remedy: "Pass action as one of: "
                      + RunHUDControl.allCases.map(\.rawValue).joined(separator: ", "))
        }
        let feed = hudFeed
        var refused: String?

        // Pause, Resume and Stop act on a run, so with no run in flight they are
        // refused rather than reduced. Latching a stop against nothing would put a
        // "Stopped by a person" ending on a panel that was not running, and the
        // menu bar would report an ending nobody caused.
        guard !action.needsRun || feed.snapshot.running else {
            return .object([
                "hud": feed.wire,
                "refused": .string("there is no run in flight, so there is nothing to "
                                 + "\(action.rawValue).")
            ])
        }

        switch action {
        case .show:
            if let reason = feed.showRefusal {
                refused = reason
            } else if !feed.drawing {
                RunHUDPanel.audit("proctor_hud.show",
                                  detail: "a person brought Proctor's run panel back from the "
                                        + "menu bar, so Pause and Stop are on screen again")
                feed.setDrawing(true)
                await RunHUDPanel.shared.drawingChanged()
            }
        case .hide:
            if feed.drawing {
                RunHUDPanel.audit("proctor_hud.hide",
                                  detail: "a person hid Proctor's run panel from the menu bar, so "
                                        + "Pause and Stop are in the menu bar rather than on "
                                        + "screen")
                feed.setDrawing(false)
                await RunHUDPanel.shared.drawingChanged()
            }
        case .pause:
            runControl.pause()
            feed.apply(.paused(step: nil, node: nil))
            await RunHUDPanel.shared.refresh()
        case .resume:
            runControl.resume()
            // The override that keeps Resume from being undone on the next
            // poll is recorded by `runControl.resume()` itself, so it holds for
            // the panel's own button too — that one reaches for the shared latch
            // and never comes through here.
            feed.apply(.resumed)
            await RunHUDPanel.shared.refresh()
        case .stop:
            runControl.stop()
            // The same ending the panel's own Stop reduces: grey, not red. Red is
            // for something going wrong; a person deciding to stop went right.
            feed.apply(.runEnded(.stoppedByPerson))
            await RunHUDPanel.shared.refresh()
        }

        var out: [String: JSONValue] = ["hud": feed.wire]
        if let refused { out["refused"] = .string(refused) }
        return .object(out)
    }

    /// Ask whether a person has halted the run. Nil means carry on. The probe is
    /// where contention is read — see `Session.contentionProbe`.
    ///
    /// Keyed by this call's ticket: a person's Pause holds every run, an
    /// automatic yield holds only the run that read it.
    func haltCheckpoint(probe: (@Sendable () async -> Void)? = nil) async -> RunControl.Halt? {
        await runControl.checkpoint(run: RunScheduler.currentRun, probe: probe)
    }

    /// Proctor is about to post, or has just posted, a synthetic event. Opens
    /// the grace window the input monitor discards arrivals inside.
    func noteSyntheticPost() {
        contentionMonitor.noteSyntheticPost()
    }
}
