# Spec PRO-0159 — Every Declared Pass Proves It Ran

**Brief:** `docs/features-to-triage/151-a-declared-pass-that-never-ran.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
One of the vacuity check's three passes reported it had no corpus for the life of this campaign, because the field naming its population was never declared. Every recorded '0 findings' was true of two passes out of three.

## Acceptance Criteria
1. Every pass a configuration declares reports whether it executed and over what population.
2. A pass that could not run holds the gate rather than contributing zero findings.
3. The summary distinguishes 'found nothing' from 'could not look'.
4. The population each pass examined is published beside its finding count.
