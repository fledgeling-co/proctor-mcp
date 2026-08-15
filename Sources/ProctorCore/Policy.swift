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

// MARK: - The lane recommendation

/// What Proctor recommended, when it handed a browser page to another tool.
///
/// PRO-0020 and PRO-0024 name a lane for a page Proctor cannot drive itself, and
/// disclose on the wire that nothing the lane then does reaches this trail. That
/// stays true — but the *recommendation* is Proctor's own act, the moment it told
/// a model to go and drive something outside its own accounting, and until now
/// there was no record it happened.
///
/// **What is recorded is exactly the set of facts the decision was made on, and
/// nothing about where the person was.** PRO-0024 routes on the address's scheme
/// alone, so the scheme is recorded and no address, host, path, query or fragment
/// ever is. An auditor can reconstruct why Proctor said what it said; nobody can
/// reconstruct a browsing session from it.
///
/// A redacted address — the length-plus-hash form `Redaction` uses above — was
/// considered and rejected here, and the reason generalises: that form is safe
/// for a password because a password cannot be guessed, and an address can.
/// Anyone holding a list of candidate addresses can match the hash, so it would
/// store browsing history in a form that only looks redacted.
public struct LaneRecommendation: Codable, Sendable, Equatable {
    /// The tool's own name for the lane — `obscura`, `browser-use`.
    public let lane: String
    /// Which rule in the routing table chose it, as a token rather than the
    /// sentence the handoff carries, so the trail is answerable by machine.
    public let rule: String
    /// The address's scheme, lowercased, and never any other part of it. Absent
    /// where no address was read at all, which is the app-level handoff.
    public let scheme: String?

    public init(lane: String, rule: String, scheme: String?) {
        self.lane = lane; self.rule = rule; self.scheme = scheme
    }
}

// MARK: - Audit record

/// One append-only line of the redacting audit trail. It records what was done —
/// the tool, the target application/window/element, the outcome and the resulting
/// state hash — while any free text that passed through it (a typed value, a
/// script body) is present only as a `Redaction`.
public struct AuditRecord: Codable, Sendable, Equatable {
    /// The vocabulary of `outcome`. `recommended` is not an actuation: it says
    /// Proctor gave advice, and it deliberately does not claim the lane ran —
    /// Proctor does not execute either browser lane and cannot know.
    public enum Outcome {
        public static let ok = "ok"
        public static let failed = "failed"
        public static let refused = "refused"
        public static let recommended = "recommended"
        /// Proctor asked, and cannot say whether it happened.
        ///
        /// Only reachable once actuation is delegated, and it exists because
        /// `failed` is a claim rather than an absence of one: it asserts the
        /// action did not happen. When Proctor performs a step itself and the call
        /// throws, that assertion is true — nothing was posted. When a subprocess
        /// stops answering, the request may have been written, delivered and
        /// performed before it went, and there is no way from here to tell. A row
        /// saying `failed` there would be exactly the thing this trail is supposed
        /// to prevent: a weaker claim wearing the same word.
        public static let indeterminate = "indeterminate"
    }

    public var timestamp: Double
    public var tool: String
    public var app: String?
    public var bundleId: String?
    public var window: String?
    public var node: String?
    public var kind: String?           // the step kind, when this records a step
    public var outcome: String         // ok | failed | refused | recommended
    public var postStateHash: String?
    public var value: Redaction?       // a redacted typed value or setValue string
    public var script: Redaction?      // a redacted script body
    public var reason: String?         // why, for a refusal or a failure
    /// Present only on a `recommended` record.
    public var recommendation: LaneRecommendation?

    // MARK: - What a record needs to be *read* as history (PRO-0047)
    //
    // Six optional fields, added after the originals so a record sealed before
    // this existed still decodes with them nil. They change neither the signed
    // material nor the chain link, both of which are computed over the sealed
    // ciphertext rather than over these fields.
    //
    // They exist because a trail of events is not a history. A person thinks in
    // runs — "that thing it just did" — and the record carried nothing that said
    // which call a line belonged to, where in it, what it cost or how it
    // travelled. Without those, a history surface can only guess by adjacency.

    /// The tool call this record belonged to. Minted once at the dispatcher's
    /// choke point and carried on the task, so a gate refusal, every step of a
    /// batch and a recommendation all share it. Nil for a record written outside
    /// a call — a person's Stop, a hold — which is its own event and is read as a
    /// run of one.
    public var run: String?
    /// Position within the run, 0-based.
    public var seq: Int?
    /// What the step cost, milliseconds.
    public var ms: Int?
    /// Which plane the step travelled. A string rather than an enum on purpose:
    /// a later actuation lane naming a plane this build has never heard of must
    /// render as an opaque label, not fail to decode a whole record.
    public var plane: String?
    /// Proctor's own past-tense wording for the step — "Pressed", "Chose". Never
    /// caller text and never an application's, so a surface can draw it plainly.
    ///
    /// Persisted rather than derived on read because it cannot be derived on
    /// read: the derivation needs the live `ActionStep` and the resolved
    /// `AXNode`, and this record keeps only a kind and a node selector.
    public var act: String?
    /// The object that wording acted on, sanitised at write. This half *is*
    /// foreign text — an application's accessibility title or a caller's label —
    /// and is kept apart from `act` so a surface can fence it without fencing
    /// Proctor's own words.
    public var obj: Object?

    /// A step's object and where it came from.
    public struct Object: Codable, Sendable, Equatable {
        public var text: String
        /// True when the caller supplied it. Both kinds are fenced; this only
        /// records which, since PRO-0014 settled that an application's own title
        /// carries the same payload as a caller's label.
        public var supplied: Bool

        public init(text: String, supplied: Bool) {
            self.text = text; self.supplied = supplied
        }
    }

    // MARK: - What a record needs to be *believed* when Proctor did not act (PRO-0045)
    //
    // Five more optional fields, appended after PRO-0047's for the same reason and
    // with the same guarantee: a row sealed before they existed decodes with them
    // nil, and neither the signed material nor the chain link moves, because both
    // are computed over the sealed ciphertext rather than over these fields.
    //
    // They exist because PRO-0044 moved actuation into another process. Until then
    // the process writing the row was the process performing the action, so intent
    // and act were one event and one field could carry both. They are now two facts
    // of different strength, and Proctor's own reading of the window is a third.
    // Merging them would leave the row's words unchanged while what stands behind
    // them got weaker, which is the failure this feature exists to prevent.

    /// Which backend performed it — `native`, `cua`. Proctor's own knowledge.
    public var by: String?
    /// The backend's own word for how it delivered the step, sanitised and
    /// length-capped. The driver's claim, kept verbatim in vocabulary so the
    /// mapping in `ActuationPlane` can be audited rather than trusted. Nil for the
    /// native backend, which reports no delivery mode.
    public var mode: String?
    /// The backend's confidence that the action landed — `confirmed`,
    /// `unverifiable`, `suspectedNoOp`. An external claim, never Proctor's.
    ///
    /// Nil for the native backend, and the nil is meaningful: it says this backend
    /// makes no claims about itself, which is different from a backend that
    /// claimed nothing. Native judges a write by reading it back.
    public var eff: String?
    /// Proctor's OWN reading of the window's accessibility state before and after
    /// the step — `changed`, `unchanged`, `unread`.
    ///
    /// This is the only part of a delegated row Proctor witnessed, and it is what
    /// stops the trail becoming a record of intent. Read it narrowly: it is the
    /// accessibility tree as Proctor walked it, never "the machine". A canvas
    /// repaint can leave the tree identical, an animation can move it for no
    /// reason, and another process can move it without this step touching it. So
    /// `changed` is evidence the step landed rather than proof, and `unchanged` is
    /// evidence it did not rather than proof.
    ///
    /// Nil on the native path, deliberately: native takes no before-hash, and
    /// filling this from the *previous* step's post-state would measure a
    /// different interval while wearing the same name.
    public var obs: String?
    /// Which lane instance acted, tying this row to a `lane.opened` record.
    public var lane: String?

    /// Proctor's own reading of the window across a step.
    public enum Observation: String, Codable, Sendable, Equatable {
        case changed
        case unchanged
        /// There was no reading to compare — a `close` step ends with no window to
        /// walk. A real answer, not a failure: claiming `unchanged` here would be
        /// a fabrication.
        case unread
    }

    public init(timestamp: Double, tool: String, app: String? = nil, bundleId: String? = nil,
                window: String? = nil, node: String? = nil, kind: String? = nil,
                outcome: String, postStateHash: String? = nil,
                value: Redaction? = nil, script: Redaction? = nil, reason: String? = nil,
                recommendation: LaneRecommendation? = nil,
                run: String? = nil, seq: Int? = nil, ms: Int? = nil, plane: String? = nil,
                act: String? = nil, obj: Object? = nil,
                by: String? = nil, mode: String? = nil, eff: String? = nil,
                obs: String? = nil, lane: String? = nil) {
        self.timestamp = timestamp; self.tool = tool; self.app = app; self.bundleId = bundleId
        self.window = window; self.node = node; self.kind = kind; self.outcome = outcome
        self.postStateHash = postStateHash; self.value = value; self.script = script
        self.reason = reason; self.recommendation = recommendation
        self.run = run; self.seq = seq; self.ms = ms; self.plane = plane
        self.act = act; self.obj = obj
        self.by = by; self.mode = mode; self.eff = eff; self.obs = obs; self.lane = lane
    }

    /// Build a record for one executed step, redacting anything that could carry a
    /// secret. `type` text, an `appleScript` body and a string `setValue` all pass
    /// user data, so each is reduced to length-plus-hash before it is stored.
    ///
    /// `node` is the element the step actually resolved to. It is taken here and
    /// not stored: the wording is derived from it now, while it exists, and only
    /// the wording is kept.
    public static func forStep(_ step: ActionStep, tool: String, timestamp: Double,
                               app: String?, bundleId: String?, window: String?,
                               outcome: String, postStateHash: String?,
                               reason: String? = nil,
                               run: String? = nil, seq: Int? = nil, ms: Int? = nil,
                               plane: String? = nil, node: AXNode? = nil,
                               by: String? = nil, mode: String? = nil, eff: String? = nil,
                               obs: String? = nil, lane: String? = nil) -> AuditRecord {
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
        // An indeterminate row is written with the NOUN form — "Press" — rather
        // than the past form — "Pressed". `act` is Proctor's own voice, and on the
        // one row whose whole purpose is to say Proctor cannot tell whether the
        // step happened, the past tense would assert that it did. The five fields
        // above would have been correct and the sentence beside them a lie.
        let described = StepDescription.past(for: step, node: node,
                                             limit: StepDescription.historyObjectLimit,
                                             asserting: outcome != Outcome.indeterminate)
        return AuditRecord(timestamp: timestamp, tool: tool, app: app, bundleId: bundleId,
                           window: window, node: step.node, kind: step.kind.rawValue,
                           outcome: outcome, postStateHash: postStateHash,
                           value: value, script: script, reason: reason,
                           run: run, seq: seq, ms: ms, plane: plane,
                           act: described.verb,
                           obj: described.object.map {
                               Object(text: $0.text, supplied: $0.supplied)
                           },
                           by: by,
                           // Sanitised for the same reason `obj` is. It is the
                           // driver's own token rather than an application's text,
                           // so it is not browsing history — but it is still
                           // foreign text entering a file Proctor keeps, and a
                           // driver returning a megabyte in this field should put a
                           // bounded token in the trail, not the megabyte.
                           mode: StepDescription.sanitised(mode),
                           eff: eff, obs: obs, lane: lane)
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
