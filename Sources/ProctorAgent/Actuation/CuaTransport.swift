import Foundation
import ProctorCore

// PRO-0044, slice 4. Talking to the driver, and reading what it says back.
//
// **The transport question is smaller than it looks, and this file says so.**
// The brief frames it as a daemon versus a one-shot CLI call per step, and warns
// that a doubled step budget is a determinism problem. Two corrections, both from
// review, both recorded in the spec:
//
// The determinism half is false. `StabilityScore.fold` folds per-step ACCESSIBILITY
// STATE HASHES and nothing else; no timing enters the score at any point. A slower
// step costs wall-clock across a sweep and does not move the number. The honest
// claim is a cost claim and is made as one.
//
// And the choice may not exist as posed. The driver's macOS permission identity
// belongs to its own app bundle, and the app-hosted daemon exists to own it, so a
// "one-shot call" plausibly spawns a CLI that talks to the daemon that was going
// to exist anyway. If that is right, the variable is client overhead per step and
// a per-step spawn buys nothing. It is unverified — the driver is not installed
// here — which is why both clients exist behind one protocol and why every step
// records its own round trip. The threshold that would move the default is in the
// spec, and it is answerable by running a sweep on a machine that has the binary.
//
// Neither transport is ever an automatic fallback for the other. A run that
// silently changes how it reaches the machine is unscoreable, and the direction
// file is explicit: a fallback is a decision, not a safety net.

/// One call to the driver.
struct CuaRequest: Sendable {
    enum Verb: String, Sendable {
        case version
        case capabilities
        case health
        case windowState
        case act
    }

    var verb: Verb
    var windowID: UInt32?
    var pid: Int32?
    /// The step, in the driver's own vocabulary. Built by `CuaClient`.
    var action: String?
    var arguments: [String: JSONValue] = [:]
    /// The handle the driver gave out for the element this acts on, from the
    /// snapshot taken moments earlier in this same step.
    var elementToken: String?
    /// Always sent explicitly. A driver that treats an unrecognised value as
    /// "background" would otherwise let a version mismatch decide, silently,
    /// whether somebody's machine gets taken.
    var deliveryMode: String?
}

/// What came back.
struct CuaResponse: Sendable {
    var ok: Bool = true
    /// The driver's own error identifier, e.g. a stale-handle code.
    var errorCode: String?
    var message: String?
    /// How the driver says it delivered the action. The outcome, not the request.
    var path: String?
    /// What the driver claims about the action landing.
    var effect: String?
    /// The window's elements, for a windowState call.
    var elements: [ElementCandidate]?
    /// The driver capped its walk, so this list is not the whole window.
    var truncated: Bool = false
    /// The window is on another Space, where the driver's tree collapses to a
    /// menu bar. Reported separately from an empty list because it is a
    /// capability limit rather than a window with nothing in it.
    var offSpace: Bool = false
    var version: String?
    /// The delivery paths this build of the driver can report.
    var vocabulary: [String]?
}

/// How a request reaches the driver.
protocol CuaTransport: Sendable {
    func send(_ request: CuaRequest) async throws -> CuaResponse

    /// Whether what was verified stays verified for the lane's life.
    ///
    /// True for a transport holding one child: a process cannot change its own
    /// code after `exec`, so the check made at spawn describes every step. False
    /// for one that re-execs per call, where each call is a different process and
    /// no lane-wide claim about identity is true.
    ///
    /// It is a property of the transport rather than a setting because the honest
    /// content of the lane record depends on it, and a record that claimed a
    /// pinned identity on an unpinned transport would be the false attestation
    /// this whole item exists to avoid.
    var identityPinned: Bool { get }

    /// What was established about the running process, when anything was.
    var processIdentity: CuaProcessIdentity? { get }

    /// A name for the transport, for the lane record.
    var kind: String { get }

    /// Tell the transport which lane it serves, so the events it raises carry the
    /// same name as the steps that travelled it. Called once, by the backend that
    /// owns both.
    func adopt(laneId: String)
}

extension CuaTransport {
    var identityPinned: Bool { false }
    var processIdentity: CuaProcessIdentity? { nil }
    var kind: String { "unknown" }
    func adopt(laneId: String) {}
}

/// The driver's error identifiers this build reacts to by name.
enum CuaErrorCode {
    static let staleElementToken = "stale_element_token"
}

/// Turning Proctor's vocabulary into the driver's, and the driver's back into
/// Proctor's.
///
/// **The mapping is a table, not control flow.** Everything here about the
/// driver's wire is read from documentation and a cross-family review rather than
/// from the shipped binary, and the whole point of holding it as data is that
/// being wrong produces a refusal at lane start — where the capability probe
/// compares this table to what the installed build actually reports — instead of
/// a wrong plane on a step result that somebody trusts.
enum CuaVocabulary {

    /// Delivery path → the plane Proctor reports.
    ///
    /// The middle two rows are the reason `routedEvent` had to exist. An event
    /// routed to one process is not the accessibility plane and is not the shared
    /// WindowServer stream, and Proctor's four original values could describe
    /// neither of those things without lying about the mechanism or about whether
    /// the machine was taken.
    static let planes: [String: ActuationPlane] = [
        "ax": .accessibility,
        "cgevent": .routedEvent,
        "key_events": .routedEvent,
        "cgevent_fg": .syntheticEvent,
        "key_events_fg": .syntheticEvent,
        // A coordinate strike. Background-safe, and the least durable evidence a
        // step can produce: it survives a replay by hitting an absolute position,
        // which is exactly what a layout change breaks. Flagged rather than
        // hidden.
        "pixel": .routedEvent,
    ]

    /// Paths that mean the application was brought to the front.
    static let foregroundPaths: Set<String> = ["cgevent_fg", "key_events_fg"]

    static let effects: [String: ActuationEffect] = [
        "confirmed": .confirmed,
        "unverifiable": .unverifiable,
        "suspected_noop": .suspectedNoOp,
    ]

    /// The plane for a reported path, or `.unknown` when this build has never
    /// heard of it. Never a guess: an unrecognised path could be background-safe
    /// or could be the machine being taken, and there is no safe direction to
    /// assume.
    static func plane(for path: String?) -> ActuationPlane {
        guard let path, let known = planes[path] else { return .unknown }
        return known
    }

    static func effect(for reported: String?) -> ActuationEffect? {
        guard let reported else { return nil }
        return effects[reported]
    }

    /// The driver's verb for a step kind, or nil when this lane cannot express it.
    ///
    /// `appleScript` and `shortcut` are deliberately absent. They are the Apple
    /// Events and declared planes, which the driver has no equivalent of, and a
    /// step naming one is REFUSED rather than quietly run on the native backend —
    /// a run that changes actuation path mid-flight is the thing the direction
    /// file rules out, and refusing keeps "the backend never changes mid-run"
    /// true rather than approximately true.
    static func action(for kind: ActionStep.Kind) -> String? {
        switch kind {
        case .press, .confirm, .cancel, .pick:      return "press"
        case .setValue, .type:                      return "set_value"
        case .focus:                                return "focus"
        case .menu:                                 return "invoke_menu"
        case .scroll:                               return "scroll"
        case .increment:                            return "increment"
        case .decrement:                            return "decrement"
        case .raise:                                return "raise_window"
        case .close:                                return "close_window"
        case .move:                                 return "move_window"
        case .resize:                               return "resize_window"
        case .click:                                return "click"
        case .hover:                                return "hover"
        case .key:                                  return "key"
        case .dragPath:                             return "drag"
        case .appleScript, .shortcut:               return nil
        case .waitFor:                              return nil
        }
    }
}
