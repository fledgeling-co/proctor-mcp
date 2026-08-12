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
                    settle: SettlePolicy) async throws -> JSONValue {
        let flow = try flowNamed(name)
        let targetID = try replayWindow(flow: flow, override: window)
        let handle = try windowHandle(targetID)
        let steps = flow.steps.map(\.step)

        // Replay uses the same actuation path as act, so a step that behaves
        // one way when recorded cannot behave another way when replayed.
        let foreground = steps.contains { Self.syntheticKinds.contains($0.kind) }
        let run = await runSteps(steps, window: handle, settle: settle, foreground: foreground,
                                 captureEach: captureEach, diffEach: false)

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
                   resetBetween: [ActionStep], includeTiles: Bool) async throws -> StabilityReport {
        let flow = try flowNamed(name)
        let targetID = try replayWindow(flow: flow, override: window)
        let handle = try windowHandle(targetID)
        let steps = flow.steps.map(\.step)
        let runs = max(requestedRuns, 1)

        var notes: [String] = []
        if runs < 2 {
            notes.append("A single run cannot measure divergence; firstDivergence and every "
                       + "instability score are reported as zero because nothing was compared.")
        }
        guard !steps.isEmpty else {
            throw AgentError(code: .invalidArguments,
                             message: "flow \(flow.name.debugDescription) has no steps to replay",
                             remedy: "Record some with proctor_flow action \"start\" and proctor_act.")
        }

        let foreground = steps.contains { Self.syntheticKinds.contains($0.kind) }
        var perRun: [[String]] = []

        for runIndex in 0..<runs {
            if runIndex > 0 && !resetBetween.isEmpty {
                let reset = await runSteps(resetBetween, window: handle,
                                           settle: .default, foreground: foreground,
                                           captureEach: false, diffEach: false)
                if let failed = reset.failedAt {
                    let message = reset.results[failed].error?.message ?? "unknown"
                    notes.append("Run \(runIndex): the reset sequence failed at step \(failed) "
                               + "(\(message)), so this run did not start from the same state as the "
                               + "others and any divergence it shows may be an artefact of that.")
                }
            }

            let run = await runSteps(steps, window: handle, settle: .default,
                                     foreground: foreground, captureEach: false, diffEach: false)
            var hashes: [String] = []

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
        }

        var stepInstability: [Double] = []
        var divergenceDetail: [String: [String]] = [:]
        for index in 0..<steps.count {
            let column = perRun.compactMap { index < $0.count ? $0[index] : nil }
            stepInstability.append(Canonical.instability(hashes: column))
            let distinct = Set(column)
            if distinct.count > 1 {
                divergenceDetail[String(index)] = distinct.sorted()
            }
            if column.count < perRun.count {
                notes.append("Step \(index) was measured on \(column.count) of \(perRun.count) runs.")
            }
        }

        let firstDivergence = Canonical.firstDivergence(perRun: perRun)
        let complete = perRun.allSatisfy { $0.count == steps.count }
        notes.append(includeTiles
            ? "Pixel tile hashes were folded into each step hash alongside the tree."
            : "Comparison was on the accessibility tree only. Rendering nondeterminism that leaves "
            + "the tree unchanged — a gradient, a cursor, an animation frame — is not covered by "
            + "this run; pass includeTiles to cover it.")

        return StabilityReport(
            flow: flow.name,
            runs: runs,
            stepCount: steps.count,
            firstDivergence: firstDivergence,
            stepInstability: stepInstability,
            deterministic: firstDivergence == nil && complete
                && stepInstability.allSatisfy { $0 == 0 } && runs > 1,
            divergenceDetail: divergenceDetail.isEmpty ? nil : divergenceDetail,
            notes: notes)
    }
}
