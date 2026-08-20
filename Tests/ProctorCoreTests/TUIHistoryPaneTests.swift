import Foundation
import Testing
@testable import ProctorCore

// PRO-0075. The history pane's reader.
//
// The campaign found this pane drawing its empty state whatever the machine was
// doing, and the first disposition recorded it as unfixable: the trail is
// sealed, `proctor_history` is not in `ToolCatalogue`, so no client could read
// it. That reasoning was wrong on both halves. The verb exists as an internal
// socket verb the app's own History window already calls, and `proctor_policy`
// action `audit` is a catalogue tool that hands a model whole records — so the
// projection drawn here is strictly narrower than what a model can already ask
// for, and reading it opens nothing.
//
// What is asserted below is therefore not "the pane has rows". It is that the
// pane cannot invent a row the reply did not carry, and cannot draw a quiet
// machine when the truth is that nobody could open the entries.

@Suite("TUI history pane")
struct TUIHistoryPaneTests {

    static func reply(runs: [JSONValue], unreadable: Double = 0) -> JSONValue {
        .object(["runs": .array(runs), "unreadable": .number(unreadable)])
    }

    static func run(tool: String, at epoch: Double, bundleId: String?,
                    outcome: String, steps: Int) -> JSONValue {
        var out: [String: JSONValue] = [
            "id": .string("run-1"),
            "tool": .string(tool),
            "startedAt": .number(epoch),
            "outcome": .string(outcome),
            "steps": .array((0..<steps).map { _ in .object([:]) })
        ]
        if let bundleId { out["bundleId"] = .string(bundleId) }
        return .object(out)
    }

    static let utc = TimeZone(identifier: "UTC")!

    @Test("a row says what the reply said and nothing else")
    func mapping() {
        let reply = Self.reply(runs: [
            Self.run(tool: "proctor_act", at: 1_700_000_000, bundleId: "com.apple.Safari",
                     outcome: "ok", steps: 3)
        ])
        let read = TUISurface.history(from: reply, timeZone: Self.utc)
        #expect(read.unreadable == 0)
        #expect(read.rows.count == 1)
        // 1_700_000_000 is 2023-11-14T22:13:20Z.
        #expect(read.rows[0].cells == ["22:13:20", "proctor_act", "com.apple.Safari", "ok", "3"])
    }

    @Test("a run with no bundle id draws a dash rather than a guess")
    func missingBundleId() {
        let reply = Self.reply(runs: [
            Self.run(tool: "proctor_snapshot", at: 0, bundleId: nil, outcome: "ok", steps: 0)
        ])
        let rows = TUISurface.history(from: reply, timeZone: Self.utc).rows
        #expect(rows[0].cells[2] == "—")
        #expect(rows[0].cells[4] == "0")
    }

    @Test("a run the reply could not name a tool for is dropped rather than half-drawn")
    func namelessRun() {
        let reply = Self.reply(runs: [.object(["id": .string("run-9")])])
        #expect(TUISurface.history(from: reply, timeZone: Self.utc).rows.isEmpty)
    }

    @Test("the clock fits its eight-cell column at every hour of the day")
    func clockWidth() {
        // Every ten minutes across two days, in a zone with a half-hour offset,
        // because a formatter's 12-hour clock with a suffix is nine cells and
        // would truncate the seconds into a different time.
        let zone = TimeZone(identifier: "Australia/Adelaide")!
        for step in stride(from: 0.0, to: 172_800, by: 600) {
            let drawn = TUISurface.clock(step, in: zone)
            #expect(TUIWidth.cells(of: drawn) == 8, "\(drawn) is not eight cells")
        }
        #expect(TUISurface.clock(nil, in: zone) == "--:--:--")
    }

    @Test("entries that could not be opened are counted, never dropped")
    func unreadableCounted() {
        let reply = Self.reply(runs: [
            Self.run(tool: "proctor_act", at: 0, bundleId: "a", outcome: "ok", steps: 1)
        ], unreadable: 4)
        #expect(TUISurface.history(from: reply, timeZone: Self.utc).unreadable == 4)
        #expect(TUISurface.unreadableNote(4) == "4 entries could not be opened")
        #expect(TUISurface.unreadableNote(1) == "1 entry could not be opened")
        #expect(TUISurface.unreadableNote(0) == nil)
    }

    @Test("a sealed trail and a quiet machine are not drawn the same way")
    func sealedIsNotEmpty() {
        var quiet = TUISurface.Model()
        quiet.pane = .history
        var sealed = quiet
        sealed.historyUnreadable = 7

        let quietFrame = TUISurface.render(quiet, cols: 100, rows: 30).lines
        let sealedFrame = TUISurface.render(sealed, cols: 100, rows: 30).lines
        #expect(quietFrame != sealedFrame)
        #expect(quietFrame.joined().contains("No runs recorded"))
        #expect(sealedFrame.joined().contains("could not be opened"))
        #expect(sealedFrame.joined().contains("keychain"))
    }

    @Test("a populated history still fits the 80x24 floor")
    func floor() {
        var model = TUISurface.Model()
        model.pane = .history
        model.historyUnreadable = 2
        model.history = (0..<6).map { i in
            TUISurface.Row4(["22:13:2\(i)", "proctor_capture", "com.apple.Safari", "refused", "12"])
        }
        let lines = TUISurface.render(model, cols: 80, rows: 24).lines
        #expect(lines.count == 24)
        for line in lines {
            #expect(TUIWidth.cells(of: line) <= 80, "\(line.debugDescription) overflows the floor")
        }
        // The shelf carries two facts and the floor is where they compete for
        // one border. Both survive, or the count is the one that goes and the
        // pane understates what it could not read.
        #expect(lines.joined().contains("could not be opened"))
    }

    @Test("the count of entries nobody could open reaches the shelf")
    func unreadableReachesTheShelf() {
        var model = TUISurface.Model()
        model.pane = .history
        model.history = [TUISurface.Row4(["22:13:20", "proctor_act", "com.apple.Safari", "ok", "3"])]
        let clean = TUISurface.render(model, cols: 100, rows: 30).lines.joined()
        model.historyUnreadable = 2
        let noted = TUISurface.render(model, cols: 100, rows: 30).lines.joined()
        #expect(!clean.contains("could not be opened"))
        #expect(noted.contains("2 entries could not be opened"))
    }

    /// Regenerates `docs/test-campaign/evidence/tui-history-pane.txt`.
    ///
    /// Gated on an environment variable rather than deleted after one run, so
    /// the campaign's artifact has a command that reproduces it instead of a
    /// provenance nobody can re-walk:
    /// `PROCTOR_WRITE_EVIDENCE=1 swift test --filter TUIHistoryPaneTests`.
    @Test("the campaign's evidence artifact regenerates from the renderer",
          .enabled(if: ProcessInfo.processInfo.environment["PROCTOR_WRITE_EVIDENCE"] == "1"))
    func writeEvidence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let reply = Self.reply(runs: [
            Self.run(tool: "proctor_act", at: 1_700_000_000, bundleId: "com.apple.Safari",
                     outcome: "ok", steps: 3),
            Self.run(tool: "proctor_capture", at: 1_700_000_042, bundleId: "com.apple.finder",
                     outcome: "refused", steps: 1),
            Self.run(tool: "proctor_snapshot", at: 1_700_000_101, bundleId: nil,
                     outcome: "ok", steps: 0),
        ], unreadable: 2)
        let read = TUISurface.history(from: reply, timeZone: Self.utc)

        var populated = TUISurface.Model()
        populated.pane = .history
        populated.history = read.rows
        populated.historyUnreadable = read.unreadable
        var quiet = TUISurface.Model(); quiet.pane = .history
        var sealed = quiet; sealed.historyUnreadable = 7

        var out: [String] = []
        out.append("CASE-0043 — the supervision TUI's history pane, fed by proctor_history.")
        out.append("Rendered at 100x30 by TUISurface.render, the same call the running program makes.")
        out.append("")
        out.append("Reply read: \(read.rows.count) runs, \(read.unreadable) entries unreadable.")
        out.append("")
        for (name, model) in [("populated", populated), ("quiet trail", quiet),
                              ("sealed trail", sealed)] {
            out.append("--- \(name) ---")
            out.append(contentsOf: TUISurface.render(model, cols: 100, rows: 30).lines)
            out.append("")
        }
        let url = root.appending(path: "docs/test-campaign/evidence/tui-history-pane.txt")
        let text = out.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)

        // An artifact writer with no assertion is a test that reports success
        // for having run. What has to be true is that the file on disk holds
        // the frames this renderer produced, so read it back and say so.
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == text, "the artifact on disk is what was rendered")
        #expect(onDisk.contains("2 entries could not be opened"))
        #expect(onDisk.contains("The trail could not be opened."))
    }
}

// PRO-0075. `TUISurface.Model`'s equality, pinned field by field.
//
// Written because the mutation assay measured it: of 24 mutants over this
// wave's core files, 14 were killed and 10 survived, and every one of the ten
// was in the hand-written `==` below. Flipping any `&&` to `||` makes two models
// that differ in a field compare equal, and flipping any field's `==` to `!=`
// makes two identical models compare unequal — and nothing noticed either.
//
// It is written by hand rather than synthesised, so the trap is real: a field
// added to `Model` and forgotten in `==` compiles, ships, and is invisible. The
// operator has no caller in the product today, which is exactly why it is worth
// pinning now: the obvious optimisation for the render loop is to skip a redraw
// when the model has not changed, and an `==` that cannot tell two models apart
// turns that into a screen that stops updating while a run is moving — the one
// failure this surface exists to prevent.

@Suite("TUI model equality")
struct TUIModelEqualityTests {

    /// One model per field, each differing from the base in exactly that field.
    ///
    /// The name is what a failure prints, so it names the field rather than an
    /// index: "history" is a defect report and "case 8" is a puzzle.
    static var variants: [(String, TUISurface.Model)] {
        func changed(_ mutate: (inout TUISurface.Model) -> Void) -> TUISurface.Model {
            var m = TUISurface.Model()
            mutate(&m)
            return m
        }
        return [
            ("pane", changed { $0.pane = .history }),
            ("connection", changed { $0.connection = .unreachable(reason: "gone", staleSeconds: 4) }),
            ("run", changed { $0.run = TUISurface.Run(phase: .acting, headline: ["Act"],
                                                     facts: [], step: 1, steps: 3) }),
            ("lanes", changed { $0.lanes = [TUISurface.Lane(name: "mac", holder: "-",
                                                            state: "free", wait: "-")] }),
            ("laneCap", changed { $0.laneCap = "one at a time" }),
            ("grants", changed { $0.grants = [TUISurface.Row4(["a", "b", "c"])] }),
            ("readiness", changed { $0.readiness = [TUISurface.Row4(["a", "b", "c"])] }),
            ("history", changed { $0.history = [TUISurface.Row4(["a", "b", "c", "d", "e"])] }),
            ("historyUnreadable", changed { $0.historyUnreadable = 3 }),
            ("historyPage", changed { $0.historyPage = (2, 5) }),
            ("historySelection", changed { $0.historySelection = 1 }),
            ("switches", changed { $0.switches = [TUISurface.Row4(["a", "b", "c", "d"])] }),
            ("handshake", changed { $0.handshake = 12 }),
        ]
    }

    @Test("two models built the same way are equal")
    func identicalModelsAreEqual() {
        // Two independently built values rather than one value compared to
        // itself. Reflexivity is what a `!=` mutation on a field breaks, so
        // `x == x` would catch it — but it is also the shape
        // scripts/campaign/cannotfail_swift.py exists to report, and a rule with
        // a standing exception is a rule nobody trusts. Building the pair twice
        // asserts the same thing without the shape, and is the stronger claim:
        // it does not lean on identity.
        let fresh = TUISurface.Model()
        let alsoFresh = TUISurface.Model()
        #expect(fresh == alsoFresh)
        for (name, _) in Self.variants {
            let a = Self.variants.first { $0.0 == name }!.1
            let b = Self.variants.first { $0.0 == name }!.1
            #expect(a == b, "two models built the same way differ once \(name) is set")
        }
    }

    @Test("a difference in any one field makes two models unequal", arguments: variants.map(\.0))
    func everyFieldParticipates(_ field: String) {
        let base = TUISurface.Model()
        let variant = Self.variants.first { $0.0 == field }!.1
        #expect(base != variant,
                "\(field) is not compared by ==, so a model that changed only there reads as unchanged")
        #expect(variant != base, "and the comparison is symmetric in \(field)")
    }

    @Test("the field list here is the field list on Model")
    func noFieldWentUncovered() {
        // A floor rather than a mirror: reflection over a struct with a
        // hand-written `==` cannot see which fields that operator reads, so what
        // is checked is that every stored property has a variant above. A field
        // added to Model and not added here fails on the count before anybody
        // has to notice it is missing from the operator too.
        let mirrored = Mirror(reflecting: TUISurface.Model()).children.compactMap(\.label)
        let covered = Set(Self.variants.map(\.0))
        let missing = mirrored.filter { !covered.contains($0) }
        #expect(missing.isEmpty,
                "these stored properties have no equality variant: \(missing.joined(separator: ", "))")
        #expect(covered.count == mirrored.count)
    }
}
