import Foundation
import ProctorCore

// The policy gate and the redacting audit trail, agent half. The decisions and
// the redaction are pure and live in ProctorCore (AppPolicy, ApprovalToken,
// AuditRecord); this file holds the session state, enforces the gate at the
// drive entry points, and writes the trail. It mirrors the unlock turn: an
// approval token is session-only and TTL-bounded, so a crashed caller leaves no
// standing authority to drive a sensitive app.

extension Session {

    /// Context handed to `runSteps` so each executed step can be recorded against
    /// the tool and target that drove it.
    struct AuditContext: Sendable {
        let tool: String
        let app: String?
        let bundleId: String?
        /// Nil for an app-scoped action (activation), which has no window to key
        /// on. The audit record's own window field is optional for the same reason.
        let window: String?
    }

    func loadPolicyIfNeeded() {
        guard !policyLoadedFlag else { return }
        policy = PolicyStore.load()
        policyLoadedFlag = true
    }

    // MARK: - Seams

    /// Install a policy without touching disk, and mark it loaded so the on-disk
    /// one is not read over the top of it. The gate's wiring — which paths check
    /// it, in what order, and what they write to the trail — is only checkable
    /// against a known policy, and a test must not write to the operator's real
    /// policy file to get one.
    func installPolicy(_ policy: AppPolicy, token: ApprovalToken? = nil) {
        self.policy = policy
        self.approvalToken = token
        self.policyLoadedFlag = true
    }

    /// Where audit records go, and what time it is for the approval token. Both
    /// default to the real thing — the on-disk trail and the wall clock — and are
    /// substituted only so a test can read what was recorded and cross a TTL
    /// boundary exactly rather than by sleeping.
    func setAuditSink(_ sink: @escaping @Sendable (AuditRecord) -> Void) { auditSink = sink }
    func setClock(_ clock: @escaping @Sendable () -> Double) { self.clock = clock }

    private func tokenValid(for bundleId: String?) -> Bool {
        guard let token = approvalToken else { return false }
        return token.isValid(at: clock(), for: bundleId)
    }

    /// Enforce the gate for a tool about to drive `window`. On refusal it writes a
    /// `refused` audit record and throws a remedied error; on success it returns
    /// the resolved app handle id and bundle id for the audit context. Fails
    /// closed: an app that cannot be identified is refused whenever an allow list
    /// is in force.
    @discardableResult
    func enforcePolicy(tool: String, window: WindowHandle) throws -> AuditContext {
        let app = appHandle(forWindow: window)
        return try enforcePolicy(tool: tool, app: app, bundleId: app?.bundleId,
                                 window: window.id)
    }

    /// The same gate for a tool acting on a whole application rather than one of
    /// its windows. Activating an app has no window to key on (an app with every
    /// window closed is exactly the case that needs it), so the decision is made
    /// on the bundle id alone. It fails closed the same way: an app whose bundle
    /// id cannot be resolved is refused whenever an allow list is in force.
    @discardableResult
    func enforcePolicy(tool: String, app: AppHandle?, bundleId: String?,
                       window: String? = nil) throws -> AuditContext {
        let outcome = policyGate(tool: tool, app: app, bundleId: bundleId, window: window)
        if let refusal = outcome.refusal {
            throw AgentError(code: .policyDenied, message: refusal.reason, remedy: refusal.remedy)
        }
        return outcome.context
    }

    /// The gate without the throw, for a caller that has to decide what a refusal
    /// means rather than simply fail — a repeated replay part-way through a run
    /// has numbers to report and cannot just unwind. The refusal record is written
    /// here either way, so the trail is identical whichever caller asked; the
    /// reason and remedy come from the shared `PolicyDecision.refusal`, so every
    /// gated path says the same thing and only the audited tool name differs.
    ///
    /// `bundleId` must be the identity of the application actually being driven.
    /// It is a separate parameter only because an app-scoped action resolves it
    /// before it has an `AppHandle`; passing anything else — the bundle id a
    /// recording carries, or one a caller supplied — would have the gate judge a
    /// name instead of the app under the pointer, which is the hole this feature
    /// exists to close.
    func policyGate(tool: String, app: AppHandle?, bundleId: String?,
                    window: String? = nil) -> (context: AuditContext, refusal: PolicyRefusal?) {
        loadPolicyIfNeeded()
        let resolved = bundleId ?? app?.bundleId
        let context = AuditContext(tool: tool, app: app?.id, bundleId: resolved, window: window)

        let decision = policy.decide(bundleId: resolved, hasValidToken: tokenValid(for: resolved))
        guard let refusal = decision.refusal else { return (context, nil) }
        auditSink(AuditRecord(timestamp: clock(), tool: tool,
                              app: app?.id, bundleId: resolved, window: window,
                              outcome: "refused", reason: refusal.reason))
        return (context, refusal)
    }

    /// The gate for one repeat of a repeated replay. The decision is made on the
    /// application being driven now — never on the one the recording names — and
    /// the verdict depends on how much of the run already happened: refused before
    /// the first repeat fails the call, refused between repeats stops it with the
    /// numbers it managed to measure.
    func repeatGate(tool: String, window: WindowHandle,
                    completedRuns: Int) -> (context: AuditContext, verdict: ReplayGate.Verdict) {
        let app = appHandle(forWindow: window)
        let outcome = policyGate(tool: tool, app: app, bundleId: app?.bundleId, window: window.id)
        guard let refusal = outcome.refusal else { return (outcome.context, .proceed) }
        return (outcome.context,
                completedRuns > 0 ? .stopRun(refusal) : .refuseRun(refusal))
    }

    /// Record one executed step, redacting anything it carried.
    func auditStep(_ step: ActionStep, context: AuditContext, ok: Bool,
                   postStateHash: String?, reason: String?) {
        auditSink(AuditRecord.forStep(step, tool: context.tool, timestamp: clock(),
                                      app: context.app, bundleId: context.bundleId,
                                      window: context.window,
                                      outcome: ok ? "ok" : "failed",
                                      postStateHash: postStateHash, reason: reason))
    }

    // MARK: - proctor_policy

    func policyStatus() -> JSONValue {
        loadPolicyIfNeeded()
        let audit = AuditLog.status()
        var out: [String: JSONValue] = [
            "allow": .array(policy.allow.sorted().map(JSONValue.string)),
            "block": .array(policy.block.sorted().map(JSONValue.string)),
            "sensitive": .array(policy.sensitive.sorted().map(JSONValue.string)),
            "auditPath": .string(AuditLog.url.path),
            "auditCount": .number(Double(AuditLog.lineCount())),
            // The trail is encrypted at rest, so its path and size are the two
            // things an operator can still see without the key — and whether it is
            // being written at all, which used to fail silently.
            "auditEncrypted": .bool(true),
            "auditWritable": .bool(audit.writable),
            // The declared filesystem roots sit alongside the app lists: both are
            // the operator-facing containment surface, and stating the roots here is
            // what makes the jail's guarantee auditable rather than implicit.
            "fsRoots": .array(fsRootsList().map(JSONValue.string))
        ]
        if let kid = audit.keyId { out["auditKeyId"] = .string(kid) }
        if let error = audit.error { out["auditError"] = .string(error) }
        // Monotonic: a later success does not erase the fact that entries were
        // lost, because a trail with a hole in it must not read as a clean one.
        if audit.dropped > 0 { out["auditDropped"] = .number(Double(audit.dropped)) }
        if audit.keyMismatch { out["auditKeyMismatch"] = .bool(true) }
        if let converted = audit.converted {
            out["auditConverted"] = .number(Double(converted))
            out["auditConvertedNote"] = .string(
                "This run converted \(converted) previously readable \(converted == 1 ? "entry" : "entries") "
                + "in place. The readable copy no longer exists and there is no backup: the trail can be "
                + "read only on this Mac with this login keychain.")
        }
        let now = clock()
        if let token = approvalToken, now < token.expiresAt {
            out["tokenLive"] = .bool(true)
            out["tokenExpiresAt"] = .number(token.expiresAt)
            if let scope = token.bundleId { out["tokenBundleId"] = .string(scope) }
        } else {
            out["tokenLive"] = .bool(false)
        }
        return .object(out)
    }

    func configurePolicy(allow: [String]?, block: [String]?, sensitive: [String]?) throws -> JSONValue {
        loadPolicyIfNeeded()
        // Supplying a key replaces that whole set; omitting it leaves the set
        // unchanged, so an operator can adjust one list without restating the rest.
        if let allow { policy.allow = Set(allow) }
        if let block { policy.block = Set(block) }
        if let sensitive { policy.sensitive = Set(sensitive) }
        try PolicyStore.save(policy)
        return policyStatus()
    }

    func approve(bundleId: String?, ttlMs: Int) -> JSONValue {
        let now = clock()
        let token = ApprovalToken.mint(bundleId: bundleId, ttl: Double(ttlMs) / 1000, now: now)
        approvalToken = token
        var out: [String: JSONValue] = [
            "token": .string(token.token),
            "expiresAt": .number(token.expiresAt),
            "ttlMs": .number(Double(ttlMs))
        ]
        if let scope = token.bundleId { out["bundleId"] = .string(scope) }
        auditSink(AuditRecord(timestamp: now, tool: "proctor_policy", bundleId: bundleId,
                              outcome: "ok", reason: "approval token issued"))
        return .object(out)
    }

    func revokeApproval() -> JSONValue {
        let had = approvalToken != nil
        approvalToken = nil
        if had {
            auditSink(AuditRecord(timestamp: clock(), tool: "proctor_policy", outcome: "ok",
                                  reason: "approval token revoked"))
        }
        return .object(["revoked": .bool(had)])
    }

    func auditTail(limit: Int) -> JSONValue {
        // The trail is sealed on disk, so reading it needs this Mac's login
        // keychain. Callers get the same records in the same shape and order as
        // before; an entry that cannot be unsealed comes back as a marked
        // placeholder rather than breaking the whole read.
        let decoder = JSONDecoder()
        var unreadable = 0
        let lines: [JSONValue] = AuditLog.openedTail(limit).map { entry in
            switch entry {
            case .opened(let line):
                guard let data = line.data(using: .utf8),
                      let value = try? decoder.decode(JSONValue.self, from: data) else {
                    return .string(line)
                }
                return value
            case .unreadable(let kid, let reason):
                unreadable += 1
                var placeholder: [String: JSONValue] = [
                    "unreadable": .bool(true),
                    "reason": .string(reason)
                ]
                if let kid { placeholder["kid"] = .string(kid) }
                return .object(placeholder)
            }
        }
        let audit = AuditLog.status()
        var out: [String: JSONValue] = [
            "auditPath": .string(AuditLog.url.path),
            "auditCount": .number(Double(AuditLog.lineCount())),
            "auditEncrypted": .bool(true),
            "auditWritable": .bool(audit.writable),
            "unreadableCount": .number(Double(unreadable)),
            "lines": .array(lines)
        ]
        if let kid = audit.keyId { out["auditKeyId"] = .string(kid) }
        if let error = audit.error { out["auditError"] = .string(error) }
        if audit.dropped > 0 { out["auditDropped"] = .number(Double(audit.dropped)) }
        if audit.keyMismatch {
            // Caught here because reading is the only moment both halves are in
            // hand: the write path holds the public key alone, by design.
            out["auditKeyMismatch"] = .bool(true)
            out["auditKeyMismatchNote"] = .string(
                "The sealing key file beside the trail is not the public half of the key this Mac "
                + "holds, so entries sealed with it cannot be read here.")
        }
        return .object(out)
    }
}
