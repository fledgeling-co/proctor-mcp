# Spec PRO-0162 — Cut or Record Every Durable Boundary

**Brief:** `docs/features-to-triage/154-seven-durable-boundaries-nobody-cut.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-012
**Defects:** none

## Context & Purpose
Forty-three of fifty durable boundaries are cut. The seven that are not sit across four journeys, which are recorded non-critical for that reason rather than because the work matters less.

## Acceptance Criteria
1. Each uncut boundary is cut, or recorded as structurally uncuttable with the reason.
2. A journey whose five cuts exist is promoted to critical on evidence rather than assertion.
3. A cut names the observable it reads and a channel distinct from the one that performed the step.
4. The boundaries-cut fraction is published on every run whether it moved or not.
