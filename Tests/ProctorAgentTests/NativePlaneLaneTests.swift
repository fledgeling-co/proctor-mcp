import Testing
import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0051, the session half. The wire's obligations are pinned in
// `NativePlaneRecordTests`; these prove the session actually meets them, and that
// the guard which stops a determinism number crossing two actuation paths covers
// the whole tape rather than its first step.
//
// A separate file from `ActuationSeamTests` on purpose: PRO-0046 is in flight on
// supervision under delegation and works in that file.

@Suite("PRO-0051 — the lane is fixed, stated, and guarded")
struct NativePlaneLaneTests {

    private func session(_ backend: (any ActuationBackend)? = nil)
    async throws -> (Session, FakeAX) {
        let ax = FakeAX(bundleId: "com.example.fake")
        let session = Session(ax: ax, capture: FakeCapture(), actuator: backend)
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: "com.example.fake", pid: nil, name: nil)
        return (session, ax)
    }

    private func flow(_ name: String, backends: [ActuationBackendID?]) -> RecordedFlow {
        RecordedFlow(name: name, window: "w1",
                     steps: backends.map {
                         RecordedStep(step: ActionStep(kind: .press, node: "n1"),
                                      plane: .accessibility, stateHash: "h", backend: $0)
                     })
    }

    // MARK: - A2 — the lane is chosen from the environment, once, and never moves

    @Test("the delegated lane is entered only by asking for it by name")
    func laneIsSelectedOnlyByName() {
        // The one predicate the whole selection turns on. Anything that is not
        // exactly the delegated lane's name means Proctor's own planes.
        #expect(CuaDriverTool.laneSelected([:]) == false)
        #expect(CuaDriverTool.laneSelected(["PROCTOR_ACTUATION": ""]) == false)
        #expect(CuaDriverTool.laneSelected(["PROCTOR_ACTUATION": "native"]) == false)
        #expect(CuaDriverTool.laneSelected(["PROCTOR_ACTUATION": "cuadriver"]) == false)
        #expect(CuaDriverTool.laneSelected(["PROCTOR_ACTUATION": " cua"]) == false)
        #expect(CuaDriverTool.laneSelected(["PROCTOR_ACTUATION": "cua"]))
        #expect(CuaDriverTool.laneSelected(["PROCTOR_ACTUATION": "CUA"]))
    }

    @Test("a session keeps the lane it was built with, whatever the environment does after")
    func laneIsFixedForTheLifeOfTheSession() async throws {
        let backend = FakeActuationBackend()
        let (session, ax) = try await session(backend)

        // The environment moving underneath a running session must not reach it.
        // `Session.actuator` is `let`, so this is a structural property — the
        // test exists so a later change from `let` to `var` fails here rather
        // than in a campaign whose record says one lane and whose steps ran on
        // another.
        setenv(CuaDriverTool.laneEnv, "cua", 1)
        defer { unsetenv(CuaDriverTool.laneEnv) }

        for _ in 0..<3 {
            _ = try await session.act(window: ax.window.id,
                                      steps: [ActionStep(kind: .press, node: "n1")],
                                      settle: .default, foreground: false,
                                      captureEach: false, diffEach: false, record: nil)
        }
        let lane = await session.actuator.id
        #expect(lane == .cua)
        #expect(backend.performed.count == 3)
        #expect(ax.performed.isEmpty)
    }

    // MARK: - A3 — the act record names the lane, including when nothing actuated

    @Test("an act result names the lane that drove it")
    func actNamesItsLane() async throws {
        let (session, ax) = try await session()
        let out = try await session.act(window: ax.window.id,
                                        steps: [ActionStep(kind: .press, node: "n1")],
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)
        #expect(out.objectValue?["backend"]?.stringValue == "native")
    }

    /// The case that made this run-level. A background click on the native lane
    /// refuses before any backend is called, so no step carries a backend and the
    /// run would otherwise be silent about which lane refused it.
    @Test("a run in which nothing actuated still names the lane that refused it")
    func refusedRunStillNamesItsLane() async throws {
        let (session, ax) = try await session()
        let out = try await session.act(window: ax.window.id,
                                        steps: [ActionStep(kind: .click, node: "n1")],
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)
        let steps = try #require(out.objectValue?["steps"]?.arrayValue)
        #expect(steps.first?.objectValue?["ok"]?.boolValue == false)
        #expect(steps.first?.objectValue?["backend"] == nil)
        #expect(out.objectValue?["backend"]?.stringValue == "native")
    }

    @Test("a delegated run names the delegated lane")
    func delegatedRunNamesItsLane() async throws {
        let backend = FakeActuationBackend()
        let (session, ax) = try await session(backend)
        let out = try await session.act(window: ax.window.id,
                                        steps: [ActionStep(kind: .press, node: "n1")],
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)
        #expect(out.objectValue?["backend"]?.stringValue == "cua")
    }

    // MARK: - A5b — the run's lane and its steps' backends agree

    @Test("every actuated step reports the lane the run reports")
    func stepsAgreeWithTheRun() async throws {
        let (session, ax) = try await session()
        let out = try await session.act(
            window: ax.window.id,
            steps: (0..<3).map { _ in ActionStep(kind: .press, node: "n1") },
            settle: .default, foreground: false, captureEach: false,
            diffEach: false, record: nil)
        let lane = try #require(out.objectValue?["backend"]?.stringValue)
        let steps = try #require(out.objectValue?["steps"]?.arrayValue)
        #expect(steps.count == 3)
        for step in steps {
            let backend = try #require(step.objectValue?["backend"]?.stringValue)
            #expect(backend == lane)
        }
    }

    // MARK: - A6 — the same-backend guard reads the whole tape

    @Test("a tape recorded before backends existed replays without complaint")
    func preBackendTapeReplays() async throws {
        let (session, _) = try await session()
        // It was recorded on the native planes, because they were the only ones
        // there. Refusing it would strand every flow recorded before PRO-0044.
        try await session.requireSameBackend(as: flow("old", backends: [nil, nil, nil]))
    }

    @Test("a legitimate multi-step tape on the same lane replays")
    func sameLaneTapeReplays() async throws {
        let (session, _) = try await session()
        try await session.requireSameBackend(
            as: flow("same", backends: [.native, .native, .native, .native]))
    }

    @Test("a tape recorded on the other lane refuses")
    func otherLaneTapeRefuses() async throws {
        let (session, _) = try await session()
        await #expect(throws: AgentError.self) {
            try await session.requireSameBackend(as: flow("other", backends: [.cua, .cua]))
        }
    }

    /// The hole the old check left. It compared the session against the tape's
    /// FIRST backend only, so a tape whose opening step agreed cleared the guard
    /// however its later steps were recorded. Unreachable today — a tape this
    /// build writes is uniform — which is why it is worth closing before
    /// something makes it reachable.
    @Test("a tape whose later steps were recorded on another lane refuses")
    func mixedTapeRefusesOnALaterStep() async throws {
        let (session, _) = try await session()
        await #expect(throws: AgentError.self) {
            try await session.requireSameBackend(
                as: flow("mixed", backends: [.native, .native, .cua]))
        }
    }

    @Test("steps that never actuated do not make a same-lane tape look mixed")
    func unactuatedStepsDoNotTriggerTheGuard() async throws {
        let (session, _) = try await session()
        // Absent is "this step never actuated", not "a different lane".
        try await session.requireSameBackend(
            as: flow("gappy", backends: [.native, nil, .native]))
    }

    // MARK: - A6b — a sweep's passes share one lane, so one label is honest

    @Test("a determinism report is labelled with the session's own lane")
    func stabilityReportCarriesTheSessionLane() async throws {
        let (session, ax) = try await session()
        _ = try await session.flowStart(name: "sweep", window: ax.window.id,
                                        description: nil)
        _ = try await session.act(window: ax.window.id,
                                  steps: [ActionStep(kind: .press, node: "n1")],
                                  settle: .default, foreground: false,
                                  captureEach: false, diffEach: false, record: "sweep")
        _ = try await session.flowStop()

        let report = try await session.stability(flow: "sweep", runs: 2,
                                                 window: ax.window.id, resetBetween: [],
                                                 includeTiles: false, captureEach: false,
                                                 pointerMarks: false)
        // Every pass ran in this one session, and the session's lane cannot
        // change, so one label describes the whole report rather than one pass.
        let lane = await session.actuator.id
        #expect(report.backend == lane)
        #expect(report.backend == .native)
    }
}
