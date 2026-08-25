# Spec PRO-0163 — A Specification Names the Figure It Will Move

**Brief:** `docs/features-to-triage/155-the-figure-sourcing-that-did-not-close-its-classes.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-032
**Defects:** none
**Moves:** warrant.evidence-integrity from 91.1 to 100

## Context & Purpose
Four specifications were written to bring five warrant classes to full figure sourcing. All four merged and the rollup still reports all five short. The work merged and the number it was for did not move.

## Acceptance Criteria
1. A specification naming a figure records that figure's value before and after.
2. A merge that does not move its named figure is reported rather than closing silently.
3. The blocking cases per class are listed with the class, not only in aggregate.
4. A class that cannot reach its threshold records the reason rather than having the threshold lowered.
