import Foundation
import Testing
@testable import ProctorCore

// PRO-0071. The history window's contract, judged without a window.

@Suite("History surface")
struct HistorySurfaceTests {

    @Test("A1 · a skipped check is never counted as a pass")
    func skippedIsNotAPass() {
        // The failure this item exists to prevent, committed by the product's
        // own UI: three passes drawn and a fourth check silently dropped because
        // nothing could measure it.
        #expect(HistorySurface.Verdict.passed.countsAsPass)
        #expect(!HistorySurface.Verdict.failed.countsAsPass)
        #expect(!HistorySurface.Verdict.skipped.countsAsPass)

        let checks = [
            HistorySurface.Check(name: "contrast", detail: "4.8:1", verdict: .passed),
            HistorySurface.Check(name: "minHitSize", detail: "28×28pt", verdict: .passed),
            HistorySurface.Check(name: "agree", detail: "no reflector",
                                 verdict: .skipped, reason: "no reflector in this app"),
        ]
        let tally = HistorySurface.tally(checks)
        #expect(tally.passed == 2)
        #expect(tally.skipped == 1)
        #expect(tally.failed == 0)
        // Three counts, never two, and the denominator excludes what could not
        // be measured — a rate over the total reports coverage never had.
        #expect(tally.measured == 2)
        #expect(tally.isClean)
    }

    @Test("A1 · a skipped verdict is drawn differently from both of the others")
    func skippedLooksDifferent() {
        let pills = Set(HistorySurface.Verdict.allCases.map(\.pill))
        #expect(pills.count == 3, "two verdicts share a treatment and would read as one")
    }

    @Test("A1 · a skipped check without a reason is refused rather than drawn")
    func skippedNeedsAReason() {
        // Otherwise it reads as "this did not run" with no way to tell a missing
        // instrument from a missing test.
        let bare = HistorySurface.Check(name: "agree", detail: "", verdict: .skipped)
        #expect(!HistorySurface.isWellFormed(bare))
        let given = HistorySurface.Check(name: "agree", detail: "", verdict: .skipped,
                                         reason: "no reflector in this app")
        #expect(HistorySurface.isWellFormed(given))
        // A pass needs no reason.
        #expect(HistorySurface.isWellFormed(
            HistorySurface.Check(name: "contrast", detail: "4.8:1", verdict: .passed)))
    }

    @Test("A2 · the empty state names the action that fills it")
    func emptyNamesTheAction() {
        #expect(!HistorySurface.Copy.emptyBody.isEmpty)
        #expect(HistorySurface.Copy.emptyBody.contains("Connect a model"))
        #expect(!HistorySurface.Copy.emptyAction.isEmpty)
        // Not "no data".
        #expect(!HistorySurface.Copy.emptyBody.lowercased().contains("no data"))
    }

    @Test("A3 · the projection carries none of the fields this window may not show")
    func projectionExcludesSecrets() {
        // The guarantee is structural: a field not on the face of the window is
        // not in the type. This asserts it over the encoded shape, so a later
        // widening of RunHistory fails here rather than leaking.
        let step = RunHistory.Step(seq: 1, at: 0, kind: "press", act: nil,
                                   object: RunHistory.Object(text: "Send", supplied: false),
                                   plane: "accessibility", ms: 12, outcome: .ok, reason: nil)
        let run = RunHistory.Run(id: "run-1", tool: "proctor_act", bundleId: "com.apple.mail",
                                 startedAt: 0, endedAt: 1, outcome: .ok, steps: [step],
                                 lane: nil, unreadable: 0, reason: nil)
        let encoded = try! JSONEncoder().encode(run)
        let json = String(decoding: encoded, as: UTF8.self)
        for field in HistorySurface.forbiddenFields {
            #expect(!json.contains("\"\(field)\":"),
                    "the projection carries \(field), which the window must never draw")
        }
    }

    @Test("A4 · a run is identified by bundle id, not by a session handle")
    func bundleIdNotHandle() {
        // `app-3` is meaningless once the agent restarts; a bundle id is the
        // durable identity the policy gate already judges on.
        let run = RunHistory.Run(id: "run-1", tool: "proctor_act", bundleId: "com.apple.mail",
                                 startedAt: 0, endedAt: 1, outcome: .ok, steps: [],
                                 lane: nil, unreadable: 0, reason: nil)
        #expect(run.bundleId == "com.apple.mail")
        #expect(run.bundleId?.contains("app-") != true)
    }

    @Test("A5 · retention is stated, and says the trail rotates rather than prunes")
    func retentionStated() {
        #expect(HistorySurface.Copy.retention.contains("14 days"))
        #expect(HistorySurface.Copy.retention.contains("10,000"))
        // Rotation is not pruning: the trail is hash-chained from a genesis over
        // its own prefix, so removing entries from the front is unrepresentable.
        #expect(HistorySurface.Copy.rotationWord == "rotates")
    }

    @Test("identifiers are unique and namespaced")
    func identifiers() {
        let all = [HistorySurface.ID.window, HistorySurface.ID.state(true),
                   HistorySurface.ID.state(false), HistorySurface.ID.copyConnect,
                   HistorySurface.ID.run("r1"), HistorySurface.ID.check("min hit size")]
        #expect(Set(all).count == all.count)
        for id in all { #expect(id.hasPrefix("proctor.history.")) }
    }
}
