import Testing
import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0044, slice 2. The seam, wired into a real session.
//
// Two things are proved here that a unit test of the backend cannot: that the
// refusal, the queue and the disclosure now ask the backend rather than a table
// of kinds, and that the native lane is untouched by all of it.

/// A backend that answers from a script, so a session can be driven without a
/// Mac, a grant, or an application on screen.
final class FakeActuationBackend: ActuationBackend, @unchecked Sendable {

    let id: ActuationBackendID
    /// What this backend claims it can do in the background, per kind.
    var capability: @Sendable (ActionStep.Kind) -> BackgroundCapability
    /// What each performed step reports back, by index.
    var outcomes: [Int: Actuation] = [:]
    /// Called while the step is "running", so a test can move the tree underneath
    /// it — which is what makes a before-and-after hash comparison meaningful.
    var onPerform: (@Sendable () -> Void)?
    var defaultOutcome = Actuation(.accessibility, .action, backend: .cua,
                                   reportedMode: "ax", effect: .confirmed)
    /// Thrown instead of returning, so a test can drive the failure paths a
    /// subprocess has and an in-process call does not (PRO-0045).
    var failure: AgentError?
    private let lock = NSLock()
    private var _performed: [ActionStep] = []
    var performed: [ActionStep] { lock.withLock { _performed } }

    init(id: ActuationBackendID = .cua,
         capability: @escaping @Sendable (ActionStep.Kind) -> BackgroundCapability
            = { _ in .maybe }) {
        self.id = id
        self.capability = capability
    }

    func backgroundCapability(for kind: ActionStep.Kind) -> BackgroundCapability {
        capability(kind)
    }

    func preflight() async throws {}

    /// What this backend has established about itself, for `proctor_doctor`.
    /// Set by a test; reading it establishes nothing, which is the property the
    /// real one has to have.
    var laneHealthValue: ToolLaneFacts?
    var laneHealth: ToolLaneFacts? { get async { laneHealthValue } }

    /// The pid this backend's driver reported and Proctor corroborated, or nil
    /// for a driver Proctor cannot recognise — which is what makes a batch take
    /// the exclusive lane (PRO-0046). Nil by default, the conservative answer.
    var actuatingPidValue: Int64?
    var actuatingPid: Int64? { get async { actuatingPidValue } }

    /// Whether the driver can be asked not to draw its own cursor. True by
    /// default so an existing test's pointer behaviour is unchanged.
    var cursorSuppressibleValue = true
    var cursorSuppressible: Bool { get async { cursorSuppressibleValue } }

    func perform(step: ActionStep, target: StepTarget,
                 foreground: Bool) async throws -> Actuation {
        let index = lock.withLock { () -> Int in
            _performed.append(step)
            return _performed.count - 1
        }
        onPerform?()
        if let failure { throw failure }
        return outcomes[index] ?? defaultOutcome
    }
}

@Suite("Actuation seam")
struct ActuationSeamTests {

    private func session(_ backend: (any ActuationBackend)? = nil)
    async throws -> (Session, FakeAX) {
        let ax = FakeAX(bundleId: "com.example.fake")
        let session = Session(ax: ax, capture: FakeCapture(), actuator: backend)
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: "com.example.fake", pid: nil, name: nil)
        return (session, ax)
    }

    @Test("a session built without a backend actuates through the native planes")
    func defaultsToNative() async throws {
        // The seam's first obligation: every existing construction keeps working
        // and keeps behaving identically. There is one argument in `Session.init`
        // and it is defaulted.
        let (session, ax) = try await session()
        _ = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .press)],
                                  settle: .default, foreground: false, captureEach: false,
                                  diffEach: false, record: nil)
        #expect(ax.performed.count == 1)
    }

    @Test("the native lane still refuses a background click")
    func nativeStillRefusesBackgroundClick() async throws {
        // Unchanged behaviour, now reached by asking the backend instead of
        // consulting a static set. A click has no accessibility expression on
        // Proctor's own planes, so `foreground: false` is a contradiction.
        let (session, ax) = try await session()
        let out = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .click)],
                                        settle: .default, foreground: false, captureEach: false,
                                        diffEach: false, record: nil)
        let steps = try #require(out.objectValue?["steps"]?.arrayValue)
        #expect(steps.first?.objectValue?["ok"]?.boolValue == false)
        #expect(ax.performed.isEmpty)
    }

    @Test("a backend that can click in the background is allowed to")
    func delegatedBackgroundClickIsNotRefused() async throws {
        // The correction that reorganised this feature. Refusing here would have
        // shipped a delegated lane in which background clicks — most of the
        // reason to delegate — are unreachable, because the refusal was built on
        // a fact about Proctor's actuator rather than about clicking.
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.routedEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent", effect: .confirmed)
        let (session, ax) = try await session(backend)
        let out = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .click)],
                                        settle: .default, foreground: false, captureEach: false,
                                        diffEach: false, record: nil)
        let steps = try #require(out.objectValue?["steps"]?.arrayValue)
        #expect(steps.first?.objectValue?["ok"]?.boolValue == true)
        #expect(steps.first?.objectValue?["plane"]?.stringValue == "routedEvent")
        #expect(backend.performed.count == 1)
        // And the native engine was not touched, so nothing quietly ran on it.
        #expect(ax.performed.isEmpty)
    }

    @Test("a background-capable batch does not announce that it took the machine")
    func backgroundBatchDoesNotClaimTheForeground() async throws {
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.routedEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent")
        let (session, ax) = try await session(backend)
        let out = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .click)],
                                        settle: .default, foreground: false, captureEach: false,
                                        diffEach: false, record: nil)
        let foreground = try #require(out.objectValue?["foreground"]?.objectValue)
        #expect(foreground["measured"]?.doubleValue == 0)
        #expect(foreground["ranInForeground"]?.boolValue == false)
        #expect(out.objectValue?["foregroundNote"] == nil)
    }

    @Test("an unproven plane makes the run say so")
    func unprovenRunDiscloses() async throws {
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.unknown, nil, backend: .cua,
                                           reportedMode: "warp_drive")
        let (session, ax) = try await session(backend)
        let out = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .press)],
                                        settle: .default, foreground: false, captureEach: false,
                                        diffEach: false, record: nil)
        let foreground = try #require(out.objectValue?["foreground"]?.objectValue)
        #expect(foreground["unproven"]?.doubleValue == 1)
        // The sentence a reader actually reads, not just a new field.
        let note = try #require(out.objectValue?["foregroundNote"]?.stringValue)
        #expect(note.contains("could not be established"))
    }

    @Test("an escalation nobody asked for is reported as one")
    func escalationIsReported() async throws {
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.syntheticEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent_fg",
                                           unrequestedForeground: true)
        let (session, ax) = try await session(backend)
        let out = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .press)],
                                        settle: .default, foreground: false, captureEach: false,
                                        diffEach: false, record: nil)
        let note = try #require(out.objectValue?["foregroundNote"]?.stringValue)
        #expect(note.contains("without being asked"))
    }

    // MARK: - The no-op cross

    @Test("a suspected no-op with an unchanged state fails the step")
    func agreedNoOpFailsTheStep() async throws {
        // Two independent observers agreeing that nothing happened. Leaving `ok`
        // true here would reproduce exactly the defect the unproven-plane rule
        // fixes: every existing reader checks `ok` and would see a success.
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.routedEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent", effect: .suspectedNoOp)
        let (session, ax) = try await session(backend)
        let out = try await session.act(window: ax.window.id, steps: [ActionStep(kind: .press)],
                                        settle: .default, foreground: false, captureEach: false,
                                        diffEach: false, record: nil)
        let step = try #require(out.objectValue?["steps"]?.arrayValue?.first?.objectValue)
        #expect(step["ok"]?.boolValue == false)
        #expect(step["error"]?.objectValue?["code"]?.stringValue == "actionNoOp")
        #expect(step["effect"]?.stringValue == "suspectedNoOp")
    }

    @Test("a suspected no-op the tree contradicts stays a success")
    func contradictedNoOpStaysOK() async throws {
        // The asymmetry is deliberate: a driver that under-reports its own
        // success must not turn a working run red. The claim is recorded beside
        // the result rather than deciding it.
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.routedEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent", effect: .suspectedNoOp)
        let (session, ax) = try await session(backend)
        // Move the tree while the step is running, so the before and after
        // hashes differ and the driver's suspicion is contradicted by
        // measurement.
        backend.onPerform = { ax.nodeRole = "AXCheckBox" }
        let out = try await session.act(window: ax.window.id,
                                        steps: [ActionStep(kind: .press)],
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)
        let step = try #require(out.objectValue?["steps"]?.arrayValue?.first?.objectValue)
        #expect(step["ok"]?.boolValue == true)
        #expect(step["effect"]?.stringValue == "suspectedNoOp")
    }
}
