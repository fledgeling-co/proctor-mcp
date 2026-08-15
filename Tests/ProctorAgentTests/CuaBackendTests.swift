import Testing
import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0044, slices 5 and 6. The delegated actuation lane, end to end, without
// the binary it delegates to.
//
// Almost every test here is a refusal. That is the point: the failure a delegated
// driver produces is not a crash, it is a confident success on the wrong element
// or on nothing at all, and a lane that only knows how to succeed would ship
// exactly that.

private func candidate(_ index: Int, _ role: String, _ label: String?,
                       parent: Int?, frame: Rect? = nil) -> ElementCandidate {
    ElementCandidate(index: index, role: role, label: label, frame: frame,
                     parentIndex: parent, depth: parent == nil ? 0 : 1)
}

private let saveFrame = Rect(x: 10, y: 10, w: 60, h: 24)

/// A window holding one Save button, as both observers see it.
private func agreeingWindow() -> [ElementCandidate] {
    [candidate(0, "AXWindow", "Fake Window", parent: nil),
     candidate(1, "AXButton", "Save", parent: 0, frame: saveFrame)]
}

private func saveIdentity() -> ElementIdentity {
    ElementIdentity(chain: [ElementStep(role: "AXWindow", label: "Fake Window"),
                            ElementStep(role: "AXButton", label: "Save")],
                    frame: saveFrame)
}

private func target(_ identity: ElementIdentity? = saveIdentity()) -> StepTarget {
    StepTarget(window: WindowHandle(id: "win-1", app: "app-1", title: "Fake Window",
                                    frame: Rect(x: 0, y: 0, w: 800, h: 600), isMain: true,
                                    isMinimized: false, isOnActiveSpace: true, cgWindowID: 7),
               app: AppHandle(id: "app-1", pid: 4242, bundleId: "com.example", name: "Fake"),
               nodeId: "node-1", identity: identity)
}

private func backend(_ transport: FakeCuaTransport,
                     env: [String: String] = [:]) -> CuaActuationBackend {
    // The signature check is bypassed only where it is not what is under test —
    // it has its own tests below, against the verdict type.
    CuaActuationBackend(transport: transport, path: "/opt/homebrew/bin/cua-driver",
                        environment: env.merging([CuaPreflight.allowUnsignedEnv: "1"]) { a, _ in a })
}

@Suite("Cua actuation lane")
struct CuaBackendTests {

    // MARK: - The happy path, and the one it makes possible

    @Test("an accessibility action reports the accessibility plane")
    func accessibilityPath() async throws {
        let fake = FakeCuaTransport()
        fake.elements = agreeingWindow()
        fake.path = "ax"
        let outcome = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                      target: target(), foreground: false)
        #expect(outcome.plane == .accessibility)
        #expect(outcome.backend == .cua)
        #expect(outcome.reportedMode == "ax")
        #expect(outcome.transportMs != nil)
    }

    @Test("a background click reaches the routed-event plane")
    func backgroundClickIsReachable() async throws {
        // The whole reason for the lane. Proctor's own planes can only express a
        // click as a post into the shared stream, so a background click is
        // refused before it is attempted; a driver that routes an event to one
        // process can do it, and the result says so without claiming either that
        // it was an accessibility action or that the machine was taken.
        let fake = FakeCuaTransport()
        fake.elements = agreeingWindow()
        fake.path = "cgevent"
        let cua = backend(fake)
        #expect(cua.backgroundCapability(for: .click) == .maybe)
        let outcome = try await cua.perform(step: ActionStep(kind: .click),
                                            target: target(), foreground: false)
        #expect(outcome.plane == .routedEvent)
        #expect(!outcome.unrequestedForeground)
    }

    @Test("the delivery mode is requested explicitly on every call")
    func deliveryModeIsAlwaysStated() async throws {
        // A driver that treats an unrecognised mode as "background" would let a
        // version mismatch decide, silently, whether somebody's machine is taken.
        let fake = FakeCuaTransport()
        fake.elements = agreeingWindow()
        _ = try await backend(fake).perform(step: ActionStep(kind: .press),
                                            target: target(), foreground: false)
        let act = try #require(fake.sent.last)
        #expect(act.deliveryMode == "background")
    }

    // MARK: - Plane mapping

    @Test("a foreground path is the shared stream, whatever else it is called")
    func foregroundPathMaps() async throws {
        let fake = FakeCuaTransport()
        fake.elements = agreeingWindow()
        fake.path = "cgevent_fg"
        let outcome = try await backend(fake).perform(step: ActionStep(kind: .click),
                                                      target: target(), foreground: true)
        #expect(outcome.plane == .syntheticEvent)
    }

    @Test("an escalation the batch did not ask for is flagged")
    func unrequestedEscalationIsFlagged() async throws {
        // The guards that make a takeover visible arm before a post, from inside
        // the process making it. This post came from another process, so nothing
        // armed them and the only honest thing left is to say so.
        let fake = FakeCuaTransport()
        fake.elements = agreeingWindow()
        fake.path = "cgevent_fg"
        let outcome = try await backend(fake).perform(step: ActionStep(kind: .click),
                                                      target: target(), foreground: false)
        #expect(outcome.plane == .syntheticEvent)
        #expect(outcome.unrequestedForeground)
    }

    @Test("an unrecognised path is unknown, never a guess")
    func unknownPathIsNotGuessed() async throws {
        let fake = FakeCuaTransport()
        fake.elements = agreeingWindow()
        fake.path = "quantum_tunnel"
        let outcome = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                      target: target(), foreground: false)
        #expect(outcome.plane == .unknown)
        // The driver's own word survives, so a reader can audit the mapping
        // rather than trust it.
        #expect(outcome.reportedMode == "quantum_tunnel")
    }

    @Test("a pixel path is background-safe and still the least durable evidence")
    func pixelPathMaps() async throws {
        let fake = FakeCuaTransport()
        fake.elements = agreeingWindow()
        fake.path = "pixel"
        let outcome = try await backend(fake).perform(step: ActionStep(kind: .click),
                                                      target: target(), foreground: false)
        #expect(outcome.plane == .routedEvent)
        #expect(outcome.reportedMode == "pixel")
    }

    // MARK: - Addressing refusals

    @Test("an element the driver cannot see refuses, with no coordinate substituted")
    func absentElementRefuses() async throws {
        let fake = FakeCuaTransport()
        fake.elements = [candidate(0, "AXWindow", "Fake Window", parent: nil)]
        await #expect(throws: AgentError.self) {
            _ = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                target: target(), foreground: false)
        }
        // Nothing was actuated: the act call was never made.
        #expect(!fake.sent.contains { $0.verb == .act })
    }

    @Test("a truncated view refuses as ambiguous rather than as absent")
    func truncationIsAmbiguous() async throws {
        // "I could not finish looking" and "it is not there" send a caller in
        // opposite directions, and only one of them is true here.
        let fake = FakeCuaTransport()
        fake.elements = [candidate(0, "AXWindow", "Fake Window", parent: nil)]
        fake.truncated = true
        let error = await #expect(throws: AgentError.self) {
            _ = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                target: target(), foreground: false)
        }
        #expect(error?.code == .targetAmbiguous)
    }

    @Test("two identical candidates refuse rather than picking one")
    func ambiguityRefuses() async throws {
        let fake = FakeCuaTransport()
        fake.elements = [candidate(0, "AXWindow", "Fake Window", parent: nil),
                         candidate(1, "AXButton", "Save", parent: 0, frame: saveFrame),
                         candidate(2, "AXButton", "Save", parent: 0, frame: saveFrame)]
        let error = await #expect(throws: AgentError.self) {
            _ = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                target: target(), foreground: false)
        }
        #expect(error?.code == .targetAmbiguous)
    }

    @Test("a window on another Space refuses by name, because this lane cannot reach it")
    func offSpaceRefusesByName() async throws {
        // A capability regression against Proctor's own planes, which reach
        // other-Space windows through retained references. Named rather than
        // discovered in production, because it is evidence for the item that
        // decides whether those planes stay.
        let fake = FakeCuaTransport()
        fake.offSpace = true
        let error = await #expect(throws: AgentError.self) {
            _ = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                target: target(), foreground: false)
        }
        #expect(error?.code == .targetUnresolved)
        #expect(error?.message.contains("another Space") == true)
    }

    @Test("an element that moved between the look and the strike refuses")
    func mutationUnderACurrentSnapshotRefuses() async throws {
        // The case a stale-handle retry cannot catch. No handle went stale — the
        // driver's view is still current — so nothing raises an error, and only
        // an agreement check before the strike sees that the thing under the
        // target is somewhere else than Proctor resolved it to be.
        let fake = FakeCuaTransport()
        fake.elements = [candidate(0, "AXWindow", "Fake Window", parent: nil),
                         candidate(1, "AXButton", "Save", parent: 0,
                                   frame: Rect(x: 600, y: 400, w: 60, h: 24))]
        let error = await #expect(throws: AgentError.self) {
            _ = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                target: target(), foreground: false)
        }
        #expect(error?.code == .targetMoved)
        // Nothing was actuated.
        #expect(!fake.sent.contains { $0.verb == .act })
    }

    @Test("an element replaced by a different one is not there, rather than moved")
    func replacedElementIsUnresolved() async throws {
        // A different label at the same position does not fail the agreement
        // check — it never reaches it, because the identity chain no longer
        // matches anything. "The element I was told to press is not in this
        // window" is the true answer, and it is the safe one.
        let fake = FakeCuaTransport()
        fake.elements = [candidate(0, "AXWindow", "Fake Window", parent: nil),
                         candidate(1, "AXButton", "Discard", parent: 0, frame: saveFrame)]
        let error = await #expect(throws: AgentError.self) {
            _ = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                target: target(), foreground: false)
        }
        #expect(error?.code == .targetUnresolved)
    }

    @Test("a step that resolves on the second look records that it retried")
    func staleRetryIsRecorded() async throws {
        // A step whose target was moving is a determinism signal, not an
        // implementation detail, so it reaches the result rather than being
        // swallowed by a successful retry.
        let fake = FakeCuaTransport()
        fake.elements = [candidate(0, "AXWindow", "Fake Window", parent: nil),
                         candidate(1, "AXButton", "Discard", parent: 0, frame: saveFrame)]
        fake.mutateAfterSnapshots = 1
        fake.elementsAfter = agreeingWindow()
        let outcome = try await backend(fake).perform(step: ActionStep(kind: .press),
                                                      target: target(), foreground: false)
        #expect(outcome.retriedOnStale)
    }

    @Test("a step naming no element needs no snapshot at all")
    func noIdentityNoSnapshot() async throws {
        let fake = FakeCuaTransport()
        _ = try await backend(fake).perform(step: ActionStep(kind: .menu),
                                            target: target(nil), foreground: false)
        #expect(!fake.sent.contains { $0.verb == .windowState })
    }

    // MARK: - Kinds this lane does not have

    @Test("a step with no equivalent is refused, never handed to the native planes")
    func nativeOnlyKindsRefuse() async throws {
        // Refusing is what keeps "the backend never changes mid-run" true rather
        // than approximately true.
        let fake = FakeCuaTransport()
        let cua = backend(fake)
        #expect(cua.backgroundCapability(for: .appleScript) == .never)
        let error = await #expect(throws: AgentError.self) {
            _ = try await cua.perform(step: ActionStep(kind: .appleScript),
                                      target: target(nil), foreground: true)
        }
        #expect(error?.code == .actionUnsupported)
        #expect(!fake.sent.contains { $0.verb == .act })
    }

    // MARK: - Preflight

    @Test("an unsupported version refuses before any step")
    func versionRefusesFirst() async throws {
        let fake = FakeCuaTransport()
        fake.version = "0.14.0"
        let error = await #expect(throws: AgentError.self) {
            try await backend(fake).preflight()
        }
        #expect(error?.code == .backendUnsupported)
        #expect(error?.message.contains("0.14.0") == true)
        // Refused at the gate, not three steps into a batch.
        #expect(!fake.sent.contains { $0.verb == .act })
    }

    @Test("an unsupported version can be forced, and forcing is stamped")
    func versionOverrideStamps() async throws {
        let fake = FakeCuaTransport()
        fake.version = "0.14.0"
        let cua = backend(fake, env: [CuaPreflight.allowUnsupportedEnv: "1"])
        try await cua.preflight()
        let report = try #require(await cua.laneReport)
        #expect(report.overrides.contains("unsupportedVersionForced"))
    }

    @Test("a vocabulary this build cannot map refuses at the gate")
    func unmappableVocabularyRefuses() async throws {
        // The version number is the driver's claim about itself; this is
        // evidence. Everything Proctor believes about the driver's wire was read
        // from documentation, so a build that reports something else refuses here
        // rather than producing planes nobody can interpret.
        let fake = FakeCuaTransport()
        fake.vocabulary = ["ax", "warp_drive"]
        let error = await #expect(throws: AgentError.self) {
            try await backend(fake).preflight()
        }
        #expect(error?.code == .backendUnsupported)
        #expect(error?.message.contains("warp_drive") == true)
    }

    @Test("a driver that says it is unhealthy refuses, and its own word is the reason")
    func unhealthyDriverRefuses() async throws {
        let fake = FakeCuaTransport()
        fake.healthy = false
        fake.healthMessage = "Accessibility is not granted to CuaDriver"
        let error = await #expect(throws: AgentError.self) {
            try await backend(fake).preflight()
        }
        #expect(error?.code == .backendUnavailable)
        #expect(error?.message.contains("Accessibility is not granted") == true)
    }

    @Test("a missing binary refuses without pretending it could be installed")
    func missingBinaryRefuses() async throws {
        let cua = CuaActuationBackend(transport: FakeCuaTransport(), path: nil,
                                      environment: [:])
        let error = await #expect(throws: AgentError.self) { try await cua.preflight() }
        #expect(error?.code == .backendUnavailable)
        // Proctor never installs anything, and never puts a command in a tool
        // result for a model with a shell to run.
        #expect(error?.remedy?.contains("curl") != true)
    }

    @Test("a driver that dies mid-step is a refusal, not a change of plane")
    func deadDriverRefuses() async throws {
        let fake = FakeCuaTransport()
        fake.elements = agreeingWindow()
        let cua = backend(fake)
        try await cua.preflight()
        fake.failNextSend = AgentError(code: .backendUnavailable,
                                       message: "the driver went away")
        await #expect(throws: AgentError.self) {
            _ = try await cua.perform(step: ActionStep(kind: .press),
                                      target: target(), foreground: false)
        }
    }

    // MARK: - Signature verdicts

    @Test("each signature failure says which one it was")
    func signatureVerdictsReadDifferently() {
        // An ad-hoc build is usually the reader's own `swift build`; a
        // wrong-identity build is a file they should look at. Collapsing the two
        // into "not signed" sends them after the wrong thing.
        let expected = CuaPreflight.expectedIdentifier
        #expect(CuaPreflight.SignatureVerdict.adhoc.describe(expecting: expected)
                    .contains("ad-hoc"))
        #expect(CuaPreflight.SignatureVerdict.unsigned.describe(expecting: expected)
                    .contains("no code signature"))
        #expect(CuaPreflight.SignatureVerdict.wrongIdentity("com.someone.else")
                    .describe(expecting: expected).contains("com.someone.else"))
    }

    @Test("a binary that is not signed by the expected identity is refused, not run")
    func unsignedBinaryRefuses() async throws {
        let fake = FakeCuaTransport()
        let error = await #expect(throws: AgentError.self) {
            _ = try await CuaPreflight.run(path: "/tmp/planted-cua-driver", transport: fake,
                                           environment: [:],
                                           verifySignature: { _ in .unsigned })
        }
        #expect(error?.code == .backendUnsupported)
        // The refusal is BEFORE the first execution, so nothing was asked of it.
        #expect(fake.sent.isEmpty)
    }
}
