import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0019 — the agent's half of "this run is going to take your machine".
//
// The panel already said it, once, during the step. This is about reach and
// timing: the same fact before the batch starts, on a surface that does not
// depend on which display the panel landed on, and as a field on the result
// rather than as something you find out by watching.
//
// What is NOT testable here: the panel drawing the row, the menu-bar glyph
// changing, the menu line rendering. `swift test` has no window server. What is
// testable is every value those surfaces read, and that is what is here.

@Suite("Foreground disclosure wiring")
struct ForegroundWiringTests {

    private static let target = "com.example.target"

    private func harness() async throws -> (session: Session, ax: FakeAX) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture())
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax)
    }

    private func act(_ h: (session: Session, ax: FakeAX), _ steps: [ActionStep],
                     foreground: Bool = false) async throws -> JSONValue {
        try await h.session.act(window: h.ax.window.id, steps: steps, settle: .default,
                                foreground: foreground, captureEach: false, diffEach: false,
                                record: nil)
    }

    private func step(_ kind: ActionStep.Kind) -> ActionStep {
        ActionStep(kind: kind, node: "node-1")
    }

    @Test("a background-safe run reports that nothing needed the front")
    func backgroundSafeRun() async throws {
        let h = try await harness()
        let result = try await act(h, [step(.press), step(.setValue)])
        let block = try #require(result["foreground"])
        #expect(block["measured"]?.intValue == 0)
        #expect(block["ranInForeground"]?.boolValue == false)
        #expect(block["totalSteps"]?.intValue == 2)
    }

    @Test("a run that took the front says so as a field, not as a sentence to parse")
    func foregroundRunIsAField() async throws {
        let h = try await harness()
        h.ax.planeAt = [1: .syntheticEvent]
        let result = try await act(h, [step(.press), step(.click)], foreground: true)
        let block = try #require(result["foreground"])
        #expect(block["declaredCertain"]?.intValue == 1)
        #expect(block["measured"]?.intValue == 1)
        #expect(block["ranInForeground"]?.boolValue == true)
    }

    @Test("a type that fell back to the event stream is counted, though nothing predicted it")
    func measuresTheFallback() async throws {
        let h = try await harness()
        // The field could not be written through the accessibility plane. A
        // kind-based count says 0; what actually happened is 1, and this is the
        // number that answers "can this suite run unattended".
        h.ax.planeAt = [0: .syntheticEvent]
        let result = try await act(h, [step(.type), step(.press)])
        let block = try #require(result["foreground"])
        #expect(block["declaredCertain"]?.intValue == 0)
        #expect(block["declaredConditional"]?.intValue == 1)
        #expect(block["measured"]?.intValue == 1)
    }

    @Test("a step that never ran is not counted as having taken the machine")
    func unrunStepsAreNotCounted() async throws {
        let h = try await harness()
        h.ax.failPerformAt = 0
        let result = try await act(h, [step(.press), step(.press)])
        let block = try #require(result["foreground"])
        #expect(block["measured"]?.intValue == 0)
        #expect(result["failedAt"]?.intValue == 0)
    }

    @Test("the menu bar can answer whether a run is taking the machine, with the panel off")
    func menuBarSeesTheRun() async throws {
        let h = try await harness()
        // The panel is off in this harness, which is the point: the scheduler and
        // the disclosure both run whether or not anything is drawn, and this is
        // the surface that reaches somebody looking at another display.
        h.ax.planeAt = [0: .syntheticEvent]
        let steps = [step(.click), step(.press), step(.press), step(.press)]

        let running = Task { try await act(h, steps, foreground: true) }
        // Sampled from outside, while the run is in flight: the state is cleared
        // when the batch ends, so reading it afterwards would only ever show the
        // resting value. The run suspends on every settle, so a poll gets in.
        var sample: JSONValue?
        for _ in 0..<400 {
            let block = await h.session.recentActivity()["foreground"]
            if block?["active"]?.boolValue == true { sample = block; break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        _ = try await running.value

        let block = try #require(sample, "the run never reported taking the foreground")
        #expect(block["running"]?.boolValue == true)
        #expect(block["takesForeground"]?.boolValue == true)
        #expect(block["certain"]?.intValue == 1)
        #expect(block["total"]?.intValue == 4)
        // The click has already been posted, so the menu bar is entitled to say
        // the machine is being taken right now.
        #expect(block["active"]?.boolValue == true)
        #expect(block["notice"]?.stringValue?.contains("in front") == true)
    }

    @Test("a finished run stops claiming the machine")
    func stateClearsWhenTheRunEnds() async throws {
        let h = try await harness()
        h.ax.planeAt = [0: .syntheticEvent]
        _ = try await act(h, [step(.click)], foreground: true)
        let block = try #require(await h.session.recentActivity()["foreground"])
        #expect(block["running"]?.boolValue == false)
        #expect(block["active"]?.boolValue == false)
        #expect(block["notice"] == .null)
    }

    @Test("a harmless run ending does not clear a foreground run still going beside it")
    func overlappingRunsDoNotWipeEachOther() async throws {
        // Two applications are two app lanes, so two runs genuinely overlap. A
        // single slot for the live state would let the short background-safe one
        // report the machine as free on its way out while the other is still
        // posting events, which is the menu bar saying the opposite of the truth.
        let h = try await harness()
        let taking = await h.session.foregroundBegan(
            demand: Session.foregroundDemand(for: [step(.click)], foreground: true),
            app: "Acme Console")
        await h.session.foregroundStep(run: taking, plane: .syntheticEvent)

        let harmless = await h.session.foregroundBegan(
            demand: Session.foregroundDemand(for: [step(.press)], foreground: false),
            app: "Other App")
        await h.session.foregroundEnded(run: harmless)

        let block = try #require(await h.session.recentActivity()["foreground"])
        #expect(block["running"]?.boolValue == true)
        #expect(block["active"]?.boolValue == true)
        #expect(block["takesForeground"]?.boolValue == true)
        // And the run reported on is the one taking the machine, not whichever
        // happened to be first.
        #expect(block["app"]?.stringValue == "Acme Console")

        await h.session.foregroundEnded(run: taking)
        let after = try #require(await h.session.recentActivity()["foreground"])
        #expect(after["running"]?.boolValue == false)
    }

    @Test("the scheduler and the disclosure agree about the same batch")
    func laneAndDisclosureAgree() async throws {
        let h = try await harness()
        // Both read `ForegroundDemand.takesForeground`. A batch that takes the
        // exclusive global lane is exactly a batch the panel warns about; if
        // these two ever came apart, one of the two surfaces would be lying.
        for (kinds, expected) in [([ActionStep.Kind.press], false),
                                  ([.press, .click], true),
                                  ([.press, .raise], true),
                                  ([.type, .press], false)] {
            let demand = Session.foregroundDemand(for: kinds.map(step), foreground: false)
            let lanes = await h.session.lanes(for: kinds.map(step), window: h.ax.window,
                                              foreground: false)
            #expect(demand.takesForeground == expected, "\(kinds)")
            #expect(lanes.needsGlobal == demand.takesForeground, "\(kinds)")
        }
    }
}
