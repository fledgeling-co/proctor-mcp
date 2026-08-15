import Testing
import Foundation
@testable import ProctorCore

// PRO-0047: a stream of audit entries folded back into the unit a person reads
// in. Pure — no file, no clock this file does not supply, no key store.

@Suite("Run history")
struct RunHistoryTests {

    // MARK: - Building records

    private func step(run: String?, seq: Int, at: Double, outcome: String = "ok",
                      kind: String = "press", act: String = "Pressed",
                      object: String? = "Send invoice", supplied: Bool = false,
                      plane: String? = "accessibility", ms: Int? = 12,
                      tool: String = "proctor_act", bundleId: String? = "com.acme.console",
                      reason: String? = nil) -> RunHistory.Entry {
        .opened(AuditRecord(
            timestamp: at, tool: tool, app: "app-1", bundleId: bundleId, window: "win-1",
            node: "e3", kind: kind, outcome: outcome, reason: reason,
            run: run, seq: seq, ms: ms, plane: plane, act: act,
            obj: object.map { AuditRecord.Object(text: $0, supplied: supplied) }))
    }

    private func bare(run: String?, at: Double, tool: String, outcome: String,
                      reason: String? = nil) -> RunHistory.Entry {
        .opened(AuditRecord(timestamp: at, tool: tool, outcome: outcome, reason: reason, run: run))
    }

    // MARK: - Grouping

    @Test("records sharing a run become one run")
    func groupsByRun() {
        let runs = RunHistory.runs(from: [
            step(run: "aaa", seq: 0, at: 100),
            step(run: "aaa", seq: 1, at: 101),
            step(run: "bbb", seq: 0, at: 200)
        ])
        #expect(runs.count == 2)
        #expect(runs.first?.id == "bbb")          // newest first
        #expect(runs.last?.steps.count == 2)
    }

    @Test("steps are ordered by the position the run recorded, not by arrival")
    func ordersStepsBySeq() {
        let runs = RunHistory.runs(from: [
            step(run: "aaa", seq: 2, at: 102),
            step(run: "aaa", seq: 0, at: 100),
            step(run: "aaa", seq: 1, at: 101)
        ])
        #expect(runs.first?.steps.map(\.seq) == [0, 1, 2])
    }

    @Test("a record written outside a call is its own run")
    func recordWithNoRunIsARunOfOne() {
        // A person's Stop is not a step of somebody's run, and folding it into
        // whatever happened to be running would file a person's decision under a
        // model's activity.
        let runs = RunHistory.runs(from: [
            step(run: "aaa", seq: 0, at: 100),
            bare(run: nil, at: 150, tool: "proctor_hud.stop", outcome: "refused",
                 reason: "a person stopped the run"),
            step(run: "aaa", seq: 1, at: 200)
        ])
        #expect(runs.count == 2)
        let stop = runs.first { $0.tool == "proctor_hud.stop" }
        #expect(stop != nil)
        #expect(stop?.steps.isEmpty == true)
        #expect(stop?.outcome == .halted)
    }

    @Test("two records with no run identifier stay two runs, not one")
    func standaloneRecordsDoNotMerge() {
        let runs = RunHistory.runs(from: [
            bare(run: nil, at: 100, tool: "proctor_policy", outcome: "ok"),
            bare(run: nil, at: 200, tool: "proctor_policy", outcome: "ok")
        ])
        #expect(runs.count == 2)
    }

    @Test("a record written before runs were recorded still reads")
    func recordsWithoutRunFieldsStillRender() {
        // Every PRO-0047 field is optional, so an entry sealed before this
        // shipped decodes with all of them nil. History that began by hiding the
        // history that already existed would be a poor history feature.
        let old = AuditRecord(timestamp: 50, tool: "proctor_act", app: "app-1",
                              bundleId: "com.acme.console", window: "win-1", node: "e3",
                              kind: "press", outcome: "ok")
        let runs = RunHistory.runs(from: [.opened(old)])
        #expect(runs.count == 1)
        #expect(runs.first?.steps.count == 1)
        #expect(runs.first?.steps.first?.act == nil)
        #expect(runs.first?.steps.first?.object == nil)
    }

    @Test("a run carries the bundle id, never the session handle")
    func runNamesTheApplicationByBundleId() {
        // The record's `app` is `app-1`, a handle that means nothing after a
        // restart. Nothing on the projection may present it as an application.
        let runs = RunHistory.runs(from: [step(run: "aaa", seq: 0, at: 100)])
        #expect(runs.first?.bundleId == "com.acme.console")
    }

    @Test("a gate refusal lands on the run, not among steps that never ran")
    func gateRefusalIsTheRunsOwnReason() {
        let runs = RunHistory.runs(from: [
            bare(run: "aaa", at: 99, tool: "proctor_act", outcome: "refused",
                 reason: "com.acme.vault is on the block list; actuation is refused.")
        ])
        #expect(runs.first?.steps.isEmpty == true)
        #expect(runs.first?.reason?.contains("block list") == true)
        #expect(runs.first?.outcome == .refused)
    }

    @Test("the run's span comes from its records")
    func spanIsFirstToLast() {
        let runs = RunHistory.runs(from: [
            step(run: "aaa", seq: 0, at: 100),
            step(run: "aaa", seq: 1, at: 100.75)
        ])
        #expect(runs.first?.spanMs == 750)
    }

    @Test("a single-instant run shows no duration rather than zero")
    func zeroSpanIsNil() {
        let runs = RunHistory.runs(from: [step(run: "aaa", seq: 0, at: 100)])
        #expect(runs.first?.spanMs == nil)
    }

    @Test("the run limit caps what comes back")
    func limitApplies() {
        let entries = (0..<40).map { step(run: "r\($0)", seq: 0, at: Double(100 + $0)) }
        #expect(RunHistory.runs(from: entries, limit: 5).count == 5)
    }

    // MARK: - Unreadable entries

    @Test("an entry that cannot be opened is counted, never dropped")
    func unreadableIsCounted() {
        // A list with silent holes in it is worse than one that says how many it
        // could not read: the first looks like nothing happened.
        let runs = RunHistory.runs(from: [
            step(run: "aaa", seq: 0, at: 100),
            .unreadable,
            .unreadable
        ])
        #expect(runs.first?.unreadable == 2)
    }

    // MARK: - Outcome

    @Test("every ok reduces to ok")
    func outcomeAllOk() { #expect(RunHistory.reduce([.ok, .ok]) == .ok) }

    @Test("every failure reduces to failed")
    func outcomeAllFailed() { #expect(RunHistory.reduce([.failed, .failed]) == .failed) }

    @Test("a person's stop outranks a failure")
    func outcomeHaltWins() {
        // A run somebody stopped had steps it never ran; reporting it as a
        // failure would blame the run for the person's decision.
        #expect(RunHistory.reduce([.ok, .failed, .halted]) == .halted)
    }

    @Test("a refusal outranks a plain success")
    func outcomeRefusalWins() {
        #expect(RunHistory.reduce([.ok, .refused]) == .refused)
    }

    @Test("some worked and some did not reduces to mixed")
    func outcomeMixed() { #expect(RunHistory.reduce([.ok, .failed]) == .mixed) }

    @Test("an advisory on its own reduces to recommended")
    func outcomeRecommended() { #expect(RunHistory.reduce([.recommended]) == .recommended) }

    @Test("no records reduces to ok rather than crashing")
    func outcomeEmpty() { #expect(RunHistory.reduce([]) == .ok) }

    @Test("a person's halt is told apart from the gate's refusal")
    func haltIsNotTheGate() {
        let gate = AuditRecord(timestamp: 1, tool: "proctor_act", outcome: "refused",
                               reason: "com.acme.vault is on the block list; actuation is refused.")
        let person = AuditRecord(timestamp: 1, tool: "proctor_act", outcome: "refused",
                                 reason: "haltedByPerson: a person stopped this run")
        #expect(RunHistory.outcome(of: gate) == .refused)
        #expect(RunHistory.outcome(of: person) == .halted)
    }

    @Test("the halt test reads only fields Proctor writes")
    func haltTestIgnoresForeignText() {
        // An application that names a button "a person stopped" must not be able
        // to make its own step read as somebody's Stop. The reason on a step
        // record is Proctor's error message, and the object — the half an
        // application controls — is never consulted here.
        let record = AuditRecord(timestamp: 1, tool: "proctor_act", kind: "press",
                                 outcome: "failed",
                                 act: "Pressed",
                                 obj: .init(text: "a person stopped the run", supplied: false))
        #expect(RunHistory.outcome(of: record) == .failed)
    }

    // MARK: - The lane recommendation

    @Test("a lane recommendation carries the scheme and never an address")
    func laneCarriesSchemeOnly() {
        let record = AuditRecord(
            timestamp: 100, tool: "proctor_apps", bundleId: "com.apple.Safari",
            outcome: AuditRecord.Outcome.recommended,
            recommendation: LaneRecommendation(lane: "obscura", rule: "httpScheme",
                                               scheme: "https"),
            run: "aaa")
        let runs = RunHistory.runs(from: [.opened(record)])
        #expect(runs.first?.lane?.lane == "obscura")
        #expect(runs.first?.lane?.scheme == "https")
        #expect(runs.first?.outcome == .recommended)
    }
}
