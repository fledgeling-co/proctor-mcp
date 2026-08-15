import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0044. A stand-in for cua-driver, because there is no cua-driver here.
//
// The driver is not installed on the machine this was built on, and installing it
// as a side effect of anything is forbidden (PRO-0023), so every claim this lane
// makes about the driver's wire is exercised against this fake rather than
// against the binary. That is a real limit and the spec records it: a wrong
// reading of the driver's vocabulary would still pass these tests. What the fake
// does prove is everything on Proctor's side of the boundary — the addressing
// chain, the refusals, the plane mapping, the escalation flag, the no-op cross —
// which is where all the decisions worth getting wrong actually live.
final class FakeCuaTransport: CuaTransport, @unchecked Sendable {

    /// Every request, in order, so a test can assert what was asked as well as
    /// what came back — including the delivery mode, which must be explicit on
    /// every call.
    private let lock = NSLock()
    private var _sent: [CuaRequest] = []
    var sent: [CuaRequest] { lock.withLock { _sent } }

    var version = "0.13.2"
    var vocabulary: [String]? = ["ax", "cgevent", "cgevent_fg", "key_events",
                                 "key_events_fg", "pixel"]
    var healthy = true
    var healthMessage: String?

    /// What the driver says is in the window.
    var elements: [ElementCandidate] = []
    var truncated = false
    var offSpace = false

    /// The delivery path the act call reports. Nil answers with no path at all,
    /// which is how an unmappable response reaches the plane logic.
    var path: String? = "ax"
    var effect: String? = "confirmed"
    var actOK = true
    var actErrorCode: String?
    var actMessage: String?

    /// Snapshots after this many windowState calls answer with `elementsAfter`
    /// instead, so a test can move the tree between the look and the strike.
    var mutateAfterSnapshots: Int?
    var elementsAfter: [ElementCandidate] = []

    /// Throw on the next send, standing in for a driver that died mid-step.
    var failNextSend: AgentError?

    private var snapshots = 0

    func send(_ request: CuaRequest) async throws -> CuaResponse {
        lock.withLock { _sent.append(request) }

        if let failure = failNextSend {
            failNextSend = nil
            throw failure
        }

        switch request.verb {
        case .version:
            return CuaResponse(version: version)
        case .capabilities:
            return CuaResponse(vocabulary: vocabulary)
        case .health:
            return CuaResponse(ok: healthy, message: healthMessage)
        case .windowState:
            let moved = lock.withLock { () -> Bool in
                snapshots += 1
                return mutateAfterSnapshots.map { snapshots > $0 } ?? false
            }
            return CuaResponse(elements: moved ? elementsAfter : elements,
                               truncated: truncated, offSpace: offSpace)
        case .act:
            return CuaResponse(ok: actOK, errorCode: actErrorCode, message: actMessage,
                               path: path, effect: effect)
        }
    }
}
