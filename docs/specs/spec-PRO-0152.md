# Spec PRO-0152 — Instrument Availability Disclosure Reporter

**Brief:** `docs/features-to-triage/144-instrument-availability-disclosure-reporter.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
A pass that cannot separate 'the instrument was unavailable' from 'the instrument was ignored' manufactures findings, and manufactured findings are what get a verification skill switched off. The tailings degraded class exists for exactly this, and the reporter is its standing counterpart.

## Acceptance Criteria
1. Every instrument a run was asked to use is recorded with whether it resolved.
2. An instrument absent from the environment is disclosed rather than passed over in silence.
3. A substitution records the fallback that ran and what established the primary's absence.
4. An environment failure is distinguishable from a deliberate routing decision in the record.
