# Spec PRO-0165 — Non-Zero Class Partition Reporting

**Brief:** `docs/features-to-triage/157-non-zero-class-partition-breakdown-reporter.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
A gate that prints a partition and a summary that reports only its total are the same green. The partition's non-zero classes must survive into whatever a reader sees.

## Acceptance Criteria
1. Every non-zero class a gate prints is carried into the summary derived from it.
2. The classes sum to the total the summary quotes.
3. A class the reporter cannot recognise is named rather than folded into a known one.
4. A summary quoting a total with no partition beside it is refused.
