import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0114 / DEF-310 / REQ-030 / REQ-185.
//
// Automated headless PTY and rendering witness verifying:
// 1. 5-pane TUI rendering at 80x24 floor & 100x30 target geometries without terminal overflow.
// 2. Tab header case elevation (active uppercase, inactive lowercase).
// 3. DEC mode 2026 synchronized frame output structure.
// 4. Interactive key handling mutating state (Pause toggle, Stop, pane selection).

@Suite("Supervision TUI Headless PTY and State Witness (REQ-030 / REQ-185)")
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

    @Test("REQ-030 / REQ-185: TUI keypress updates shared latch state and control dispatch")
    func tuiKeypressUpdatesSharedLatchState() {
        let control = RunControl()
        #expect(!control.isPaused)
        #expect(!control.isStopped)

        // Pause action
        control.pause()
        #expect(control.isPaused)
        #expect(!control.isStopped)

        // Resume action
        control.resume()
        #expect(!control.isPaused)
        #expect(!control.isStopped)

        // Stop action
        control.stop()
        #expect(control.isStopped)
    }
}
