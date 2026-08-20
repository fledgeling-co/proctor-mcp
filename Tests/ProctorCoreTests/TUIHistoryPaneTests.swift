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
