import Foundation
import ProctorCore

// Flows and the determinism instrument built on them.

extension Session {

    // MARK: - Recording

    func appendToFlow(named name: String, window: WindowHandle, run: StepRun,
                      steps: [ActionStep]) throws {
        loadFlowsIfNeeded()
        let key = try FlowStore.sanitised(name)
        var flow = flows[key] ?? RecordedFlow(name: key, window: window.id,
                                              app: window.app,
                                              appBundleId: appHandle(forWindow: window)?.bundleId)
        for result in run.results where result.ok {
            flow.steps.append(RecordedStep(step: result.step,
                                           selector: selector(for: result.step),
                                           plane: result.plane,
                                           stateHash: result.stateHash,
                                           settleReason: result.settle?.reason))
        }
        flow.updatedAt = Date().timeIntervalSince1970
        putFlow(flow)
        try FlowStore.save(flow)
    }

    /// What the step's node looked like when it resolved. A raw node id does
    /// not survive the app relaunching; role, identifier and title give a
    /// replay something to re-find it by.
    private func selector(for step: ActionStep) -> JSONValue? {
        guard let id = step.node else { return nil }
        var out: [String: JSONValue] = ["node": .string(id)]
        if let node = try? ax.node(id: id) {
            out["role"] = .string(node.role)
            if let identifier = node.identifier { out["identifier"] = .string(identifier) }
            if let title = node.title { out["title"] = .string(title) }
            if let label = node.label { out["label"] = .string(label) }
        }
        return .object(out)
    }

    func flowNamed(_ name: String) throws -> RecordedFlow {
        loadFlowsIfNeeded()
        let key = try FlowStore.sanitised(name)
        guard let flow = flows[key] else {
            throw AgentError(code: .invalidArguments,
                             message: "no flow named \(key.debugDescription)",
                             remedy: "Call proctor_flow with action \"list\" to see what is stored.")
        }
        return flow
    }

    // MARK: - proctor_flow

    func flowStart(name: String, window: String?, description: String?) throws -> JSONValue {
        loadFlowsIfNeeded()
        let key = try FlowStore.sanitised(name)
        if let current = recording, current != key {
            throw AgentError(
                code: .invalidArguments,
                message: "flow \(current.debugDescription) is still recording",
                remedy: "Stop it first with proctor_flow action \"stop\". Two open recordings would "
                      + "silently split one sequence across both.")
        }
        var flow = RecordedFlow(name: key, description: description, window: window)
        if let window, let handle = try? windowHandle(window) {
            flow.app = handle.app
            flow.appBundleId = appHandle(forWindow: handle)?.bundleId
        }
        putFlow(flow)
        try FlowStore.save(flow)
        setRecording(key)
        return .object(["recording": .string(key),
                        "flow": try JSONValue.encode(flow)])
    }

    func flowStop() throws -> JSONValue {
        loadFlowsIfNeeded()
        guard let key = recording else {
            return .object(["recording": .null,
                            "note": .string("nothing was recording")])
        }
        setRecording(nil)
        guard let flow = flows[key] else {
            return .object(["stopped": .string(key), "steps": .number(0)])
        }
        try FlowStore.save(flow)
        return .object(["stopped": .string(key),
                        "steps": .number(Double(flow.steps.count)),
                        "flow": try JSONValue.encode(flow)])
    }

    func flowList() throws -> JSONValue {
        loadFlowsIfNeeded()
        let entries = flows.values.sorted { $0.name < $1.name }.map { flow -> JSONValue in
            var out: [String: JSONValue] = [
                "name": .string(flow.name),
                "steps": .number(Double(flow.steps.count)),
                "createdAt": .number(flow.createdAt),
                "updatedAt": .number(flow.updatedAt)
            ]
            if let description = flow.description { out["description"] = .string(description) }
            if let window = flow.window { out["window"] = .string(window) }
            if let bundleId = flow.appBundleId { out["bundleId"] = .string(bundleId) }
            return .object(out)
        }
        return .object(["flows": .array(entries),
                        "directory": .string(FlowStore.directory.path),
                        "recording": recording.map(JSONValue.string) ?? .null])
    }

    func flowShow(name: String) throws -> JSONValue {
        try JSONValue.encode(try flowNamed(name))
    }

    func flowDelete(name: String) throws -> JSONValue {
        loadFlowsIfNeeded()
        let key = try FlowStore.sanitised(name)
        let existed = try FlowStore.delete(key)
        removeFlow(key)
        if recording == key { setRecording(nil) }
        return .object(["deleted": .bool(existed), "name": .string(key)])
    }

    func flowReplay(name: String, window: String?, captureEach: Bool,
                    settle: SettlePolicy, pointerMarks: Bool = false) async throws -> JSONValue {
        let flow = try flowNamed(name)
        let targetID = try replayWindow(flow: flow, override: window)
        let handle = try windowHandle(targetID)
        // A replay drives an application exactly as `act` does, so it passes the
        // same gate before anything is actuated: a blocked app, or a sensitive one
        // with no current token, is refused here (and the refusal audited) rather
        // than replayed. The decision is made on the application behind the window
        // being driven *now* — `flow.appBundleId` is deliberately not consulted,
        // because a recording can be pointed at a different window and the
        // authority that matters is over the app actually being touched. It fails
        // closed the same way the live path does: a target whose bundle id cannot
        // be resolved is refused whenever an allow list is in force.
        let audit = try enforcePolicy(tool: AuditTool.flowReplay, window: handle)
        let steps = flow.steps.map(\.step)
        let foreground = steps.contains { Self.syntheticKinds.contains($0.kind) }

        // A replay drives an application exactly as `act` does, so it queues
        // exactly as `act` does: one lane set, taken after the gate and held from
        // the first replayed step to the last.
        let demand = lanes(for: steps, window: handle, foreground: foreground)
        let summary = StepDescription.runLine(.replay(flow: flow.name),
                                              app: appHandle(forWindow: handle)?.name)
        return try await scheduled(lanes: demand, summary: summary) {
            try await replayInLane(flow: flow, targetID: targetID, handle: handle, steps: steps,
                                   foreground: foreground, captureEach: captureEach,
                                   settle: settle, pointerMarks: pointerMarks, audit: audit)
        }
    }

    private func replayInLane(flow: RecordedFlow, targetID: String, handle: WindowHandle,
                              steps: [ActionStep], foreground: Bool, captureEach: Bool,
                              settle: SettlePolicy, pointerMarks: Bool,
                              audit: AuditContext) async throws -> JSONValue {
        // Re-read the gate now the lane is ours: a run that waited for its turn
        // may have been let through by an approval that has since expired, and
        // the authority that matters is the one held when the app is touched.
        let audit = try enforcePolicy(tool: audit.tool, window: handle)
        // Replay uses the same actuation path as act, so a step that behaves
        // one way when recorded cannot behave another way when replayed. Handing
        // it the audit context is what puts each replayed step in the trail
        // individually, redacted the same way a live step is.
        hudRunControlBegin()
        let run = await runSteps(steps, window: handle, settle: settle, foreground: foreground,
                                 captureEach: captureEach, diffEach: false, audit: audit,
                                 pointerMarks: pointerMarks)

        var comparisons: [JSONValue] = []
        var firstDivergence: Int?
        for (index, recorded) in flow.steps.enumerated() {
            let actual = index < run.results.count ? run.results[index].stateHash : nil
            let matched: Bool? = {
                guard let expected = recorded.stateHash, let actual else { return nil }
                return expected == actual
            }()
            if matched == false, firstDivergence == nil { firstDivergence = index }
            comparisons.append(.object([
                "index": .number(Double(index)),
                "label": recorded.step.label.map(JSONValue.string) ?? .null,
                "recordedHash": recorded.stateHash.map(JSONValue.string) ?? .null,
                "replayHash": actual.map(JSONValue.string) ?? .null,
                "matched": matched.map(JSONValue.bool) ?? .null
            ]))
        }

        var out: [String: JSONValue] = [
            "flow": .string(flow.name),
            "window": .string(targetID),
            "completed": .number(Double(run.completed)),
            "failedAt": run.failedAt.map { JSONValue.number(Double($0)) } ?? .null,
            "firstDivergence": firstDivergence.map { JSONValue.number(Double($0)) } ?? .null,
            "steps": .array(try run.results.map { try JSONValue.encode($0) }),
            "comparison": .array(comparisons)
        ]
        if captureEach { out["captures"] = .array(run.captures) }
        if foreground {
            out["note"] = .string("This flow contains synthetic-event steps, so the replay activated "
                                + "the application. The result is not a background-safe one.")
        }
        return .object(out)
    }

    private func replayWindow(flow: RecordedFlow, override: String?) throws -> String {
        if let override { return override }
        if let recorded = flow.window { return recorded }
        throw AgentError(code: .invalidArguments,
                         message: "flow \(flow.name.debugDescription) records no window and none was given",
                         remedy: "Pass `window` with a handle from proctor_apps.")
    }

    // MARK: - proctor_stability

    func stability(flow name: String, runs requestedRuns: Int, window: String?,
                   resetBetween: [ActionStep], includeTiles: Bool,
                   captureEach: Bool = false,
                   pointerMarks: Bool = false) async throws -> StabilityReport {
        let flow = try flowNamed(name)
        let targetID = try replayWindow(flow: flow, override: window)
        let handle = try windowHandle(targetID)
        let steps = flow.steps.map(\.step)
        let requested = max(requestedRuns, 1)

        // Reconcile the two opt-in switches once, up front: asking for the marker
        // with capture off switches capture on rather than accepting a switch that
        // does nothing, and any capturing run says that its timings moved.
        let artifacts = StabilityCaptureOptions.resolve(captureEach: captureEach,
                                                        pointerMarks: pointerMarks)

        let notes: [String] = artifacts.notes
        guard !steps.isEmpty else {
            throw AgentError(code: .invalidArguments,
                             message: "flow \(flow.name.debugDescription) has no steps to replay",
                             remedy: "Record some with proctor_flow action \"start\" and proctor_act.")
        }

        let foreground = steps.contains { Self.syntheticKinds.contains($0.kind) }

        // A sweep takes its lanes ONCE, for the whole call, and holds them across
        // every repeat. Rejoining the line between passes would let another
        // session drive the app in the middle of a determinism measurement, which
        // is both the interleaving this exists to prevent and a guaranteed false
        // divergence. A long sweep may therefore hold its lanes for its whole
        // length; only a person's Stop shortens it, and the give-up ceiling caps
        // how long anybody *waits*, never how long a run may take.
        let demand = lanes(for: steps, window: handle, foreground: foreground)
        let summary = StepDescription.runLine(.stability(flow: flow.name, runs: requested),
                                              app: appHandle(forWindow: handle)?.name)
        return try await scheduled(lanes: demand, summary: summary) {
            try await stabilityInLane(flow: flow, handle: handle, steps: steps,
                                      requested: requested, resetBetween: resetBetween,
                                      includeTiles: includeTiles, artifacts: artifacts,
                                      foreground: foreground, notes: notes)
        }
    }

    private func stabilityInLane(flow: RecordedFlow, handle: WindowHandle, steps: [ActionStep],
                                 requested: Int, resetBetween: [ActionStep], includeTiles: Bool,
                                 artifacts: StabilityCaptureOptions.Resolved,
                                 foreground: Bool,
                                 notes initialNotes: [String]) async throws -> StabilityReport {
        var notes = initialNotes
        hudRunControlBegin()
        var perRun: [[String]] = []
        var captures: [StabilityCapture] = []

        for runIndex in 0..<requested {
            // The reset runs first in a repeat and drives the app exactly as a
            // replayed step does, so it gets its own gate under its own name: a
            // refused reset ends the run the same way a refused replay does, and
            // the refusal entry says which of the two was refused.
            if runIndex > 0 && !resetBetween.isEmpty {
                // The reset is scaffolding that returns the app to its start state,
                // not part of the flow being measured, so it is never captured: its
                // frames would sit in the ledger under step indices that belong to
                // the flow's own steps.
                let resetGate = repeatGate(tool: AuditTool.stabilityReset, window: handle,
                                           completedRuns: perRun.count)
                switch resetGate.verdict {
                case .proceed:
                    let reset = await runSteps(resetBetween, window: handle,
                                               settle: .default, foreground: foreground,
                                               captureEach: false, diffEach: false,
                                               audit: resetGate.context)
                    if let failed = reset.failedAt {
                        let message = reset.results[failed].error?.message ?? "unknown"
                        notes.append("Run \(runIndex): the reset sequence failed at step \(failed) "
                                   + "(\(message)), so this run did not start from the same state as "
                                   + "the others and any divergence it shows may be an artefact "
                                   + "of that.")
                    }
                case .refuseRun(let refusal):
                    throw AgentError(code: .policyDenied, message: refusal.reason,
                                     remedy: refusal.remedy)
                case .stopRun(let refusal):
                    notes.append(ReplayGate.earlyStopNote(completedRuns: perRun.count,
                                                          requestedRuns: requested,
                                                          reason: refusal.reason))
                    return Self.stabilityReport(flow: flow.name, steps: steps, perRun: perRun,
                                                notes: &notes, includeTiles: includeTiles,
                                                truncated: true,
                                                captures: artifacts.captureEach ? captures : nil)
                }
            }

            // Permission is re-checked at the top of every measured repeat, on the
            // application being driven now. A repeated run is where a TTL-bounded
            // approval has to actually expire: checking once at the start would
            // carry the authority of minute one to the last repeat an hour later.
            // `perRun.count` is the number of repeats that have already finished
            // measuring, which is what separates "refuse the call" from "stop and
            // report what we have".
            let gate = repeatGate(tool: AuditTool.stabilityReplay, window: handle,
                                  completedRuns: perRun.count)
            switch gate.verdict {
            case .proceed:
                break
            case .refuseRun(let refusal):
                // Nothing ran, so there is nothing to measure and no report to
                // make — the caller gets the same refusal a live drive would give.
                throw AgentError(code: .policyDenied, message: refusal.reason,
                                 remedy: refusal.remedy)
            case .stopRun(let refusal):
                // Authority went away between repeats. There is nobody to ask for
                // a fresh approval mid-run, so the run ends here and reports what
                // it did measure, marked as measured on fewer repeats.
                notes.append(ReplayGate.earlyStopNote(completedRuns: perRun.count,
                                                      requestedRuns: requested,
                                                      reason: refusal.reason))
                return Self.stabilityReport(flow: flow.name, steps: steps, perRun: perRun,
                                            notes: &notes, includeTiles: includeTiles,
                                            truncated: true,
                                            captures: artifacts.captureEach ? captures : nil)
            }

            let run = await runSteps(steps, window: handle, settle: .default,
                                     foreground: foreground, captureEach: artifacts.captureEach,
                                     diffEach: false, audit: gate.context,
                                     pointerMarks: artifacts.pointerMarks)
            var hashes: [String] = []

            // One ledger entry per step this replay attempted, whether or not it
            // produced a frame. Steps after a failure were never attempted and get
            // none; the failing step itself does, because it ran and produced
            // nothing (capture only happens after a step succeeds).
            if artifacts.captureEach {
                captures.append(contentsOf: StabilityCaptureOptions.ledger(
                    run: runIndex, artifacts: run.stepArtifacts, failedStep: run.failedAt,
                    pointerMarksRequested: artifacts.pointerMarks))
            }

            for index in 0..<steps.count {
                guard index < run.results.count, let treeHash = run.results[index].stateHash else {
                    break
                }
                if includeTiles {
                    do {
                        let frame = try await capture.capture(window: handle, to: nil,
                                                              waitForComplete: true, timeoutMs: 3000,
                                                              scale: nil, tileHashes: true,
                                                              includeCursor: false)
                        if let tiles = frame.tileHashes, !tiles.isEmpty {
                            hashes.append(Canonical.hash(treeHash + "|" + tiles.joined(separator: ",")))
                        } else {
                            notes.append("Run \(runIndex) step \(index): the capture returned no tile "
                                       + "hashes, so this step was compared on the tree alone while "
                                       + "others were compared on tree plus tiles; a divergence "
                                       + "reported here may be an artefact of that.")
                            hashes.append(treeHash)
                        }
                    } catch {
                        notes.append("Run \(runIndex) step \(index): the capture failed (\(error)), so "
                                   + "this step was compared on the tree alone.")
                        hashes.append(treeHash)
                    }
                } else {
                    hashes.append(treeHash)
                }
            }

            if let failed = run.failedAt {
                let message = run.results[failed].error?.message ?? "unknown"
                notes.append("Run \(runIndex) ended early at step \(failed): \(message). Steps after "
                           + "it were not replayed in this run and are scored on fewer samples.")
            } else if hashes.count < steps.count {
                notes.append("Run \(runIndex) produced hashes for \(hashes.count) of \(steps.count) "
                           + "steps; the post-state of the remainder could not be read.")
            }
            perRun.append(hashes)

            // A person stopped the sweep, not just this pass. Reported through
            // the same truncated shape a withdrawn permission uses, so the
            // repeats that did finish survive and the run is never scored
            // deterministic on fewer samples than were commissioned.
            if let failed = run.failedAt, run.results[failed].error?.code == .haltedByPerson {
                notes.append("A person stopped the sweep during run \(runIndex), so it was measured "
                           + "on \(perRun.count) of \(requested) repeats.")
                return Self.stabilityReport(flow: flow.name, steps: steps, perRun: perRun,
                                            notes: &notes, includeTiles: includeTiles,
                                            truncated: true,
                                            captures: artifacts.captureEach ? captures : nil)
            }
        }

        return Self.stabilityReport(flow: flow.name, steps: steps, perRun: perRun,
                                    notes: &notes, includeTiles: includeTiles, truncated: false,
                                    captures: artifacts.captureEach ? captures : nil)
    }

    /// Score whatever was measured. Called from two places on purpose: the end of
    /// a full run, and the point a run stops early because permission went away
    /// between repeats. Both report on the repeats that completed rather than the
    /// number asked for, so `runs` counts what was measured. A `truncated` run is
    /// never reported deterministic: agreement across three repeats when five were
    /// asked for is a weaker claim than the one the caller commissioned, and this
    /// instrument's whole value is that it does not overstate its evidence.
    private static func stabilityReport(flow: String, steps: [ActionStep], perRun: [[String]],
                                        notes: inout [String], includeTiles: Bool,
                                        truncated: Bool,
                                        captures: [StabilityCapture]?) -> StabilityReport {
        let runs = perRun.count
        if runs < 2 {
            notes.append("A single run cannot measure divergence; firstDivergence and every "
                       + "instability score are reported as zero because nothing was compared.")
        }

        // The fold takes hash columns and nothing else, so no artifact — a frame,
        // a marker, a failed capture — has a route into a score.
        let score = StabilityScore.fold(perRun: perRun, stepCount: steps.count, runs: runs)
        for (index, samples) in score.undersampled.sorted(by: { $0.key < $1.key }) {
            notes.append("Step \(index) was measured on \(samples) of \(runs) runs.")
        }
        notes.append(includeTiles
            ? "Pixel tile hashes were folded into each step hash alongside the tree."
            : "Comparison was on the accessibility tree only. Rendering nondeterminism that leaves "
            + "the tree unchanged — a gradient, a cursor, an animation frame — is not covered by "
            + "this run; pass includeTiles to cover it.")

        return StabilityReport(
            flow: flow,
            runs: runs,
            stepCount: steps.count,
            firstDivergence: score.firstDivergence,
            stepInstability: score.stepInstability,
            // The fold cannot know a run was cut short, and a run that agreed
            // across three repeats when five were commissioned is a weaker claim
            // than the one asked for, so truncation suppresses the verdict here.
            deterministic: score.deterministic && !truncated,
            divergenceDetail: score.divergenceDetail.isEmpty ? nil : score.divergenceDetail,
            notes: notes,
            captures: captures)
    }
}
