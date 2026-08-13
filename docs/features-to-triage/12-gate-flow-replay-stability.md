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
