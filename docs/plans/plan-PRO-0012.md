# plan-PRO-0012: Gate flow-replay + stability through policy + audit

**Spec:** docs/specs/spec-PRO-0012.md · **Branch:** ai/pro-0012 · **Tier:** Small

## What ships

`proctor_flow` replay and `proctor_stability` stop being the two drive paths that
skip the rails PRO-0005 built. Both now pass the fail-closed policy gate before
anything actuates, both write every executed step to the redacting JSONL trail, and
a repeated stability run re-checks the gate at the top of each repeat so a
TTL-bounded approval actually expires mid-run instead of carrying stale authority
to the last repeat.

No new tool, no schema change, no change to the stored recording format.

## Grounding — what already exists

- `Session.enforcePolicy(tool:window:)` (SessionPolicy.swift) resolves the app from
  the **live** window handle, calls `AppPolicy.decide`, writes a `refused`
  `AuditRecord` and throws an `AgentError(.policyDenied)` with a remedy. It returns
  an `AuditContext(tool:app:bundleId:window:)`.
- `Session.runSteps(_:window:settle:foreground:captureEach:diffEach:audit:pointerMarks:)`
  (SessionAct.swift) already audits every step it runs **when an audit context is
  supplied** — `auditStep` on success, on a refusal and on both failure paths.
  `proctor_act` and both CUA façades pass one; `flowReplay` and `stability` pass
  nothing, which is the entire gap.
- Sub-action tool naming already exists: `SessionActivate` audits as
  `proctor_apps.activate`.
- Only `ProctorCoreTests` exists (depends on `ProctorCore` alone), so every
  red→green test lands in Core and the pure decision must live there. This is the
  house pattern PRO-0005 set: "The decisions and the redaction are pure and live in
  ProctorCore … this file holds the session state."

## Architecture

### 1. Core — `Sources/ProctorCore/ReplayGate.swift` (new, tested)

Three pure pieces, no clock and no disk:

- **`AuditTool`** — the canonical tool names, so the trail can tell a live drive
  from a replay from a determinism run: `act` = `proctor_act`,
  `flowReplay` = `proctor_flow.replay`, `stability` = `proctor_stability.replay`,
  `stabilityReset` = `proctor_stability.reset`, plus the existing
  `appsActivate` = `proctor_apps.activate`. All follow the `tool.subaction`
  convention already in use.
- **`PolicyRefusal { reason, remedy }`** and `PolicyDecision.refusal` — the refusal
  text lifted out of `enforcePolicy` so every gated path (live, replay, determinism,
  reset) emits the *identical* reason and remedy and only the audited `tool` differs.
  This is the spec's "same reason, message and remedies as the live path" clause,
  made structural rather than duplicated.
- **`ReplayGate.verdict(for:completedRuns:) -> Verdict`** —
  `.proceed` | `.refuseRun(PolicyRefusal)` when nothing has run yet |
  `.stopRun(PolicyRefusal)` once at least one repeat has completed. This is the
  no-partial / partial-with-provenance split: refused before the first repeat ⇒ the
  call throws and reports no numbers; refused between repeats ⇒ the run stops, keeps
  what it measured, and says so.
- **`ReplayGate.earlyStopNote(completedRuns:requestedRuns:reason:)`** — the note text
  that marks a report as measured on fewer repeats and carries the refusal reason.

### 2. Agent — `Sources/ProctorAgent/Session/SessionPolicy.swift`

- Split `enforcePolicy` into a non-throwing `policyGate(tool:app:bundleId:window:)
  -> (context: AuditContext, refusal: PolicyRefusal?)` which writes the `refused`
  audit record, plus the existing throwing `enforcePolicy` built on top of it (so
  `proctor_act`, the CUA façades and `proctor_apps.activate` are byte-for-byte
  unchanged in behaviour). The refusal text now comes from `PolicyDecision.refusal`.

### 3. Agent — `Sources/ProctorAgent/Session/SessionFlow.swift`

- **`flowReplay`**: resolve the target window first (override wins over the recorded
  window), then `enforcePolicy(tool: AuditTool.flowReplay, window: handle)` **before**
  any actuation, and pass the returned context into `runSteps(audit:)`. The gate keys
  on the app behind the window being driven now; `flow.appBundleId` is never
  consulted, so a recording made against an allowed app and pointed at a blocked one
  is refused. Fail-closed on an unidentifiable target is inherited from
  `AppPolicy.decide(bundleId: nil, …)` under an allow list.
- **`stability`**: gate once before the loop (refusal ⇒ throw, no numbers), then at
  the top of every repeat call `policyGate` again and run `ReplayGate.verdict`:
  `.proceed` continues; `.refuseRun` throws (repeat 0); `.stopRun` breaks the loop,
  appends `earlyStopNote` and reports on the repeats that completed. The reset
  sequence runs after that check, inside the same permitted repeat, and is audited
  under `AuditTool.stabilityReset`; the measured replay is audited under
  `AuditTool.stability`.
- `StabilityReport.runs` becomes the number of repeats **completed** rather than the
  number requested (identical in the normal case; correct when a run is cut short).
  `deterministic` already requires `runs > 1`, so a run stopped after one repeat
  cannot report deterministic.

## Acceptance clauses → proving tests (new `@Suite("Replay gate")` in ProctorCoreTests)

1. **A replay of a blocked app is refused exactly as a live drive is** → the refusal
   for a `.blocked` decision is one value; the reason and remedy are identical
   whichever tool asks.
2. **A sensitive app without a token refuses a replay with the approve remedy** →
   `.needsApproval.refusal` carries the `proctor_policy action "approve"` remedy.
3. **An unidentifiable target fails closed under an allow list** →
   `decide(bundleId: nil, hasValidToken: false)` is `.blocked` for a replay target.
4. **The gate is judged on the app being driven now, not the one recorded** →
   a recorded-allowed / live-blocked pair resolves to `.blocked`.
5. **Refused before the first repeat reports no numbers** →
   `verdict(for: .blocked, completedRuns: 0) == .refuseRun`.
6. **An approval expiring between repeats stops the run and keeps what it measured** →
   `verdict(for: .needsApproval, completedRuns: 3) == .stopRun`; and a valid token at
   repeat 0 that is invalid at repeat 3 (`ApprovalToken.isValid` across the TTL
   boundary) produces exactly that pair.
7. **A cut-short run says so, with the count and the reason** → `earlyStopNote`
   names completed vs requested repeats and carries the refusal reason.
8. **The three drive paths are named distinctly in the trail** → `AuditTool` values
   are pairwise distinct, and replay/stability/reset all follow `tool.subaction`.
9. **A replayed step is redacted like a live one** → `AuditRecord.forStep` under
   `AuditTool.flowReplay` stores a typed secret as length-plus-hash and never in the
   clear, and the record names the replay tool.
10. **Recording, listing, showing and deleting stay ungated** → the catalogue's
    annotations for `proctor_flow`/`proctor_stability` are unchanged and the tool
    count stays 19.

## Out of scope

- The recording format, and the fact that `proctor_flow action "show"` still returns
  typed text the trail redacts (named in the spec as a deliberately open gap).
- Audit retention or size limits (spec names the cost as accepted).
- Re-gating anything PRO-0005 already gated.

## Verification

`swift build` + `swift test` from the worktree root. New suite red→green; the full
Core suite is the affected-test sweep (one test target).
