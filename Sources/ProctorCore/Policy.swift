import Foundation
import CryptoKit

// The two paired safety rails, decision-and-serialisation half. Everything here
// is pure: no clock it does not take, no disk, no actor. The agent supplies the
// state (the current policy, the live token, the wall clock) and the file I/O;
// this file decides and redacts, so both can be tested in isolation the way
// CUATranslator, SetOfMarks and Canonical are.
//
// Two rules run through it. The gate fails closed: an app that cannot be
// identified, or one an allow list does not name, is refused rather than driven.
// The audit redacts: a value that passed through `type` or a script body is
// stored as length-plus-hash, never in the clear, so the log proves what was
// entered without becoming the biggest secret leak in the system.

// MARK: - Redaction

/// A value reduced to its length and SHA-256. This proves "a value was entered
/// here, and it was *this* value" — verifiable against a known input — without
/// storing the secret. Logging the value verbatim would turn the audit trail
/// into a plaintext store of every password the agent ever typed.
public struct Redaction: Codable, Sendable, Equatable {
    public let len: Int
    public let sha256: String

    public init(of text: String) {
        let bytes = Data(text.utf8)
        self.len = bytes.count
        self.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// For decoding a stored record back.
    public init(len: Int, sha256: String) { self.len = len; self.sha256 = sha256 }
}

// MARK: - Policy

/// App allow/block lists and the sensitive set, all keyed by bundle identifier.
/// A bundle id is the durable identity of an application; a display name is not.
public struct AppPolicy: Codable, Sendable, Equatable {
    /// When non-empty, only these bundle ids may be driven — allow-list mode,
    /// which is fail-closed by construction: anything not named is refused.
    public var allow: Set<String>
    /// Always refused, and this wins over everything else.
    public var block: Set<String>
    /// May be driven only while a valid approval token is held.
    public var sensitive: Set<String>

    public init(allow: Set<String> = [], block: Set<String> = [], sensitive: Set<String> = []) {
        self.allow = allow; self.block = block; self.sensitive = sensitive
    }

    public var isEmpty: Bool { allow.isEmpty && block.isEmpty && sensitive.isEmpty }
}

/// The gate's verdict for driving one application. `blocked` and `needsApproval`
/// each carry a reason a model can act on rather than retry blindly.
public enum PolicyDecision: Sendable, Equatable {
    case allow
    case blocked(reason: String)
    case needsApproval(reason: String)
}

public extension AppPolicy {
    /// Decide whether an application may be driven right now.
    ///
    /// Order is the safety property. Block is checked first and is absolute. Then
    /// allow-list mode: if an allow list is in force, anything it does not name —
    /// including an application whose bundle id could not be resolved — is
    /// refused, so the gate fails closed rather than driving an unknown app.
    /// Then the sensitive set, which is permitted only against a valid token.
    /// Anything that survives all three is allowed.
    func decide(bundleId: String?, hasValidToken: Bool) -> PolicyDecision {
        if let bundleId, block.contains(bundleId) {
            return .blocked(reason: "\(bundleId) is on the block list; actuation is refused.")
        }
        if !allow.isEmpty {
            guard let bundleId, allow.contains(bundleId) else {
                let named = bundleId ?? "an application with no bundle identifier"
                return .blocked(reason:
                    "An allow list is in force and \(named) is not on it; actuation is refused.")
            }
        }
        if let bundleId, sensitive.contains(bundleId), !hasValidToken {
            return .needsApproval(reason:
                "\(bundleId) is a sensitive application and requires a current approval token. "
                + "Mint one with proctor_policy action \"approve\" before driving it.")
        }
        return .allow
    }
}

// MARK: - Approval token

/// A short-lived grant to drive a sensitive application, bounded by a TTL exactly
/// as the unlock turn is: a crashed caller cannot leave a standing authority to
/// drive a password manager. Scoped to a bundle id (nil authorizes any sensitive
/// app) so approving one app does not silently approve the next.
public struct ApprovalToken: Codable, Sendable, Equatable {
    public let token: String
    public let bundleId: String?
    public let issuedAt: Double        // seconds since epoch
    public let expiresAt: Double

    public init(token: String, bundleId: String?, issuedAt: Double, expiresAt: Double) {
        self.token = token; self.bundleId = bundleId
        self.issuedAt = issuedAt; self.expiresAt = expiresAt
    }

    /// Mint a token valid for `ttl` seconds from `now`, with a random secret.
    public static func mint(bundleId: String?, ttl: TimeInterval, now: Double,
                            token: String = ApprovalToken.randomToken()) -> ApprovalToken {
        ApprovalToken(token: token, bundleId: bundleId, issuedAt: now, expiresAt: now + ttl)
    }

    /// Valid when it has not expired and its scope covers the requested app: a
    /// token scoped to nil covers any sensitive app; a scoped token covers only
    /// its own bundle id.
    public func isValid(at now: Double, for bundleId: String?) -> Bool {
        guard now < expiresAt else { return false }
        guard let scope = self.bundleId else { return true }
        return scope == bundleId
    }

    public static func randomToken() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

// MARK: - Audit record

/// One append-only line of the redacting audit trail. It records what was done —
/// the tool, the target application/window/element, the outcome and the resulting
/// state hash — while any free text that passed through it (a typed value, a
/// script body) is present only as a `Redaction`.
public struct AuditRecord: Codable, Sendable, Equatable {
    public var timestamp: Double
    public var tool: String
    public var app: String?
    public var bundleId: String?
    public var window: String?
    public var node: String?
    public var kind: String?           // the step kind, when this records a step
    public var outcome: String         // ok | failed | refused
    public var postStateHash: String?
    public var value: Redaction?       // a redacted typed value or setValue string
    public var script: Redaction?      // a redacted script body
    public var reason: String?         // why, for a refusal or a failure

    public init(timestamp: Double, tool: String, app: String? = nil, bundleId: String? = nil,
                window: String? = nil, node: String? = nil, kind: String? = nil,
                outcome: String, postStateHash: String? = nil,
                value: Redaction? = nil, script: Redaction? = nil, reason: String? = nil) {
        self.timestamp = timestamp; self.tool = tool; self.app = app; self.bundleId = bundleId
        self.window = window; self.node = node; self.kind = kind; self.outcome = outcome
        self.postStateHash = postStateHash; self.value = value; self.script = script
        self.reason = reason
    }

    /// Build a record for one executed step, redacting anything that could carry a
    /// secret. `type` text, an `appleScript` body and a string `setValue` all pass
    /// user data, so each is reduced to length-plus-hash before it is stored.
    public static func forStep(_ step: ActionStep, tool: String, timestamp: Double,
                               app: String?, bundleId: String?, window: String?,
                               outcome: String, postStateHash: String?,
                               reason: String? = nil) -> AuditRecord {
        var value: Redaction?
        var script: Redaction?
        switch step.kind {
        case .type:
            if let text = step.text { value = Redaction(of: text) }
        case .appleScript:
            if let body = step.text { script = Redaction(of: body) }
        case .setValue:
            if let s = step.value?.stringValue { value = Redaction(of: s) }
        default:
            break
        }
        return AuditRecord(timestamp: timestamp, tool: tool, app: app, bundleId: bundleId,
                           window: window, node: step.node, kind: step.kind.rawValue,
                           outcome: outcome, postStateHash: postStateHash,
                           value: value, script: script, reason: reason)
    }

    /// One line of JSONL: a single compact object with sorted keys, no newlines,
    /// so a line is a record and the file is append-only. Falls back to a minimal
    /// hand-built line only if encoding somehow fails, which keeps the trail
    /// complete rather than dropping an event.
    public func jsonLine() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(self), let line = String(data: data, encoding: .utf8) {
            return line
        }
        return "{\"timestamp\":\(timestamp),\"tool\":\"\(tool)\",\"outcome\":\"\(outcome)\"}"
    }
}
