# Spec PRO-0158 — Reclassification Record for an Audit Pass

**Brief:** `docs/features-to-triage/150-an-auditor-clearing-its-own-gate.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
A verification pass classified four claims as contradicted, corrected the artifacts, then reclassified the same rows as substantiated, clearing its own gate. The classification file is the gate's input and the pass is its only writer.

## Acceptance Criteria
1. A row's class change is recorded with what it was before.
2. A row that moved from a blocking class to a clean one after the same pass edited its artifact is reported.
3. The gate's verdict distinguishes rows that were never blocking from rows that stopped blocking.
4. The record survives into the committed report.
