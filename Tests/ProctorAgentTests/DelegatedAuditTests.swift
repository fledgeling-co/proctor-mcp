import Testing
import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0045. What the trail attests to once Proctor stopped performing the action
// it records.
//
// The clause each test proves is named in its comment. Almost all of them are
// about a claim rather than a behaviour, because that is what this item changes:
// the batch stops in the same places it stopped before, and what moved is what
// the row is entitled to say.

@Suite("Delegated calls are gated and recorded")
struct DelegatedAuditTests {

    private func session(_ backend: (any ActuationBackend)? = nil)
    async throws -> (Session, FakeAX, AuditCollector) {
        let ax = FakeAX(bundleId: "com.example.fake")
        let audit = AuditCollector()
        let session = Session(ax: ax, capture: FakeCapture(), actuator: backend)
        await session.setAuditSink(audit.sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: "com.example.fake", pid: nil, name: nil)
        return (session, ax, audit)
    }

    private func press(_ session: Session, _ ax: FakeAX,
                       kind: ActionStep.Kind = .press) async throws -> JSONValue {
        try await session.act(window: ax.window.id, steps: [ActionStep(kind: kind)],
                              settle: .default, foreground: false, captureEach: false,
                              diffEach: false, record: nil)
    }

    /// The rows that describe steps, as opposed to the run's own events.
    private func steps(_ audit: AuditCollector) -> [AuditRecord] {
        audit.records.filter { $0.kind != nil }
    }

    // MARK: - A1. The gate stands in front of the delegated call, including the spawn

    @Test("a blocked app is refused before the backend is reached at all")
    func gatePrecedesTheBackend() async throws {
        // The ordering matters more than the refusal. Preflight is what spawns
        // the driver, and it is reachable only from `perform`, which is reachable
        // only from inside the gated batch — so a refusal must cost zero backend
        // calls. Asserted structurally, because reading the call graph is exactly
        // the kind of proof a later refactor invalidates silently.
        let backend = FakeActuationBackend()
        let (session, ax, audit) = try await session(backend)
        await session.installPolicy(AppPolicy(allow: [], block: ["com.example.fake"],
                                              sensitive: []))
        _ = try? await press(session, ax)

        #expect(backend.performed.isEmpty)
        let refusals = audit.records.filter { $0.outcome == AuditRecord.Outcome.refused }
        #expect(refusals.count == 1)
        #expect(steps(audit).isEmpty)
    }

    // MARK: - A2. Who acted, what they claimed, what Proctor observed

    @Test("a delegated row carries the backend, its claim and Proctor's own reading")
    func delegatedRowCarriesThreeFacts() async throws {
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.routedEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent", effect: .confirmed,
                                           laneId: "lane-7")
        let (session, ax, audit) = try await session(backend)
        backend.onPerform = { ax.nodeRole = "AXCheckBox" }
        _ = try await press(session, ax)

        let row = try #require(steps(audit).first)
        #expect(row.outcome == AuditRecord.Outcome.ok)
        #expect(row.by == "cua")
        #expect(row.mode == "cgevent")
        #expect(row.eff == "confirmed")
        // Proctor's own before/after walk, not the driver's word.
        #expect(row.obs == "changed")
        #expect(row.lane == "lane-7")
    }

    @Test("a native row makes no claims it is not entitled to")
    func nativeRowCarriesNoDelegatedFields() async throws {
        // The nils are the feature, not an omission. Native reports no delivery
        // mode and no confidence because it judges a write by reading it back,
        // and it takes no before-hash, so an observation would have to be
        // manufactured from the previous step's post-state — a different interval
        // under the same name.
        let (session, ax, audit) = try await session()
        _ = try await press(session, ax)

        let row = try #require(steps(audit).first)
        #expect(row.by == "native")
        #expect(row.mode == nil)
        #expect(row.eff == nil)
        #expect(row.obs == nil)
    }

    // MARK: - A3. The two observers stay separate, including when they disagree

    @Test("a suspected no-op the window contradicts stays a success, with both readings")
    func disagreementIsRecordedRatherThanResolved() async throws {
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.routedEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent", effect: .suspectedNoOp)
        let (session, ax, audit) = try await session(backend)
        backend.onPerform = { ax.nodeRole = "AXCheckBox" }
        _ = try await press(session, ax)

        let row = try #require(steps(audit).first)
        // The step passed BECAUSE Proctor's own reading overruled the driver's
        // suspicion, and both halves of that are on the row.
        #expect(row.outcome == AuditRecord.Outcome.ok)
        #expect(row.eff == "suspectedNoOp")
        #expect(row.obs == "changed")
    }

    @Test("two observers agreeing nothing happened is a failure, with its inputs beside it")
    func agreementOnNothingHappeningFails() async throws {
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.routedEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent", effect: .suspectedNoOp)
        let (session, ax, audit) = try await session(backend)
        _ = try await press(session, ax)

        let row = try #require(steps(audit).first)
        #expect(row.outcome == AuditRecord.Outcome.failed)
        #expect(row.eff == "suspectedNoOp")
        #expect(row.obs == "unchanged")
    }

    // MARK: - A4. A driver that dies leaves an indeterminate row, not a failed one

    @Test("a backend that dies mid-step records indeterminate and keeps Proctor's reading")
    func aDeadDriverIsNotAFailure() async throws {
        // `failed` asserts the action did not happen. When a subprocess stops
        // answering, the request may have been written, delivered and performed
        // before it went, and nothing here can tell. The row says so, and carries
        // the only evidence left — Proctor's own walk of the window.
        let backend = FakeActuationBackend()
        backend.failure = CuaEndpointTransport.gone(nil, lane: "lane-9")
        let (session, ax, audit) = try await session(backend)
        backend.onPerform = { ax.nodeRole = "AXCheckBox" }
        _ = try await press(session, ax)

        let row = try #require(steps(audit).first)
        #expect(row.outcome == AuditRecord.Outcome.indeterminate)
        #expect(row.obs == "changed")

        // And the lane's own event, on its own row rather than folded into the step.
        let lane = try #require(audit.records.first { $0.tool == "proctor_actuation" })
        #expect(lane.kind == nil)
        #expect(lane.outcome == AuditRecord.Outcome.indeterminate)
        #expect(lane.lane == "lane-9")
    }

    @Test("a native failure still says failed, even carrying the same error code")
    func nativeFailureIsNotIndeterminate() async throws {
        // This is what pins the type-not-code decision. The judgment is the
        // backend's, carried on the error; a code alone would flip this row.
        let backend = FakeActuationBackend(id: .native)
        backend.failure = AgentError(code: .actionIndeterminate, message: "native gave up")
        let (session, ax, audit) = try await session(backend)
        _ = try await press(session, ax)

        let row = try #require(steps(audit).first)
        #expect(row.outcome == AuditRecord.Outcome.failed)
        #expect(row.obs == nil)
    }

    // MARK: - A9. The wording on an indeterminate row asserts nothing

    @Test("an indeterminate row does not say Proctor pressed anything")
    func indeterminateRowsUseTheNounForm() async throws {
        let backend = FakeActuationBackend()
        backend.failure = CuaEndpointTransport.late(30, lane: "lane-3")
        let (session, ax, audit) = try await session(backend)
        _ = try await press(session, ax)

        let row = try #require(steps(audit).first)
        #expect(row.outcome == AuditRecord.Outcome.indeterminate)
        // "Press", never "Pressed". `act` is Proctor's own voice, and the past
        // tense on this row would assert the very thing the row cannot establish.
        #expect(row.act == "Press")
    }

    @Test("no indeterminate line anywhere claims the step happened")
    func noIndeterminateWordingIsPastTense() {
        // Walks the whole vocabulary rather than the one kind a test happened to
        // use: a new step kind must not be able to reintroduce the assertion.
        for kind in ActionStep.Kind.allCases {
            let step = ActionStep(kind: kind)
            let line = StepDescription.line(for: step, node: nil, outcome: .indeterminate)
            // The asserting form for this same kind — what the row would have
            // said before this item, and must never say now.
            let past = StepDescription.past(for: step, node: nil).verb
            #expect(!line.contains(past),
                    "the \(kind.rawValue) line asserts \"\(past)\": \(line)")
            #expect(!line.contains("failed"))
        }
    }

    // MARK: - A10. An indeterminate step is never retried

    @Test("the batch stops at an indeterminate step and runs it exactly once")
    func indeterminateStopsTheBatchWithoutRetrying() async throws {
        // Replaying a step that may already have been delivered is how one click
        // becomes two, and `failed` is the sort of thing a retry loop feels
        // entitled to re-run.
        let backend = FakeActuationBackend()
        backend.failure = CuaEndpointTransport.gone(nil, lane: "lane-1")
        let (session, ax, audit) = try await session(backend)
        let out = try await session.act(window: ax.window.id,
                                        steps: [ActionStep(kind: .press),
                                                ActionStep(kind: .focus)],
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)

        #expect(backend.performed.count == 1)
        #expect(steps(audit).count == 1)
        #expect(out.objectValue?["failedAt"]?.doubleValue == 0)
    }

    // MARK: - A7. Nothing recorded about the target widens

    @Test("no delegated field carries application or caller text")
    func delegatedFieldsCarryNoForeignText() async throws {
        let secret = "SENTINEL-do-not-record-me"
        let backend = FakeActuationBackend()
        // A driver returning prose where a delivery path belongs. The value is
        // the driver's own, not the application's, but it is still foreign text
        // entering a file Proctor keeps.
        backend.defaultOutcome = Actuation(.unknown, nil, backend: .cua,
                                           reportedMode: secret
                                               + String(repeating: "x", count: 500),
                                           effect: .unverifiable)
        let (session, ax, audit) = try await session(backend)
        _ = try await session.act(window: ax.window.id,
                                  steps: [ActionStep(kind: .type, text: secret)],
                                  settle: .default, foreground: false,
                                  captureEach: false, diffEach: false, record: nil)

        let row = try #require(steps(audit).first)
        // The typed text is redacted as it always was, and the mode is bounded
        // rather than stored whole.
        #expect(row.value?.len == secret.count)
        let mode = try #require(row.mode)
        #expect(mode.count <= StepDescription.objectLimit)
        // Every field this item added is either a closed vocabulary or bounded.
        #expect(row.by == "cua")
        #expect(row.eff == "unverifiable")
        #expect([nil, "changed", "unchanged", "unread"].contains(row.obs))
    }

    // MARK: - A6. Lane events are the run's, not a step's

    @Test("a lane event is written as its own record with no step kind")
    func laneEventsBelongToTheRun() async throws {
        let backend = FakeActuationBackend()
        backend.failure = AgentError(
            code: .backendUnsupported, message: "the build moved",
            indeterminate: false,
            lane: LaneEvent(kind: .identityChanged, backend: .cua, laneId: "lane-2",
                            reason: "the cua-driver build changed between batches"))
        let (session, ax, audit) = try await session(backend)
        _ = try await press(session, ax)

        let lane = try #require(audit.records.first { $0.tool == "proctor_actuation" })
        // No step kind is what makes `RunHistory` read it as the run's own event
        // rather than as one of its steps.
        #expect(lane.kind == nil)
        #expect(lane.outcome == AuditRecord.Outcome.refused)
        #expect(lane.by == "cua")
        // A refusal that reached no driver is not indeterminate.
        #expect(steps(audit).first?.outcome == AuditRecord.Outcome.failed)
    }

    @Test("two overlapping batches keep their own lane events")
    func laneEventsStayWithTheRunThatProducedThem() async throws {
        // The test the plan review asked for, and the one that fails against an
        // accumulate-then-drain design: `Session` is a reentrant actor, so a
        // second batch finishing between `await perform` and a later `await
        // drain` would have its events attributed to the first.
        let first = FakeActuationBackend()
        first.failure = AgentError(code: .backendUnavailable, message: "one",
                                   indeterminate: true,
                                   lane: LaneEvent(kind: .died, backend: .cua,
                                                   laneId: "lane-A", reason: "A died"))
        let second = FakeActuationBackend()
        second.failure = AgentError(code: .backendUnavailable, message: "two",
                                    indeterminate: true,
                                    lane: LaneEvent(kind: .died, backend: .cua,
                                                    laneId: "lane-B", reason: "B died"))
        let (sessionA, axA, auditA) = try await session(first)
        let (sessionB, axB, auditB) = try await session(second)

        async let a: JSONValue = press(sessionA, axA)
        async let b: JSONValue = press(sessionB, axB)
        _ = try await (a, b)

        let lanesA = auditA.records.filter { $0.tool == "proctor_actuation" }
        let lanesB = auditB.records.filter { $0.tool == "proctor_actuation" }
        #expect(lanesA.allSatisfy { $0.lane == "lane-A" })
        #expect(lanesB.allSatisfy { $0.lane == "lane-B" })
        #expect(lanesA.count == 1)
        #expect(lanesB.count == 1)
    }

    @Test("an over-claiming driver leaves a passing row that still says the two disagree")
    func aConfirmedClaimAgainstAnUnchangedTreeIsWrittenDown() async throws {
        // The completeness gate's finding. The step stays ok, and it should: a
        // hover moves nothing and a focus onto an already-focused element moves
        // nothing, so failing every unchanged tree would be a false negative
        // across most of the step vocabulary. But a driver that over-claims would
        // otherwise write a clean row whose disagreement was reachable only by
        // crossing two fields, and the outcome people actually filter on would say
        // nothing at all.
        let backend = FakeActuationBackend()
        backend.defaultOutcome = Actuation(.routedEvent, .eventStream, backend: .cua,
                                           reportedMode: "cgevent", effect: .confirmed)
        let (session, ax, audit) = try await session(backend)
        _ = try await press(session, ax)

        let row = try #require(steps(audit).first)
        #expect(row.outcome == AuditRecord.Outcome.ok)
        #expect(row.eff == "confirmed")
        #expect(row.obs == "unchanged")
        #expect(row.reason?.contains("do not agree") == true)
    }

    @Test("a native step never acquires a disagreement it has no second observer for")
    func nativeStepsCarryNoDisagreementSentence() async throws {
        let (session, ax, audit) = try await session()
        _ = try await press(session, ax)
        let row = try #require(steps(audit).first)
        #expect(row.reason == nil)
    }

    // MARK: - A12. The claim is written where the next person will change it

    @Test("auditStep's header still says what the trail attests to")
    func theAttestationIsInTheCode() throws {
        // A documentation test is unusual, and it is here because the spec makes
        // the sentence a deliverable rather than a nicety. The claim this trail
        // makes is the load-bearing output of this item, and a comment nothing
        // checks is a comment the next refactor deletes without noticing that it
        // deleted the specification.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ProctorAgentTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/ProctorAgent/Session/SessionPolicy.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        // Fragments rather than whole sentences, because the source wraps them
        // across comment lines. Each is still specific enough that it cannot
        // survive the paragraph being rewritten into something weaker.
        for sentence in ["Every row is a claim Proctor makes",
                         "three facts, of three different",
                         "the row says it cannot say",
                         "The gate is not a sandbox",
                         "never about the machine"] {
            #expect(text.contains(sentence),
                    "the attestation paragraph no longer says: \(sentence)")
        }
    }
}
