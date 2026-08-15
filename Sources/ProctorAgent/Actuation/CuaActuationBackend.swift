import Foundation
import ProctorCore

// PRO-0044, slice 6. Actuation performed by cua-driver, reported honestly.
//
// The shape of every step is the same, and it is the architecture of wave 7 in
// one sequence: Proctor resolves what to hit from its OWN tree, asks the driver
// what it can see, requires the two to agree, and only then acts. The driver is
// told what to strike and asked what it did. It is never the authority on either.
//
// **Why the agreement check is before the strike and not after an error.** The
// driver's element handle goes stale when a newer snapshot supersedes it, and a
// stale handle raises an error a caller can retry. But a tree that mutates while
// the driver's view of it is still current raises nothing at all: the slot the
// handle points at simply has a new occupant, and the first attempt lands on it.
// Retrying correctly protects the second attempt and not the one that did the
// damage. So the guard is two independent observers agreeing about the target at
// the moment of acting — which is this repo's own tri-observer premise, applied
// to addressing.

final class CuaActuationBackend: ActuationBackend {

    let id: ActuationBackendID = .cua

    private let transport: any CuaTransport
    private let path: String?
    private let environment: [String: String]
    /// Preflight runs once per lane, not once per step. Guarded because a
    /// reentrant actor can reach this from two awaits.
    private let state = LaneState()

    init(transport: any CuaTransport, path: String?,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.transport = transport
        self.path = path
        self.environment = environment
    }

    /// What the driver can do without the foreground.
    ///
    /// Every kind it can perform is `.maybe`, and that is the whole point of the
    /// lane: the driver tries an accessibility action, then a routed event
    /// delivered to one process, and escalates to the front only when neither
    /// works. A click is therefore *possibly* background-safe here where on
    /// Proctor's own planes it never is — and `.maybe` rather than `.yes` because
    /// which rung it took is not knowable until the step has run, which is
    /// exactly what the reported path says afterwards.
    ///
    /// The two kinds the driver has no equivalent of answer `.never` so that a
    /// caller asking for the background is refused up front with the ordinary
    /// message, and `perform` refuses them outright rather than handing them to
    /// the native planes behind the caller's back.
    func backgroundCapability(for kind: ActionStep.Kind) -> BackgroundCapability {
        CuaVocabulary.action(for: kind) == nil ? .never : .maybe
    }

    func preflight() async throws {
        if let done = await state.report() { _ = done; return }
        // A refusal is remembered as well as a success. Without that, a lane that
        // failed at its signature check reports the same "nothing established
        // yet" as one nobody has used — and a health report that cannot tell a
        // dead lane from an untried one is the thing PRO-0050 exists to fix. The
        // stage comes from preflight's own ordered checks rather than from
        // parsing a message.
        let recorder = RefusalRecorder()
        do {
            let report = try await CuaPreflight.run(path: path, transport: transport,
                                                    environment: environment,
                                                    onRefusal: { stage, _ in
                                                        recorder.record(stage)
                                                    })
            await state.store(report)
        } catch {
            await state.storeRefusal(stage: recorder.stage)
            throw error
        }
    }

    /// Carries the stage out of preflight's synchronous refusal callback. A class
    /// rather than a captured `var` because the callback is not `inout`-friendly
    /// across the async boundary.
    private final class RefusalRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CuaPreflightStage?
        func record(_ stage: CuaPreflightStage) {
            lock.lock(); value = stage; lock.unlock()
        }
        var stage: CuaPreflightStage? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    var laneReport: CuaLaneReport? {
        get async { await state.report() }
    }

    /// What `proctor_doctor` reports about this lane, mapped out of whatever
    /// preflight left behind.
    ///
    /// **Every driver-supplied string is dropped here.** The version is what
    /// Proctor's own parser accepted, the stage is Proctor's own enum, the
    /// overrides are Proctor's own words for switches an operator set, and the
    /// permission map is filtered to names Proctor recognises. The driver's
    /// prose — its health message, its error text — reaches no part of a tool
    /// result, because `proctor_doctor` is the first call a model makes and a
    /// health report is not a place to pipe another process's writing into.
    var laneHealth: ToolLaneFacts? {
        get async {
            if let report = await state.report() {
                let grants = ToolLaneFacts.filterGrants(report.driverReportedGrants)
                return ToolLaneFacts(version: report.version?.description,
                                     healthy: true,
                                     overrides: report.overrides,
                                     driverReportedGrants: grants.kept,
                                     unrecognisedGrantKeys: grants.dropped)
            }
            if let stage = await state.refusalStage() {
                return ToolLaneFacts(healthy: false, failedStage: stage.rawValue)
            }
            return nil
        }
    }

    func perform(step: ActionStep, target: StepTarget,
                 foreground: Bool) async throws -> Actuation {
        try await preflight()

        guard let action = CuaVocabulary.action(for: step.kind) else {
            // Refused, never quietly run on the native planes. A run that changes
            // actuation path mid-flight is what the direction file rules out, and
            // refusing is what keeps "the backend never changes mid-run" true
            // rather than approximately true.
            throw AgentError(
                code: .actionUnsupported,
                message: "step kind \(step.kind.rawValue) has no equivalent in the Cua actuation "
                       + "lane, and Proctor will not quietly perform it on a different backend",
                remedy: "appleScript and shortcut are the Apple Events and declared planes, which "
                      + "this lane does not have. Run the batch on Proctor's own planes by "
                      + "unsetting PROCTOR_ACTUATION, or express the step another way.")
        }

        let started = DispatchTime.now().uptimeNanoseconds
        func elapsedMs() -> Int {
            Int((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000)
        }

        var token: String?
        var retried = false
        if let identity = target.identity {
            // Look once, and on any addressing failure look again — exactly once.
            //
            // The retry covers every way the boundary can go wrong rather than
            // only the driver's own stale-handle error, because all of them have
            // the same cause: a tree that changed between the two observations.
            // A handle goes stale when a newer snapshot supersedes it; an element
            // goes missing, or doubles, or stops agreeing, when the window
            // relayouts mid-look. Retrying only the first would leave the others
            // refusing a step that a second glance would have resolved — and
            // more importantly it makes every refusal below mean "twice", which
            // is what makes them worth acting on.
            do {
                token = try await resolve(identity, target: target)
            } catch let first as AgentError where isAddressing(first) {
                retried = true
                do {
                    token = try await resolve(identity, target: target)
                } catch let second as AgentError {
                    throw second
                }
            }
        }

        // The delivery mode is requested EXPLICITLY on every call, never left to
        // a default. A driver that treats an unrecognised mode as "background"
        // would otherwise let a version mismatch decide, silently, whether
        // somebody's machine gets taken.
        let requested = foreground ? "foreground" : "background"
        let reply = try await transport.send(CuaRequest(
            verb: .act, windowID: target.window.cgWindowID, pid: target.app?.pid,
            action: action, arguments: arguments(for: step),
            elementToken: token, deliveryMode: requested))

        guard reply.ok else {
            throw AgentError(
                code: reply.errorCode == CuaErrorCode.staleElementToken
                    ? .targetMoved : .actionFailed,
                message: reply.message ?? "cua-driver refused the \(step.kind.rawValue) step",
                detail: .object(["driverError": .string(reply.errorCode ?? "")]))
        }

        let plane = CuaVocabulary.plane(for: reply.path)
        // An escalation to the front that this batch did not ask for. The guards
        // that make a takeover visible arm before a post, from inside the process
        // making it — and this post was made by another process, so nothing could
        // have armed them. Saying so is the only honest thing left.
        let escalated = !foreground
            && reply.path.map(CuaVocabulary.foregroundPaths.contains) == true

        return Actuation(plane, route(for: plane), backend: .cua,
                         reportedMode: reply.path,
                         effect: CuaVocabulary.effect(for: reply.effect),
                         retriedOnStale: retried,
                         unrequestedForeground: escalated,
                         transportMs: elapsedMs())
    }

    // MARK: - Addressing

    /// Failures a second look could plausibly resolve, all of which mean the tree
    /// changed under the observation rather than that the request was wrong.
    ///
    /// An off-Space window is deliberately NOT here: it is a capability limit
    /// that will read the same way every time, and retrying it would spend a
    /// second round trip to be told the same thing.
    private func isAddressing(_ error: AgentError) -> Bool {
        switch error.code {
        case .targetMoved, .targetAmbiguous:
            return true
        case .targetUnresolved:
            // Absent because the window is elsewhere is permanent; absent because
            // the element had not been laid out yet is not.
            return !error.message.contains("another Space")
        default:
            return false
        }
    }

    /// Find the driver's handle for the element Proctor resolved, or refuse.
    private func resolve(_ identity: ElementIdentity,
                         target: StepTarget) async throws -> String {
        let snapshot = try await transport.send(CuaRequest(
            verb: .windowState, windowID: target.window.cgWindowID, pid: target.app?.pid))

        if snapshot.offSpace {
            // A documented limit rather than a corner case: on another Space the
            // driver's tree collapses to a menu bar, while Proctor's retained
            // references keep resolving. So this lane cannot drive windows the
            // native planes can — a capability regression, named as one, and
            // evidence for the item that decides whether the native planes stay.
            throw AgentError(
                code: .targetUnresolved,
                message: "cua-driver reports this window is on another Space, where its "
                       + "accessibility tree contains only the menu bar, so the element cannot "
                       + "be addressed through this lane",
                remedy: "Proctor's own actuation planes reach other-Space windows through "
                      + "retained element references. Bring the window to the current Space, or "
                      + "run this batch on Proctor's planes.",
                detail: .object(["node": .string(target.nodeId ?? "")]))
        }

        let candidates = snapshot.elements ?? []
        switch ElementMatch.match(identity: identity, candidates: candidates,
                                  truncated: snapshot.truncated) {
        case .matched(let index):
            guard let candidate = candidates.first(where: { $0.index == index }) else {
                throw AgentError(code: .internalError,
                                 message: "the matcher returned an index that is not in the list")
            }
            // Both observers, at the same moment, about the same element.
            guard ElementMatch.agrees(identity: identity, candidate: candidate) else {
                throw AgentError(
                    code: .targetMoved,
                    message: "Proctor and cua-driver disagree about the element at this target: "
                           + "Proctor reads \(describe(identity)) and the driver reads "
                           + "\(describe(candidate)). The element moved or was replaced between "
                           + "resolving it and acting on it.",
                    remedy: "Nothing was actuated. Re-read the window and re-run the step; "
                          + "acting on whatever occupies the position now is how a delegated run "
                          + "corrupts the thing it was meant to verify.",
                    detail: .object(["node": .string(target.nodeId ?? "")]))
            }
            return "\(index)"

        case .ambiguous(let why, let hits):
            throw AgentError(
                code: .targetAmbiguous,
                message: "the element could not be addressed unambiguously through cua-driver: "
                       + why,
                remedy: "Name a more specific element — a descendant, or one whose label differs "
                      + "from its siblings'. Proctor will not pick between candidates by "
                      + "position, because a match resting on a coordinate replays by striking "
                      + "an absolute point and breaks when the layout moves.",
                detail: .object(["node": .string(target.nodeId ?? ""),
                                 "candidates": .array(hits.map { .number(Double($0)) })]))

        case .absent:
            throw AgentError(
                code: .targetUnresolved,
                message: "cua-driver cannot see the element Proctor resolved "
                       + "(\(describe(identity)))",
                remedy: "The driver's own documentation records that its accessibility tree is "
                      + "incomplete on some surfaces. Nothing was actuated, and no coordinate "
                      + "was substituted for the element.",
                detail: .object(["node": .string(target.nodeId ?? "")]))
        }
    }

    private func arguments(for step: ActionStep) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        if let text = step.text { out["text"] = .string(text) }
        if let value = step.value { out["value"] = value }
        if let key = step.key { out["key"] = .string(key) }
        if let modifiers = step.modifiers {
            out["modifiers"] = .array(modifiers.map { .string($0) })
        }
        if let menuPath = step.menuPath {
            out["menuPath"] = .array(menuPath.map { .string($0) })
        }
        if let delta = step.delta { out["delta"] = .array(delta.map { .number($0) }) }
        if let point = step.point { out["point"] = .array(point.map { .number($0) }) }
        if let path = step.path {
            out["path"] = .array(path.map { .array($0.map { .number($0) }) })
        }
        if let durationMs = step.durationMs { out["durationMs"] = .number(Double(durationMs)) }
        return out
    }

    /// The route beside the plane. Coarser than the native backend's, because the
    /// driver reports the side it travelled and not which of several
    /// accessibility routes it took — and inventing a finer answer than the
    /// evidence supports is what this whole feature refuses to do.
    private func route(for plane: ActuationPlane) -> ActuationRoute? {
        switch plane {
        case .accessibility: return .action
        case .routedEvent, .syntheticEvent: return .eventStream
        default: return nil
        }
    }

    private func describe(_ identity: ElementIdentity) -> String {
        "\(identity.role ?? "?") \"\(identity.label ?? "")\""
    }

    private func describe(_ candidate: ElementCandidate) -> String {
        "\(candidate.role) \"\(candidate.label ?? "")\""
    }

    /// Preflight's result, held once per lane. A refusal is held too, so a lane
    /// that was tried and refused reads differently from one nobody has used.
    private actor LaneState {
        private var stored: CuaLaneReport?
        private var refusal: CuaPreflightStage?
        func report() -> CuaLaneReport? { stored }
        func store(_ report: CuaLaneReport) { stored = report; refusal = nil }
        func refusalStage() -> CuaPreflightStage? { refusal }
        func storeRefusal(stage: CuaPreflightStage?) { refusal = stage ?? .presence }
    }
}
