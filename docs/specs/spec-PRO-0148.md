# Spec PRO-0148 — Deterministic Lane Routing and Selection Record

**Brief:** `docs/features-to-triage/140-deterministic-lane-routing-and-selection-record.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-030
**Defects:** none

## Context & Purpose
A verification stage that picks a reviewer lane by direct invocation leaves no record of which model family judged the work, so cross-family independence cannot be audited afterwards. The tailings pass found eighteen such choices. A selection record makes the routing chain reconstructable from evidence rather than from prose.

## Acceptance Criteria
1. Lane selection writes a structured record naming the chosen family, the task shape and the reason.
2. A selection that stayed in the writer's own family is flagged where independence was expected, rather than passing silently.
3. A fallback records the primary lane that was unavailable and what established the unavailability.
4. The routing chain behind any verification verdict is reconstructable from the records alone.
