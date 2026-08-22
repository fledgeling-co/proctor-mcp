# PRO-0012: Gate flow-replay + stability through policy + audit

**ID:** PRO-0012
**Brief:** `docs/features-to-triage/12-gate-flow-replay-stability.md`
**Status:** Merged
**Plan:** docs/plans/plan-PRO-0012.md
**Created:** 2026-08-13
**Last updated:** 2026-08-14

## Feature description

# Gate recorded flow-replay and stability through the policy gate + audit

**Status:** untriaged · **Value:** high (security) · **Effort:** med · **Source:** deferred child of PRO-0005 (scheduled 2026-08-13 via whats-left ingest)
<!-- Promoted from ORCHESTRATOR.md "Deferred children" on the reader's all-three answer. Security hardening that matters the day the tool is shared. -->

## What it is
Route recorded-flow **replay** and `proctor_stability` runs through the same policy gate and redacting audit log that `act` and both computer facades already pass through.

## The gap
This pass gated `act` and the two computer facades. Recorded flows are replayed **without** the permission gate the live path enforces, and stability replays them N times. So a recording made under one policy can be replayed under another, and the replay is not written to the audit trail the live actions are. On a single-user Mac this is fine; on a shared tool it is a hole.

## Scope
- In: every replayed step passes the fail-closed policy gate; every replayed step is written to the redacting JSONL audit log; stability replays inherit both.
- Out: changing the recording format; re-gating anything already gated.

## Success looks like
A recorded flow that violates the current policy is blocked on replay exactly as the same action would be blocked live, and every replayed step appears in the audit log.

## Dependencies / notes
- Parent: PRO-0005 (reuses its gate + audit rails).
- Pairs with the audit-log encryption child (13): both are "shared-tool" hardening.

---

## Triage — 2026-08-14

**Ready for Implementation Plan**

**Sentinel review:** S2 — Approve with assumptions (governance-adjacent: permission enforcement and the audit trail; no price-sensitive or investor-facing surface, so not S3)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** the replay tool and the determinism tool an agent or test harness calls *(behind the scenes — nothing visible changes in any app)*. Nothing customer-facing changes, and no new screen. The permission-and-trail tool is unchanged.
- **What users will see:** nothing on screen. A caller replaying a recording against an app the operator has blocked, or a sensitive one with no live approval, now gets the same refusal — same wording, same remedies — they already get when they drive that app directly, instead of the replay proceeding. Every replayed step now shows up when the operator reads the trail, with typed text and script bodies hidden the same way live actions hide them.
- **Behaviour changes:**
  - A replay that is not permitted refuses before its first step, so nothing half-runs.
  - A time-limited approval that expires partway through a repeated-replay run stops the remaining repeats instead of carrying stale authority to the end, and the run reports what it managed to measure.

**Assumptions**
- `[Compliance]` Permission is checked before any step of a replay runs, and refusal stops the whole run. *(matches how driving an app is gated today — one check per batch)*
- `[Compliance]` Permission is decided on the app being driven and nothing else, so one standing approval covers a replay exactly as it covers driving that app by hand — replaying does not need its own separate approval. *(the operator's decision is about the app, not about which tool reached it)*
- `[Compliance]` Permission is judged on the app being driven now, not the app named in the recording. *(a recording can be pointed at a different window)*
- `[Compliance]` A replay whose target app cannot be identified is refused whenever an allow list is in force, as the live path already refuses it. *(fail-closed; an unidentifiable target is the case a shared tool must not wave through)*
- `[Compliance]` Permission is re-checked at the start of each repeat in a repeated-replay run. *(a time-limited approval must actually expire mid-run)*
- `[Compliance]` When a time-limited approval expires between repeats, the run stops there and reports how many repeats it completed; it never pauses to ask for a fresh one. *(there is nobody to ask mid-run — a new approval is a deliberate caller action)*
- `[Compliance]` Each replayed step is written to the trail individually, with the same hiding of typed text and script bodies as a live action. *(the brief asks for per-step; the hiding already exists)*
- `[Compliance]` Trail entries name the tool that drove the step — the replay tool, the determinism tool, and the live-drive tool each named distinctly, following the existing naming for a tool's sub-actions. *(a trail that cannot tell a replay from a live action cannot answer "who did this")*
- `[Compliance]` The between-repeat reset steps in a determinism run are gated and recorded like any other step, and a refused reset ends the run the same way a refused replay step does. *(they drive the app exactly as replayed steps do)*
- `[Operations]` A refusal carries the same reason, message and remedies as the live path, and writes a refusal entry of the same shape — the only difference is that it names the replay or determinism tool rather than the live one. *(one behaviour to learn; the name is what makes the trail useful)*
- `[Operations]` A run refused before anything runs reports no determinism numbers. A run that started and was cut short — an expired approval, a refused reset — reports the numbers from the repeats that did complete, marked in its notes as measured on fewer repeats. *(matches how the tool already reports a run that ended early, rather than inventing a second convention)*
- `[Operations]` No clean-up or size limit is added, and a long repeated run writes one entry per step per repeat. *(named as an accepted cost; retention would be its own change)*
- `[Data & scope]` Recording, listing, showing and deleting a recording stay ungated. *(none of them drives an app; the brief rules out re-gating what is already covered)*
- `[Data & scope]` Known gap left open, deliberately: reading back a stored recording returns its steps as recorded, including any typed text, which the trail hides. Closing that is not this change. *(the brief fixes the recording format as out of scope; it belongs with the other shared-tool hardening work)*
- `[Data & scope]` The stored recording format is untouched, so recordings made before this change replay unchanged. *(explicitly out of scope in the brief)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0012` before the planner picks this up.*

**Out-of-family spec review:** grok-4.6 at `xhigh`, read-only — this repo's out-of-family reviewer; Codex is off per ORCHESTRATOR.md. (First attempt hit its deadline with no verdict; the retry, with the artifact supplied inline, returned one.) Verdict: material defects, 6 findings. **5 accepted** (approval expiry mid-run left unspecified; the tool names in the trail left unfixed; a contradiction between "identical refusal entry" and "distinctly named entry"; no stated behaviour for a target that cannot be identified; a refused reset not covered by the no-partial-numbers rule) — each is now an assumption above. **1 rejected**: the claim that replay might need its own approval separate from a live drive rests on the permission decision keying on the tool, which it does not — it keys on the app; an assumption naming that explicitly was added anyway so the planner cannot re-introduce the confusion.

**Assumptions review gate:** a separate reviewer flagged 2 of 14 defaults as likely to surprise the owner, neither of them an external dependency. Both were fixed rather than raised as questions: partial determinism numbers are now reported with their provenance instead of withheld (matching how the tool already reports a run that ended early), and the fact that a stored recording still hands back typed text that the trail hides is now named as a deliberately open gap rather than left silent.

---

## Progress — 2026-08-14

**Branch:** `ai/pro-0012` · **Worktree:** `.worktrees/PRO-0012` · **Status:** ready to merge, not merged.

**What shipped.** `proctor_flow` replay and `proctor_stability` now pass the same fail-closed
policy gate and write to the same redacting trail as `proctor_act`. New pure module
`Sources/ProctorCore/ReplayGate.swift`: `AuditTool` (the distinct trail names),
`PolicyRefusal` + `PolicyDecision.refusal` (the refusal reason and remedy lifted out of the
agent so every gated path emits identical text), `ReplayGate.verdict` (refuse-before-start vs
stop-and-keep) and `earlyStopNote`. `SessionPolicy` gains a non-throwing `policyGate` that
writes the refusal record, with the throwing `enforcePolicy` rebuilt on it, plus `repeatGate`.
`flowReplay` gates on the live window before any actuation and passes its audit context into
`runSteps`. `stability` gates the reset and the measured replay separately per repeat, stops on
a mid-run expiry and reports the repeats it completed. Tool descriptions for both now state the
gate, as `proctor_kill` and the CUA façade already do. No schema change; tool count stays 19.

**Gate evidence.** `swift build` clean. `swift test` = **196 tests in 26 suites passed**
(baseline at HEAD was 173 in 24). Red→green verified: with the gate and audit wiring stripped,
9 of the 12 agent wiring tests fail.

**Two decisions beyond the letter of the spec, both deliberate.**
1. A truncated stability run is never reported `deterministic`, even when the repeats it
   completed agreed. The spec only required the note and the reduced count; agreement over two
   repeats when ten were commissioned is a weaker claim than the one asked for, and this
   instrument's value is that it does not overstate its evidence. Test:
   `truncatedRunIsNotDeterministic`.
2. A new test target, `ProctorAgentTests`, links `ProctorAgent` and drives a real `Session`
   against fake AX/capture engines. Without it the load-bearing behaviour here — the gate runs
   *before* actuation, the audit context is actually passed — was unprovable, which the plan
   review named as the plan's weakest point. Session gained four internal seams for it
   (`installPolicy`, `installFlow`, `setAuditSink`, `setClock`); the audit sink and clock default
   to the on-disk trail and the wall clock, so production behaviour is unchanged and no test
   touches the operator's policy file or trail.

**Out-of-family gates (grok-4.6, `xhigh`, read-only; Codex off per ORCHESTRATOR.md).**
Plan review: material defects, 4 findings. Accepted: gate the reset separately under its own
name (implemented); define `completedRuns` as finished measured repeats (it is `perRun.count`,
now documented); the Core-only suite cannot cover the wiring (answered with the agent test
target). Rejected with reason: that `replayWindow`/`windowHandle` might actuate before the gate
— both are lookups, verified in source. Completeness critic: complete on all twelve behaviours,
4 residual risks, all closed — live-path regression (test `liveActPathUnchanged`: one refusal
record, byte-identical remedy), refused reset after progress (`stabilityRefusedResetEndsRun`),
secrets in reset steps (`stabilityRedactsResetSecrets`), truncated determinism
(`truncatedRunIsNotDeterministic`). A future caller passing a non-driven bundle id to
`policyGate` is warned off in its doc comment. The first attempt at each gate failed the lane
(deadline, then prompt truncation); both were retried with compacted inline evidence.

**Deferred.** Nothing from this spec. The open gap the spec names deliberately — `proctor_flow`
action `"show"` still returns recorded typed text that the trail redacts — is untouched, as
scoped, and belongs with PRO-0013.
