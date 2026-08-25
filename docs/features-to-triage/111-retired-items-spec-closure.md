---
sources: [DEF-215]
status: retired
---
# Retired Items Standalone Spec Closure for PRO-0022, PRO-0031, PRO-0039

- origin: intake sweep over DEF-215 (rows lacking standalone spec files) · 2026-08-24
- audience: pipeline auditors and automated ledger reconciliation tools
- platforms: n/a
- proposed-by-ai: true

## What and why
DEF-215 records that three historical rows in `docs/feature-specs/LEDGER.md` (PRO-0022, PRO-0031, PRO-0039) lack standalone spec files in `docs/specs/`, requiring explicit declarations in `## Rows with no spec file`. Authoring formal retrospective specs for these three retired/shipped items will provide complete 1-to-1 spec-to-ledger mapping and allow DEF-215 to close cleanly.

## Acceptance sketch
- `docs/specs/spec-PRO-0022.md`, `docs/specs/spec-PRO-0031.md`, and `docs/specs/spec-PRO-0039.md` exist and cite their historical briefs.
- Every ledger row in `docs/feature-specs/LEDGER.md` has a corresponding spec file on disk.
- DEF-215 transitions from open to fixed.

## Assumptions made writing this
- Assuming retrospective specs accurately summarize the historical commits without altering shipped behavior.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-100
- surface: SURF-024
- cases: CASE-0430, CASE-0431, CASE-0432, CASE-0433, CASE-0434, CASE-0435
- rungs reached: effect-witness, outcome
- provider: none
- reached through a closed defect: REQ-100 via DEF-215
