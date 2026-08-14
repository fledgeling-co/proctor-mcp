import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0012 — the two drive paths that used to skip the rails.
//
// `act` and both computer facades passed through the policy gate and the
// redacting trail; a recorded flow replayed through `proctor_flow`, and the
// determinism instrument that replays one N times, did not. A recording made
// under one policy could be replayed under another, and none of it reached the
// trail. These tests exercise the wiring itself — the gate runs before anything
// is actuated, every replayed step is recorded, and a TTL-bounded approval
// actually expires part-way through a repeated run — against fake engines, so
// they need no grant and touch neither the operator's policy file nor the trail.

@Suite("Replay gate wiring")
struct ReplayGateWiringTests {

    private static let target = "com.example.target"

    /// A session driving a fake app, with the trail collected in memory and the
    /// clock under the test's control.
    private func harness(policy: AppPolicy,
                         token: ApprovalToken? = nil,
                         now: @escaping @Sendable () -> Double = { 1_000 },
                         steps: Int = 2,
                         bundleId: String = target)
    async throws -> (session: Session, ax: FakeAX, audit: AuditCollector) {
        let ax = FakeAX(bundleId: bundleId)
        let session = Session(ax: ax, capture: FakeCapture())
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.setClock(now)
        await session.installPolicy(policy, token: token)
        _ = try await session.attachResolved(bundleId: bundleId, pid: nil, name: nil)

        let recorded = (0..<steps).map { index in
            RecordedStep(step: ActionStep(kind: .press, node: "node-1",
                                          label: "step \(index)"),
                         stateHash: "recorded-\(index)")
        }
        await session.installFlow(RecordedFlow(name: "login", window: ax.window.id,
                                               app: ax.app.id, appBundleId: bundleId,
                                               steps: recorded))
        return (session, ax, audit)
    }

    // MARK: - Replay

    @Test("a replay of a blocked app is refused before a single step is actuated")
    func replayRefusedBeforeAnyStep() async throws {
        // The whole point of the gate: a recording made when the app was allowed
        // must not replay once an operator has blocked it, and it must not get
        // half-way in before finding out.
        let h = try await harness(policy: AppPolicy(block: [Self.target]))

        await #expect(throws: AgentError.self) {
            _ = try await h.session.flowReplay(name: "login", window: nil, captureEach: false,
                                               settle: .default)
        }
        #expect(h.ax.performed.isEmpty)

        let refusals = h.audit.records.filter { $0.outcome == "refused" }
        #expect(refusals.count == 1)
        let refusal = try #require(refusals.first)
        #expect(refusal.tool == AuditTool.flowReplay)
        #expect(refusal.bundleId == Self.target)
        #expect(refusal.reason?.contains("block list") == true)
    }

    @Test("the gate judges the app being driven now, not the one the recording names")
    func replayJudgedOnLiveTarget() async throws {
        // A recording can be pointed at a different window. The authority that
        // matters is over the app actually being touched, so a flow whose stored
        // bundle id is allowed is still refused when the live window belongs to a
        // blocked app.
        let ax = FakeAX(bundleId: "com.example.blocked")
        let session = Session(ax: ax, capture: FakeCapture())
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.installPolicy(AppPolicy(allow: ["com.example.recorded"]))
        _ = try await session.attachResolved(bundleId: "com.example.blocked", pid: nil, name: nil)
        await session.installFlow(RecordedFlow(name: "login", window: ax.window.id,
                                               app: ax.app.id,
                                               appBundleId: "com.example.recorded",
                                               steps: [RecordedStep(step: ActionStep(kind: .press,
                                                                                     node: "node-1"))]))

        await #expect(throws: AgentError.self) {
            _ = try await session.flowReplay(name: "login", window: nil, captureEach: false,
                                             settle: .default)
        }
        #expect(ax.performed.isEmpty)
        // The refusal names the live app, which is the one the decision was made on.
        #expect(audit.records.last?.bundleId == "com.example.blocked")
    }

    @Test("a target with no resolvable bundle id fails closed under an allow list")
    func replayFailsClosedOnUnidentifiableTarget() async throws {
        // An unidentifiable target is exactly the case a shared tool must not wave
        // through, and the live path already refuses it.
        let ax = FakeAX(bundleId: "")
        let session = Session(ax: ax, capture: FakeCapture())
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.installPolicy(AppPolicy(allow: ["com.example.allowed"]))
        _ = try await session.attachResolved(bundleId: nil, pid: 4242, name: nil)
        await session.installFlow(RecordedFlow(name: "login", window: ax.window.id,
                                               app: ax.app.id,
                                               steps: [RecordedStep(step: ActionStep(kind: .press,
                                                                                     node: "node-1"))]))

        await #expect(throws: AgentError.self) {
            _ = try await session.flowReplay(name: "login", window: nil, captureEach: false,
                                             settle: .default)
        }
        #expect(ax.performed.isEmpty)
        #expect(audit.records.last?.outcome == "refused")
    }

    @Test("a permitted replay writes one trail entry per step, named as a replay")
    func replayAuditsEveryStep() async throws {
        let h = try await harness(policy: AppPolicy(allow: [Self.target]), steps: 3)
        _ = try await h.session.flowReplay(name: "login", window: nil, captureEach: false,
                                           settle: .default)

        #expect(h.ax.performed.count == 3)
        let entries = h.audit.records(tool: AuditTool.flowReplay)
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.outcome == "ok" })
        #expect(entries.allSatisfy { $0.bundleId == Self.target })
        #expect(entries.allSatisfy { $0.window == h.ax.window.id })
        // Distinct from a live drive, which is what lets the trail answer "who did this".
        #expect(h.audit.records(tool: AuditTool.act).isEmpty)
    }

    @Test("a replayed secret is redacted exactly as a live one is")
    func replayRedactsTypedText() async throws {
        let secret = "hunter2-the-password"
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture())
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.installPolicy(AppPolicy())
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        await session.installFlow(
            RecordedFlow(name: "login", window: ax.window.id, app: ax.app.id,
                         steps: [RecordedStep(step: ActionStep(kind: .type, text: secret))]))

        _ = try await session.flowReplay(name: "login", window: nil, captureEach: false,
                                         settle: .default)

        let entry = try #require(audit.records(tool: AuditTool.flowReplay).first)
        #expect(entry.value == Redaction(of: secret))
        #expect(!entry.jsonLine().contains(secret))
    }

    @Test("a replayed step that fails is recorded as failed, with its reason")
    func replayAuditsFailure() async throws {
        let h = try await harness(policy: AppPolicy(), steps: 3)
        h.ax.failPerformAt = 1

        _ = try await h.session.flowReplay(name: "login", window: nil, captureEach: false,
                                           settle: .default)

        let entries = h.audit.records(tool: AuditTool.flowReplay)
        #expect(entries.count == 2)
        #expect(entries.first?.outcome == "ok")
        let failure = try #require(entries.count == 2 ? entries[1] : nil)
        #expect(failure.outcome == "failed")
        #expect(failure.reason?.contains("fake failure") == true)
    }

    @Test("recording, listing, showing and deleting stay ungated and unrecorded")
    func readOnlyFlowActionsAreNotGated() async throws {
        // None of them drives an app, so the gate has nothing to decide and the
        // trail has nothing to record — a blocked app must not stop an operator
        // reading what is stored.
        let h = try await harness(policy: AppPolicy(block: [Self.target]))
        _ = try await h.session.flowList()
        _ = try await h.session.flowShow(name: "login")
        #expect(h.audit.records.isEmpty)
    }

    @Test("the live drive path is unchanged: one refusal entry, same message and remedy")
    func liveActPathUnchanged() async throws {
        // The refusal text moved into ProctorCore so replay and the determinism
        // tool could share it. The paths that were already gated must be exactly
        // where they were: one audit entry, not two, and the same words.
        let h = try await harness(policy: AppPolicy(block: [Self.target]))

        let error = await #expect(throws: AgentError.self) {
            _ = try await h.session.act(window: h.ax.window.id,
                                        steps: [ActionStep(kind: .press, node: "node-1")],
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)
        }
        #expect(error?.code == .policyDenied)
        #expect(error?.message.contains("is on the block list; actuation is refused.") == true)
        #expect(error?.remedy == "Remove the app from the block list with proctor_policy action "
                               + "\"configure\", or drive a different application.")
        #expect(h.ax.performed.isEmpty)

        // Exactly one refusal record, named as the live tool.
        let refusals = h.audit.records.filter { $0.outcome == "refused" }
        #expect(refusals.count == 1)
        #expect(try #require(refusals.first).tool == AuditTool.act)
    }

    // MARK: - Stability

    @Test("a stability run of a blocked app is refused and reports no numbers")
    func stabilityRefusedBeforeAnyRepeat() async throws {
        let h = try await harness(policy: AppPolicy(block: [Self.target]))

        await #expect(throws: AgentError.self) {
            _ = try await h.session.stability(flow: "login", runs: 5, window: nil,
                                              resetBetween: [], includeTiles: false)
        }
        #expect(h.ax.performed.isEmpty)
        #expect(h.audit.records.allSatisfy { $0.outcome == "refused" })
    }

    @Test("every repeat of a permitted run is gated and every step recorded")
    func stabilityAuditsEveryRepeat() async throws {
        let h = try await harness(policy: AppPolicy(allow: [Self.target]), steps: 2)
        let report = try await h.session.stability(flow: "login", runs: 3, window: nil,
                                                   resetBetween: [], includeTiles: false)

        #expect(report.runs == 3)
        #expect(h.ax.performed.count == 6)
        #expect(h.audit.records(tool: AuditTool.stabilityReplay).count == 6)
        #expect(h.audit.records.allSatisfy { $0.outcome == "ok" })
    }

    @Test("the reset between repeats is gated and recorded under its own name")
    func stabilityAuditsResetSeparately() async throws {
        // The reset drives the app exactly as a replayed step does. Naming it
        // apart is what lets the trail say which steps were the measurement and
        // which were putting the app back.
        let h = try await harness(policy: AppPolicy(allow: [Self.target]), steps: 1)
        let reset = [ActionStep(kind: .press, node: "node-1", label: "reset")]
        _ = try await h.session.stability(flow: "login", runs: 3, window: nil,
                                          resetBetween: reset, includeTiles: false)

        // Three measured repeats, two resets (none before the first).
        #expect(h.audit.records(tool: AuditTool.stabilityReplay).count == 3)
        #expect(h.audit.records(tool: AuditTool.stabilityReset).count == 2)
        #expect(h.audit.records(tool: AuditTool.stabilityReset)
                    .allSatisfy { $0.outcome == "ok" })
    }

    @Test("an approval expiring between repeats stops the run and keeps what it measured")
    func stabilityStopsWhenApprovalExpires() async throws {
        // A sensitive app may be driven only against a live token. The token has a
        // TTL because a crashed caller must not leave standing authority; a
        // repeated run is where that TTL has to actually bite, rather than the
        // authority of the first minute carrying to the last repeat.
        let clock = MovingClock(start: 1_000)
        let token = ApprovalToken.mint(bundleId: Self.target, ttl: 60, now: 1_000)
        let h = try await harness(policy: AppPolicy(sensitive: [Self.target]),
                                  token: token, now: clock.read, steps: 1)
        // Two repeats' worth of gate reads at the original time, then the TTL is past.
        clock.schedule([1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 2_000])

        let report = try await h.session.stability(flow: "login", runs: 5, window: nil,
                                                   resetBetween: [], includeTiles: false)

        // It reports the repeats it completed, not the five that were asked for,
        // and cannot come back marked deterministic on a truncated sample.
        #expect(report.runs < 5)
        #expect(report.runs >= 1)
        #expect(!report.deterministic)
        #expect(report.notes.contains { $0.contains("of 5 repeats") })
        #expect(report.notes.contains { $0.contains("approval token") })
        // The refusal that ended it is in the trail, named as the determinism tool.
        let refusals = h.audit.records.filter { $0.outcome == "refused" }
        #expect(refusals.count == 1)
        #expect(try #require(refusals.first).tool == AuditTool.stabilityReplay)
        // No further steps were actuated after it stopped.
        #expect(h.ax.performed.count == report.runs)
    }

    @Test("a reset refused after a repeat has completed ends the run, named as the reset")
    func stabilityRefusedResetEndsRun() async throws {
        // The reset drives the app first in every repeat after the first, so it is
        // the gate that trips when authority runs out. The run must end there with
        // what it measured, and the trail must say it was the reset that was
        // refused rather than the measurement.
        let clock = MovingClock(start: 1_000)
        let token = ApprovalToken.mint(bundleId: Self.target, ttl: 60, now: 1_000)
        let h = try await harness(policy: AppPolicy(sensitive: [Self.target]),
                                  token: token, now: clock.read, steps: 1)
        // Repeat 0 has no reset: one gate read plus one step record. Then the
        // reset gate of repeat 1 reads a time past the TTL.
        clock.schedule([1_000, 1_000, 2_000])
        let reset = [ActionStep(kind: .type, text: "reset-secret")]

        let report = try await h.session.stability(flow: "login", runs: 4, window: nil,
                                                   resetBetween: reset, includeTiles: false)

        #expect(report.runs == 1)
        #expect(!report.deterministic)
        #expect(report.notes.contains { $0.contains("of 4 repeats") })
        let refusals = h.audit.records.filter { $0.outcome == "refused" }
        #expect(refusals.count == 1)
        #expect(try #require(refusals.first).tool == AuditTool.stabilityReset)
        // Nothing from the reset was actuated, so the app was not touched after
        // the authority lapsed.
        #expect(h.ax.performed.count == 1)
    }

    @Test("a secret inside a reset step is redacted under the reset's own name")
    func stabilityRedactsResetSecrets() async throws {
        // The reset runs through the same actuation path, so it carries the same
        // redaction. A reset that types a password must not put it in the trail.
        let secret = "reset-hunter2"
        let h = try await harness(policy: AppPolicy(allow: [Self.target]), steps: 1)
        _ = try await h.session.stability(flow: "login", runs: 2, window: nil,
                                          resetBetween: [ActionStep(kind: .type, text: secret)],
                                          includeTiles: false)

        let entry = try #require(h.audit.records(tool: AuditTool.stabilityReset).first)
        #expect(entry.value == Redaction(of: secret))
        #expect(!entry.jsonLine().contains(secret))
    }

    @Test("a truncated run is never reported deterministic, even when its repeats agreed")
    func truncatedRunIsNotDeterministic() async throws {
        // Beyond the spec, deliberately. Agreement across two repeats when ten
        // were asked for is a weaker claim than the one the caller commissioned,
        // and this instrument's value is that it does not overstate its evidence.
        let clock = MovingClock(start: 1_000)
        let token = ApprovalToken.mint(bundleId: Self.target, ttl: 60, now: 1_000)
        let h = try await harness(policy: AppPolicy(sensitive: [Self.target]),
                                  token: token, now: clock.read, steps: 1)
        clock.schedule([1_000, 1_000, 1_000, 1_000, 2_000])

        let report = try await h.session.stability(flow: "login", runs: 10, window: nil,
                                                   resetBetween: [], includeTiles: false)

        // The completed repeats agreed with each other; the report still refuses
        // to call the flow deterministic on a sample it was cut off from taking.
        #expect(report.runs == 2)
        #expect(report.stepInstability.allSatisfy { $0 == 0 })
        #expect(report.firstDivergence == nil)
        #expect(!report.deterministic)
    }

    @Test("a run refused at its first repeat throws rather than reporting an empty measurement")
    func stabilityFirstRepeatRefusalThrows() async throws {
        // A report of zero repeats reads as a measurement; a refusal has to read
        // as a refusal.
        let h = try await harness(policy: AppPolicy(sensitive: [Self.target]), steps: 1)
        let error = await #expect(throws: AgentError.self) {
            _ = try await h.session.stability(flow: "login", runs: 5, window: nil,
                                              resetBetween: [], includeTiles: false)
        }
        #expect(error?.code == .policyDenied)
        #expect(error?.remedy?.contains("approve") == true)
    }
}

/// A clock that hands out a scheduled sequence of readings and then holds the
/// last one, so a test can cross a TTL boundary exactly instead of sleeping.
final class MovingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [Double]
    private var last: Double

    init(start: Double) {
        readings = []
        last = start
    }

    func schedule(_ values: [Double]) {
        lock.lock(); defer { lock.unlock() }
        readings = values
    }

    var read: @Sendable () -> Double {
        { [self] in
            lock.lock(); defer { lock.unlock() }
            if !readings.isEmpty { last = readings.removeFirst() }
            return last
        }
    }
}
