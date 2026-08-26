# Spec PRO-0169 — Waiting Without Polling

**Brief:** `docs/features-to-triage/161-polling-loop-suppression-and-notification-monitor.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-018
**Defects:** none

## Context & Purpose
Repeated identical polls spend a turn budget to learn nothing. The harness already notifies on completion, and a bounded until-loop covers what it does not.

## Acceptance Criteria
1. A wait on a condition uses an until-loop or the harness's own notification rather than repeated identical calls.
2. A repository sweep names any script polling on a fixed interval with no exit condition.
3. A bounded wait states its bound and what happens when the bound is reached.
4. The sweep prints how many wait sites it examined.
