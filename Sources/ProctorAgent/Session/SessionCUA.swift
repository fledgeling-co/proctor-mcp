import Foundation
import ProctorCore

// The CUA schema façade, execution half. The translation lives in ProctorCore
// (CUAFacade) and is pure; this drives the resulting plan through the machinery
// the native tools already use — runSteps for actuation (so settle, hashing,
// planes and diffs come for free), capture for a screenshot, a bounded settle
// for a wait. Nothing here re-implements actuation; a façade-driven step is the
// same step a native caller would have run, and reports the same provenance.

extension Session {

    /// Translate a CUA payload for a window and run it. The whole batch is
    /// translated up front: an action Proctor cannot map refuses the call before
    /// anything is actuated, rather than half-running an impossible plan. Once
    /// running, the plan stops at the first step that fails and reports failedAt,
    /// which is the OpenAI batch shape.
    func computerUse(schema: CUASchema, window id: String, payload: JSONValue,
                     scale: Double, foreground: Bool) async throws -> JSONValue {
        let window = try windowHandle(id)
        // A façade-driven run is gated exactly as a native one: the policy check
        // and audit are on the drive path, not on any one tool's schema.
        let tool = schema == .anthropic ? "proctor_computer" : "proctor_openai_computer"
        let audit = try enforcePolicy(tool: tool, window: window)

        let plan: [CUAStep]
        switch schema {
        case .anthropic: plan = try CUATranslator.anthropic(payload, windowFrame: window.frame, scale: scale)
        case .openai:    plan = try CUATranslator.openai(payload, windowFrame: window.frame, scale: scale)
        }

        var stepsOut: [JSONValue] = []
        var completed = 0
        var failedAt: Int?
        var finalHash: String?

        for (index, cua) in plan.enumerated() {
            var entry: [String: JSONValue] = [
                "index": .number(Double(index)),
                "action": .string(cua.action),
                "summary": .string(cua.summary)
            ]
            var failed = false

            switch cua.operation {
            case .act(let step):
                let run = await runSteps([step], window: window, settle: .default,
                                         foreground: foreground, captureEach: false, diffEach: true,
                                         audit: audit)
                if let result = run.results.first {
                    entry["ok"] = .bool(result.ok)
                    if let plane = result.plane { entry["plane"] = .string(plane.rawValue) }
                    if let hash = result.stateHash { entry["stateHash"] = .string(hash); finalHash = hash }
                    if let settle = result.settle { entry["settle"] = encoded(settle) }
                    if let error = result.error { entry["error"] = encoded(error) }
                    if result.ok { completed += 1 } else { failed = true }
                } else {
                    entry["ok"] = .bool(false)
                    entry["error"] = .string("the step produced no result")
                    failed = true
                }

            case .screenshot:
                do {
                    let frame = try await capture.capture(window: window, to: nil, waitForComplete: true,
                                                          timeoutMs: 3000, scale: nil, tileHashes: false,
                                                          includeCursor: false)
                    entry["ok"] = .bool(true)
                    entry["capture"] = encoded(frame)
                    completed += 1
                } catch let error as AgentError {
                    entry["ok"] = .bool(false)
                    entry["error"] = encoded(error)
                    failed = true
                } catch {
                    entry["ok"] = .bool(false)
                    entry["error"] = .string("capture failed: \(error)")
                    failed = true
                }

            case .wait(let ms):
                if ms > 0 { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
                let report = await settleNow(window: window, pid: appHandle(forWindow: window)?.pid,
                                             policy: .default)
                entry["ok"] = .bool(true)
                entry["settle"] = encoded(report)
                if let outcome = try? walk(window: id) {
                    entry["stateHash"] = .string(outcome.hash)
                    finalHash = outcome.hash
                }
                completed += 1
            }

            stepsOut.append(.object(entry))
            if failed { failedAt = index; break }
        }

        var out: [String: JSONValue] = [
            "schema": .string(schema.rawValue),
            "window": .string(id),
            "translatedSteps": .number(Double(plan.count)),
            "completed": .number(Double(completed)),
            "steps": .array(stepsOut)
        ]
        if let failedAt { out["failedAt"] = .number(Double(failedAt)) }
        if let finalHash { out["finalHash"] = .string(finalHash) }
        return .object(out)
    }

    private func encoded<T: Encodable>(_ value: T) -> JSONValue {
        (try? JSONValue.encode(value)) ?? .null
    }
}
