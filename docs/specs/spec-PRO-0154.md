# Spec PRO-0154 — Verdict-Word Reading in the Provenance Gate

**Brief:** `docs/features-to-triage/146-a-gate-that-reads-the-number-and-not-the-word.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
A committed evidence page stated a test run failed under a heading saying the work was complete, and the provenance gate passed over it: it matches a figure and never reads the verdict the same sentence carries.

## Acceptance Criteria
1. A stated figure is read together with the verdict word in the same sentence.
2. A page asserting a failure under a heading asserting success is reported.
3. A verdict word the scanner cannot classify is reported rather than ignored.
4. The report distinguishes a wrong number from a right number beside a wrong word.
