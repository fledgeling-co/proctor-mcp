import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0016 — the scheduler wired to real runs.
//
// The half that cannot be proved as arithmetic: that a lane is actually held
// across the awaits inside `runSteps`, that it comes back however a run ends,
// and that a caller told to wait is eventually told something rather than left
// hanging. All of it runs against a real `Session` driving fake AX and capture
// engines, because the thing under test is the interleaving and the interleaving
// only exists once there is an actor with awaits in it.
//
// What is NOT testable here: the queue bar rendering, a click on Hold, Clear or a
// row's drop control, and the expand. `swift test` has no window server.

@Suite("Queue wiring")
struct RunQueueWiringTests {

    private static let target = "com.example.target"

    /// A session with its own scheduler and its own halt latch, the panel off.
    /// One session is one machine's worth of lanes, which is exactly the
    /// production shape: every connection goes through one `Session`.
    private func harness(waitLimit: TimeInterval = 30)
    async throws -> (session: Session, ax: FakeAX, scheduler: RunScheduler) {
        let ax = FakeAX(bundleId: Self.target)
        let scheduler = RunScheduler(waitLimit: waitLimit, now: { 0 })
        let session = Session(ax: ax, capture: FakeCapture(), scheduler: scheduler)
        // Every step these tests drive is audited, and without a sink of its own
        // that lands in the operator's live trail. Its siblings already do this.
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setRunControl(RunControl(pauseLimit: 900, now: { 0 }))
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax, scheduler)
    }

    private func steps(_ n: Int) -> [ActionStep] {
        (0..<n).map { ActionStep(kind: .press, node: "node-1", label: "step \($0)") }
    }

    private func identity(_ name: String) -> RunSessionIdentity {
        RunSessionIdentity(project: name, connection: "0000", key: name)
    }

    private func act(_ session: Session, window: String, steps: [ActionStep],
                     as who: String) async throws -> JSONValue {
        try await SessionIdentity.$current.withValue(identity(who)) {
            try await session.act(window: window, steps: steps, settle: .default,
                                  foreground: false, captureEach: false, diffEach: false,
                                  record: nil)
        }
    }

    @Test("two sessions driving the same app take turns, and both finish")
    func sameAppSerialises() async throws {
        let h = try await harness()
        // The failure this replaces, reproduced exactly: `Session` is reentrant,
        // so isolation drops at every settle and capture await inside the step
        // loop, and before the queue existed these two runs' steps landed
        // interleaved. Each run labels its own steps, so the recorded order is
        // the evidence — every step of one before any step of the other.
        let one = (0..<4).map { ActionStep(kind: .press, node: "node-1", label: "one \($0)") }
        let two = (0..<4).map { ActionStep(kind: .press, node: "node-1", label: "two \($0)") }

        async let first: JSONValue = SessionIdentity.$current.withValue(identity("one")) {
            try await h.session.act(window: h.ax.window.id, steps: one, settle: .default,
                                    foreground: false, captureEach: false, diffEach: false,
                                    record: nil)
        }
        async let second: JSONValue = SessionIdentity.$current.withValue(identity("two")) {
            try await h.session.act(window: h.ax.window.id, steps: two, settle: .default,
                                    foreground: false, captureEach: false, diffEach: false,
                                    record: nil)
        }
        let results = try await [first, second]

        // Both completed in full: taking turns is not the same as one of them
        // losing, which is what a lock held too coarsely would produce.
        for result in results {
            #expect(result["completed"]?.intValue == 4)
            #expect((result["failedAt"] ?? .null) == .null)
        }

        let order = h.ax.performed.compactMap { $0.label?.prefix(3) }
        #expect(order.count == 8)
        // One switch between the two runs, and only one. Any interleaving shows
        // up here as three or more.
        let switches = zip(order, order.dropFirst()).filter { $0 != $1 }.count
        #expect(switches == 1, "steps interleaved: \(order.joined(separator: ", "))")

        // And the lanes came back afterwards, so the machine is not left wedged.
        let snapshot = await h.scheduler.snapshot()
        #expect(snapshot.active.isEmpty)
        #expect(snapshot.waiting.isEmpty)
    }

    @Test("two sessions driving different apps run at the same time")
    func differentAppsRunTogether() async throws {
        // The other half of the claim, and the reason this is three lanes rather
        // than one queue: an accessibility press is IPC to one process, so two
        // sessions on different apps genuinely do not interfere. Queueing them
        // would make Proctor feel broken for the common case.
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let a = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:a")]),
                                            identity: identity("one"), summary: "a")
        let b = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:b")]),
                                            identity: identity("two"), summary: "b")
        let snapshot = await scheduler.snapshot()
        #expect(snapshot.active.count == 2)
        #expect(snapshot.waiting.isEmpty)
        await scheduler.release(a)
        await scheduler.release(b)
    }

    @Test("a run that contends with nobody starts at once even with a line ahead of it")
    func joiningTheLineIsNotWaitingInIt() async throws {
        // The lost wake-up this closes: a run behind a blocked one, against an app
        // nothing else wants, used to sit in the list until some unrelated release
        // happened to wake it. It now starts on the same scan that put it there.
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let blocker = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:a")]),
                                                  identity: identity("one"), summary: "holding a")
        let queued = Task {
            try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:a")]),
                                        identity: identity("two"), summary: "wants a")
        }
        try await settle(scheduler) { $0.waiting.count == 1 }

        // Third in, second app, nothing in its way. It must not inherit the wait
        // of the run ahead of it.
        let free = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:b")]),
                                               identity: identity("three"), summary: "wants b")
        #expect(await scheduler.snapshot().active.count == 2)
        #expect(await scheduler.snapshot().waiting.count == 1)

        await scheduler.release(free)
        await scheduler.release(blocker)
        await scheduler.release(try await queued.value)
    }

    @Test("a synthetic run waits for the app it targets and holds it while it runs")
    func syntheticTakesTheMachine() async throws {
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let synthetic = LaneDemand(lanes: [.app("app:a"), .global])
        let held = try await scheduler.acquire(lanes: synthetic, identity: identity("one"),
                                               summary: "clicking")
        // Another synthetic run anywhere on the machine waits: there is one event
        // stream and the target has to be in front.
        let waiter = Task {
            try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:b"), .global]),
                                        identity: identity("two"), summary: "clicking elsewhere")
        }
        try await settle(scheduler) { $0.waiting.count == 1 }
        #expect(await scheduler.snapshot().active.count == 1)
        await scheduler.release(held)
        let ticket = try await waiter.value
        await scheduler.release(ticket)
    }

    @Test("a run holds its lane across every await inside the step loop")
    func laneIsHeldAcrossTheRun() async throws {
        let h = try await harness()
        // The load-bearing property. `runSteps` awaits on settling at every step,
        // and an actor drops isolation at an await — which is why a lane held by
        // the actor's own turn-taking would be no lane at all. This asserts the
        // lane is still held mid-run.
        let held = Sampler()
        h.ax.onPerform = { [scheduler = h.scheduler] _ in
            Task { await held.record(scheduler.snapshot().active.count) }
        }
        _ = try await act(h.session, window: h.ax.window.id, steps: steps(3), as: "one")
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(await held.samples.allSatisfy { $0 == 1 })
        #expect(await held.samples.isEmpty == false)
    }

    @Test("a whole batch queues, never a step")
    func theWholeBatchQueues() async throws {
        let h = try await harness()
        // One acquisition per call, so the queue's own list never grows a row per
        // step — splitting a six-step login across two sessions' turns is exactly
        // what this prevents.
        let seen = Sampler()
        h.ax.onPerform = { [scheduler = h.scheduler] _ in
            Task { await seen.record(scheduler.snapshot().active.first?.id ?? -1) }
        }
        _ = try await act(h.session, window: h.ax.window.id, steps: steps(5), as: "one")
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(Set(await seen.samples).count == 1)
    }

    @Test("a reading never joins the line")
    func readsNeverQueue() async throws {
        let h = try await harness()
        // Reads observe without mutating and never reach the step loop, so they
        // answer whatever is running. Note what this claims: reads never *queue*.
        // It is not a claim about the actor, which still takes its turn.
        _ = try await h.session.snapshot(window: h.ax.window.id,
                                         options: Session.SnapshotOptions(), sinceRevision: nil)
        _ = try await h.session.find(window: h.ax.window.id,
                                     predicate: FindPredicate(json: .object(["role": .string("AXButton")])),
                                     limit: 5)
        let snapshot = await h.scheduler.snapshot()
        #expect(snapshot.active.isEmpty)
        #expect(snapshot.waiting.isEmpty)
    }

    @Test("a lane comes back when a run throws, not only when it returns")
    func laneReleasedOnThrow() async throws {
        let h = try await harness()
        // A leaked hold wedges the machine until Proctor restarts, which is the
        // one failure worse than the interleaving this replaces.
        await #expect(throws: AgentError.self) {
            try await SessionIdentity.$current.withValue(self.identity("one")) {
                try await h.session.act(window: "win:nope", steps: self.steps(1), settle: .default,
                                        foreground: false, captureEach: false, diffEach: false,
                                        record: nil)
            }
        }
        // A window that does not resolve throws before the lane is ever taken —
        // and a run whose flow name is wrong throws after the gate, which is the
        // path that would actually leak one.
        await #expect(throws: AgentError.self) {
            try await h.session.flowReplay(name: "no-such-flow", window: h.ax.window.id,
                                           captureEach: false, settle: .default)
        }
        let snapshot = await h.scheduler.snapshot()
        #expect(snapshot.active.isEmpty)
    }

    @Test("a session may keep three runs waiting; the fourth is refused at once")
    func perSessionCap() async throws {
        let h = try await harness(waitLimit: 30)
        let looping = identity("loop")
        // Fill the lane and the allowance.
        let lanes = LaneDemand(lanes: [.app("app:x")])
        let holder = try await h.scheduler.acquire(lanes: lanes, identity: identity("holder"),
                                                   summary: "holder")
        var waiters: [Task<Void, Error>] = []
        for index in 0..<3 {
            waiters.append(Task {
                _ = try await h.scheduler.acquire(lanes: lanes, identity: looping,
                                                  summary: "waiting \(index)")
            })
        }
        try await settle(h.scheduler) { $0.waiting.count == 3 }

        // A session in a loop cannot starve the others, so it is told now rather
        // than joining a line it would only lengthen.
        await #expect(throws: AgentError.self) {
            _ = try await h.scheduler.acquire(lanes: lanes, identity: looping, summary: "fourth")
        }
        do {
            _ = try await h.scheduler.acquire(lanes: lanes, identity: looping, summary: "fourth")
        } catch let error as AgentError {
            #expect(error.code == .queueBusy)
            #expect(error.message.contains("3 runs waiting"))
        }
        _ = await h.scheduler.clear()
        await h.scheduler.release(holder)
        for waiter in waiters { waiter.cancel() }
    }

    @Test("a call still waiting when the ceiling fires is told the machine was busy")
    func ceilingFires() async throws {
        // Proved in milliseconds rather than in forty-five seconds. A caller that
        // gets no answer retries, and a retry behind a queue is how a queue
        // becomes a stampede — so the ceiling exists to make sure something is
        // always said.
        let scheduler = RunScheduler(waitLimit: 0.05, now: { 0 })
        let lanes = LaneDemand(lanes: [.app("app:x")])
        let holder = try await scheduler.acquire(lanes: lanes, identity: identity("one"),
                                                 summary: "holder")
        do {
            _ = try await scheduler.acquire(lanes: lanes, identity: identity("two"),
                                            summary: "waiter")
            Issue.record("the waiting call should have given up")
        } catch let error as AgentError {
            #expect(error.code == .queueBusy)
            #expect(error.message.contains("first of 1"))
            // Nothing was actuated, so this one really is safe to send again.
            #expect(error.remedy?.contains("safe to send again") == true)
        }
        await scheduler.release(holder)
    }

    @Test("Hold stops the next start and leaves the run in flight alone")
    func holdStopsTheNextStart() async throws {
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let lanes = LaneDemand(lanes: [.app("app:x")])
        let running = try await scheduler.acquire(lanes: lanes, identity: identity("one"),
                                                  summary: "running")
        await scheduler.setHeld(true)
        let waiter = Task {
            try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:y")]),
                                        identity: identity("two"), summary: "waiting")
        }
        try await settle(scheduler) { $0.waiting.count == 1 }
        // A different app entirely, which would otherwise have started at once.
        #expect(await scheduler.snapshot().active.count == 1)
        // The active run is untouched — Hold acts on the list, Stop acts on the
        // run, and they are deliberately different words on different rows.
        await scheduler.release(running)
        try await settle(scheduler) { $0.active.isEmpty }
        #expect(await scheduler.snapshot().waiting.count == 1)

        await scheduler.setHeld(false)
        let ticket = try await waiter.value
        await scheduler.release(ticket)
    }

    @Test("Clear returns every waiting call saying a person did it, and leaves the active run")
    func clearReturnsEveryone() async throws {
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let lanes = LaneDemand(lanes: [.app("app:x")])
        let running = try await scheduler.acquire(lanes: lanes, identity: identity("one"),
                                                  summary: "running")
        let waiters = (0..<2).map { index in
            Task { () -> AgentError? in
                do {
                    _ = try await scheduler.acquire(lanes: lanes, identity: identity("q\(index)"),
                                                    summary: "waiting")
                    return nil
                } catch let error as AgentError { return error }
            }
        }
        try await settle(scheduler) { $0.waiting.count == 2 }

        #expect(await scheduler.clear() == 2)
        for waiter in waiters {
            let error = try #require(await waiter.value)
            // A person's decision, not a failed step: one is a signal to stop and
            // ask, the other a signal to retry.
            #expect(error.code == .haltedByPerson)
            #expect(error.message.contains("cleared Proctor's queue"))
        }
        // The active run is untouched.
        #expect(await scheduler.snapshot().active.count == 1)
        await scheduler.release(running)
    }

    @Test("a drop returns one call; everything else keeps its place")
    func dropTakesOne() async throws {
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let lanes = LaneDemand(lanes: [.app("app:x")])
        let running = try await scheduler.acquire(lanes: lanes, identity: identity("one"),
                                                  summary: "running")
        let dropped = Task { () -> AgentError? in
            do {
                _ = try await scheduler.acquire(lanes: lanes, identity: identity("two"),
                                                summary: "first waiting")
                return nil
            } catch let error as AgentError { return error }
        }
        try await settle(scheduler) { $0.waiting.count == 1 }
        let survivor = Task {
            try await scheduler.acquire(lanes: lanes, identity: identity("three"),
                                        summary: "second waiting")
        }
        try await settle(scheduler) { $0.waiting.count == 2 }

        let victim = try #require(await scheduler.snapshot().waiting.first?.id)
        #expect(await scheduler.drop(id: victim))
        let error = try #require(await dropped.value)
        #expect(error.code == .haltedByPerson)
        #expect(error.message.contains("removed this run"))

        // Everything else keeps its position and its turn.
        let after = await scheduler.snapshot()
        #expect(after.waiting.count == 1)
        #expect(after.waiting.first?.summary == "second waiting")
        await scheduler.release(running)
        let ticket = try await survivor.value
        await scheduler.release(ticket)
    }

    @Test("a release re-examines the whole list, not only the lane that freed")
    func releaseWakesAMultiLaneWaiter() async throws {
        // A run waiting on two lanes would never be woken by one of them, and a
        // wake-up that never comes looks exactly like a wedged machine.
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let app = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:x")]),
                                              identity: identity("one"), summary: "app run")
        let waiter = Task {
            try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:x"), .global]),
                                        identity: identity("two"), summary: "synthetic run")
        }
        try await settle(scheduler) { $0.waiting.count == 1 }
        await scheduler.release(app)
        let ticket = try await waiter.value
        #expect(ticket.lanes.contains(.global))
        await scheduler.release(ticket)
    }

    @Test("a lane whose holder simply went away is reclaimed")
    func tornDownTicketReleases() async throws {
        // The backstop. A leaked hold wedges the machine until Proctor restarts,
        // so letting go of the receipt has to give the lane back even when
        // nothing called release.
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        do {
            _ = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("app:x")]),
                                            identity: identity("gone"), summary: "abandoned")
        }
        try await settle(scheduler) { $0.active.isEmpty }
        #expect(await scheduler.snapshot().active.isEmpty)
    }

    @Test("the permission gate is read again once the lane is ours")
    func gateIsRereadAfterTheWait() async throws {
        let h = try await harness(waitLimit: 5)
        // A run can sit in the line for the whole of the give-up ceiling, and the
        // approval that admitted it may have expired in that time. The authority
        // that matters is the one held when the app is actually touched — the
        // rule a repeated sweep already follows between its repeats. Policy is
        // installed in memory, never through the tool that writes the operator's
        // own file.
        await h.session.installPolicy(AppPolicy(allow: [Self.target]))

        // Hold the lane so the run has to wait, then withdraw its permission
        // while it waits.
        let blocker = try await h.scheduler.acquire(
            lanes: LaneDemand(lanes: [.app(h.ax.window.app)]),
            identity: identity("blocker"), summary: "holding")

        let run = Task { () -> AgentError? in
            do {
                _ = try await self.act(h.session, window: h.ax.window.id,
                                       steps: self.steps(2), as: "waiter")
                return nil
            } catch let error as AgentError { return error }
        }
        try await settle(h.scheduler) { $0.waiting.count == 1 }
        await h.session.installPolicy(AppPolicy(block: [Self.target]))
        await h.scheduler.release(blocker)

        let error = try #require(await run.value)
        #expect(error.code == .policyDenied)
        // Nothing was actuated, and the lane did not stay held behind the refusal.
        #expect(h.ax.performed.isEmpty)
        try await settle(h.scheduler) { $0.active.isEmpty }
    }

    @Test("the health report answers how many runs are active and waiting, per lane")
    func doctorSeesTheQueue() async throws {
        let h = try await harness()
        let status = try #require(await h.session.queueStatus().objectValue)
        #expect(status["active"]?.intValue == 0)
        #expect(status["waiting"]?.intValue == 0)
        #expect(status["held"]?.boolValue == false)
        #expect(status["perSessionWaitingCap"]?.intValue == 3)
        // The scheduler runs whether or not the panel is on screen, so a wedged
        // lane is answerable without a window.
        #expect(status["lanes"]?.arrayValue != nil)
    }

    /// Poll the scheduler until a condition holds. Polled rather than slept on a
    /// fixed delay: a fixed wait under a parallel test run measures the machine
    /// rather than the scheduler.
    private func settle(_ scheduler: RunScheduler,
                        _ condition: @escaping @Sendable (RunQueueSnapshot) -> Bool)
    async throws {
        for _ in 0..<400 {
            if condition(await scheduler.snapshot()) { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("the scheduler never reached the expected state")
    }
}

/// A recorder a fake engine can write to from any task.
private actor Sampler {
    private(set) var samples: [Int] = []
    func record(_ value: Int) { samples.append(value) }
}

// MARK: - PRO-0037: activate joins the line

@Suite("Activate queueing")
struct ActivateQueueWiringTests {

    private static let target = "com.example.target"

    @Test("a queued activate is refused as busy, before it activates anything")
    func aQueuedActivateIsRefusedWithoutActivating() async throws {
        let ax = FakeAX(bundleId: Self.target)
        // A ceiling short enough that the test is a test rather than a wait.
        let scheduler = RunScheduler(waitLimit: 0.2, now: { Date().timeIntervalSince1970 })
        let session = Session(ax: ax, capture: FakeCapture(), scheduler: scheduler)
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setRunControl(RunControl(pauseLimit: 900, now: { 0 }))

        // Somebody else holds the whole machine.
        let holder = try await scheduler.acquire(
            lanes: LaneDemand(lanes: [.global]),
            identity: RunSessionIdentity(project: "armada", connection: "b915", key: "armada"),
            summary: "Act x4")

        do {
            _ = try await session.activate(bundleId: Self.target, pid: nil, name: nil,
                                           app: nil, timeoutMs: 100)
            Issue.record("activate should have been refused while the global lane was held")
        } catch let error as AgentError {
            // `queueBusy` rather than `appNotFound` is the whole assertion: this
            // bundle id resolves to nothing on disk, so reaching the activation
            // at all would have produced the other error. Getting the queue's
            // refusal proves the lane was taken first and nothing was brought to
            // the front.
            #expect(error.code == .queueBusy)
            #expect(error.message.contains("still waiting"))
        }
        await scheduler.release(holder)
    }

    @Test("an activate on a free machine is not held up by the queue")
    func anUncontendedActivateDoesNotWait() async throws {
        let ax = FakeAX(bundleId: Self.target)
        let scheduler = RunScheduler(waitLimit: 45, now: { Date().timeIntervalSince1970 })
        let session = Session(ax: ax, capture: FakeCapture(), scheduler: scheduler)
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setRunControl(RunControl(pauseLimit: 900, now: { 0 }))

        // Most calls take the immediate path, which is what stops the queue
        // making Proctor feel broken for the common case. This one fails for the
        // reason it always did — nothing on disk matches — rather than waiting
        // out a ceiling.
        do {
            _ = try await session.activate(bundleId: Self.target, pid: nil, name: nil,
                                           app: nil, timeoutMs: 100)
            Issue.record("expected the unresolvable bundle id to fail")
        } catch let error as AgentError {
            #expect(error.code == .appNotFound)
        }
        // And the lane came back, however that ended.
        #expect(await scheduler.snapshot().active.isEmpty)
    }
}

// MARK: - The interlock that keeps a test off the operator's trail

@Suite("Audit trail isolation")
struct AuditIsolationTests {

    @Test("a test process resolves the audit trail away from the operator's own")
    func testsNeverWriteTheLiveTrail() {
        // This exists because the absence of it cost real data. A wiring test drove
        // a Session without redirecting its sink, wrote 17 entries into the live
        // trail, and fired the deliberately one-way plaintext-to-sealed conversion
        // on real history. Discipline alone is not enough here: forgetting one line
        // in one future test is all it takes, and the failure is silent and
        // irreversible.
        #expect(AuditLog.isTestProcess)
        let live = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(Wire.bundleIdentifier)/audit")
        #expect(AuditLog.directory.standardizedFileURL != live.standardizedFileURL)
        #expect(!AuditLog.url.path.hasPrefix(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support").path))
    }
}
