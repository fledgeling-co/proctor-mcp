import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0015 — the half of the run HUD that is not drawing.
//
// The panel's whole reason for existing is that somebody can stop a run, so the
// tests that matter are about what a stop actually does: the steps already done
// survive, nothing runs after the halt, the refusal lands on the first step that
// never ran and says a person did it, and the halt is accounted for in the trail
// like any other refusal. None of that needs a window, which is why it is here
// rather than left to a human's glance.
//
// What is NOT testable here: the panel rendering, a click reaching Pause, the
// blur, the appearance and the drag. `swift test` has no window server.

@Suite("Run control")
struct RunControlTests {

    private func control(now: @escaping @Sendable () -> Double = { 0 },
                         limit: TimeInterval = 900) -> RunControl {
        let control = RunControl(pauseLimit: limit, now: now)
        control.pollNanoseconds = 1_000_000
        return control
    }

    @Test("a run nobody has touched is never held up")
    func idlePassesThrough() async {
        let control = control()
        #expect(await control.checkpoint(run: 0) == nil)
        #expect(!control.isPaused)
        #expect(!control.isStopped)
    }

    @Test("Stop is seen at the next checkpoint and keeps being seen")
    func stopIsSticky() async {
        let control = control()
        control.stop()
        #expect(await control.checkpoint(run: 0) == .stopped)
        // Sticky on purpose: a run stopped once must not resume itself at the
        // next step because nobody pressed the button a second time.
        #expect(await control.checkpoint(run: 0) == .stopped)
    }

    @Test("Pause holds the checkpoint until somebody resumes it")
    func pauseHoldsUntilResumed() async throws {
        let control = control()
        control.pause()

        let held = Task { await control.checkpoint(run: 0) }
        // The checkpoint is parked, not spinning on a lock: the resume below
        // arrives from a different task and is seen.
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(control.isPaused)
        control.resume()
        #expect(await held.value == nil)
        #expect(!control.isPaused)
    }

    @Test("Stop releases a pause rather than leaving the run held for ever")
    func stopEndsAPause() async {
        let control = control()
        control.pause()
        let held = Task { await control.checkpoint(run: 0) }
        control.stop()
        #expect(await held.value == .stopped)
    }

    @Test("a pause nobody resumes gives up on the backstop, and says that is what happened")
    func pauseBackstop() async {
        // A paused run holds Proctor's attention, so an unbounded hold queues
        // every other request behind it. The clock is injected: this is a
        // fifteen-minute rule proved in milliseconds.
        let clock = MutableClock(0)
        let control = control(now: { clock.value }, limit: 900)
        control.pause()
        clock.value = 901

        let halt = await control.checkpoint(run: 0)
        #expect(halt == .pauseExpired(seconds: 900))
        // And it gives up the way a stop does, so the run does not carry on
        // after the pause it was told to hold at.
        #expect(control.isStopped)
        #expect(!control.isPaused)
    }

    @Test("a pause inside the backstop is still a pause")
    func pauseWithinTheBackstop() async throws {
        let clock = MutableClock(0)
        let control = control(now: { clock.value }, limit: 900)
        control.pause()
        clock.value = 899

        let held = Task { await control.checkpoint(run: 0) }
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(control.isPaused)
        control.resume()
        #expect(await held.value == nil)
    }

    @Test("a new run starts with nobody's hand on it")
    func beginClearsTheLatch() async {
        let control = control()
        control.stop()
        control.begin(run: 0)
        #expect(await control.checkpoint(run: 0) == nil)
    }

    @Test("the backstop is adjustable by the same kind of setting as the off-switch")
    func backstopIsConfigurable() {
        #expect(RunControl.pauseLimit(from: [:]) == RunControl.defaultPauseLimit)
        #expect(RunControl.pauseLimit(from: ["PROCTOR_HUD_PAUSE_LIMIT": "60"]) == 60)
        // A nonsense value falls back rather than producing a pause that expires
        // instantly or never.
        #expect(RunControl.pauseLimit(from: ["PROCTOR_HUD_PAUSE_LIMIT": "nope"])
                == RunControl.defaultPauseLimit)
        #expect(RunControl.pauseLimit(from: ["PROCTOR_HUD_PAUSE_LIMIT": "0"])
                == RunControl.defaultPauseLimit)
    }

    @Test("both halts refuse under their own code, never as a policy rule or an app fault")
    func haltRefusals() {
        for halt in [RunControl.Halt.stopped, .pauseExpired(seconds: 900)] {
            let refusal = halt.refusal
            #expect(refusal.code == .haltedByPerson)
            #expect(refusal.code != .policyDenied)
            #expect(refusal.code != .actionFailed)
            #expect(refusal.remedy?.isEmpty == false)
        }
        #expect(RunControl.Halt.stopped.refusal.message.contains("a person stopped"))
        #expect(RunControl.Halt.pauseExpired(seconds: 900).refusal.message.contains("900"))
    }
}

/// A clock a test moves by hand. `@unchecked Sendable` because the mutation and
/// the read are both on the test's own task.
private final class MutableClock: @unchecked Sendable {
    var value: Double
    init(_ value: Double) { self.value = value }
}

@Suite("Run HUD halt wiring")
struct RunHUDWiringTests {

    private static let target = "com.example.target"

    /// A session driving a fake app, with the trail collected in memory, its own
    /// halt latch, and the panel off — the panel needs a window server and the
    /// decisions being tested do not.
    private func harness(steps: Int = 3)
    async throws -> (session: Session, ax: FakeAX, audit: AuditCollector,
                     control: RunControl, steps: [ActionStep]) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture())
        let audit = AuditCollector()
        let control = RunControl(pauseLimit: 900, now: { 0 })
        control.pollNanoseconds = 1_000_000
        await session.setAuditSink(audit.sink)
        await session.setDrawsHUD(false)
        // A feed of this session's own, so the switch and the phase can be driven
        // without reaching into the singleton another test is also using. Started
        // off, which is what an agent launched with PROCTOR_HUD off looks like.
        await session.setHUDFeed(RunHUDFeed(drawing: false))
        await session.setRunControl(control)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)

        let list = (0..<steps).map {
            ActionStep(kind: .press, node: "node-1", label: "step \($0)")
        }
        return (session, ax, audit, control, list)
    }

    @Test("a person's stop ends the run after the step in flight, and nothing after it runs")
    func stopEndsTheRun() async throws {
        let h = try await harness(steps: 4)
        // Somebody presses Stop while step 0 is being actuated. The step in
        // flight finishes — killing it would leave the app in a state nobody can
        // describe — and the run stops before step 1.
        h.ax.onPerform = { [control = h.control] index in
            if index == 0 { control.stop() }
        }

        let result = try await h.session.act(window: h.ax.window.id, steps: h.steps,
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)

        #expect(h.ax.performed.count == 1)
        #expect(result["completed"]?.intValue == 1)
        #expect(result["failedAt"]?.intValue == 1)
    }

    @Test("the steps already done are still reported alongside the refusal")
    func completedStepsSurvive() async throws {
        let h = try await harness(steps: 4)
        h.ax.onPerform = { [control = h.control] index in
            if index == 1 { control.stop() }
        }

        let result = try await h.session.act(window: h.ax.window.id, steps: h.steps,
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        let steps = try #require(result["steps"]?.arrayValue)
        #expect(result["completed"]?.intValue == 2)
        #expect(steps.count == 3)                       // two done, one refused
        #expect(steps[0]["ok"]?.boolValue == true)
        #expect(steps[1]["ok"]?.boolValue == true)
    }

    @Test("the refusal lands on the first step that never ran, and names a person")
    func refusalNamesAPerson() async throws {
        let h = try await harness(steps: 3)
        h.ax.onPerform = { [control = h.control] index in
            if index == 0 { control.stop() }
        }

        let result = try await h.session.act(window: h.ax.window.id, steps: h.steps,
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        let steps = try #require(result["steps"]?.arrayValue)
        let halted = try #require(steps.last)
        #expect(halted["index"]?.intValue == 1)
        #expect(halted["ok"]?.boolValue == false)
        #expect(halted["error"]?["code"]?.stringValue == "haltedByPerson")
        let message = try #require(halted["error"]?["message"]?.stringValue)
        #expect(message.contains("a person stopped"))
        // Never reported as a configured rule or as a fault in the application.
        #expect(halted["error"]?["code"]?.stringValue != "policyDenied")
    }

    @Test("a stop with no step left to refuse simply lets the run complete")
    func stopAfterTheLastStep() async throws {
        let h = try await harness(steps: 2)
        h.ax.onPerform = { [control = h.control] index in
            if index == 1 { control.stop() }
        }

        let result = try await h.session.act(window: h.ax.window.id, steps: h.steps,
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        #expect(result["completed"]?.intValue == 2)
        #expect((result["failedAt"] ?? .null) == .null)
        #expect(h.ax.performed.count == 2)
    }

    @Test("a halt is recorded alongside the step it interrupted, like any other refusal")
    func haltIsAudited() async throws {
        let h = try await harness(steps: 3)
        h.ax.onPerform = { [control = h.control] index in
            if index == 0 { control.stop() }
        }

        _ = try await h.session.act(window: h.ax.window.id, steps: h.steps, settle: .default,
                                    foreground: false, captureEach: false, diffEach: false,
                                    record: nil)

        // A person halting a run is a security-relevant event, so it accounts for
        // itself in the trail rather than showing up as a run that just stopped.
        // It is written exactly as any other refused step is — the outcome
        // vocabulary the trail already uses — with the reason naming the person.
        let notOK = h.audit.records.filter { $0.outcome != "ok" }
        #expect(notOK.count == 1)
        let halt = try #require(notOK.first)
        #expect(halt.reason?.contains("a person stopped") == true)
        #expect(halt.tool == "proctor_act")
        // The step that did run is in the trail too, so the record accounts for
        // how far the run got as well as why it ended.
        #expect(h.audit.records.filter { $0.outcome == "ok" }.count == 1)
    }

    @Test("a pause holds the run and lets it carry on when it is resumed")
    func pauseThenResume() async throws {
        let h = try await harness(steps: 3)
        h.ax.onPerform = { [control = h.control] index in
            if index == 0 { control.pause() }
        }

        let run = Task {
            try await h.session.act(window: h.ax.window.id, steps: h.steps, settle: .default,
                                    foreground: false, captureEach: false, diffEach: false,
                                    record: nil)
        }
        // Held before step 1, with step 0 finished rather than killed mid-flight.
        // Polled rather than slept on a fixed delay: a fixed wait under a
        // parallel test run measures the machine, not the latch.
        var waited = 0
        while !h.control.isPaused, waited < 400 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waited += 1
        }
        #expect(h.control.isPaused)
        #expect(h.ax.performed.count == 1)

        h.control.resume()
        let result = try await run.value
        #expect(result["completed"]?.intValue == 3)
        #expect(h.ax.performed.count == 3)
    }

    @Test("a run left paused for ever gives up, and says a pause did it rather than a fault")
    func pauseBackstopEndsTheRun() async throws {
        let h = try await harness(steps: 3)
        h.control.pauseLimit = 0.02
        h.ax.onPerform = { [control = h.control] index in
            if index == 0 { control.pause() }
        }
        h.control.now = { Date().timeIntervalSince1970 }

        let result = try await h.session.act(window: h.ax.window.id, steps: h.steps,
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        let steps = try #require(result["steps"]?.arrayValue)
        #expect(result["completed"]?.intValue == 1)
        #expect(steps.last?["error"]?["code"]?.stringValue == "haltedByPerson")
        #expect(steps.last?["error"]?["message"]?.stringValue?.contains("resumed") == true)
    }

    @Test("Stop acts on the run the panel is showing, and never on the next one")
    func haltDoesNotLeakBetweenRuns() async throws {
        let h = try await harness(steps: 2)
        // Pressed while nothing is running. A latch that held this would make the
        // next unrelated run fail for a decision somebody made about a run that
        // had already ended, which is a stop control nobody could reason about.
        h.control.stop()

        let first = try await h.session.act(window: h.ax.window.id, steps: h.steps,
                                            settle: .default, foreground: false,
                                            captureEach: false, diffEach: false, record: nil)
        #expect(first["completed"]?.intValue == 2)

        // And a stop during a run still ends that one. The index counts every
        // perform this fake has seen, so the first step of the second run is
        // whatever the first run left off at.
        let firstStepOfSecondRun = h.ax.performed.count
        h.ax.onPerform = { [control = h.control] index in
            if index == firstStepOfSecondRun { control.stop() }
        }
        let second = try await h.session.act(window: h.ax.window.id, steps: h.steps,
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        #expect(second["completed"]?.intValue == 1)
        #expect(second["failedAt"]?.intValue == 1)
    }

    @Test("a run with the panel switched off still runs, and the health report says why")
    func hudOffStillRuns() async throws {
        let h = try await harness(steps: 2)
        let status = try #require(await h.session.hudStatus().objectValue)
        #expect(status["enabled"]?.boolValue == false)
        #expect(status["available"]?.boolValue == false)
        // A silent absence would leave somebody believing they have a stop button
        // they do not have, so the reason is spelled out.
        #expect(status["note"]?.stringValue?.contains("PROCTOR_HUD") == true)

        let result = try await h.session.act(window: h.ax.window.id, steps: h.steps,
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        #expect(result["completed"]?.intValue == 2)
    }

    @Test("with the panel on, the health report says whether it is actually on screen")
    func hudOnReportsPresence() async throws {
        let h = try await harness(steps: 1)
        await h.session.setDrawsHUD(true)
        await h.session.setHUDFeed(RunHUDFeed(drawing: true))
        let status = try #require(await h.session.hudStatus().objectValue)
        #expect(status["enabled"]?.boolValue == true)
        #expect(status["pauseLimitSeconds"]?.doubleValue == 900)
        // Nothing has drawn it in this process, and the report says so rather
        // than claiming a control that is not there.
        #expect(status["onScreen"]?.boolValue == false)
    }
}
