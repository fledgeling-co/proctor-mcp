# Spec PRO-0156 — Ledger Status Distribution

**Brief:** `docs/features-to-triage/148-nothing-counts-the-ledgers-status-words.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-024
**Defects:** none

## Context & Purpose
A wave was reported as every row merged over a ledger holding two rows in a different terminal state. The gate checks specs-on-disk and git agreement, never how the statuses are distributed.

## Acceptance Criteria
1. The status distribution across all ledger rows is published, summing to the row count.
2. A terminal status that is not the merged one is named rather than folded into it.
3. A status word the gate does not recognise is reported rather than counted as a known one.
4. The outstanding count and the merged count are stated as separate figures.
