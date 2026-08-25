---
sources: [REQ-170, REQ-171, REQ-172, DEF-295]
status: retired
validated-by: REQ-170, REQ-171, REQ-172 via CASE-0670, CASE-0671, CASE-0672
validated-rungs: outcome
validated-provider: none
---
# Brief join rate optimization and retirement ladder

**Wave 19, brief 3.**

## What and why

Reckon 1.2.0 measures that only 26/102 (25.5%) of briefs in `docs/features-to-triage/` are joined to the registry with confidence 1.0. Below 50%, retirement claims are withheld.
Audit the unjoined briefs, populate `source` / `sources` frontmatter and structured citations across legacy specs, and raise the join rate past the 50% threshold to enable automated retirement verification.
