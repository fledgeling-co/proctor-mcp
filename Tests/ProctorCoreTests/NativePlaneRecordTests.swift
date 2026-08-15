import Testing
import Foundation
@testable import ProctorCore

// PRO-0051. The native planes stay, chosen deliberately, and the record says so.
//
// The decision is the deliverable and it lives in the spec. These tests pin the
// part of it that is a property of the wire: a run record names the lane that
// produced it, on every surface a determinism claim is read from, including the
// runs where no step ever actuated and there is nothing to infer it from.
//
// They also pin the thing measurement corrected. The first draft of this item
// believed a native step's record omitted its backend. It does not, and never
// did — `Actuation.backend` is `.native` by default and `carry(_:)` copies it
// unconditionally. That is asserted here rather than assumed, because a later
// change that quietly made native silent again would reintroduce exactly the
// ambiguity this item exists to remove: silence that could mean "the native
// lane" or "a build from before lanes existed".

@Suite("PRO-0051 — a run record names its actuation lane")
struct NativePlaneRecordTests {

    private func step(_ kind: ActionStep.Kind = .press) -> ActionStep {
        ActionStep(kind: kind, node: "n1")
    }

    private func report(deterministic: Bool = true,
                        backend: ActuationBackendID?) -> StabilityReport {
        StabilityReport(flow: "login", runs: 3, stepCount: 2, firstDivergence: nil,
                        stepInstability: [0, 0], deterministic: deterministic,
                        divergenceDetail: nil, notes: [], backend: backend)
    }

    // MARK: - A5 — a step that actuated names its backend; one that did not, does not

    @Test("an actuated native step says it was native, and always has")
    func actuatedNativeStepNamesItsBackend() throws {
        var result = StepResult(index: 0, step: step(), ok: true, plane: .accessibility,
                                error: nil, settle: nil, stateHash: "h", diff: nil,
                                elapsedMs: 1)
        result.carry(Actuation(.accessibility, .action))
        #expect(result.backend == .native)

        let encoded = try JSONValue.encode(result)
        #expect(encoded["backend"] == .string("native"))
    }

    @Test("a step that refused before actuating carries no backend at all")
    func unactuatedStepCarriesNoBackend() throws {
        // The shape SessionAct builds for a refusal reached before any backend
        // was called: no `carry`, so nothing to say about how it was driven.
        let result = StepResult(index: 0, step: step(), ok: false, plane: nil,
                                error: AgentError(code: .nodeNotFound, message: "gone"),
                                settle: nil, stateHash: nil, diff: nil, elapsedMs: 1)
        #expect(result.backend == nil)

        let encoded = try JSONValue.encode(result)
        #expect(encoded["backend"] == nil || encoded["backend"] == .null)
    }

    @Test("a delegated step says so, and keeps the driver's own word beside it")
    func delegatedStepNamesItsBackend() throws {
        var result = StepResult(index: 0, step: step(.click), ok: true, plane: .routedEvent,
                                error: nil, settle: nil, stateHash: "h", diff: nil,
                                elapsedMs: 1)
        result.carry(Actuation(.routedEvent, .eventStream, backend: .cua,
                               reportedMode: "cgevent"))
        #expect(result.backend == .cua)
        #expect(result.reportedMode == "cgevent")
    }

    // MARK: - A3 — every run record names the lane

    @Test("an act result names its lane")
    func actResultNamesItsLane() throws {
        var actuated = StepResult(index: 0, step: step(), ok: true, plane: .accessibility,
                                  error: nil, settle: nil, stateHash: "h", diff: nil,
                                  elapsedMs: 1)
        actuated.carry(Actuation(.accessibility, .action))
        let result = ActResult(window: "w1", steps: [actuated], completed: 1,
                               failedAt: nil, finalHash: "h", backend: .native)
        #expect(try JSONValue.encode(result)["backend"] == .string("native"))
    }

    /// The case per-step reporting cannot cover, and the reason this field is
    /// run-level rather than derived: nothing actuated, so no step has a backend
    /// to read, and without this the record cannot say which lane refused it.
    @Test("a run where nothing actuated still says which lane refused it")
    func runWithNoActuationStillNamesItsLane() throws {
        let refused = StepResult(index: 0, step: step(.click), ok: false, plane: nil,
                                 error: AgentError(code: .actionUnsupported,
                                                   message: "needs the foreground"),
                                 settle: nil, stateHash: nil, diff: nil, elapsedMs: 1)
        let result = ActResult(window: "w1", steps: [refused], completed: 0,
                               failedAt: 0, finalHash: nil, backend: .cua)
        let encoded = try JSONValue.encode(result)
        #expect(encoded["backend"] == .string("cua"))
        // And the step itself says nothing, which is the honest half of the pair.
        #expect(encoded["steps"]?.arrayValue?.first?["backend"] == nil)
    }

    @Test("a stability report names its lane")
    func stabilityReportNamesItsLane() throws {
        #expect(try JSONValue.encode(report(backend: .native))["backend"] == .string("native"))
    }

    // MARK: - A4 — a determinism verdict never travels without its path

    @Test("a determinism verdict carries the actuation path it was measured on")
    func determinismVerdictCarriesItsPath() throws {
        for verdict in [true, false] {
            let encoded = try JSONValue.encode(report(deterministic: verdict,
                                                      backend: .cua))
            #expect(encoded["deterministic"] == .bool(verdict))
            #expect(encoded["backend"] == .string("cua"),
                    "a score without its actuation path measures the path")
        }
    }

    // MARK: - A5b — the run-level lane and the step-level backends agree

    @Test("every actuated step in a run reports the run's own lane")
    func stepBackendsAgreeWithTheRun() throws {
        var steps: [StepResult] = []
        for index in 0..<3 {
            var result = StepResult(index: index, step: step(), ok: true,
                                    plane: .accessibility, error: nil, settle: nil,
                                    stateHash: "h", diff: nil, elapsedMs: 1)
            result.carry(Actuation(.accessibility, .action))
            steps.append(result)
        }
        let run = ActResult(window: "w1", steps: steps, completed: 3, failedAt: nil,
                            finalHash: "h", backend: .native)
        // Two fields that could disagree and are never checked are worse than one.
        for result in run.steps where result.backend != nil {
            #expect(result.backend == run.backend)
        }
    }

    // MARK: - A6 — records written before this field existed still decode

    @Test("an act result with no lane still decodes, so an older record is not lost")
    func actResultWithoutALaneStillDecodes() throws {
        let json = #"{"window":"w1","steps":[],"completed":0}"#
        let result = try JSONDecoder().decode(ActResult.self, from: Data(json.utf8))
        // Absent reads as "this build did not say", which is a different and more
        // honest thing than a default of `.native` under a delegated run.
        #expect(result.backend == nil)
    }

    @Test("a stability report with no lane still decodes")
    func stabilityReportWithoutALaneStillDecodes() throws {
        let json = #"""
        {"flow":"login","runs":2,"stepCount":1,"stepInstability":[0],
         "deterministic":true,"notes":[]}
        """#
        let back = try JSONDecoder().decode(StabilityReport.self, from: Data(json.utf8))
        #expect(back.backend == nil)
        #expect(back.deterministic)
    }

    @Test("both records survive a round trip, since they go out on the wire")
    func recordsRoundTrip() throws {
        let run = ActResult(window: "w1", steps: [], completed: 0, failedAt: nil,
                            finalHash: nil, backend: .cua)
        let backRun = try JSONDecoder().decode(ActResult.self,
                                               from: JSONEncoder().encode(run))
        #expect(backRun.backend == .cua)

        let backReport = try JSONDecoder().decode(
            StabilityReport.self, from: JSONEncoder().encode(report(backend: .cua)))
        #expect(backReport.backend == .cua)
    }
}
