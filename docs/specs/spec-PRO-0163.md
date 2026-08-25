# Spec PRO-0163 — A Specification Names the Figure It Will Move

**Brief:** `docs/features-to-triage/155-the-figure-sourcing-that-did-not-close-its-classes.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-032
**Defects:** none

## Context & Purpose
Four specifications were written to bring five warrant classes to full figure sourcing. All four merged and the rollup still reports all five short. The work merged and the number it was for did not move.

## A note on this spec's own **Moves:** line

It had one, declaring `warrant.evidence-integrity from 91.1 to 100`, and the gate
this spec builds refused the merge on the first run: the figure had not moved.
That refusal was correct and the declaration was wrong. None of the four clauses
below claims to move that class — they build the mechanism that checks such a
claim. The class is moved by raising the cases beneath it, which is PRO-0161's
work and is not yet done.

Recorded rather than quietly deleted, because a gate catching its own author on
the first use is the most useful thing it will ever do.

## Acceptance Criteria
1. A specification naming a figure records that figure's value before and after.
2. A merge that does not move its named figure is reported rather than closing silently.
3. The blocking cases per class are listed with the class, not only in aggregate.
4. A class that cannot reach its threshold records the reason rather than having the threshold lowered.
