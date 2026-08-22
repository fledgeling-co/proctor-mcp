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
    func projectionExcludesSecrets() throws {
        // The guarantee is structural: a field not on the face of the window is
        // not in the type. This asserts it over the encoded shape, so a later
        // widening of RunHistory fails here rather than leaking.
        let step = RunHistory.Step(seq: 1, at: 0, kind: "press", act: nil,
                                   object: RunHistory.Object(text: "Send", supplied: false),
                                   plane: "accessibility", ms: 12, outcome: .ok, reason: nil)
        let run = RunHistory.Run(id: "run-1", tool: "proctor_act", bundleId: "com.apple.mail",
                                 startedAt: 0, endedAt: 1, outcome: .ok, steps: [step],
                                 lane: nil, unreadable: 0, reason: nil)
        let encoded = try JSONEncoder().encode(run)
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

// PRO-0090. What the history window draws, now that it is a value.
//
// `HistoryWindow.swift` held 71 user-facing literals of 91 examined and now
// holds none: one interpolated count with no words in it is all that is left.
// These are the claims the window itself could not be asked for — there is no
// `ProctorUI` test target and `swift test` has no window server — so they are
// asked of the values it now reads.
@Suite("History window copy")
struct HistoryWindowCopyTests {

    /// DEF-130, found while moving this table out of the view.
    ///
    /// The view matched `case "appleEvent"` and `ActuationPlane`'s raw value is
    /// `appleEvents`. Nothing in this repo produces the singular spelling, so
    /// the branch was unreachable and an Apple Events step fell through to the
    /// default arm and drew the wire word. Asked here against the enum's own
    /// raw values rather than against literals, which is what makes the answer
    /// track a rename instead of surviving one.
    @Test("DEF-130 · an Apple Events step is labelled, not drawn as its wire word")
    func appleEventsIsSaidInWords() {
        // The defect itself. Keyed off the enum, so a rename of the case moves
        // this expectation with it instead of leaving it passing over a
        // spelling nothing produces any more — which is how the branch this
        // replaces went dead in the first place.
        let wire = ActuationPlane.appleEvents.rawValue
        #expect(HistorySurface.Copy.planeLabel(wire) == "Apple event")
        #expect(HistorySurface.Copy.planeLabel(wire) != wire,
                "an Apple Events step still draws the wire word \(wire)")
        // The other two planes read as English already, so their label and their
        // wire word coincide by design rather than by accident. Asserted as
        // equality so that is on the record rather than looking like an
        // oversight.
        #expect(HistorySurface.Copy.planeLabel(ActuationPlane.accessibility.rawValue)
                == "accessibility")
        #expect(HistorySurface.Copy.planeLabel(ActuationPlane.syntheticEvent.rawValue)
                == "synthetic")
    }

    /// A plane this build has no word for is echoed rather than hidden. The
    /// window would otherwise draw a blank where the agent named something
    /// newer than itself, which is worse than an unfamiliar word.
    @Test("an unrecognised plane is echoed rather than dropped")
    func anUnknownPlaneIsEchoed() {
        #expect(HistorySurface.Copy.planeLabel("something-newer") == "something-newer")
        #expect(HistorySurface.Copy.planeLabel(ActuationPlane.routedEvent.rawValue)
                == ActuationPlane.routedEvent.rawValue)
    }

    /// Every outcome draws a distinct mark, and a person's own stop is not
    /// drawn as a fault.
    @Test("every outcome has its own mark, and halted is not a failure mark")
    func everyOutcomeHasItsOwnMark() {
        let marks = RunHistory.Outcome.allCases.map(HistorySurface.Copy.outcomeSymbol)
        #expect(Set(marks).count == marks.count, "two outcomes share a mark")
        #expect(marks.allSatisfy { !$0.isEmpty })
        #expect(HistorySurface.Copy.outcomeSymbol(.halted)
                != HistorySurface.Copy.outcomeSymbol(.failed))
    }

    /// `indeterminate` is never the word "failed". The whole reason that
    /// outcome exists is that Proctor has no basis for saying the step did not
    /// happen, and a summary that says "failed" throws that away.
    @Test("a run whose outcome is unknown is never summarised as failed")
    func indeterminateIsNeverCalledFailed() {
        let summary = HistorySurface.Copy.runSummary(steps: 3, outcome: .indeterminate)
        #expect(!summary.contains("failed"), "an indeterminate run reads as \(summary)")
        #expect(summary == "3 steps, outcome unknown")
    }

    /// The counts read as English at one and at many. Each of these was a
    /// ternary inside a `Text(` before this item, where nothing could ask it.
    @Test("every counted sentence agrees with its number")
    func countedSentencesAgreeWithTheirNumbers() {
        #expect(HistorySurface.Copy.runSummary(steps: 0, outcome: .ok) == "no steps")
        #expect(HistorySurface.Copy.runSummary(steps: 1, outcome: .ok) == "1 step")
        #expect(HistorySurface.Copy.runSummary(steps: 2, outcome: .ok) == "2 steps")
        #expect(HistorySurface.Copy.entriesHeld(1) == "entry held")
        #expect(HistorySurface.Copy.entriesHeld(0) == "entries held")
        #expect(HistorySurface.Copy.droppedTitle(1) == "1 action was not recorded")
        #expect(HistorySurface.Copy.droppedTitle(2) == "2 actions were not recorded")
        #expect(HistorySurface.Copy.unopenedTitle(1) == "1 entry could not be opened")
        #expect(HistorySurface.Copy.unopenedTitle(3) == "3 entries could not be opened")
        #expect(HistorySurface.Copy.droppedMessage(1).contains("it is"))
        #expect(HistorySurface.Copy.droppedMessage(2).contains("they are"))
        #expect(HistorySurface.Copy.unopenedMessage(1).hasPrefix("It was"))
        #expect(HistorySurface.Copy.unopenedMessage(2).hasPrefix("They were"))
        #expect(HistorySurface.Copy.rotatedMessage(1).contains("entry was"))
        #expect(HistorySurface.Copy.rotatedMessage(2).contains("entries were"))
        #expect(HistorySurface.Copy.runUnreadable(1).hasPrefix("1 entry "))
        #expect(HistorySurface.Copy.runUnreadable(4).hasPrefix("4 entries "))
    }

    /// A cost under a second is said in milliseconds and over one in seconds,
    /// with the boundary asked rather than assumed.
    @Test("a step's cost is said in the unit that reads")
    func durationsUseTheUnitThatReads() {
        #expect(HistorySurface.Copy.duration(ms: 999) == "999 ms")
        #expect(HistorySurface.Copy.duration(ms: 1000) == "1.0 s")
        #expect(HistorySurface.Copy.duration(ms: 1500) == "1.5 s")
    }

    /// The window's scene id and title, which three places name and one of them
    /// silently depends on: `excludeFromCapture()` keeps a window holding
    /// opened history out of every screenshot — `proctor_capture`'s included —
    /// by matching the id and falling back to the title.
    @Test("the history scene's id and title have one definition")
    func theSceneIsNamedOnce() throws {
        #expect(HistorySurface.sceneID == "history")
        #expect(HistorySurface.sceneTitle == "History")
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ProctorUI")
        let window = try String(contentsOf: ui.appendingPathComponent("HistoryWindow.swift"),
                                encoding: .utf8)
        #expect(window.contains("HistorySurface.sceneID"),
                "the capture exclusion does not read the shared scene id")
        #expect(window.contains("HistorySurface.sceneTitle"),
                "the capture exclusion does not read the shared scene title")
    }

    /// DEF-039's clause for this file, asked inside the gate: no string literal
    /// in the view outside a comment. `source-analysis` and nothing above it —
    /// it says the view holds no literal, not that the window renders the
    /// constant.
    @Test("DEF-039 · the history view holds no user-facing literal of its own")
    func theHistoryViewHoldsNoUserFacingLiterals() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ProctorUI")
        for name in ["HistoryWindow.swift", "HistoryModel.swift"] {
            let source = WalkthroughFlowTests.withoutComments(
                try String(contentsOf: ui.appendingPathComponent(name), encoding: .utf8))
            // What survives in each is an interpolated string with no words in
            // it — a row id, and a count drawn beside its own noun — which is
            // the classifier's `punctuation` and `interpolated`, not `display`.
            for line in source.components(separatedBy: "\n") where line.contains("\"") {
                #expect(line.contains("\\("),
                        "\(name) holds a literal with no interpolation in it: \(line)")
            }
        }
    }
}
