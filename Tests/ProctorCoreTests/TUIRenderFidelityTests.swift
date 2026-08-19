import Foundation
import Testing
@testable import ProctorCore

// PRO-0074 A1/A2. The compiled mock is the oracle.
//
// The 22 frames under `design/surfaces/tui/` were compiled from declarative
// specs by tui-design, which measured every cell with tui-craft's width
// function. `TUIWidth` is the same arithmetic, so a difference between a frame
// and this renderer is a difference in the build rather than in the arithmetic
// — which is the whole reason the comparison is worth making.
//
// This is also what proves the 80-column floor rather than hoping for it: every
// case runs at both sizes, and a column narrower than its own content is a
// recorded finding rather than a torn border somebody notices in a screenshot.

@Suite("TUI render fidelity")
struct TUIRenderFidelityTests {

    /// The repo root, from this file rather than from a working directory: a
    /// test that depends on where it was launched from passes locally and fails
    /// in CI for a reason that has nothing to do with the code.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func frame(_ name: String) throws -> [String] {
        let url = root.appending(path: "design/surfaces/tui/\(name).json")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let cells = object?["cells"] as? [[[String: Any]]] ?? []
        return cells.map { row in
            row.map { cell in
                (cell["w"] as? Int) == 0 ? "" : (cell["ch"] as? String ?? " ")
            }.joined()
        }
    }

    /// Compare row by row and name the first difference by its row and column.
    /// A whole-frame equality failure prints two 30-line blobs and leaves the
    /// reader to find the cell.
    static func compare(_ measured: [String], _ expected: [String],
                        _ label: String) {
        #expect(measured.count == expected.count,
                "\(label): \(measured.count) rows against \(expected.count)")
        for (i, pair) in zip(measured, expected).enumerated() where pair.0 != pair.1 {
            let column = zip(pair.0, pair.1).enumerated().first { $0.element.0 != $0.element.1 }?
                .offset ?? min(pair.0.count, pair.1.count)
            Issue.record("""
                \(label) row \(i) differs at column \(column)
                  built: \(pair.0)
                  mock:  \(pair.1)
                """)
        }
    }

    // MARK: - The fixtures the mock was drawn from
    //
    // The same data the specs carry, so the comparison is of the layout rather
    // than of the copy. Where a value here disagrees with the frame, the frame
    // wins and this is wrong.

    static let lanes = [
        TUISurface.Lane(name: "app:Mail", holder: "mcp claude-code",
                        state: "holding", wait: "12s"),
        TUISurface.Lane(name: "event-stream", holder: "free", state: "free", wait: "-"),
        TUISurface.Lane(name: "app:Xcode", holder: "cli lukerhodes",
                        state: "waiting", wait: "3s"),
    ]

    static let busyLanes = [
        TUISurface.Lane(name: "app:Mail", holder: "mcp claude-code",
                        state: "paused", wait: "12s"),
        TUISurface.Lane(name: "app:Xcode", holder: "cli lukerhodes",
                        state: "waiting", wait: "31s"),
        TUISurface.Lane(name: "event-stream", holder: "mcp cursor",
                        state: "waiting", wait: "8s"),
    ]

    static func base(_ pane: TUISurface.Pane) -> TUISurface.Model {
        var m = TUISurface.Model()
        m.pane = pane
        return m
    }

    static var runIdeal: TUISurface.Model {
        var m = base(.run)
        m.run = TUISurface.Run(
            phase: .acting,
            headline: ["Typing into Search in Mail",
                       "settled: allSignalsQuiet after 412ms"],
            facts: [.init("plane", "accessibility"), .init("route", "selectedText"),
                    .init("backend", "native"), .init("elapsed", "00:12.4")],
            step: 4, steps: 7)
        m.lanes = lanes
        return m
    }

    static var runPartial: TUISurface.Model {
        var m = base(.run)
        m.run = TUISurface.Run(
            phase: .paused,
            headline: ["Paused. Somebody started using this Mac and",
                       "the run yielded at the first keystroke."],
            facts: [.init("held by", "contention yield"), .init("resumes", "on <p>"),
                    .init("pause cap", "15:00"), .init("elapsed", "00:12.4")],
            step: 4, steps: 7)
        m.lanes = busyLanes
        return m
    }

    static var runDone: TUISurface.Model {
        var m = base(.run)
        m.run = TUISurface.Run(
            phase: .finished,
            headline: ["Finished. 7 steps, no refusals.",
                       "2 took the foreground and said so."],
            facts: [.init("planes", "accessibility x5, syntheticEvent x2"),
                    .init("backend", "native"),
                    .init("recorded", "run-4f2c, sealed and signed"),
                    .init("elapsed", "00:41.8")],
            step: 7, steps: 7)
        return m
    }

    static var queueIdeal: TUISurface.Model {
        var m = base(.queue)
        m.lanes = [
            TUISurface.Lane(name: "app:Mail", holder: "mcp claude-code",
                            state: "holding", wait: "12s"),
            TUISurface.Lane(name: "app:Xcode", holder: "cli lukerhodes",
                            state: "waiting", wait: "31s"),
            TUISurface.Lane(name: "event-stream", holder: "mcp cursor",
                            state: "waiting", wait: "8s"),
            TUISurface.Lane(name: "app:Safari", holder: "free", state: "free", wait: "-"),
        ]
        m.laneCap = "45s"
        return m
    }

    static var readinessIdeal: TUISurface.Model {
        var m = base(.readiness)
        m.grants = [
            .init(["Accessibility", "granted", "the tree, and writes to it"]),
            .init(["Screen Recording", "granted", "pixels, and frame status"]),
            .init(["Input Monitoring", "off", "noticing a person sooner"]),
        ]
        m.readiness = [
            .init(["mac", "ready", "the two grants above"]),
            .init(["browser", "ready", "obscura"]),
            .init(["ios", "unconfirmed", "simctl, maestro"]),
            .init(["cua", "unavailable", "cua-driver, not on this Mac"]),
            .init(["guest", "ready", "lume, prlctl"]),
        ]
        return m
    }

    static var historyIdeal: TUISurface.Model {
        var m = base(.history)
        m.history = [
            .init(["09:14:02", "proctor_act", "com.apple.mail", "ok", "7"]),
            .init(["09:13:41", "proctor_assert", "com.apple.mail", "ok", "4"]),
            .init(["09:13:20", "proctor_act", "com.apple.dt.Xcode", "refused", "0"]),
            .init(["09:12:55", "proctor_apps", "com.apple.mail", "ok", "1"]),
            .init(["09:11:03", "proctor_flow", "com.apple.mail", "ok", "12"]),
            .init(["09:08:17", "proctor_guest", "-", "refused", "0"]),
        ]
        m.historySelection = 1
        m.historyPage = (1, 6)
        return m
    }

    static var switchesIdeal: TUISurface.Model {
        var m = base(.switches)
        m.switches = [
            .init(["PROCTOR_HUD", "on", "default", "now"]),
            .init(["PROCTOR_CURSOR", "on", "default", "next start"]),
            .init(["PROCTOR_TAKEOVER", "on", "default", "next start"]),
            .init(["PROCTOR_YIELD", "on", "saved", "next start"]),
            .init(["PROCTOR_YIELD_INPUT", "on", "saved", "next start"]),
            .init(["PROCTOR_TAKEOVER_INPUT", "off", "default", "next start"]),
            .init(["PROCTOR_SECOND_LANE", "off", "default", "next start"]),
            .init(["PROCTOR_ACTUATION", "off", "environment", "next start"]),
        ]
        return m
    }

    static var runLoading: TUISurface.Model {
        var m = base(.run)
        m.connection = .connecting
        return m
    }

    static var runError: TUISurface.Model {
        var m = base(.run)
        m.connection = .unreachable(reason: "Connection refused on the agent socket.",
                                    staleSeconds: 4)
        return m
    }

    static var cases: [(String, TUISurface.Model)] {
        [("run-empty", base(.run)), ("run-loading", runLoading), ("run-ideal", runIdeal),
         ("run-partial", runPartial), ("run-error", runError), ("run-done", runDone),
         ("queue-ideal", queueIdeal), ("readiness-ideal", readinessIdeal),
         ("history-ideal", historyIdeal), ("history-empty", base(.history)),
         ("switches-ideal", switchesIdeal)]
    }

    @Test("A2 · every pane renders exactly what the mock compiled, at 100x30",
          arguments: cases.map(\.0))
    func matchesTheMockAtDesignSize(_ name: String) throws {
        let model = Self.cases.first { $0.0 == name }!.1
        let built = TUISurface.render(model, cols: 100, rows: 30).lines
        Self.compare(built, try Self.frame("\(name)-100x30"), "\(name) at 100x30")
    }

    @Test("A1 · and again at the 80x24 floor, which is what still exists everywhere",
          arguments: cases.map(\.0))
    func matchesTheMockAtTheFloor(_ name: String) throws {
        let model = Self.cases.first { $0.0 == name }!.1
        let built = TUISurface.render(model, cols: 80, rows: 24).lines
        Self.compare(built, try Self.frame("\(name)-80x24"), "\(name) at 80x24")
    }

    @Test("A1 · nothing is clipped at the floor, so the floor is proven not hoped for",
          arguments: cases.map(\.0))
    func nothingIsClippedAtTheFloor(_ name: String) {
        let model = Self.cases.first { $0.0 == name }!.1
        let canvas = TUISurface.render(model, cols: 80, rows: 24)
        let clipped = canvas.findings.filter {
            $0.kind == "truncated" || $0.kind == "column-too-narrow"
                || $0.kind == "shelf-too-wide" || $0.kind == "keybar-overflow"
        }
        #expect(clipped.isEmpty,
                "\(name) at 80x24: \(clipped.map { "\($0.kind) \($0.where_)" }.joined(separator: ", "))")
    }
}

// PRO-0074 A2/A3. The build, captured and compared.
//
// The suite above proves the renderer reproduces the design. This proves the
// *running program* draws what the renderer produces — which is a different
// claim, and the one a capture can settle and a unit test cannot.
//
// The frames under `design/surfaces/tui/captures/` were taken from
// `proctor-cli tui` through a pty by tui-craft's `tui_capture.py`, at both
// sizes, and gated with `tui_gates.py --strict`: 0 high findings, and the
// attribute inventory reports bold and dim in use, so the ladder survives a
// monochrome terminal.
//
// They were captured against an agent that predates this feature, so the state
// on them is the one that says so. That is the state most worth having under a
// standing test: every other pane is drawn from data, and this one is drawn when
// there is none.

@Suite("TUI capture fidelity")
struct TUICaptureFidelityTests {

    static func capture(_ name: String) throws -> (rows: [String], kind: String) {
        let url = TUIRenderFidelityTests.root
            .appending(path: "design/surfaces/tui/captures/\(name).json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            as? [String: Any]
        let cells = object?["cells"] as? [[[String: Any]]] ?? []
        return (cells.map { row in
            row.map { ($0["w"] as? Int) == 0 ? "" : ($0["ch"] as? String ?? " ") }.joined()
        }, object?["kind"] as? String ?? "")
    }

    /// The reason is live text from the agent, so it is read back out of the
    /// capture rather than written here. Pinning it would make this a test of a
    /// string rather than of the layout around it.
    static func reason(from rows: [String]) -> String {
        String(rows[4].dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    @Test("A2 · the running program draws what the renderer produces, at 100x30")
    func captureMatchesTheBuildAtDesignSize() throws {
        let (rows, kind) = try Self.capture("run-tooold-100x30")
        // A mock supports no claim about a running program. This must be a
        // capture or the comparison below proves nothing.
        #expect(kind == "captured")
        var model = TUISurface.Model()
        model.connection = .tooOld(reason: Self.reason(from: rows))
        let built = TUISurface.render(model, cols: 100, rows: 30).lines
        TUIRenderFidelityTests.compare(built, rows, "capture at 100x30")
    }

    @Test("A2 · and at the 80x24 floor, where a wide glyph would have torn a border")
    func captureMatchesTheBuildAtTheFloor() throws {
        let (rows, kind) = try Self.capture("run-tooold-80x24")
        #expect(kind == "captured")
        var model = TUISurface.Model()
        model.connection = .tooOld(reason: Self.reason(from: rows))
        let built = TUISurface.render(model, cols: 80, rows: 24).lines
        TUIRenderFidelityTests.compare(built, rows, "capture at 80x24")
    }
}
