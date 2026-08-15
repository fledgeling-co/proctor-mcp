import Testing
import Foundation
@testable import ProctorCore

// PRO-0044, slice 1. The wire contract a delegated actuation backend reports
// through, and the two places where adding a field would not have been enough.
//
// The pattern both halves share: a new field that existing readers do not read
// changes nothing for them. `note == nil` is the signal a caller already uses
// for "this run disclosed nothing", and `ok` is the signal a caller already uses
// for "this step worked". Anything that must reach those callers has to change
// the answer they already ask for, not sit beside it.

private let synthetic: Set<ActionStep.Kind> = [.dragPath, .hover, .click, .key]
private let conditional: Set<ActionStep.Kind> = [.type, .scroll]

private func demand(_ kinds: [ActionStep.Kind], foreground: Bool = false) -> ForegroundDemand {
    ForegroundDemand.forBatch(kinds: kinds, synthetic: synthetic,
                              conditional: conditional, foreground: foreground)
}

private func step(_ kind: ActionStep.Kind = .press) -> ActionStep {
    ActionStep(kind: kind)
}

private func result(_ index: Int, plane: ActuationPlane?,
                    actuation: Actuation? = nil) -> StepResult {
    var out = StepResult(index: index, step: step(), ok: true, plane: plane,
                         error: nil, settle: nil, stateHash: nil, diff: nil,
                         elapsedMs: 1)
    if let actuation { out.carry(actuation) }
    return out
}

@Suite("Delegated actuation wire")
struct ActuationWireTests {

    // MARK: - The plane a caller reads to decide whether a run was unattended

    @Test("a routed event is an injected event that did not take the machine")
    func routedEventIsNotForeground() {
        let report = ForegroundReport.from(demand([.click, .click]),
                                           planes: [.routedEvent, .routedEvent])
        // The whole reason this case exists: the native actuator cannot deliver
        // a click without the front, a delegated one can, and counting it as
        // foreground would report every such run as having taken the machine.
        #expect(report.measured == 0)
        #expect(report.unproven == 0)
    }

    @Test("an unproven step changes the sentence, not just a new field")
    func unprovenChangesTheNote() {
        let report = ForegroundReport.from(demand([.press, .press]),
                                           planes: [.accessibility, .unknown])
        #expect(report.unproven == 1)
        // The load-bearing assertion. A reader that only ever looked at `note`
        // would otherwise see nil — the same answer it gets from a genuinely
        // clean run — and conclude this one was background-safe.
        #expect(report.note != nil)
        #expect(report.note?.contains("could not be established") == true)
    }

    @Test("a clean background run still discloses nothing")
    func cleanRunStaysSilent() {
        let report = ForegroundReport.from(demand([.press, .setValue]),
                                           planes: [.accessibility, .routedEvent])
        #expect(report.unproven == 0)
        #expect(report.note == nil)
    }

    @Test("an escalation nobody asked for outranks every other sentence")
    func unrequestedForegroundLeadsTheNote() {
        let results = [
            result(0, plane: .accessibility),
            result(1, plane: .syntheticEvent,
                   actuation: Actuation(.syntheticEvent, .eventStream, backend: .cua,
                                        unrequestedForeground: true)),
        ]
        let report = ForegroundReport.from(demand([.press, .press]), results: results)
        #expect(report.unrequestedForeground == 1)
        #expect(report.note?.contains("without being asked") == true)
        // A batch of two accessibility-shaped kinds predicts no foreground at
        // all. It escalated anyway, and a report still claiming a background run
        // would be the disclosure failing exactly where it matters most.
        #expect(report.ranInForeground)
    }

    // MARK: - Encoding

    @Test("a step the native backend ran encodes no new keys")
    func nativeStepEncodesUnchanged() throws {
        let native = result(0, plane: .accessibility)
        let json = try JSONEncoder().encode(native)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        // Every delegated field is absent rather than null, so a consumer reading
        // today's shape sees byte-identical output and a golden file does not move.
        for key in ["backend", "reportedMode", "effect", "retriedOnStale",
                    "unrequestedForeground", "transportMs"] {
            #expect(object[key] == nil, "\(key) should be omitted for a native step")
        }
    }

    @Test("the delegated facts survive a round trip")
    func delegatedStepRoundTrips() throws {
        let actuation = Actuation(.routedEvent, .eventStream, backend: .cua,
                                  reportedMode: "cgevent", effect: .unverifiable,
                                  retriedOnStale: true, transportMs: 12)
        let encoded = try JSONEncoder().encode(result(0, plane: .routedEvent,
                                                      actuation: actuation))
        let decoded = try JSONDecoder().decode(StepResult.self, from: encoded)
        #expect(decoded.backend == .cua)
        // Carried verbatim so a reader can audit the mapping rather than trust
        // it — the plane above is this build's reading of that string.
        #expect(decoded.reportedMode == "cgevent")
        #expect(decoded.effect == .unverifiable)
        #expect(decoded.retriedOnStale == true)
        #expect(decoded.transportMs == 12)
    }

    @Test("a false flag is omitted rather than written as false")
    func falseFlagsAreOmitted() throws {
        let actuation = Actuation(.accessibility, .action, backend: .cua,
                                  reportedMode: "ax", effect: .confirmed)
        let encoded = try JSONEncoder().encode(result(0, plane: .accessibility,
                                                      actuation: actuation))
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["retriedOnStale"] == nil)
        #expect(object["unrequestedForeground"] == nil)
        // The facts that are true are still there.
        #expect(object["backend"] as? String == "cua")
    }

    @Test("the new planes and effects carry their wire names")
    func vocabularyIsStable() {
        #expect(ActuationPlane.routedEvent.rawValue == "routedEvent")
        #expect(ActuationPlane.unknown.rawValue == "unknown")
        #expect(ActuationEffect.suspectedNoOp.rawValue == "suspectedNoOp")
        #expect(ActuationBackendID.cua.rawValue == "cua")
    }
}
