import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0033 — the agent's half: the declaration the actuator makes before it
// posts, and the arming that follows the panel's mouse gate rather than the
// step's kind.
//
// `RunHUDGeometry.shared` is process-wide, so every test here clears it on the
// way in and on the way out. A test that left a panel frame published would
// decide the gate for whatever suite ran next.
//
// The declaration keeper is no longer taken from the process at all. `.serialized`
// orders the tests inside this suite and nothing else, so a declaration left on
// `SyntheticPost.shared` reached whichever other suite happened to be stepping
// concurrently — which is how `TakeoverWiringTests` came to believe its statement
// was already raised and stopped raising it (PRO-0053). This suite now drives its
// own instance, injected into the session.
//
// Two properties are code readings rather than tests and are named as such in
// the spec: that the declaration sits at the end of
// `Actuator.requireEventPlaneAvailable()`, so a step refused for Secure Event
// Input throws above it and declares nothing (A4), and that the same placement
// is past every accessibility route, so a declaration cannot precede an
// accessibility success (A5). Both are properties of where one line sits in a
// private function, and a fake actuator cannot witness either.

@Suite("Stop reachability wiring", .serialized)
struct StopReachabilityWiringTests {

    private static let target = "com.example.target"
    /// A panel docked bottom-right of a 1728x1117 display, in Quartz space.
    private static let panel = Rect(x: 1342, y: 731, w: 352, h: 352)
    private static let stop = Rect(x: 1600, y: 1040, w: 64, h: 28)

    private func harness() async throws
        -> (session: Session, ax: FakeAX, takeover: FakeTakeover, contention: FakeContention,
            post: SyntheticPost) {
        RunHUDGeometry.shared.clear()
        // This suite's own declaration keeper rather than the process-wide one.
        // `.serialized` orders the tests inside this suite and nothing else, so
        // before this the declarations below reached whatever other suite
        // happened to be stepping at the time — which is how a batch elsewhere
        // came to believe its statement was already raised.
        let post = SyntheticPost()
        post.beginStep()
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture())
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        let takeover = FakeTakeover()
        await session.setTakeover(takeover)
        let contention = FakeContention()
        await session.setContentionMonitor(contention)
        await session.setYieldSwitches(enabled: true, observesInput: false)
        await session.setSyntheticPost(post)
        let control = RunControl(pauseLimit: 900, now: { Date().timeIntervalSince1970 })
        control.begin(run: 0)
        await session.setRunControl(control)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax, takeover, contention, post)
    }

    private func act(_ h: (session: Session, ax: FakeAX, takeover: FakeTakeover,
                           contention: FakeContention, post: SyntheticPost),
                     _ steps: [ActionStep]) async throws -> JSONValue {
        try await h.session.act(window: h.ax.window.id, steps: steps, settle: .default,
                                foreground: true, captureEach: false, diffEach: false,
                                record: nil)
    }

    /// A step aimed at an explicit screen point, which is what the actuator
    /// posts at and therefore what the gate measures against.
    private func scroll(at x: Double, _ y: Double) -> ActionStep {
        ActionStep(kind: .scroll, delta: [0, -3], point: [x, y])
    }

    // MARK: - A7: arming follows the gate, not the step's kind

    @Test("a fallback-capable step posting under the panel arms the block")
    func armingFollowsTheGate() async throws {
        // `scroll` is not a synthetic kind, so before this nothing armed for it
        // at all — and the panel had no reason to move either. Now the two agree:
        // if the panel is standing where the step may post, the panel steps aside
        // and the block is armed for as long as it does. A gate open wider than
        // the armed window is this feature's own hole in miniature.
        let h = try await harness()
        RunHUDGeometry.shared.publish(panel: Self.panel, stop: Self.stop)
        defer { RunHUDGeometry.shared.clear() }
        _ = try await act(h, [scroll(at: 1500, 900)])
        #expect(h.takeover.arms.count == 1)
        #expect(h.takeover.shows.count == 1)
        #expect(h.takeover.armed == 0, "the arming must be released with the step")
    }

    @Test("the same step posting away from the panel arms nothing")
    func awayFromThePanelNothingArms() async throws {
        // The panel is not in the way, so it does not move and Stop stays
        // clickable right through the step. There is nothing to hold.
        let h = try await harness()
        RunHUDGeometry.shared.publish(panel: Self.panel, stop: Self.stop)
        defer { RunHUDGeometry.shared.clear() }
        _ = try await act(h, [scroll(at: 400, 300)])
        #expect(h.takeover.arms.isEmpty)
        #expect(h.takeover.shows.isEmpty)
    }

    @Test("with no panel on screen nothing is in the way and nothing arms")
    func noPanelNothingArms() async throws {
        let h = try await harness()
        _ = try await act(h, [scroll(at: 1500, 900)])
        #expect(h.takeover.arms.isEmpty)
    }

    @Test("a certainly synthetic step still arms wherever it posts")
    func aSyntheticStepIsUnchanged() async throws {
        // The kind-driven half is not weakened: a `click` takes the machine
        // whatever the geometry says, so the statement and the block are
        // unchanged from PRO-0026 for every step that was already covered.
        let h = try await harness()
        _ = try await act(h, [ActionStep(kind: .click, point: [400, 300])])
        #expect(h.takeover.arms.count == 1)
        #expect(h.takeover.shows.count == 1)
    }

    @Test("a thrown step still lets go")
    func aThrownStepStillLetsGo() async throws {
        let h = try await harness()
        RunHUDGeometry.shared.publish(panel: Self.panel, stop: Self.stop)
        defer { RunHUDGeometry.shared.clear() }
        h.ax.failPerformAt = 0
        _ = try await act(h, [scroll(at: 1500, 900)])
        #expect(h.takeover.armed == 0)
    }

    // MARK: - A6: what the declaration feeds

    @Test("a declaration made during the post opens the grace window and raises the statement")
    func theDeclarationFeedsBothConsumers() async throws {
        // The actuator declares at its choke point, in the middle of `perform`.
        // Before this, neither consumer knew: the grace window never opened for
        // a fallback post at all — so the application's echo of Proctor's own
        // wheel event could read as a person and yield the run — and the
        // statement went up only once the step had settled, claiming the machine
        // after it was taken.
        let h = try await harness()
        h.ax.planeAt[0] = .syntheticEvent
        let post = h.post
        h.ax.onPerform = { _ in post.declare() }
        let postsBefore = h.contention.syntheticPosts
        _ = try await act(h, [scroll(at: 400, 300)])
        #expect(h.contention.syntheticPosts > postsBefore)
        #expect(h.takeover.shows.count >= 1)
    }

    @Test("the handler is uninstalled when the run ends")
    func theHandlerDoesNotOutliveTheRun() async throws {
        // It captures this run's monitor and this run's takeover driver. Left
        // installed, a later declaration would feed a finished run's fakes — and
        // in production, a stale driver.
        let h = try await harness()
        _ = try await act(h, [ActionStep(kind: .press, node: "node-1")])
        let showsAfterRun = h.takeover.shows.count
        h.post.declare()
        h.post.beginStep()
        #expect(h.takeover.shows.count == showsAfterRun)
    }

    // MARK: - A9: the in-flight window closes however the step ended

    @Test("a post in flight is closed by the step's end, including a throw")
    func theInFlightWindowClosesOnEveryPath() async throws {
        // While it is open the tap declines to read the Stop rectangle at all,
        // which is what makes "our own click can never press Stop" structural.
        // Left open, it would leave the tap unable to read a Stop press for the
        // rest of the run — this feature failing in the way it exists to
        // prevent.
        let h = try await harness()
        h.ax.failPerformAt = 0
        let post = h.post
        h.ax.onPerform = { _ in post.declare() }
        _ = try await act(h, [scroll(at: 1500, 900)])
        #expect(!h.post.inFlight)
    }

    @Test("a declaring step is recorded as having taken the machine")
    func aDeclaringStepSaysSo() async throws {
        let h = try await harness()
        h.ax.planeAt[0] = .syntheticEvent
        let post = h.post
        h.ax.onPerform = { _ in post.declare() }
        _ = try await act(h, [scroll(at: 400, 300)])
        #expect(h.takeover.reports == 1)
    }

    // MARK: - The keeper itself

    @Test("the keeper publishes and clears both rectangles together")
    func theKeeperClearsBoth() {
        RunHUDGeometry.shared.publish(panel: Self.panel, stop: Self.stop)
        #expect(RunHUDGeometry.shared.panelFrame != nil)
        #expect(RunHUDGeometry.shared.stopRect != nil)
        RunHUDGeometry.shared.clear()
        #expect(RunHUDGeometry.shared.panelFrame == nil)
        #expect(RunHUDGeometry.shared.stopRect == nil)
    }

    @Test("a long gesture does not hold the Stop rectangle unreadable for its whole length")
    func aLongGestureStaysStoppable() {
        // The completeness gate's finding, and it was a real defect. A
        // `dragPath` is clamped at thirty seconds and declares once, at its
        // start. Holding the in-flight window for the whole step would leave the
        // tap refusing to read a Stop press for half a minute — and a long
        // gesture is precisely the step PRO-0026 says must stay stoppable
        // throughout.
        let clock = Clock()
        let post = SyntheticPost()
        post.now = { clock.value }

        post.beginStep()
        clock.value = 1000
        post.declare()
        #expect(post.inFlight)
        // Still inside the quarter second that covers our own event's delivery.
        clock.value = 1000 + PersonInput.graceSeconds / 2
        #expect(post.inFlight)
        // Two seconds into a thirty-second drag: the person's Stop press is
        // readable again, and our own events are covered by `isOurs`, which is
        // tested first anyway.
        clock.value = 1002
        #expect(!post.inFlight)
        post.beginStep()
    }

    @Test("the step's end closes the window even inside the quarter second")
    func endStepClosesItEarly() {
        let clock = Clock()
        let post = SyntheticPost()
        post.now = { clock.value }
        post.beginStep()
        clock.value = 500
        post.declare()
        #expect(post.inFlight)
        post.endStep()
        #expect(!post.inFlight)
    }

    @Test("a step begins with no declaration carried over from the last one")
    func eachStepStartsClean() {
        let post = SyntheticPost()
        post.declare()
        #expect(post.declaredThisStep)
        post.beginStep()
        #expect(!post.declaredThisStep)
        #expect(!post.inFlight)
    }
}

/// A hand-wound clock, so the in-flight window is tested as arithmetic rather
/// than by sleeping.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Double = 0
    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
