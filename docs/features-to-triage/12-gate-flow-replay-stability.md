---
sources: [REQ-013, REQ-016]
status: retired
---
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

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-013, REQ-016
- surface: SURF-001, SURF-011, SURF-012
- cases: CASE-0001, CASE-0015, CASE-0016, CASE-0017, CASE-0018, CASE-0038
- rungs reached: effect-witness, metamorphic, outcome
- provider: none
