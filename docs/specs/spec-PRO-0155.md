# Spec PRO-0155 — Durable Record of a Failing Check

**Brief:** `docs/features-to-triage/147-a-gate-that-loses-which-check-failed.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
A standing gate reported one failure out of several hundred checks and none on three re-runs, and which check failed could not be established because it prints to the terminal and keeps nothing.

## Acceptance Criteria
1. A failing check is written to a durable record naming which check it was.
2. A run that passes after a failure leaves both records, so an intermittent result is visible as one.
3. The record carries enough to re-run the single failing check on its own.
4. A gate that has gone red and green over the same tree is reported as unreproducible rather than as green.
