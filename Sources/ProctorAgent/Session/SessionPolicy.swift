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
        let window: String
    }

    func loadPolicyIfNeeded() {
        guard !policyLoadedFlag else { return }
        policy = PolicyStore.load()
        policyLoadedFlag = true
    }

    private func tokenValid(for bundleId: String?) -> Bool {
        guard let token = approvalToken else { return false }
        return token.isValid(at: Date().timeIntervalSince1970, for: bundleId)
    }

    /// Enforce the gate for a tool about to drive `window`. On refusal it writes a
    /// `refused` audit record and throws a remedied error; on success it returns
    /// the resolved app handle id and bundle id for the audit context. Fails
    /// closed: an app that cannot be identified is refused whenever an allow list
    /// is in force.
    @discardableResult
    func enforcePolicy(tool: String, window: WindowHandle) throws -> AuditContext {
        loadPolicyIfNeeded()
        let app = appHandle(forWindow: window)
        let bundleId = app?.bundleId
        let context = AuditContext(tool: tool, app: app?.id, bundleId: bundleId, window: window.id)

        switch policy.decide(bundleId: bundleId, hasValidToken: tokenValid(for: bundleId)) {
        case .allow:
            return context
        case .blocked(let reason):
            AuditLog.append(AuditRecord(timestamp: Date().timeIntervalSince1970, tool: tool,
                                        app: app?.id, bundleId: bundleId, window: window.id,
                                        outcome: "refused", reason: reason))
            throw AgentError(code: .policyDenied, message: reason,
                             remedy: "Remove the app from the block list with proctor_policy action "
                                   + "\"configure\", or drive a different application.")
        case .needsApproval(let reason):
            AuditLog.append(AuditRecord(timestamp: Date().timeIntervalSince1970, tool: tool,
                                        app: app?.id, bundleId: bundleId, window: window.id,
                                        outcome: "refused", reason: reason))
            throw AgentError(code: .policyDenied, message: reason,
                             remedy: "Mint an approval token with proctor_policy action \"approve\" "
                                   + "(optionally scoped to this bundle id), then retry within its TTL.")
        }
    }

    /// Record one executed step, redacting anything it carried.
    func auditStep(_ step: ActionStep, context: AuditContext, ok: Bool,
                   postStateHash: String?, reason: String?) {
        AuditLog.append(AuditRecord.forStep(step, tool: context.tool,
                                            timestamp: Date().timeIntervalSince1970,
                                            app: context.app, bundleId: context.bundleId,
                                            window: context.window,
                                            outcome: ok ? "ok" : "failed",
                                            postStateHash: postStateHash, reason: reason))
    }

    // MARK: - proctor_policy

    func policyStatus() -> JSONValue {
        loadPolicyIfNeeded()
        var out: [String: JSONValue] = [
            "allow": .array(policy.allow.sorted().map(JSONValue.string)),
            "block": .array(policy.block.sorted().map(JSONValue.string)),
            "sensitive": .array(policy.sensitive.sorted().map(JSONValue.string)),
            "auditPath": .string(AuditLog.url.path),
            "auditCount": .number(Double(AuditLog.lineCount()))
        ]
        let now = Date().timeIntervalSince1970
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
        let now = Date().timeIntervalSince1970
        let token = ApprovalToken.mint(bundleId: bundleId, ttl: Double(ttlMs) / 1000, now: now)
        approvalToken = token
        var out: [String: JSONValue] = [
            "token": .string(token.token),
            "expiresAt": .number(token.expiresAt),
            "ttlMs": .number(Double(ttlMs))
        ]
        if let scope = token.bundleId { out["bundleId"] = .string(scope) }
        AuditLog.append(AuditRecord(timestamp: now, tool: "proctor_policy", bundleId: bundleId,
                                    outcome: "ok", reason: "approval token issued"))
        return .object(out)
    }

    func revokeApproval() -> JSONValue {
        let had = approvalToken != nil
        approvalToken = nil
        if had {
            AuditLog.append(AuditRecord(timestamp: Date().timeIntervalSince1970,
                                        tool: "proctor_policy", outcome: "ok",
                                        reason: "approval token revoked"))
        }
        return .object(["revoked": .bool(had)])
    }

    func auditTail(limit: Int) -> JSONValue {
        // Each stored line is already a JSON object; parse it back so the caller
        // gets structured records rather than strings-of-JSON.
        let decoder = JSONDecoder()
        let lines: [JSONValue] = AuditLog.tail(limit).map { line in
            guard let data = line.data(using: .utf8),
                  let value = try? decoder.decode(JSONValue.self, from: data) else {
                return .string(line)
            }
            return value
        }
        return .object([
            "auditPath": .string(AuditLog.url.path),
            "auditCount": .number(Double(AuditLog.lineCount())),
            "lines": .array(lines)
        ])
    }
}
