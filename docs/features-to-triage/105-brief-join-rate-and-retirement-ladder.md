---
sources: [REQ-170, REQ-171, REQ-172, DEF-295]
status: retired
---
# Brief join rate optimization and retirement ladder

**Wave 19, brief 3.**

## What and why

Reckon 1.2.0 measures that only 26/102 (25.5%) of briefs in `docs/features-to-triage/` are joined to the registry with confidence 1.0. Below 50%, retirement claims are withheld.
Audit the unjoined briefs, populate `source` / `sources` frontmatter and structured citations across legacy specs, and raise the join rate past the 50% threshold to enable automated retirement verification.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-170, REQ-171, REQ-172
- surface: SURF-033
- cases: CASE-0670, CASE-0671, CASE-0672
- rungs reached: outcome
- provider: none
