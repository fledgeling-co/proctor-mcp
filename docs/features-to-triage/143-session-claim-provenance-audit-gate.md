---
generated-by: tailings
tailings-sources: [T3, T11, T17]
reckon-sources: [REQ-156, REQ-122]
status: retired
---
# Session Claim Provenance Audit Gate

- origin: docs/.ideation/tailings-intake-round1-trawl.md · 2026-08-25
- audience: Pipeline operators requiring every reported figure to trace to a command that produced it
- platforms: mac
- proposed-by-ai: true

## What and why
Reports summarizing verification results carry figures drawn from gate output, test counts, and coverage measurements. When a figure appears in a durable artifact without an earlier command producing it, downstream sessions plan from a number nobody measured. A provenance audit gate cross-references every reported figure against the command output that produced it before the report is committed.

## Acceptance sketch
- Audit gate extracts numeric figures from durable artifacts and delivery reports
- Each figure is matched against earlier command output in the same session
- Figures with no producing command are flagged before the artifact is committed
- Gate output names the artifact, the figure, and the line where it appears
- Clean gate runs record which figures were traced and how many were examined

## Assumptions made writing this
- Assuming figure extraction distinguishes measurements from identifiers and dates
- Assuming matching is order-bound so a later measurement cannot retroactively justify an earlier claim

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-122, REQ-156
- surface: SURF-024, SURF-031
- cases: CASE-0430, CASE-0431, CASE-0432, CASE-0433, CASE-0434, CASE-0435
- rungs reached: effect-witness, outcome
- provider: none
