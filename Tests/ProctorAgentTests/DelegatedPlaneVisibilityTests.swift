import Testing
import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0084 — the delegated lane's two silent facts, and the coupling that
// decides whether one of them was silent at all.
//
// THIS SUITE EXISTS IN THE SHAPE IT DOES BECAUSE ARMING CHANGED THE ANSWER.
//
// The brief's first claim was that an unrequested escalation raises no takeover
// statement, and the first version of this suite asserted that a delegated step
// reporting `unrequestedForeground` raises one. It passed — and it also passed
// with the production line that raised it deleted, which means it measured
// nothing. The cause is `CuaVocabulary`: `escalated` is set only for a path in
// `foregroundPaths`, and every member of that set maps to `.syntheticEvent` in
// `planes`, which `SessionAct` has always raised the statement for. So the
// statement was never missing. The wording was.
//
// What is pinned here instead is that coupling, because it is load-bearing and
// nothing was holding it: if a future vocabulary change mapped a foreground path
// to anything else, the statement would stop appearing for a real takeover and
// no test in the tree would notice.
@Suite("Delegated plane coupling")
struct CuaPlaneCouplingTests {

    @Test("CASE-0236: every foreground path maps to the plane that raises the statement")
    func foregroundPathsRaiseTheStatement() {
        // `SessionAct` raises the takeover statement on `plane == .syntheticEvent`
        // and on nothing else. `CuaActuationBackend` sets `unrequestedForeground`
        // exactly for the paths below. The two meet only here, in a dictionary,
        // and this is the assertion that keeps them meeting.
        #expect(!CuaVocabulary.foregroundPaths.isEmpty,
                "an empty set would make every expectation below vacuous")
        for path in CuaVocabulary.foregroundPaths {
            #expect(CuaVocabulary.plane(for: path) == .syntheticEvent,
                    "\(path) escalates to the front but no longer reports the plane SessionAct raises the takeover statement for")
        }
    }

    @Test("CASE-0237: a background path does not report that plane")
    func backgroundPathsDoNot() {
        // The arming control. Without it CASE-0236 would pass against a
        // vocabulary that mapped EVERY path to `.syntheticEvent` — which would
        // raise the statement for steps that took nothing, and train a reader to
        // ignore it.
        for path in CuaVocabulary.planes.keys where !CuaVocabulary.foregroundPaths.contains(path) {
            #expect(CuaVocabulary.plane(for: path) != .syntheticEvent,
                    "\(path) is not a foreground path but claims the machine was taken")
        }
    }

    @Test("CASE-0238: an unrecognised path is never guessed into a background plane")
    func unknownPathIsUnknown() {
        // The direction that costs nothing to be wrong in. A path this build has
        // never heard of could be either, so it is neither.
        #expect(CuaVocabulary.plane(for: "some_future_path") == .unknown)
        #expect(CuaVocabulary.plane(for: nil) == .unknown)
    }
}

// The run's half: which pointer a delegated batch left drawing, and whether it
// said so. The fakes stand in for the panels exactly as `TakeoverWiringTests`
// does, and the same boundary applies — this proves the seam, never the paint.
@Suite("Delegated pointer ownership")
struct DelegatedPointerVisibilityTests {

    private static let target = "com.example.fake"

    private func session(cursorSuppressible: Bool)
    async throws -> (Session, FakeAX) {
        let ax = FakeAX(bundleId: Self.target)
        let backend = FakeActuationBackend()
        backend.cursorSuppressibleValue = cursorSuppressible
        let session = Session(ax: ax, capture: FakeCapture(),
                              secureInputProbe: { false }, actuator: backend)
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setTakeover(FakeTakeover())
        await session.setContentionMonitor(FakeContention())
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax)
    }

    private func run(_ session: Session, _ ax: FakeAX) async throws -> JSONValue {
        try await session.act(window: ax.window.id, steps: [ActionStep(kind: .press)],
                              settle: .default, foreground: false, captureEach: false,
                              diffEach: false, record: nil)
    }

    @Test("CASE-0242: a driver that cannot stand its cursor down leaves a run with no Proctor pointer")
    func deferredPointerIsRecorded() async throws {
        // The wire fact the panel's new sentence is drawn from, and the state
        // the person reported: no Proctor pointer anywhere, and the real cursor
        // moving on its own.
        let (session, ax) = try await session(cursorSuppressible: false)
        let out = try await run(session, ax)
        #expect(out.objectValue?["pointerDrawnBy"]?.stringValue
                    == PointerOwner.deferredToDriver.rawValue)
    }

    @Test("CASE-0243: a driver that can stand its cursor down leaves Proctor drawing")
    func suppressiblePointerStaysProctors() async throws {
        // The arming control for CASE-0242: the field is absent when Proctor
        // draws, so the assertion above reads a decision rather than a constant.
        let (session, ax) = try await session(cursorSuppressible: true)
        let out = try await run(session, ax)
        #expect(out.objectValue?["pointerDrawnBy"] == nil)
    }

    @Test("CASE-0244: the native lane never defers its pointer")
    func nativeNeverDefers() async throws {
        // `PointerOwnership.decide` short-circuits on `delegated`, so no native
        // run can reach the deferred state whatever a driver would have said.
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture(), secureInputProbe: { false })
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setTakeover(FakeTakeover())
        await session.setContentionMonitor(FakeContention())
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        let out = try await run(session, ax)
        #expect(out.objectValue?["pointerDrawnBy"] == nil)
    }
}
