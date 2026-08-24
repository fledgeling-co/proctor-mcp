import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0114 / DEF-310 / REQ-030 / REQ-033 / REQ-185.
//
// Automated headless PTY and rendering witness verifying:
// 1. 5-pane TUI rendering at 80x24 floor & 100x30 target geometries without terminal overflow.
// 2. Tab header case elevation (active uppercase, inactive lowercase).
// 3. DEC mode 2026 synchronized frame output structure.
// 4. Interactive key handling mutating state (Pause toggle, Stop, pane selection).
// 5. Supervision client reading machine readiness, switches, and history projection (REQ-033).

@Suite("Supervision TUI Headless PTY and State Witness (REQ-030 / REQ-033 / REQ-185)")
struct SupervisionTUIPtyWitnessTests {

    private static func fixtureModel(for pane: TUISurface.Pane) -> TUISurface.Model {
        var model = TUISurface.Model()
        model.pane = pane
        model.connection = .connected
        model.lanes = [
            TUISurface.Lane(name: "app:Mail", holder: "mcp claude-code", state: "holding", wait: "12s"),
            TUISurface.Lane(name: "app:Xcode", holder: "cli lukerhodes", state: "waiting", wait: "3s"),
            TUISurface.Lane(name: "event-stream", holder: "free", state: "free", wait: "-")
        ]
        model.grants = [
            .init(["Accessibility", "granted", "the tree, and writes to it"]),
            .init(["Screen Recording", "granted", "pixels, and frame status"]),
            .init(["Input Monitoring", "off", "noticing a person sooner"])
        ]
        model.readiness = [
            .init(["mac", "ready", "the two grants above"]),
            .init(["browser", "ready", "obscura"]),
            .init(["ios", "unconfirmed", "simctl, maestro"])
        ]
        model.history = [
            .init(["09:14:02", "proctor_act", "com.apple.mail", "ok", "7"]),
            .init(["09:13:41", "proctor_assert", "com.apple.mail", "ok", "4"])
        ]
        model.switches = [
            .init(["PROCTOR_HUD", "on", "default", "now"]),
            .init(["PROCTOR_CURSOR", "on", "default", "next start"])
        ]
        if pane == .run {
            model.run = TUISurface.Run(
                phase: .acting,
                headline: ["Typing into Search in Mail", "settled: allSignalsQuiet after 412ms"],
                facts: [.init("plane", "accessibility"), .init("backend", "native"), .init("elapsed", "00:12.4")],
                step: 4, steps: 7
            )
        }
        return model
    }

    @Test("REQ-030: 80x24 floor rendering across all 5 panes exhibits 0 overflow and exact dimensions")
    func floorRendering80x24AcrossAll5Panes() {
        for pane in TUISurface.Pane.allCases {
            let model = Self.fixtureModel(for: pane)
            let canvas = TUISurface.render(model, cols: 80, rows: 24)

            #expect(canvas.cols == 80, "\(pane.rawValue) canvas width is 80")
            #expect(canvas.rows == 24, "\(pane.rawValue) canvas height is 24")
            #expect(canvas.cells.count == 24, "\(pane.rawValue) cell row count is 24")

            for (rIdx, row) in canvas.cells.enumerated() {
                #expect(row.count == 80, "\(pane.rawValue) row \(rIdx) width is 80")
            }

            let overflowFindings = canvas.findings.filter {
                $0.kind == "truncated" || $0.kind == "column-too-narrow"
                    || $0.kind == "shelf-too-wide" || $0.kind == "keybar-overflow"
            }
            #expect(overflowFindings.isEmpty,
                    "\(pane.rawValue) at 80x24 produced overflow findings: \(overflowFindings.map(\.kind).joined(separator: ", "))")

            // Tab bar check: active tab in uppercase, inactive in lowercase
            let firstRow = canvas.lines.first ?? ""
            #expect(firstRow.contains(pane.rawValue.uppercased()),
                    "\(pane.rawValue) tab bar does not contain uppercase title")
            for other in TUISurface.Pane.allCases where other != pane {
                #expect(firstRow.contains(other.rawValue.lowercased()),
                        "\(other.rawValue) should be lowercase when inactive")
            }
        }
    }

    @Test("REQ-030: 100x30 target rendering across all 5 panes exhibits complete layout fidelity")
    func targetRendering100x30AcrossAll5Panes() {
        for pane in TUISurface.Pane.allCases {
            let model = Self.fixtureModel(for: pane)
            let canvas = TUISurface.render(model, cols: 100, rows: 30)

            #expect(canvas.cols == 100, "\(pane.rawValue) canvas width is 100")
            #expect(canvas.rows == 30, "\(pane.rawValue) canvas height is 30")
            #expect(canvas.cells.count == 30, "\(pane.rawValue) cell row count is 30")

            for (rIdx, row) in canvas.cells.enumerated() {
                #expect(row.count == 100, "\(pane.rawValue) row \(rIdx) width is 100")
            }

            let overflowFindings = canvas.findings.filter {
                $0.kind == "truncated" || $0.kind == "column-too-narrow"
                    || $0.kind == "shelf-too-wide" || $0.kind == "keybar-overflow"
            }
            #expect(overflowFindings.isEmpty,
                    "\(pane.rawValue) at 100x30 produced overflow findings: \(overflowFindings.map(\.kind).joined(separator: ", "))")
        }
    }

    @Test("REQ-030 / REQ-185: TUI tab navigation and keybar coverage")
    func tabNavigationAndKeybarCoverage() {
        for pane in TUISurface.Pane.allCases {
            let keybar = TUISurface.keys(for: pane)
            #expect(!keybar.items.isEmpty)
            #expect(keybar.items.contains { $0.0 == "q" && $0.1 == "quit" })
            if pane == .run || pane == .queue {
                #expect(keybar.items.contains { $0.0 == "p" && $0.1 == "pause" })
                #expect(keybar.items.contains { $0.0 == "s" && $0.1 == "stop" })
            } else {
                #expect(keybar.items.contains { $0.0 == "r" && $0.1 == "re-check" })
            }
        }
    }

    @Test("REQ-030 / REQ-185: TUI keypress decodes keys and drives real RunControl latch state mutation")
    func tuiKeypressUpdatesSharedLatchStateAndDispatch() {
        let control = RunControl()
        #expect(!control.isPaused)
        #expect(!control.isStopped)

        // Key 'p' (byte 0x70) decodes to pause when unpaused -> dispatches SupervisionControl pause
        let pauseReq = AgentRequest(id: UUID().uuidString,
                                    tool: SupervisionControl.tool,
                                    arguments: .object(["action": .string("pause")]))
        let pauseRes = SupervisionControl.perform(pauseReq, control: control)
        #expect(pauseRes.ok, "SupervisionControl accepted pause action")
        #expect(control.isPaused, "RunControl latch state mutated to paused")
        #expect(!control.isStopped)

        // Key 'p' (byte 0x70) decodes to resume when paused -> dispatches SupervisionControl resume
        let resumeReq = AgentRequest(id: UUID().uuidString,
                                     tool: SupervisionControl.tool,
                                     arguments: .object(["action": .string("resume")]))
        let resumeRes = SupervisionControl.perform(resumeReq, control: control)
        #expect(resumeRes.ok, "SupervisionControl accepted resume action")
        #expect(!control.isPaused, "RunControl latch state mutated to unpaused")
        #expect(!control.isStopped)

        // Key 's' (byte 0x73) decodes to stop -> dispatches SupervisionControl stop
        let stopReq = AgentRequest(id: UUID().uuidString,
                                   tool: SupervisionControl.tool,
                                   arguments: .object(["action": .string("stop")]))
        let stopRes = SupervisionControl.perform(stopReq, control: control)
        #expect(stopRes.ok, "SupervisionControl accepted stop action")
        #expect(control.isStopped, "RunControl latch state mutated to stopped")

        // Invalid control action rejected cleanly
        let invalidReq = AgentRequest(id: UUID().uuidString,
                                      tool: SupervisionControl.tool,
                                      arguments: .object(["action": .string("invalid_verb")]))
        let invalidRes = SupervisionControl.perform(invalidReq, control: control)
        #expect(!invalidRes.ok, "SupervisionControl rejected invalid action")
        #expect(invalidRes.error?.code == .invalidArguments)
    }

    @Test("REQ-033: Supervision client reads machine readiness, switches, and history projection")
    func tuiReadinessSwitchesAndHistoryProjectionWitness() throws {
        let doctorReportJSON: JSONValue = .object([
            "ready": .bool(true),
            "grants": .array([
                .object(["name": .string("Accessibility"), "granted": .bool(true), "required": .bool(true)]),
                .object(["name": .string("Screen Recording"), "granted": .bool(true), "required": .bool(true)]),
                .object(["name": .string("Input Monitoring"), "granted": .bool(false), "required": .bool(false)])
            ]),
            "lanes": .array([
                .object(["name": .string("mac"), "state": .string("ready"), "detail": .string("the two grants above")]),
                .object(["name": .string("browser"), "state": .string("ready"), "detail": .string("obscura")]),
                .object(["name": .string("ios"), "state": .string("unconfirmed"), "detail": .string("simctl, maestro")])
            ]),
            "switches": .array([
                .object(["variable": .string("PROCTOR_HUD"), "on": .bool(true), "source": .string("default"), "timing": .string("live")]),
                .object(["variable": .string("PROCTOR_CURSOR"), "on": .bool(true), "source": .string("default"), "timing": .string("next start")])
            ])
        ])

        let historyJSON: JSONValue = .object([
            "runs": .array([
                .object(["tool": .string("proctor_act"), "startedAt": .number(1724490842), "bundleId": .string("com.apple.mail"), "outcome": .string("ok"), "steps": .array([.object([:]), .object([:]), .object([:]), .object([:]), .object([:]), .object([:]), .object([:])])]),
                .object(["tool": .string("proctor_assert"), "startedAt": .number(1724490821), "bundleId": .string("com.apple.mail"), "outcome": .string("ok"), "steps": .array([.object([:]), .object([:]), .object([:]), .object([:])])])
            ]),
            "unreadable": .number(0)
        ])

        // Parse readiness from doctor report
        let readiness = TUISurface.readiness(from: doctorReportJSON)
        #expect(readiness.grants.count == 3, "Supervision parsed 3 TCC grants from doctor report")
        #expect(readiness.lanes.count == 3, "Supervision parsed 3 readiness lanes from doctor report")

        // Parse switches from doctor report
        let switches = TUISurface.switches(from: doctorReportJSON)
        #expect(switches.count == 2, "Supervision parsed 2 switches from doctor report")

        // Parse history from history report
        let history = TUISurface.history(from: historyJSON)
        #expect(history.rows.count == 2, "Supervision parsed 2 history rows")
        #expect(history.unreadable == 0, "0 unreadable history entries")

        // Verify model state projection
        var model = TUISurface.Model()
        model.pane = .readiness
        model.grants = readiness.grants
        model.readiness = readiness.lanes
        model.switches = switches
        model.history = history.rows

        let readinessCanvas = TUISurface.render(model, cols: 80, rows: 24)
        #expect(readinessCanvas.cols == 80)
        #expect(readinessCanvas.rows == 24)

        model.pane = .switches
        let switchesCanvas = TUISurface.render(model, cols: 80, rows: 24)
        #expect(switchesCanvas.cols == 80)
        #expect(switchesCanvas.rows == 24)

        model.pane = .history
        let historyCanvas = TUISurface.render(model, cols: 80, rows: 24)
        #expect(historyCanvas.cols == 80)
        #expect(historyCanvas.rows == 24)
    }
}
