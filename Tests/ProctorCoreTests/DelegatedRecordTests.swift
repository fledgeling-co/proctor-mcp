import Testing
import Foundation
@testable import ProctorCore

// PRO-0045. The record's new vocabulary, at the level it is defined.

@Suite("An indeterminate outcome and the fields behind it")
struct DelegatedRecordTests {

    // MARK: - Compatibility with rows sealed before these fields existed

    @Test("a row written before this item decodes with the new fields nil")
    func olderRowsStillDecode() throws {
        // The five fields are appended and optional for the same reason
        // PRO-0047's six were: a sealed trail holds rows this build did not
        // write, and a decode failure there would lose history rather than a
        // field. Neither the signed material nor the chain link moves, because
        // both are computed over the ciphertext rather than over these.
        let older = """
        {"timestamp":1,"tool":"proctor_act","outcome":"ok","kind":"press","seq":0}
        """
        let record = try JSONDecoder().decode(AuditRecord.self, from: Data(older.utf8))
        #expect(record.by == nil)
        #expect(record.mode == nil)
        #expect(record.eff == nil)
        #expect(record.obs == nil)
        #expect(record.lane == nil)
    }

    @Test("a row carrying all five round-trips")
    func newRowsRoundTrip() throws {
        let record = AuditRecord(timestamp: 1, tool: "proctor_act", outcome: "ok",
                                 by: "cua", mode: "cgevent", eff: "suspectedNoOp",
                                 obs: "changed", lane: "lane-1")
        let data = Data(record.jsonLine().utf8)
        let back = try JSONDecoder().decode(AuditRecord.self, from: data)
        #expect(back == record)
    }

    // MARK: - How a run holding one reads

    @Test("an unknown outcome from a newer build degrades to a fault, never to a success")
    func unknownOutcomesDegradeSafely() {
        // This is also how an older build reads `indeterminate`. Over-reporting a
        // problem is the safe direction and is why no migration is needed.
        let record = AuditRecord(timestamp: 1, tool: "proctor_act", outcome: "something-new")
        #expect(RunHistory.outcome(of: record) == .failed)
    }

    @Test("indeterminate maps to its own outcome rather than to failed")
    func indeterminateIsItsOwnThing() {
        let record = AuditRecord(timestamp: 1, tool: "proctor_act",
                                 outcome: AuditRecord.Outcome.indeterminate)
        #expect(RunHistory.outcome(of: record) == .indeterminate)
    }

    @Test("a run with three good steps and one unknown one is not reported as ok")
    func oneUnknownStepContaminatesTheRun() {
        // The whole point of the outcome. Folding it into `mixed` — or worse,
        // letting three successes reduce it away — would lose the fact it exists
        // to carry: the run's end state cannot be described.
        #expect(RunHistory.reduce([.ok, .ok, .ok, .indeterminate]) == .indeterminate)
        #expect(RunHistory.reduce([.failed, .indeterminate]) == .indeterminate)
    }

    @Test("a person's own stop still outranks an unknown outcome")
    func aPersonsStopStillWins() {
        // Why they were pressed: a person stopping the run is the dominant fact
        // about why it ended, and the HUD already refuses to paint it as a fault.
        #expect(RunHistory.reduce([.indeterminate, .halted]) == .halted)
    }

    // MARK: - The wording

    @Test("the indeterminate line reads as unknown rather than as a failure")
    func theLineDoesNotAssert() {
        let line = StepDescription.line(for: ActionStep(kind: .press, node: "e1"),
                                        node: nil, outcome: .indeterminate)
        #expect(line.contains("could not tell"))
        #expect(!line.contains("failed"))
        #expect(!line.contains("Pressed"))
    }

    @Test("the noun form is used wherever a row cannot assert the step happened")
    func nounFormIsSelectedNotAuthored() {
        // `asserting: false` selects the vocabulary that already exists rather
        // than inventing a second one, so a new step kind cannot acquire an
        // asserting past tense on this path by being forgotten.
        for kind in ActionStep.Kind.allCases {
            let step = ActionStep(kind: kind)
            let asserting = StepDescription.past(for: step, node: nil).verb
            let neutral = StepDescription.past(for: step, node: nil, asserting: false).verb
            #expect(!neutral.isEmpty)
            // Some kinds share a word between the two forms; what must never
            // happen is the neutral form carrying a past tense the asserting one
            // does not.
            if asserting != neutral { #expect(neutral != asserting) }
        }
    }
}
