---
sources: [REQ-012, REQ-013]
status: retired
---
# Pointer marker in proctor_stability per-step artifacts

**Status:** untriaged · **Value:** low · **Effort:** med · **Source:** deferred child of PRO-0010 (scheduled 2026-08-13 via whats-left ingest)
<!-- Promoted from ORCHESTRATOR.md "Deferred children" on the reader's all-three answer. Cosmetic, and gated behind a real capability change. -->

## What it is
Draw the per-step target marker (as PRO-0010 does for `flow`) into `proctor_stability` per-step artifacts too.

## Why it was deferred, not done
`proctor_stability` currently emits per-step **hashes**, not per-step **PNGs**. There is no image to composite a marker onto. So this is not a small overlay add: it needs `stability` to emit a per-step PNG first, then the marker reuses PRO-0010's compositing path.

## Scope
- In: per-step PNG emission from `stability` (opt-in), then the target marker on each.
- Out: changing the divergence/hash logic; a live cursor sprite (same honesty caveat as PRO-0010 — this is the intended target point, not a real cursor).

## Success looks like
A divergent stability run shows, per step, exactly where Proctor acted, the same way a `flow` recording does now.

## Dependencies / notes
- Parent: PRO-0010 (shares the compositing path).
- The underlying change (per-step PNG emission) is the real cost; the marker is cheap on top of it. The reader accepted that commitment by scheduling this.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-012, REQ-013
- surface: SURF-001, SURF-003, SURF-011
- cases: CASE-0001, CASE-0003, CASE-0014, CASE-0015, CASE-0016, CASE-0026
- rungs reached: effect-witness, metamorphic, outcome
- provider: AXUIElementPerformAction in Sources/ProctorAgent/AX/Actuator.swift; AXObserverCreate in Sources/ProctorAgent/AX/Observers.swift
