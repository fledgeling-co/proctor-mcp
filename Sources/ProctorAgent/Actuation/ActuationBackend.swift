import Foundation
import ProctorCore

// PRO-0044, slice 2. The seam actuation is delegated through.
//
// There is exactly one actuation call site in this agent, in
// `SessionAct.runSteps`, and until now it called straight into the accessibility
// engine. That engine bundles observation with actuation, and wave 7 splits the
// two: Proctor keeps observation — its own capture path, its own frame-status
// reporting, its own tree — and hands actuation to a driver that does it across
// three platforms with a hundred contributors.
//
// So `perform` moves out and observation stays. `AXEngine.perform` is untouched
// and still does exactly what it did; `NativeActuationBackend` is a forwarder to
// it, and `Sources/ProctorAgent/AX/Actuator.swift` is not opened by this change
// at all. That is what makes this an extraction rather than a rewrite, and it is
// checkable rather than asserted.

/// One backend's answer for how a step will be performed and what it will cost
/// the person sitting at the machine.
protocol ActuationBackend: AnyObject, Sendable {

    var id: ActuationBackendID { get }

    /// Whether this backend can perform a kind of step without bringing the
    /// application to the front.
    ///
    /// **This is why the seam is a protocol rather than a function.** Proctor has
    /// always answered this from two static sets of step kinds — a click needs
    /// the foreground, a press does not — and that answer is correct about
    /// Proctor's own actuator, because a click is only expressible here as a
    /// CGEventPost into the shared WindowServer stream. It is not a fact about
    /// clicking. A backend that routes an event to one process answers
    /// differently, and a refusal built on the static sets would make its
    /// background clicks unreachable — which is most of the reason to delegate
    /// at all. The refusal, the foreground disclosure and the queue's lane
    /// demand all ask this instead of consulting a list.
    func backgroundCapability(for kind: ActionStep.Kind) -> BackgroundCapability

    /// Establish that this backend can be used at all: reachable, a supported
    /// version, a vocabulary this build understands, and healthy enough to
    /// actuate. Async because a delegated backend answers over a transport.
    ///
    /// Called before a lane is used rather than at the first step, so an
    /// unusable backend refuses with a reason instead of failing partway through
    /// a batch with a schema error.
    func preflight() async throws

    /// Perform one step. The target is resolved by the caller, from Proctor's own
    /// observation, so a backend is told what to hit and is never asked what is
    /// there.
    func perform(step: ActionStep, target: StepTarget,
                 foreground: Bool) async throws -> Actuation
}

/// What to hit, described so that any backend can act on it.
///
/// The identity is computed by the observation side before the call. A backend
/// holding its own element handles ignores it — the native one already holds a
/// retained `AXUIElement`, which resolves across Spaces and occlusion and is
/// strictly better than any re-resolution, and that advantage is kept rather
/// than levelled down to the weakest common denominator.
struct StepTarget: Sendable {
    var window: WindowHandle
    var app: AppHandle?
    /// The node id as the caller gave it, for error messages and the trail.
    var nodeId: String?
    /// How the element describes itself, for a backend that has to find it again
    /// in a tree of its own. Nil when the step names no element.
    var identity: ElementIdentity?
}

/// The native planes, unchanged, behind the new seam.
///
/// Everything this type does is forward. The capability answers are read from
/// `Session.syntheticKinds` and `Session.conditionalKinds` rather than restated
/// here, because those sets have always been a description of THIS actuator:
/// `.click`, `.key`, `.hover` and `.dragPath` can only be synthetic events here,
/// and `.type` and `.scroll` decide at the element. One definition, now asked for
/// through the seam instead of consulted directly, which changes no native
/// behaviour and makes the question askable of something else.
final class NativeActuationBackend: ActuationBackend {

    let id: ActuationBackendID = .native
    private let ax: any AXEngine

    init(ax: any AXEngine) {
        self.ax = ax
    }

    func backgroundCapability(for kind: ActionStep.Kind) -> BackgroundCapability {
        if Session.syntheticKinds.contains(kind) { return .never }
        if Session.conditionalKinds.contains(kind) { return .maybe }
        return .yes
    }

    func preflight() async throws {
        // Nothing to establish: this backend is the process it runs in. The
        // grants it needs are Proctor's own and are reported by proctor_doctor.
    }

    func perform(step: ActionStep, target: StepTarget,
                 foreground: Bool) async throws -> Actuation {
        try ax.perform(step: step, window: target.window.id, foreground: foreground)
    }
}
