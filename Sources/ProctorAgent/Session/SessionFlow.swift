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
                                           settleReason: result.settle?.reason,
                                           backend: result.backend ?? actuator.id))
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

    /// Refuse to replay a flow through an actuation path other than the one that
    /// recorded it.
    ///
    /// A replay's whole claim is that it repeats the recorded run, and a
    /// determinism score is a comparison of what that repetition produced. Run the
    /// two halves through different actuation paths and any divergence measures
    /// the paths rather than the application — the one comparison the instrument
    /// must not quietly make.
    ///
    /// Note where this does NOT bite, because the obvious guard is the wrong one:
    /// a repeat sweep runs every pass inside one session with one backend, so its
    /// passes always agree with each other trivially. Recording against replay is
    /// where the two can genuinely differ.
    ///
    /// A flow recorded before backends were tracked carries no backend and is
    /// replayed without complaint: it was recorded on the native planes, because
    /// they were the only ones there.
    ///
    /// The rule is that EVERY backend the tape carries must match, not just the
    /// first one. Reading only the first would clear a tape whose opening step
    /// happens to agree and whose later steps do not. That cannot happen today —
    /// `appendToFlow` stamps every recorded step from one immutable session
    /// actuator, so a tape this build writes is uniform — which is exactly why
    /// the check costs one word now and would cost a debugging session later.
    /// Deliberately NOT a uniqueness check: "the tape holds more than one value"
    /// invites counting backend-bearing steps, and every real multi-step flow has
    /// several. Matching is the property; cardinality is not.
    func requireSameBackend(as flow: RecordedFlow) throws {
        let recorded = flow.steps.compactMap(\.backend)
        guard let was = recorded.first(where: { $0 != actuator.id }) else { return }
        throw AgentError(
            code: .backendUnsupported,
            message: "flow \"\(flow.name)\" was recorded with the \(was.rawValue) actuation "
                   + "backend and this session is using \(actuator.id.rawValue)",
            remedy: "Replay it on the backend that recorded it, or record it again on this one. "
                  + "A divergence between a recording and a replay that used different actuation "
                  + "paths measures the paths, not the application under test.",
            detail: .object(["recordedWith": .string(was.rawValue),
                             "running": .string(actuator.id.rawValue)]))
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
        try requireSameBackend(as: flow)
        let steps = flow.steps.map(\.step)
        let foreground = steps.contains { backendSyntheticKinds.contains($0.kind) }

        // A replay drives an application exactly as `act` does, so it queues
        // exactly as `act` does: one lane set, taken after the gate and held from
        // the first replayed step to the last.
        let demand = await lanes(for: steps, window: handle, foreground: foreground)
        try refuseHostTakeoverIfRouted(steps: steps, foreground: foreground)
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
            // Which lane replayed it. A replay's whole claim is that it repeats
            // the recording, so the path it repeated it on belongs beside the
            // comparison rather than being inferred from the steps — and a
            // replay in which nothing actuated has no step to infer it from.
            "backend": .string(actuator.id.rawValue),
            "completed": .number(Double(run.completed)),
            "failedAt": run.failedAt.map { JSONValue.number(Double($0)) } ?? .null,
            "firstDivergence": firstDivergence.map { JSONValue.number(Double($0)) } ?? .null,
            "steps": .array(try run.results.map { try JSONValue.encode($0) }),
            "comparison": .array(comparisons)
        ]
        if captureEach { out["captures"] = .array(run.captures) }
        // How much of the replay needed the front, measured from the planes its
        // steps actually travelled rather than inferred from the recorded kinds.
        // A recorded `type` that fell back to the event stream is invisible to a
        // kind-based note and shows here, which is the difference between
        // "contains synthetic steps" and "cannot be replayed unattended".
        let report = ForegroundReport.from(
            foregroundDemand(for: steps, foreground: foreground),
            planes: run.results.map(\.plane))
        out["foreground"] = (try? JSONValue.encode(report)) ?? .null
        if let note = report.note { out["foregroundNote"] = .string(note) }
        // And every time the replay got out of somebody's way, for the same
        // reason act reports it: a suite that took four minutes because a person
        // was at the machine should say so rather than look slow.
        if !run.yields.isEmpty {
            out["yields"] = .array(run.yields.compactMap { try? JSONValue.encode($0) })
            if let held = YieldRecord.note(for: run.yields) { out["yieldNote"] = .string(held) }
        }
        // And the same block act reports: a replay that took the machine said so
        // on every display, and may have held it.
        if let takeover = run.takeover {
            out["takeover"] = (try? JSONValue.encode(takeover)) ?? .null
            if let note = takeover.note { out["takeoverNote"] = .string(note) }
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
        // The same rule as a replay, and for a sharper reason: this call's whole
        // output is a determinism score, and scoring a recording against passes
        // driven through a different actuation path measures the paths.
        try requireSameBackend(as: flow)
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

        let foreground = steps.contains { backendSyntheticKinds.contains($0.kind) }

        // A sweep takes its lanes ONCE, for the whole call, and holds them across
        // every repeat. Rejoining the line between passes would let another
        // session drive the app in the middle of a determinism measurement, which
        // is both the interleaving this exists to prevent and a guaranteed false
        // divergence. A long sweep may therefore hold its lanes for its whole
        // length; only a person's Stop shortens it, and the give-up ceiling caps
        // how long anybody *waits*, never how long a run may take.
        let demand = await lanes(for: steps, window: handle, foreground: foreground)
        try refuseHostTakeoverIfRouted(steps: steps, foreground: foreground)
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
        // Accumulated across every repeat, by step index. `subjects` holds each
        // distinct value in first-seen order, so repeats that disagreed about which
        // side of the page boundary a step fell on report both rather than the
        // first; `withheld` counts the repeats whose hash the fold refused.
        var subjects: [Int: [HashSubject]] = [:]
        var withheld: [Int: Int] = [:]
        // Whether a browser renders the window under test at all, read once. Nil
        // leaves the report exactly as it was before this existed.
        let renderedByBrowser =
            BrowserCatalogue.identify(bundleId: appHandle(forWindow: handle)?.bundleId)

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
                                                captures: artifacts.captureEach ? captures : nil,
                                                backend: actuator.id, machine: machine,
                                                subjects: subjects, withheld: withheld,
                                                browser: renderedByBrowser)
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
                                            captures: artifacts.captureEach ? captures : nil,
                                                backend: actuator.id, machine: machine,
                                                subjects: subjects, withheld: withheld,
                                                browser: renderedByBrowser)
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
                // A hash taken after an action Proctor cannot vouch happened is
                // not a sample of that step's post-state.
                //
                // PRO-0045 records such a step `indeterminate` and takes a
                // post-state walk anyway, correctly: with the backend gone it is
                // the only evidence left about what the machine did, and its own
                // comment calls it evidence and not proof. The score is where the
                // distinction has to bite. Folded in, it either masks a real
                // divergence or invents one, and a determinism number is exactly
                // the output somebody trusts without checking.
                //
                // So the hash stays on the `StepResult` and in the trail, and only
                // the fold refuses it — PRO-0049 settles the same question the same
                // way for a repeat that never reached the app: not a sample of the
                // application's behaviour, therefore not folded, reported beside
                // the score instead.
                //
                // Judged on the backend's own flag and NEVER on the error code.
                // That is PRO-0045's rule and it is load-bearing: only the thing
                // that failed knows whether its request may already have been
                // delivered, and the same code can arrive from another domain.
                //
                // `break` rather than `continue`, because such a step sets
                // `failedAt` and ends its repeat, so there is nothing after it —
                // pinned by `anIndeterminateStepIsTheLastResultInItsRepeat`, since
                // the day that stops being true this line starts dropping data.
                // `continue` would be worse than either: it would left-shift the
                // remaining hashes and compare them against the wrong steps.
                if run.results[index].error?.indeterminate == true {
                    withheld[index, default: 0] += 1
                    notes.append("Run \(runIndex) step \(index): the backend could not say "
                               + "whether this step happened, so its post-state was withheld "
                               + "from the score and kept as evidence on the step.")
                    break
                }
                if let subject = run.results[index].hashSubject,
                   !(subjects[index]?.contains(subject) ?? false) {
                    subjects[index, default: []].append(subject)
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
                                            captures: artifacts.captureEach ? captures : nil,
                                                backend: actuator.id, machine: machine,
                                                subjects: subjects, withheld: withheld,
                                                browser: renderedByBrowser)
            }
        }

        return Self.stabilityReport(flow: flow.name, steps: steps, perRun: perRun,
                                    notes: &notes, includeTiles: includeTiles, truncated: false,
                                    captures: artifacts.captureEach ? captures : nil,
                                                backend: actuator.id, machine: machine,
                                                subjects: subjects, withheld: withheld,
                                                browser: renderedByBrowser)
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
                                        captures: [StabilityCapture]?,
                                        backend: ActuationBackendID,
                                        machine: Machine,
                                        subjects: [Int: [HashSubject]],
                                        withheld: [Int: Int],
                                        browser: KnownBrowser?) -> StabilityReport {
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

        let basis = stepBasis(stepCount: steps.count, score: score, subjects: subjects,
                              withheld: withheld, browser: browser)
        // The steps whose hash was taken over a render tree in AT LEAST ONE repeat.
        // A step that was page content in one repeat and browser chrome in another
        // belongs here and also carries both subjects, which is what says its
        // number is attributable to neither side. Erring toward disclosing is the
        // direction this boundary already takes for an advisory that never refuses.
        let pageSteps = (0..<steps.count).filter { subjects[$0]?.contains(.pageContent) == true }
        let pageContent = browser.flatMap { browser -> PageContentDisclosure? in
            guard !pageSteps.isEmpty else { return nil }
            return PageContentDisclosure(browser: browser.name, bundleId: browser.bundleId,
                                         steps: pageSteps,
                                         // The sentence proctor_act has always
                                         // emitted, not a second wording of it.
                                         evidence: BrowserTarget.evidence)
        }
        if !pageSteps.isEmpty {
            notes.append("Step\(pageSteps.count == 1 ? "" : "s") "
                       + pageSteps.map(String.init).joined(separator: ", ")
                       + " ran against page content in \(browser?.name ?? "a browser"), so "
                       + "\(pageSteps.count == 1 ? "its score is" : "their scores are") a "
                       + "measurement of the page as much as of the application. The number stands; "
                       + "what it is a number about is the page.")
        }

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
            captures: captures,
            // Every pass folded above ran in one session, and a session's
            // actuator is immutable, so one value is an honest label for the
            // whole report rather than for one of its passes.
            backend: backend,
            stepBasis: basis,
            pageContent: pageContent,
            // Same argument as `backend` above: every pass ran in one session, and
            // a session's machine does not change under it.
            machine: machine)
    }

    /// What each step's number was taken over and what it was computed from.
    ///
    /// Nil when there is nothing to disclose — no browser rendered the window and
    /// no repeat withheld a hash — so an ordinary native sweep encodes exactly as
    /// it did before this existed. When it is emitted it covers every step, so a
    /// reader can index it in parallel with `stepInstability`.
    ///
    /// `samples` and `instability` both come from the fold that produced
    /// `stepInstability`, never from arithmetic here: two paths to one number drift
    /// the first time either definition moves, and this way the disagreement is
    /// unavailable rather than merely tested for.
    private static func stepBasis(stepCount: Int, score: StabilityScore.Fold,
                                  subjects: [Int: [HashSubject]],
                                  withheld: [Int: Int],
                                  browser: KnownBrowser?) -> [StabilityStepBasis]? {
        guard browser != nil || !withheld.isEmpty else { return nil }
        return (0..<stepCount).map { index in
            let samples = index < score.samples.count ? score.samples[index] : 0
            return StabilityStepBasis(
                step: index,
                subjects: browser == nil ? nil : (subjects[index] ?? []),
                samples: samples,
                withheld: withheld[index],
                // Below two samples there is no comparison, and
                // `Canonical.instability` answers 0.0 — which reads as five
                // agreeing repeats. Absent is the honest value.
                instability: samples >= 2 && index < score.stepInstability.count
                    ? score.stepInstability[index] : nil)
        }
    }
}
