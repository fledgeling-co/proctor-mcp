# Spec PRO-0164 — Judge Every Judgeable Capture

**Brief:** `docs/features-to-triage/156-two-captures-nobody-judged.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-027
**Defects:** none

## Context & Purpose
Six of eight judgeable captures carry a verdict. An unjudged capture is an uncompared one, and this is the one lineage pass that ratchets rather than blocks — which is where a figure stops being looked at.

## Acceptance Criteria
1. Every judgeable published capture carries a verdict against its reference.
2. The ratchet is raised to the count that clears, so a new unjudged capture shows immediately.
3. A capture that cannot be judged records what prevents it.
4. The judged fraction is published beside the published-capture count on every run.
