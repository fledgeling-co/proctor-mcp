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
                              outcome: "refused", reason: refusal.reason,
                              run: RunIdentity.current))
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
    ///
    /// **What a row of this trail attests to.** Every row is a claim Proctor makes
    /// about a request it made. For a step Proctor performed itself, that claim
    /// covers the action too: one process asked and acted, so intent and act are
    /// the same event, and the post-state hash is Proctor reading back its own
    /// work.
    ///
    /// For a delegated step the row carries three facts, of three different
    /// strengths, and never merges them. *Proctor's own knowledge:* the gate
    /// allowed this application, and Proctor sent this request to this backend at
    /// this time. *An external claim:* the driver reported it delivered the action
    /// by this path (`mode`), with this confidence that it landed (`eff`) —
    /// Proctor did not witness it and does not vouch for it. *Proctor's own
    /// observation:* Proctor walked the window's accessibility tree before and
    /// after, on its own tree, and the state either changed or did not (`obs`).
    ///
    /// The third is what stops the trail becoming a record of intent. It is weaker
    /// than having performed the action and stronger than taking the driver's
    /// word: a delegated row is corroborated, where a native row is merely
    /// self-reported. Where the two disagree — the driver claims success and
    /// nothing moved, or suspects a no-op and the window changed — the row records
    /// the disagreement rather than resolving it.
    ///
    /// Where Proctor cannot say, the row says it cannot say. A driver that dies
    /// mid-step or answers after the deadline may have delivered the action before
    /// it went. That row is `indeterminate`, not `failed`, and it carries Proctor's
    /// own before/after reading as the only evidence left.
    ///
    /// **The gate is not a sandbox.** It stands in front of every call Proctor
    /// makes and in front of nothing else. `cua-driver` is an ordinary binary on
    /// the machine, and any model holding a shell can drive it directly, unlogged
    /// and ungated, without Proctor being aware. Proctor cannot prevent that, does
    /// not try to, and the trail's completeness is a claim about Proctor's own
    /// actions, never about the machine.
    ///
    /// `node` is the element the step resolved to. It is handed in and not
    /// stored: the wording is derived from it here, while it still exists, and
    /// only the wording is kept. A history read has no element to derive from —
    /// the record holds a kind and a node selector, and neither carries the
    /// readable name the wording needs.
    func auditStep(_ step: ActionStep, context: AuditContext, outcome: String,
                   postStateHash: String?, reason: String?,
                   seq: Int? = nil, ms: Int? = nil, plane: ActuationPlane? = nil,
                   node: AXNode? = nil, actuation: Actuation? = nil,
                   observation: AuditRecord.Observation? = nil) {
        auditSink(AuditRecord.forStep(step, tool: context.tool, timestamp: clock(),
                                      app: context.app, bundleId: context.bundleId,
                                      window: context.window,
                                      outcome: outcome,
                                      postStateHash: postStateHash, reason: reason,
                                      run: RunIdentity.current, seq: seq, ms: ms,
                                      plane: plane?.rawValue, node: node,
                                      by: actuation?.backend.rawValue,
                                      mode: actuation?.reportedMode,
                                      eff: actuation?.effect?.rawValue,
                                      obs: observation?.rawValue,
                                      lane: actuation?.laneId))
    }

    /// One lane event: the actuation lane being opened, refused, or lost.
    ///
    /// Its own record rather than a field on a step, because these are facts about
    /// the lane and not about any one action — and because a lane can die between
    /// steps, before the first one, or during a call that has no row of its own
    /// yet. Written with no step kind, which is how `RunHistory` already tells a
    /// run's own event from one of its steps.
    func auditLane(_ event: LaneEvent) {
        auditSink(AuditRecord(timestamp: clock(), tool: "proctor_actuation",
                              outcome: event.outcome, reason: event.reason,
                              run: RunIdentity.current,
                              by: event.backend.rawValue, lane: event.laneId))
    }

    // MARK: - proctor_policy

    /// The trail's verdict, small enough to ride on every status call. Leads with
    /// whether it is clean, because that is the question; carries the counts and
    /// the *first* fault, because a trail with forty broken links needs one
    /// position to start from rather than forty.
    ///
    /// `clean` deliberately requires the signing key to have been reachable. A
    /// verdict that is only self-consistent — a trail and a key that agree with
    /// each other, both of which a forger could supply — is reported as
    /// unconfirmed instead.
    private func auditVerdict() -> JSONValue {
        let verdict = AuditLog.verify()
        let status = AuditLog.status()
        var out: [String: JSONValue] = [
            "clean": .bool(verdict.isClean),
            "entries": .number(Double(verdict.total)),
            "verified": .number(Double(verdict.verified)),
            "completeness": .string(verdict.completeness.state.rawValue),
            "keyConfirmed": .bool(verdict.keyConfirmed)
        ]
        // Entries dropped this run leave no hole in the chain to find: an entry
        // that was never written cannot break a link. The verdict would otherwise
        // read clean while the run knew perfectly well that events went
        // unrecorded, so the count travels with it rather than only beside it.
        if status.dropped > 0 {
            out["droppedThisRun"] = .number(Double(status.dropped))
            out["droppedNote"] = .string(
                "\(status.dropped) \(status.dropped == 1 ? "entry" : "entries") could not be written "
                + "this run, so \(status.dropped == 1 ? "that action is" : "those actions are") "
                + "missing from the trail. A trail with nothing wrong in it is not the same as a "
                + "complete one.")
        }
        if verdict.preChain > 0 {
            out["preChain"] = .number(Double(verdict.preChain))
            out["preChainNote"] = .string(
                "\(verdict.preChain) \(verdict.preChain == 1 ? "entry predates" : "entries predate") "
                + "signing, so nothing could have proved \(verdict.preChain == 1 ? "it" : "them") at "
                + "the time. The first signed entry pins \(verdict.preChain == 1 ? "it" : "them") as "
                + "\(verdict.preChain == 1 ? "it" : "they") stood, so a later edit is detected.")
        }
        if let count = verdict.completeness.count { out["completenessCount"] = .number(Double(count)) }
        if let reason = verdict.completeness.reason { out["completenessNote"] = .string(reason) }
        if let first = verdict.faults.first {
            out["faultCount"] = .number(Double(verdict.faults.count))
            out["firstFault"] = .object([
                "kind": .string(first.kind.rawValue),
                "entry": .number(Double(first.position)),
                "detail": .string(first.detail)
            ])
        }
        if !verdict.keyConfirmed {
            out["keyConfirmedNote"] = .string(
                "The signing key could not be reached, so the trail is internally consistent but "
                + "unconfirmed: nothing here proves it was written on this Mac.")
        }
        return .object(out)
    }

    /// The gate's posture for `proctor_doctor`: shape and counts, never rules.
    ///
    /// A sibling of `policyStatus()` rather than a filter over it, and that is the
    /// load-bearing part. `Toolchain.posture` takes counts and booleans, so there
    /// is no parameter here that could carry a bundle identifier, a filesystem
    /// root, a key id or a token — a later edit cannot leak one through this seam
    /// without changing a signature, which is a much louder thing to do than
    /// adding a key to a dictionary.
    ///
    /// `policyStatus()` is deliberately unchanged. Narrowing what *that* tool
    /// answers would change a shipped surface, and it is recorded as child work
    /// rather than done quietly here.
    func policyPosture() -> DoctorReport.PolicyPosture {
        loadPolicyIfNeeded()
        let audit = AuditLog.status()
        let verdict = AuditLog.verify()
        return Toolchain.posture(
            allowCount: policy.allow.count,
            blockCount: policy.block.count,
            sensitiveCount: policy.sensitive.count,
            approvalTokenLive: approvalToken.map { clock() < $0.expiresAt } ?? false,
            fsRootCount: fsRootsList().count,
            auditWritable: audit.writable,
            auditClean: verdict.isClean,
            auditKeyConfirmed: verdict.keyConfirmed,
            auditEntries: verdict.total,
            auditDropped: audit.dropped)
    }

    func policyStatus() -> JSONValue {        loadPolicyIfNeeded()
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
            // Sealing hides the contents; signing says who wrote them. The verdict
            // is the answer to the question sealing could never answer, which is
            // whether the trail is the one Proctor wrote.
            "auditSigned": .bool(true),
            "auditVerdict": auditVerdict(),
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
                              outcome: "ok", reason: "approval token issued",
                              run: RunIdentity.current))
        return .object(out)
    }

    func revokeApproval() -> JSONValue {
        let had = approvalToken != nil
        approvalToken = nil
        if had {
            auditSink(AuditRecord(timestamp: clock(), tool: "proctor_policy", outcome: "ok",
                                  reason: "approval token revoked",
                                  run: RunIdentity.current))
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
            "auditSigned": .bool(true),
            "auditVerdict": auditVerdict(),
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
