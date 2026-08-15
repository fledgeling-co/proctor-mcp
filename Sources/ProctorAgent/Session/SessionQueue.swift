import Foundation
import ProctorCore

// The run's side of the scheduler: where a call takes its lanes, and where it
// gives them back.
//
// TAKEN ONCE FOR A WHOLE CALL, NEVER PER STEP AND NEVER PER PASS. This is the
// point of the whole feature: splitting a six-step login across two sessions'
// interleaved turns is exactly the failure the queue exists to prevent, so the
// four entry points below take their lanes here — outside `runSteps`, which a
// stability sweep enters once per repeat — and hold them until the call returns.
//
// AFTER THE PERMISSION GATE, NEVER BEFORE IT. A run the policy gate refuses
// never takes a place in the line: it was never going to drive anything, and a
// refused run holding a lane would make somebody else wait for nothing. The gate
// reads configured settings and a session token and touches no window, so
// running it first costs nothing.

extension Session {

    /// The lanes a batch needs, decided before it starts from its own steps and
    /// from whether it asked for the app in front. Both are known without
    /// touching anything, which is what makes this schedulable rather than
    /// guesswork.
    func lanes(for steps: [ActionStep], window: WindowHandle, foreground: Bool) -> LaneDemand {
        // `LaneDemand` answers this through `ForegroundDemand.takesForeground`,
        // which is the same question the panel and the menu bar ask. The
        // conditional kinds go with it so the predicate can tell a `foreground`
        // batch that could post from one that asked out of habit: see the note
        // there.
        LaneDemand.forBatch(kinds: steps.map(\.kind),
                            synthetic: Self.syntheticKinds,
                            conditional: Self.conditionalKinds,
                            app: window.app,
                            foreground: foreground)
    }

    /// Take the lanes, run, and give them back however it ends.
    ///
    /// `defer` cannot await, so the release is spelled out on both exits rather
    /// than hidden — and `LaneTicket`'s own teardown releases again as a backstop,
    /// idempotently, so a lane comes back even if this frame never runs to either
    /// of them. A leaked hold wedges the machine until Proctor restarts, which is
    /// the one failure worse than the interleaving this replaces.
    func scheduled<T>(lanes: LaneDemand, summary: String,
                      _ body: () async throws -> T) async throws -> T {
        // A nested acquisition would wait on lanes this task already holds and
        // hang with nothing on screen to explain it. Nothing nests today; the
        // guard is what keeps that true.
        guard !RunScheduler.holdingLanes else { return try await body() }

        let scheduler = runScheduler
        let ticket = try await scheduler.acquire(lanes: lanes,
                                                 identity: SessionIdentity.current,
                                                 summary: summary)
        do {
            // Both task-locals in one chain: the guard that stops a nested
            // acquisition, and the ticket id anything inside the run needs to
            // name the run it is in. A hold decided six awaits deep still knows
            // which queue row it belongs to.
            let out = try await RunScheduler.$holdingLanes.withValue(true) {
                try await RunScheduler.$currentRun.withValue(ticket.id) { try await body() }
            }
            await scheduler.release(ticket)
            return out
        } catch {
            await scheduler.release(ticket)
            throw error
        }
    }

    /// What `proctor_doctor` says about contention. A wedged lane is otherwise
    /// invisible — every later call simply fails as busy with nothing to point at.
    func queueStatus() async -> JSONValue {
        let snapshot = await runScheduler.snapshot()
        let now = Date().timeIntervalSince1970
        let lanes = snapshot.laneReport.map { entry in
            JSONValue.object([
                "lane": .string(entry.lane),
                "active": .number(Double(entry.active)),
                "waiting": .number(Double(entry.waiting))
            ])
        }
        // How long each running hold has been held. A long sweep may hold its
        // lanes for its whole length by design — only a person's Stop shortens
        // one — so this is the number that separates "somebody is running a big
        // sweep" from "something is stuck", which nothing else would show.
        let active = snapshot.active.map { run in
            var entry: [String: JSONValue] = [
                "session": .string(run.identity.label),
                "run": .string(run.summary),
                "lanes": .array(run.lanes.map { .string($0.description) }.sorted { a, b in
                    (a.stringValue ?? "") < (b.stringValue ?? "")
                }),
                "heldForSeconds": .number((now - run.since).rounded())
            ]
            // Whether this run is held because somebody is using the machine,
            // and whose hold it is. Without it a machine where a person walked
            // away mid-run reads exactly like a wedged lane, and the two want
            // opposite responses: one waits, the other needs somebody to look.
            entry["held"] = run.held.map { hold in
                .object(["reason": .string(hold.reason.rawValue),
                         "line": .string(hold.line),
                         "session": .string(hold.session),
                         "app": hold.app.map(JSONValue.string) ?? .null,
                         "display": hold.display.map { .string($0.name) } ?? .null])
            } ?? .null
            return JSONValue.object(entry)
        }
        return .object([
            "active": .number(Double(snapshot.active.count)),
            "waiting": .number(Double(snapshot.waitingCount)),
            "held": .bool(snapshot.held),
            "perSessionWaitingCap": .number(Double(RunQueuePlan.perSessionWaitingCap)),
            "waitLimitSeconds": .number(await runScheduler.waitLimit),
            "lanes": .array(lanes),
            "activeRuns": .array(active)
        ])
    }

    /// The waiting count the menu bar mirrors, so the queue is answerable without
    /// the panel on screen. The scheduler runs whether or not anything is drawn —
    /// taking turns is correctness, not decoration — so this is readable with the
    /// HUD switched off.
    func queueCount() async -> Int {
        await runScheduler.snapshot().waitingCount
    }
}
