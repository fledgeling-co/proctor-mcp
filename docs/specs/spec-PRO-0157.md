# Spec PRO-0157 — Capture Store Discovery by Convention

**Brief:** `docs/features-to-triage/149-a-capture-store-an-outside-probe-can-find.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-027
**Defects:** none

## Context & Purpose
An external audit reports no capture directory over a tree holding fifty-four images, because it tries conventional names at the repository root and reads no project configuration. The gap is discovery rather than data.

## Acceptance Criteria
1. The capture store is reachable from a conventional location without reading project configuration.
2. An outside probe following convention finds the same population the project's own instruments count.
3. The conventional location stays in step with the real one rather than drifting into a second copy.
4. Nothing is duplicated on disk to achieve this.
