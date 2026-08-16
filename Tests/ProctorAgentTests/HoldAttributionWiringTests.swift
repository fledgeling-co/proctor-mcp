import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0037 — a hold names whose run it is.
//
// Three things are proved here, and the first two are behaviour rather than
// wording. A yield parks the run that read it and nobody else, because at HEAD
// one shared latch parked every run in flight — including an accessibility-plane
// run in another session against another app, which got no event, no record and
// no reason, and simply stopped for up to the whole backstop. A run beginning
// does not lift another run's hold, which it did at HEAD because
// `RunScheduler.acquire` never consults the latch. And the hold that results is
// published into the keeper, where every surface that can carry a name reads it.
//
// The latch is driven directly where the question is the parking rule, because
// that is arithmetic over two flags and a clock and does not need a run around
// it. The publishing is driven through a real `Session`, because the thing under
// test there is what survives the actor's reentrancy.

@Suite("Attributed holds", .serialized)
struct HoldAttributionWiringTests {

    private static let target = "com.example.target"

    private func latch(limit: TimeInterval = 900,
                       now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 })
        -> RunControl {
        let control = RunControl(pauseLimit: limit, now: now)
        control.begin(run: 0)
        return control
    }

    // MARK: - A3: a yield parks the run that read it, and only that one

    @Test("a yield parks its owner and leaves every other run alone")
    func aYieldParksOnlyItsOwner() async {
        let control = latch()
        control.yield(run: 7, hold: aHold(.frontmostChanged))

        // The run that read it is held.
        #expect(control.isParked(run: 7))
        // The one that did not is not. This is the whole feature at HEAD: an
        // accessibility press into Slack is not fighting somebody who cmd-tabbed
        // away from Safari, and parking it told its caller nothing while
        // stopping it for up to fifteen minutes.
        #expect(!control.isParked(run: 9))
        #expect(await control.checkpoint(run: 9) == nil)
    }

    @Test("a person's Pause parks every run, because it is about the machine")
    func aPersonsPauseParksEveryRun() {
        let control = latch()
        control.pause()
        #expect(control.isParked(run: 7))
        #expect(control.isParked(run: 9))
    }

    @Test("the yielded run really is held, and carries on when it clears")
    func theYieldedRunIsHeldAndCarriesOn() async throws {
        let control = latch()
        control.pollNanoseconds = 1_000_000
        control.yield(run: 3, hold: aHold(.secureInput))

        let held = Task { await control.checkpoint(run: 3) }
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(!held.isCancelled)
        control.release(run: 3)
        #expect(await held.value == nil)
    }

    @Test("the machine-wide read still says something is held, for the panel")
    func theMachineWideReadStillAnswers() {
        // `isPaused` answers "is anything held on this Mac", which is what the
        // panel's own state needs; `isParked(run:)` answers "is THIS run held",
        // which is what a run needs. Keeping both is what lets the two questions
        // stop being confused for each other.
        let control = latch()
        control.yield(run: 4, hold: aHold(.userInput))
        #expect(control.isPaused)
        #expect(control.isYielded)
        #expect(!control.isParked(run: 5))
    }

    @Test("a second hold never unparks the first")
    func aSecondHoldNeverUnparksTheFirst() {
        // The lane model means two runs should not be yielded at once: arming
        // implies the batch takes the foreground, which takes the exclusive
        // global lane. This asserts what happens if that ever stops holding,
        // because the failure would be silent and severe — a single owner would
        // be retargeted by the second yield, and the first run would resume
        // posting into the very person it had just got out of the way of.
        let control = latch()
        control.yield(run: 7, hold: aHold(.frontmostChanged))
        control.yield(run: 9, hold: aHold(.secureInput))

        #expect(control.isParked(run: 7))
        #expect(control.isParked(run: 9))
        // Each keeps its own reason rather than the last writer's.
        #expect(control.heldBy(run: 7)?.reason == .frontmostChanged)
        #expect(control.heldBy(run: 9)?.reason == .secureInput)
        // And the machine-wide read takes the highest-precedence one, which is
        // the one that most explains why injected input is least welcome.
        #expect(control.heldBy?.reason == .secureInput)

        // Releasing one leaves the other exactly where it was.
        control.release(run: 9)
        #expect(control.isParked(run: 7))
        #expect(!control.isParked(run: 9))
        #expect(control.isYielded)
        control.release(run: 7)
        #expect(!control.isYielded)
    }

    @Test("releasing a run that is not held changes nothing")
    func releasingAnUnheldRunIsANoOp() {
        let control = latch()
        control.yield(run: 7, hold: aHold(.frontmostChanged))
        control.release(run: 9)
        #expect(control.isParked(run: 7))
        #expect(control.heldBy?.reason == .frontmostChanged)
    }

    // MARK: - A4: a run beginning does not erase another run's hold

    @Test("a run beginning does not lift a hold it does not own")
    func beginDoesNotEraseAnotherRunsHold() {
        let control = latch()
        control.yield(run: 7, hold: aHold(.frontmostChanged))

        // Run 9 starts on a free app lane while run 7 is yielded. The scheduler
        // does not consult this latch, so this happens; at HEAD it cleared run
        // 7's hold, its clock and its bound, and run 7's next look saw nothing
        // holding it and carried on posting into the person it had just got out
        // of the way of.
        control.begin(run: 9)

        #expect(control.isParked(run: 7))
        #expect(control.isYielded)
        #expect(control.heldBy?.reason == .frontmostChanged)
        #expect(!control.isParked(run: 9))
    }

    @Test("a run beginning does clear its own hold, so nothing carries over")
    func beginClearsItsOwnHold() {
        let control = latch()
        control.yield(run: 7, hold: aHold(.frontmostChanged))
        control.begin(run: 7)
        #expect(!control.isYielded)
        #expect(!control.isParked(run: 7))
        #expect(control.heldBy == nil)
    }

    @Test("a run beginning still clears a person's decision, which is settled")
    func beginStillClearsAPersonsDecision() {
        // PRO-0015 fixed Pause and Stop to the live line, and a new run is a new
        // live line. That is not changed here; only the automatic cause gained
        // an owner. Recorded as child work rather than widened.
        let control = latch()
        control.pause()
        control.begin(run: 9)
        #expect(!control.isPaused)
    }

    // MARK: - A5: the backstop expires the run it was holding

    @Test("an expired yield gives up on its owner and nobody else")
    func anExpiredYieldGivesUpOnlyItsOwner() async {
        let clock = TestClock()
        let control = RunControl(pauseLimit: 10, now: { clock.value })
        control.begin(run: 0)
        control.pollNanoseconds = 1_000_000
        control.yield(run: 7, hold: aHold(.frontmostChanged))
        clock.value += 11

        #expect(await control.checkpoint(run: 7) == .pauseExpired(seconds: 10))
        // And the sibling is untouched — not stopped, not expired, not told a
        // person did anything. At HEAD the expiry set the global stop flag, so
        // this run's caller was told "a person stopped this run from Proctor's
        // run HUD": a halt nobody chose, attributed to somebody who was not
        // there.
        #expect(await control.checkpoint(run: 9) == nil)
        #expect(!control.isStopped)
    }

    @Test("an expired person's pause still reaches every run")
    func anExpiredPersonsPauseStillReachesEveryRun() async {
        let clock = TestClock()
        let control = RunControl(pauseLimit: 10, now: { clock.value })
        control.begin(run: 0)
        control.pollNanoseconds = 1_000_000
        control.pause()
        clock.value += 11
        // A person's pause held everything, so its expiry stops everything.
        #expect(await control.checkpoint(run: 7) == .pauseExpired(seconds: 10))
        #expect(await control.checkpoint(run: 9) == .stopped)
    }

    @Test("the bound is still on the run, so a flapping condition is still bounded")
    func aFlappingConditionIsStillBoundedPerRun() async {
        let clock = TestClock()
        let control = RunControl(pauseLimit: 10, now: { clock.value })
        control.begin(run: 0)
        control.pollNanoseconds = 1_000_000

        // Six seconds held, released, then held again: the second episode is
        // individually legal and the pair is not. PRO-0018 banked the time
        // against the run; keying the ledger by run is what keeps that true when
        // another run begins in between, which used to reset the single total
        // and hand the condition a fresh bound it had already spent.
        control.yield(run: 7, hold: aHold(.frontmostChanged))
        clock.value += 6
        control.release(run: 7)
        control.begin(run: 9)          // an unrelated run, which used to wipe the ledger
        control.yield(run: 7, hold: aHold(.frontmostChanged))
        clock.value += 5

        #expect(await control.checkpoint(run: 7) == .pauseExpired(seconds: 10))
    }

    @Test("a run parked only by a person never inherits another run's spent bound")
    func aPersonsPauseDoesNotInheritBankedYieldTime() async throws {
        let clock = TestClock()
        let control = RunControl(pauseLimit: 10, now: { clock.value })
        control.begin(run: 0)
        control.pollNanoseconds = 1_000_000

        // Run 7 spends nine of the ten seconds and lets go.
        control.yield(run: 7, hold: aHold(.frontmostChanged))
        clock.value += 9
        control.release(run: 7)

        // Run 9 has spent none of its own, so two seconds is two seconds. Under
        // a single shared ledger this run would read eleven and be given up for
        // time somebody else's hold had cost.
        control.yield(run: 9, hold: aHold(.frontmostChanged))
        clock.value += 2
        let probe = Task { await control.checkpoint(run: 9) }
        try await Task.sleep(nanoseconds: 30_000_000)
        control.release(run: 9)
        // Nil rather than `.pauseExpired`: it was parked and then let out, which
        // is what a hold that has not reached its bound does.
        #expect(await probe.value == nil)
    }

    // MARK: - A2: the join is published into the keeper

    @Test("a hold lands on its own ticket and leaves the others alone")
    func aHoldLandsOnItsOwnTicket() async throws {
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let one = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("a")]),
                                              identity: Self.who("diolog-web"), summary: "Act ×2")
        let two = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("b")]),
                                              identity: Self.who("armada"), summary: "Act ×3")
        let hold = aHold(.frontmostChanged, session: "diolog-web 0000", app: "Acme Console")
        await scheduler.hold(run: one.id, hold)

        let snapshot = await scheduler.snapshot()
        #expect(snapshot.active.first { $0.id == one.id }?.held == hold)
        #expect(snapshot.active.first { $0.id == two.id }?.held == nil)

        await scheduler.unhold(run: one.id)
        #expect(await scheduler.snapshot().active.allSatisfy { $0.held == nil })
        await scheduler.release(one)
        await scheduler.release(two)
    }

    @Test("a released ticket cannot be held, so a race cannot resurrect one")
    func aReleasedTicketCannotBeHeld() async throws {
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let ticket = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("a")]),
                                                 identity: Self.who("armada"), summary: "Act ×1")
        let id = ticket.id
        await scheduler.release(ticket)
        // A Stop racing a release would otherwise stamp a hold onto a run that
        // has already finished, and the panel would show a machine held by a run
        // that is not there.
        await scheduler.hold(run: id, aHold(.secureInput))
        #expect(await scheduler.snapshot().active.isEmpty)
    }

    /// A session wired to yield on demand, and its scheduler.
    ///
    /// The contention script mirrors what a real run sees: Proctor's target is
    /// confirmed in front first, because the frontmost reading cannot fire until
    /// the pid it expects has actually been observed there, and only then does
    /// the person move away. `planeAt` makes the first step report the event
    /// stream, which is what sets the expected pid at all.
    private func yieldingHarness(control: RunControl)
        async throws -> (session: Session, ax: FakeAX, contention: FakeContention,
                         scheduler: RunScheduler) {
        let ax = FakeAX(bundleId: Self.target)
        ax.planeAt = [0: .syntheticEvent]
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let session = Session(ax: ax, capture: FakeCapture(), scheduler: scheduler, secureInputProbe: { false })
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        let contention = FakeContention()
        await session.setContentionMonitor(contention)
        await session.setYieldSwitches(enabled: true, observesInput: false)
        control.begin(run: 0)
        await session.setRunControl(control)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        let now = Date().timeIntervalSince1970
        contention.play([
            ContentionSample(expectedPid: 1, frontmostPid: 1, now: now),
            ContentionSample(expectedPid: 1, frontmostPid: 2, now: now)
        ])
        return (session, ax, contention, scheduler)
    }

    /// Three steps rather than one, and it is not padding. `runSteps` probes at
    /// the checkpoint before each step, so a single-step run has exactly one
    /// probe — the one that confirms the front — and finishes before the sample
    /// that would hold it is ever read. Three steps guarantee a checkpoint after
    /// the person has moved, and another one after whatever lifts the hold.
    private func clicks(_ n: Int = 3) -> [ActionStep] {
        (0..<n).map { _ in ActionStep(kind: .click, node: "node-1") }
    }

    /// Wait for the hold to exist rather than sleeping a guessed interval. A
    /// decision that lands before the run has yielded is spent on nothing: the
    /// override marks an empty condition set, the yield latches immediately
    /// after it, and the only thing left to lift that hold is the backstop.
    ///
    /// The budget is generous because this suite runs beside every other one and
    /// a run under load takes longer to reach its second checkpoint than one
    /// running alone. Every latch here is built with a bounded backstop as well,
    /// so a genuine miss fails in seconds rather than hanging for fifteen
    /// minutes — which is what hid this same mistake the last time somebody made
    /// it.
    private func awaitHold(_ control: RunControl) async -> Bool {
        for _ in 0..<4000 {
            if control.isYielded { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    /// A backstop short enough to be a test and long enough not to expire a hold
    /// the test is still looking at.
    private static let testBackstop: TimeInterval = 20

    @Test("a yield reaches the ticket, and every way it can end clears it")
    func everyEndingPathLeavesNothingHeld() async throws {
        // Four endings, driven through a real run: the contention clearing, a
        // person's Resume, a person's Stop, and the run simply finishing. The
        // scheduler's copy is a copy — the latch stays the truth, because the
        // buttons write it synchronously from the main thread — so what has to
        // hold is that nothing ever clears the latch without also clearing the
        // copy. The backstop is the fifth and is proved on the latch directly in
        // `anExpiredYieldGivesUpOnlyItsOwner`, because waiting one out through a
        // run means waiting one out.
        for ending in ["released", "resumed", "stopped", "ended"] {
            let control = RunControl(pauseLimit: Self.testBackstop,
                                     now: { Date().timeIntervalSince1970 })
            control.pollNanoseconds = 5_000_000
            let h = try await yieldingHarness(control: control)

            let run = Task {
                try await SessionIdentity.$current.withValue(Self.who("diolog-web")) {
                    try await h.session.act(window: h.ax.window.id, steps: clicks(),
                                            settle: .default, foreground: true,
                                            captureEach: false, diffEach: false, record: nil)
                }
            }
            #expect(await awaitHold(control), "\(ending): the run never yielded")

            // The hold is published while it is held — the half that has to be
            // true before "it is cleared" means anything.
            let duringHold = await h.scheduler.snapshot()
            #expect(duringHold.active.contains { $0.held != nil },
                    "\(ending): the hold never reached a ticket")

            switch ending {
            case "resumed": control.resume()
            case "stopped": control.stop()
            default: break
            }
            // Whatever ended it, put the front back: a branch that ended the
            // hold some other way is unaffected, and one whose decision landed
            // before the yield did is let out here rather than left to the
            // backstop.
            h.contention.set(ContentionSample(expectedPid: 1, frontmostPid: 1,
                                              now: Date().timeIntervalSince1970 + 30))
            _ = try? await run.value

            #expect(await h.scheduler.snapshot().active.allSatisfy { $0.held == nil },
                    "\(ending) left a hold published on a ticket the latch had let go")
        }
    }

    // MARK: - A7 / A9: what the surfaces are told

    @Test("the yield block names the session, the app and the display")
    func theYieldBlockNamesTheSessionAppAndDisplay() async throws {
        let control = RunControl(pauseLimit: Self.testBackstop,
                                 now: { Date().timeIntervalSince1970 })
        control.pollNanoseconds = 5_000_000
        let h = try await yieldingHarness(control: control)

        let run = Task {
            try await SessionIdentity.$current.withValue(Self.who("diolog-web")) {
                try await h.session.act(window: h.ax.window.id, steps: clicks(),
                                        settle: .default, foreground: true,
                                        captureEach: false, diffEach: false, record: nil)
            }
        }
        #expect(await awaitHold(control))

        let activity = await h.session.recentActivity()
        let yield = activity["foreground"]?["yield"]?.objectValue
        #expect(yield?["active"]?.boolValue == true)
        #expect(yield?["reason"]?.stringValue == "frontmostChanged")
        // The name is the derived pair, and it is on the block the menu bar and
        // the status window both read — never on the icon, which is one glyph
        // and cannot carry a name.
        #expect(yield?["session"]?.stringValue == "diolog-web 0000")
        #expect(yield?["line"]?.stringValue?.contains("diolog-web 0000") == true)
        #expect(yield?["line"]?.stringValue?.hasPrefix(YieldReason.frontmostChanged.line) == true)

        h.contention.set(ContentionSample(expectedPid: 1, frontmostPid: 1,
                                          now: Date().timeIntervalSince1970 + 30))
        _ = try? await run.value
    }

    @Test("the glyph ladder is not reordered by any of this")
    func theGlyphLadderIsUnchangedForAHeldRun() {
        // A menu bar item is one glyph. Attribution lives where a name fits;
        // this rung is untouched and still reaches the character through its
        // existing order — reachability, grants, foreground, phase.
        #expect(MenuBarIcon.decide(reachable: true, block: nil, phase: .paused,
                                   takingForeground: false) == .character(.paused))
        #expect(MenuBarIcon.decide(reachable: false, block: nil, phase: .paused)
                == .symbol("bolt.horizontal.circle"))
        #expect(MenuBarIcon.decide(reachable: true, block: .secureInput, phase: .paused)
                == .symbol("lock.laptopcomputer"))
    }

    @Test("the yield block keeps its shape when nothing is held")
    func theYieldBlockIsUnchangedWhenNothingIsHeld() async throws {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture(), secureInputProbe: { false })
        await session.setDrawsHUD(false)
        let activity = await session.recentActivity()
        let yield = activity["foreground"]?["yield"]?.objectValue
        #expect(yield?["active"]?.boolValue == false)
        // Present and null rather than absent, so a poller reading this block
        // does not have to tell "no hold" from "an older agent".
        for key in ["reason", "line", "session", "app", "display"] {
            #expect(yield?[key] == .null, "\(key) should be null, not missing")
        }
    }

    @Test("the health report marks a held run, so a busy Mac is not read as a wedged one")
    func theHealthReportMarksAHeldRun() async throws {
        let ax = FakeAX(bundleId: Self.target)
        let scheduler = RunScheduler(waitLimit: 5, now: { 0 })
        let session = Session(ax: ax, capture: FakeCapture(), scheduler: scheduler, secureInputProbe: { false })
        await session.setDrawsHUD(false)

        let ticket = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("a"), .global]),
                                                 identity: Self.who("proctor-mcp"),
                                                 summary: "Act ×6")
        await scheduler.hold(run: ticket.id,
                             aHold(.secureInput, session: "proctor-mcp 0000", app: "Mail"))

        let status = await session.queueStatus()
        let first = status["activeRuns"]?.arrayValue?.first?.objectValue
        let held = first?["held"]?.objectValue
        #expect(held?["reason"]?.stringValue == "secureInput")
        #expect(held?["session"]?.stringValue == "proctor-mcp 0000")
        #expect(held?["app"]?.stringValue == "Mail")

        await scheduler.unhold(run: ticket.id)
        let after = await session.queueStatus()
        #expect(after["activeRuns"]?.arrayValue?.first?["held"] == .null)
        await scheduler.release(ticket)
    }

    private static func who(_ name: String) -> RunSessionIdentity {
        RunSessionIdentity(project: name, connection: "0000", key: name)
    }
}
