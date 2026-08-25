import Testing
import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0046, wired into a real session. What a unit test of the decisions cannot
// prove: that the keeper's accounting holds under the concurrency the scheduler
// actually permits, that a delegated run leaves the native declaration protocol
// alone, and that an unrecognised driver serialises rather than arming anything.

@Suite("Supervision under delegation, wired")
struct DelegatedSupervisionWiringTests {

    // MARK: - The keeper's accounting

    /// A keeper with a clock a test can move, so a grace and a ceiling are
    /// arithmetic rather than a sleep.
    private func keeper(now: @escaping @Sendable () -> Double) -> DelegatedPost {
        let post = DelegatedPost()
        post.now = now
        return post
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t: Double = 1000
        var read: @Sendable () -> Double { { [self] in lock.withLock { t } } }
        func advance(_ seconds: Double) { lock.withLock { t += seconds } }
    }

    @Test("a driver's pid is recognised while its call is in flight")
    func aCallMakesItsDriverRecognised() {
        let clock = Clock()
        let post = keeper(now: clock.read)
        #expect(post.recognisedPids.isEmpty)
        let token = post.begin(pid: 9001)
        #expect(post.recognisedPids == [9001])
        #expect(!post.hasUnrecognised)
        post.end(token)
    }

    @Test("two calls on one driver are retained, so the first to end does not drop it")
    func twoCallsOnOnePidAreRetained() {
        // The plan gate's second finding. Keyed on the pid alone, the first
        // `end` would lapse a pid the second call is still using and drop it
        // mid-gesture. Two delegated runs overlap: both hold only an app lane,
        // so the scheduler starts them together.
        let clock = Clock()
        let post = keeper(now: clock.read)
        let first = post.begin(pid: 9001)
        let second = post.begin(pid: 9001)
        post.end(first)
        clock.advance(PersonInput.graceSeconds * 4)
        // Still in flight on the second call, so still recognised long after the
        // first call's grace would have lapsed.
        #expect(post.recognisedPids == [9001])
        post.end(second)
    }

    @Test("membership outlives the call by the grace, so a gesture's tail is not stripped")
    func theWindowOutlivesTheCallByTheGrace() {
        // A driver's mouseDown can land while the call is open and its mouseUp
        // arrive after it returns. A window ending at the boundary strips the end
        // off the gesture and leaves the application holding a button nobody is
        // pressing — a state that outlives the block, the run and the process.
        let clock = Clock()
        let post = keeper(now: clock.read)
        post.end(post.begin(pid: 9001))
        #expect(post.recognisedPids == [9001])
        clock.advance(PersonInput.graceSeconds / 2)
        #expect(post.recognisedPids == [9001])
        clock.advance(PersonInput.graceSeconds)
        #expect(post.recognisedPids.isEmpty)
    }

    @Test("a call that never ends expires at the ceiling rather than leaking forever")
    func aHungCallExpiresAtTheCeiling() {
        // A `perform` that hangs, a cancelled task, a driver that dies mid-call.
        // A leaked entry leaves a reused pid exempt from the block indefinitely.
        let clock = Clock()
        let post = keeper(now: clock.read)
        _ = post.begin(pid: 9001)
        _ = post.begin(pid: nil)
        #expect(post.outstanding == 2)
        clock.advance(Takeover.ceilingSeconds + 1)
        #expect(post.outstanding == 0)
        #expect(post.recognisedPids.isEmpty)
        #expect(!post.hasUnrecognised)
    }

    @Test("releasing twice is a no-op, so a ceiling and a release cannot both account for a call")
    func endIsIdempotent() {
        let clock = Clock()
        let post = keeper(now: clock.read)
        let token = post.begin(pid: 9001)
        post.end(token)
        post.end(token)
        post.end(token)
        #expect(post.outstanding == 0)
    }

    @Test("a reported pid of zero or Proctor's own is refused and reads as unrecognised")
    func zeroAndOurOwnPidAreNotRecognised() {
        // Zero is what hardware carries. Admitting it would make every keystroke
        // a person makes "ours" while the label claimed input was held.
        let clock = Clock()
        let post = keeper(now: clock.read)
        _ = post.begin(pid: 0)
        #expect(post.recognisedPids.isEmpty)
        #expect(post.hasUnrecognised)

        let ours = keeper(now: clock.read)
        _ = ours.begin(pid: Int64(ProcessInfo.processInfo.processIdentifier))
        #expect(ours.recognisedPids.isEmpty)
        #expect(ours.hasUnrecognised)
    }

    @Test("a swallow during a delegated call is never reported as a person")
    func aSwallowDuringADelegatedCallIsNotPersonInput() {
        // The completeness gate's sharpest finding, and it was one of this
        // feature's own acceptance clauses left unimplemented. Everything about
        // the driver's wire is a documentary reading: if its events arrive
        // looking like hardware, an armed tap swallows them AND hands each one to
        // the contention monitor, so the run yields on its own actuation and
        // holds to the backstop — PRO-0018's measured 902-second failure by a new
        // road. `outstandingCall` is what the tap consults to refuse that.
        let clock = Clock()
        let post = keeper(now: clock.read)
        #expect(!post.outstandingCall)
        let token = post.begin(pid: nil)
        #expect(post.outstandingCall)
        post.end(token)
        #expect(!post.outstandingCall)
    }

    @Test("the suppression covers a recognised driver too, not only an unrecognised one")
    func theSuppressionIsNotConditionalOnRecognition() {
        // A driver whose pid corroborated at preflight can still put an event on
        // the wire that does not carry it. Recognition is what makes its events
        // PASS; this is what stops a swallow that happened anyway from holding
        // the run. The two are independent and both are needed.
        let clock = Clock()
        let post = keeper(now: clock.read)
        let token = post.begin(pid: 9001)
        #expect(post.outstandingCall)
        post.end(token)
    }

    @Test("a driver that reported no pid is outstanding but never recognised")
    func anUnrecognisedCallIsTracked() {
        let clock = Clock()
        let post = keeper(now: clock.read)
        let token = post.begin(pid: nil)
        #expect(post.hasUnrecognised)
        #expect(post.recognisedPids.isEmpty)
        post.end(token)
        #expect(!post.hasUnrecognised)
    }

    // MARK: - The session

    private func session(_ backend: (any ActuationBackend)? = nil)
    async throws -> (Session, FakeAX) {
        let ax = FakeAX(bundleId: "com.example.fake")
        let session = Session(ax: ax, capture: FakeCapture(), actuator: backend)
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: "com.example.fake", pid: nil, name: nil)
        return (session, ax)
    }

    // MARK: - A2: a delegated run leaves the declaration keeper alone

    @Test("a delegated run never joins the declaration protocol")
    func aDelegatedRunNeverParticipates() async throws {
        // PRO-0053's rule at its actual width: it admitted the runs that CAN
        // post, and a delegated run cannot — `SyntheticPost.declare()` is reached
        // only from Proctor's own actuator. Left in, it would install a handler
        // nothing can fire and clear the keeper at every step boundary while
        // having nothing of its own to record there.
        let post = SyntheticPost()
        let declared = Counter()
        post.onDeclare { declared.bump() }

        let backend = FakeActuationBackend()
        let (session, ax) = try await session(backend)
        await session.setSyntheticPost(post)
        _ = try await session.act(window: ax.window.id,
                                  steps: [ActionStep(kind: .click), ActionStep(kind: .click)],
                                  settle: .default, foreground: true, captureEach: false,
                                  diffEach: false, record: nil)
        // The handler the TEST installed is still there: a delegated run neither
        // replaced it nor cleared it on the way out.
        #expect(declared.value == 0)
        post.declare()
        #expect(declared.value == 1)
    }

    @Test("a concurrent native poster's declaration survives a whole delegated batch")
    func aNativePostersStateSurvivesADelegatedBatch() async throws {
        // The cross-run half. A native run declares; a delegated batch runs its
        // whole length beside it; the declaration and its in-flight window are
        // exactly as the native run left them.
        let post = SyntheticPost()
        // A frozen clock, deliberately. `inFlight` is bounded to
        // `PersonInput.graceSeconds` from the declaration, so against a real
        // clock this would assert that a multi-step batch takes under a quarter
        // second — the timer, not the thing under test. Frozen, the ONLY way
        // `inFlight` can go false is `beginStep()` or `endStep()` niling
        // `declaredAt`, which is exactly the clobber this pins.
        post.now = { 1000 }
        post.declare()
        #expect(post.declaredThisStep)
        #expect(post.inFlight)

        let backend = FakeActuationBackend()
        let (session, ax) = try await session(backend)
        await session.setSyntheticPost(post)
        _ = try await session.act(window: ax.window.id,
                                  steps: [ActionStep(kind: .click), ActionStep(kind: .press),
                                          ActionStep(kind: .click)],
                                  settle: .default, foreground: true, captureEach: false,
                                  diffEach: false, record: nil)
        #expect(post.declaredThisStep)
        #expect(post.inFlight)
    }

    // MARK: - A7: an unrecognised driver serialises

    @Test("a delegated batch whose driver reported no pid takes the exclusive lane")
    func anUnrecognisedDelegatedBatchTakesTheGlobalLane() async throws {
        // The alternative to arbitrating a hold two runs share. Only a posting
        // native batch arms the block, and such a batch holds `.global`, which is
        // exclusive against itself — so holding it here makes the overlap
        // impossible rather than something to resolve.
        let backend = FakeActuationBackend()
        backend.actuatingPidValue = nil
        let (session, ax) = try await session(backend)
        let window = try await session.windowHandle(ax.window.id)
        let demand = await session.lanes(for: [ActionStep(kind: .press)],
                                         window: window, foreground: false)
        #expect(demand.needsGlobal)
    }

    @Test("a delegated batch whose driver is recognised shares the machine as before")
    func aRecognisedDelegatedBatchDoesNotSerialise() async throws {
        let backend = FakeActuationBackend()
        backend.actuatingPidValue = 9001
        let (session, ax) = try await session(backend)
        let window = try await session.windowHandle(ax.window.id)
        let demand = await session.lanes(for: [ActionStep(kind: .press)],
                                         window: window, foreground: false)
        #expect(!demand.needsGlobal)
    }

    @Test("the native lane's own lane demand is untouched by any of this")
    func theNativeLaneDemandIsUnchanged() async throws {
        let (session, ax) = try await session()
        let window = try await session.windowHandle(ax.window.id)
        let quiet = await session.lanes(for: [ActionStep(kind: .press)],
                                        window: window, foreground: false)
        #expect(!quiet.needsGlobal)
        let posting = await session.lanes(for: [ActionStep(kind: .click)],
                                          window: window, foreground: true)
        #expect(posting.needsGlobal)
    }

    // MARK: - A8: exactly one pointer, decided per run

    @Test("a delegated run whose driver cannot stand down records that Proctor stood down")
    func theResultSaysWhenProctorStoodDown() async throws {
        let backend = FakeActuationBackend()
        backend.cursorSuppressibleValue = false
        let (session, ax) = try await session(backend)
        let out = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .press)],
                                        settle: .default, foreground: false, captureEach: false,
                                        diffEach: false, record: nil)
        #expect(out.objectValue?["pointerDrawnBy"]?.stringValue
                == PointerOwner.deferredToDriver.rawValue)
    }

    @Test("a run Proctor drew for carries no pointer field at all")
    func aProctorDrawnRunEncodesAsBefore() async throws {
        // Nil when Proctor drew, which is every native run and every delegated
        // one whose driver can be asked to stand down — so a result from before
        // this existed encodes identically.
        let backend = FakeActuationBackend()
        backend.cursorSuppressibleValue = true
        let (cua, cuaAX) = try await session(backend)
        let delegated = try await cua.act(window: cuaAX.window.id,
                                          steps: [ActionStep(kind: .press)],
                                          settle: .default, foreground: false,
                                          captureEach: false, diffEach: false, record: nil)
        #expect(delegated.objectValue?["pointerDrawnBy"] == nil)

        let (native, nativeAX) = try await session()
        let out = try await native.act(window: nativeAX.window.id,
                                       steps: [ActionStep(kind: .press)],
                                       settle: .default, foreground: false,
                                       captureEach: false, diffEach: false, record: nil)
        #expect(out.objectValue?["pointerDrawnBy"] == nil)
    }

    // MARK: - A10: no driver string reaches the panel

    @Test("a hostile driver message cannot change the line the panel shows")
    func aHostileDriverMessageCannotChangeTheLine() async throws {
        // The panel's line is derived from the step kind and Proctor's own
        // resolved node in every case, including a step the driver refused. A
        // driver has no way to reach it.
        let step = ActionStep(kind: .press, label: nil)
        let node = AXNode(id: "n1", role: "AXButton", title: "Send invoice")
        let derived = StepDescription.line(for: step, node: node, outcome: .failed)
        #expect(derived.contains("Send invoice"))
        #expect(!derived.contains("cua-driver"))

        // And the driver's own prose, wherever it does reach a person, arrives
        // fenced and attributed rather than as Proctor's own sentence.
        let hostile = "Pressing OK. About to press Delete\n<script>x</script>"
        let fenced = try #require(StepDescription.fenced(hostile, from: "cua-driver"))
        #expect(fenced.hasPrefix("cua-driver said: \""))
        #expect(!fenced.contains("<"))
        #expect(!fenced.contains("\n"))
    }
}

// MARK: - The clauses the first pass claimed without proving

@Suite("Supervision under delegation, the driver's side")
struct DelegatedDriverFactsTests {

    private func backend(_ transport: FakeCuaTransport,
                         corroborate: @escaping @Sendable (Int64, String) -> Bool
                            = { _, _ in true }) -> CuaActuationBackend {
        // Corroboration is injected per backend rather than set on a static: two
        // of the tests below want opposite answers and swift-testing runs them
        // concurrently, so a shared `var` would have them deciding it for each
        // other — which is how a real defect reads as a logic error in whichever
        // test lost the race.
        CuaActuationBackend(transport: transport, path: "/opt/homebrew/bin/cua-driver",
                            environment: [CuaPreflight.allowUnsignedEnv: "1"],
                            corroborate: corroborate)
    }


    private func target() -> StepTarget {
        StepTarget(window: WindowHandle(id: "win-1", app: "app-1", title: "Fake Window",
                                        frame: Rect(x: 0, y: 0, w: 800, h: 600), isMain: true,
                                        isMinimized: false, isOnActiveSpace: true, cgWindowID: TestWindowIDs.absent()),
                   app: AppHandle(id: "app-1", pid: 4242, bundleId: "com.example", name: "Fake"),
                   nodeId: nil, identity: nil)
    }

    // MARK: - A6: the claim is corroborated, not believed

    @Test("a pid the driver claims is recognised only when the process corroborates")
    func aClaimedPidIsCorroboratedBeforeItIsTrusted() async throws {
        let fake = FakeCuaTransport()
        fake.actuatingPid = 9001
        let cua = backend(fake, corroborate: { pid, identifier in
            pid == 9001 && identifier == CuaPreflight.expectedIdentifier
        })
        try await cua.preflight()
        #expect(await cua.actuatingPid == 9001)
    }

    @Test("a pid that does not corroborate is treated as no pid at all")
    func anUncorroboratedPidIsNotRecognised() async throws {
        // A number a program reports about itself is a claim. Refusing to act on
        // it costs a serialised lane; believing it would let anything that knew
        // the number through a hold meant to keep a person out of a run.
        let fake = FakeCuaTransport()
        fake.actuatingPid = 9001
        let cua = backend(fake, corroborate: { _, _ in false })
        try await cua.preflight()
        #expect(await cua.actuatingPid == nil)
    }

    @Test("a driver that reports no pid at all is simply unrecognised, never a refusal")
    func noReportedPidIsNotARefusal() async throws {
        // It can still actuate perfectly well. What it cannot do is share a
        // machine with an armed input block, which is a scheduling consequence
        // rather than a reason to turn the lane down.
        let fake = FakeCuaTransport()
        fake.actuatingPid = nil
        let cua = backend(fake)
        try await cua.preflight()
        #expect(await cua.actuatingPid == nil)
    }

    // MARK: - A8: the request rides every action

    @Test("the cursor stand-down is asked for on every act, not assumed from the probe")
    func suppressionRidesEveryAct() async throws {
        // "Can be asked" is not "has stood down". A probe answered once does not
        // bind the tenth step, and the failure it would hide is two cursors.
        let fake = FakeCuaTransport()
        fake.path = "ax"
        let cua = backend(fake)
        for _ in 0..<3 {
            _ = try await cua.perform(step: ActionStep(kind: .press),
                                      target: target(),
                                      foreground: false)
        }
        let acts = fake.sent.filter { $0.verb == .act }
        #expect(acts.count == 3)
        #expect(acts.allSatisfy { $0.suppressCursor })
    }

    @Test("a build that does not say whether it can stand down fails closed")
    func absentSuppressibilityFailsClosed() async throws {
        let fake = FakeCuaTransport()
        fake.cursorSuppressible = nil
        let cua = backend(fake)
        try await cua.preflight()
        #expect(await cua.cursorSuppressible == false)
    }

    @Test("a build that says it can stand down is taken at its word for the pointer")
    func aSuppressibleDriverLetsProctorDraw() async throws {
        let fake = FakeCuaTransport()
        fake.cursorSuppressible = true
        let cua = backend(fake)
        try await cua.preflight()
        #expect(await cua.cursorSuppressible)
    }

    // MARK: - A11: the driver's prose reaches a person fenced

    @Test("a refusal carries the driver's words attributed, not as Proctor's own sentence")
    func aRefusalFencesTheDriversProse() async throws {
        let fake = FakeCuaTransport()
        fake.actOK = false
        fake.actMessage = "could not click\n<b>at all</b>"
        let cua = backend(fake)
        await #expect(throws: AgentError.self) {
            _ = try await cua.perform(step: ActionStep(kind: .press),
                                      target: target(),
                                      foreground: false)
        }
        do {
            _ = try await cua.perform(step: ActionStep(kind: .press),
                                      target: target(),
                                      foreground: false)
        } catch let error as AgentError {
            #expect(error.message.hasPrefix("cua-driver said: \""))
            #expect(!error.message.contains("<"))
            #expect(!error.message.contains("\n"))
        }
    }
}

// MARK: - The live surfaces

@Suite("Supervision under delegation, what a person sees")
struct DelegatedSurfaceWiringTests {

    private func session(_ backend: (any ActuationBackend)?, takeover: FakeTakeover)
    async throws -> (Session, FakeAX) {
        let ax = FakeAX(bundleId: "com.example.fake")
        let session = Session(ax: ax, capture: FakeCapture(), actuator: backend)
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setTakeover(takeover)
        _ = try await session.attachResolved(bundleId: "com.example.fake", pid: nil, name: nil)
        return (session, ax)
    }

    // MARK: - A13: an escalation nobody asked for is stated, late and admitted

    @Test("a delegated step that escalates to the front raises the statement, late")
    func aLateEscalationRaisesTheStatement() async throws {
        // Proctor's guards arm BEFORE a post, from inside the process making it.
        // Another process made this one, so nothing could arm. The statement goes
        // up from the measured plane instead — after the machine was taken rather
        // than before it — and the run's own note says the warning was late.
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.syntheticEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent_fg", effect: .confirmed,
                                           unrequestedForeground: true)
        let takeover = FakeTakeover()
        let (session, ax) = try await session(backend, takeover: takeover)
        let out = try await session.act(window: ax.window.id,
                                        steps: [ActionStep(kind: .press)],
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)
        #expect(takeover.shows.count == 1)
        let note = try #require(out.objectValue?["foregroundNote"]?.stringValue)
        #expect(note.contains("without being asked"))
        #expect(note.contains("no warning shown"))
    }

    @Test("a delegated batch that stays on the accessibility plane states nothing on screen")
    func aQuietDelegatedBatchDrawsNoStatement() async throws {
        // A run that never takes the machine never draws the full-screen claim.
        // The panel's own row is where such a run is disclosed.
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.accessibility, .action, backend: .cua,
                                           reportedMode: "ax", effect: .confirmed)
        let takeover = FakeTakeover()
        let (session, ax) = try await session(backend, takeover: takeover)
        _ = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .press)],
                                  settle: .default, foreground: false,
                                  captureEach: false, diffEach: false, record: nil)
        #expect(takeover.shows.isEmpty)
    }

    // MARK: - A5: a delegated batch never holds itself

    @Test("a delegated batch yields zero times against an application Proctor raised")
    func aDelegatedBatchYieldsZeroTimes() async throws {
        let backend = FakeActuationBackend()
        let takeover = FakeTakeover()
        let (session, ax) = try await session(backend, takeover: takeover)
        let out = try await session.act(window: ax.window.id,
                                        steps: Array(repeating: ActionStep(kind: .press),
                                                     count: 10),
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)
        #expect(out.objectValue?["yields"] == nil)
        #expect(out.objectValue?["yieldNote"] == nil)
    }

    // MARK: - A12: the menu bar carries the lane

    @Test("the menu bar's foreground block names which backend is performing the steps")
    func theMenuBarCarriesTheBackend() async throws {
        // So the fact does not depend on which display the run panel landed on.
        // Proctor's own enum, never a string the driver supplied.
        let takeover = FakeTakeover()
        let (delegated, _) = try await session(FakeActuationBackend(), takeover: takeover)
        let cua = await delegated.recentActivity()
        #expect(cua.objectValue?["foreground"]?.objectValue?["backend"]?.stringValue == "cua")

        let (native, _) = try await session(nil, takeover: FakeTakeover())
        let own = await native.recentActivity()
        #expect(own.objectValue?["foreground"]?.objectValue?["backend"]?.stringValue == "native")
    }
}
