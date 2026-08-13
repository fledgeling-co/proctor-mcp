# Plan — PRO-0005: Audit trail + policy gate

**Spec:** docs/specs/spec-PRO-0005.md · **Branch:** ai/pro-0005 · **Tier:** Standard
**Gate:** `swift build` + `swift test` from the worktree root.

## Shape

Two paired operator rails, built the way the repo already builds this class of thing:
pure decision/serialisation logic in `ProctorCore` (like `CUATranslator`, `SetOfMarks`,
`Canonical`), tested in isolation; thin stateful wiring in `ProctorAgent` (like
`UnlockTurn`/`FlowStore`), verified by build. One new action-based tool
`proctor_policy` mirrors `proctor_unlock`'s shape.

## ProctorCore — `Sources/ProctorCore/Policy.swift` (pure, unit-tested)

- `Redaction {len, sha256}` — `init(of:)` reduces a string to length + SHA-256
  (CryptoKit, same idiom as `Canonical`). Never stores cleartext. Clause 1.
- `AppPolicy {allow, block, sensitive: Set<String>}` keyed by bundle id, with
  `decide(bundleId:hasValidToken:) -> PolicyDecision` where
  `PolicyDecision = .allow | .blocked(reason) | .needsApproval(reason)`.
  Fail-closed ordering: block wins; a non-empty allow list blocks anything not on it
  (including an unidentifiable app); sensitive-without-valid-token → needsApproval;
  else allow. Clause 3.
- `ApprovalToken {token, bundleId?, expiresAt}` with `isValid(at:for:)` — TTL-bounded,
  scoped to a bundle id (nil = any sensitive app). Mirrors the unlock turn. Clause 2.
- `AuditRecord` — timestamp, tool, app, bundleId, window, node, kind, outcome,
  postStateHash, `value: Redaction?`, `script: Redaction?`, reason. `forStep(...)`
  redacts `type`/`appleScript` text and `setValue` string values; `jsonLine()`
  emits one sorted-key JSON line. Clause 1 + "every action accounted for".

## ProctorAgent — wiring (build-verified)

- `Sources/ProctorAgent/Session/PolicyStore.swift`: `PolicyStore` (load/save `AppPolicy`
  under `Application Support/<bundle>/policy/policy.json`) and `AuditLog`
  (append/`tail` JSONL under `.../audit/audit.jsonl`, dir 0700) — mirrors `FlowStore`.
- `Session` state: `policy`, `approval: ApprovalToken?`, lazy-loaded; methods
  `policyStatus`, `configurePolicy`, `approve`, `revoke`, `auditTail`.
- Gate at the model-facing drive entry points — `act` and `computerUse` (both façades):
  resolve the window's bundle id via `appHandle(forWindow:)`, `policy.decide(...)`;
  blocked/needsApproval → write a `refused` audit record and throw a remedied
  `AgentError`; allowed → proceed. Per-step `ok`/`failed` audit records appended in
  the shared `runSteps` path (so replay/stability execution is audited too).
  Flow replay drives an already-recorded, vetted flow, so it is audited but not
  re-gated this pass (noted).
- `proctor_doctor` gains a `policy` block: counts of allow/block/sensitive and whether
  an approval token is live — the operator surface the spec asks to tie into.

## Catalogue / dispatch (shared files — mechanical union merge)

- `ToolCatalogue.swift`: append `policy` spec; `all` grows 14 → **15**.
  Non-destructive, non-read-only, idempotent (mutates session/config only, like `apps`;
  it does not actuate an app, so it stays out of the `destructive` set).
- `Dispatch.swift`: add `case "proctor_policy"` + a `policy(_:)` decoder mirroring `unlock`.
- `ToolOutputSchemas.swift`: add a `proctor_policy` output schema.
- `ProctorProfiles`: `policy` is `full`-only (specialist/operator surface, like `unlock`/`inspect`).

## Tests — `Tests/ProctorCoreTests/ProctorCoreTests.swift` (red → green)

New `@Suite("Policy gate")` + `@Suite("Redacting audit")`, one test per clause:
1. Redaction: a secret value is stored as `{len, sha256}`, cleartext absent, hash
   verifiable against the known input; audit `jsonLine()` for a `type` step contains
   no cleartext.
2. ApprovalToken: valid before `expiresAt`, invalid after, invalid for the wrong bundle.
3. PolicyEngine: blocked bundle → `.blocked`; allow-list mode blocks a non-listed app
   and an unidentifiable app (fail-closed); sensitive without token → `.needsApproval`;
   sensitive with valid token → `.allow`; plain app → `.allow`.
4. AuditRecord accounts for an action: carries tool, target (app/window/node), outcome
   and postStateHash.
Plus update `CatalogueTests.count` 14 → 15 and its name.

Clause 4 (encryption-at-rest) is an explicit scope exclusion — no code, no test.
