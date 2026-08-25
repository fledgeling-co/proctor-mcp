---
generated-by: tailings
tailings-sources: [T11]
reckon-sources: [REQ-045, REQ-120]
status: to-triage
---
# Non-Zero Class Partition Breakdown Reporter

- origin: tailings audit probe T11 · 2026-08-25
- audience: Engineers reading gate and census summaries who need the full breakdown of non-zero sub-classes
- platforms: n/a
- proposed-by-ai: false

## What and why
When a gate prints an aggregate total along with non-zero sub-classes (such as unhandled categories, unexamined modules, or unarmed cases), downstream summaries often condense the output into a single headline number. This hides critical sub-class distributions, causing operators to overlook actionable categories like source-analysis rungs or unverified arms. A non-zero class partition breakdown reporter ensures that all non-zero sub-classes are explicitly presented alongside the aggregate total in every summary.

## Acceptance sketch
- Gate reporters extract and parse all non-zero sub-class counts from tool outputs
- Delivery summaries format and display the complete partition of non-zero sub-classes
- Sub-classes with zero counts are excluded to maintain clean and concise reporting
- Downstream summary documents fail validation if any printed non-zero sub-class is omitted
- Aggregate totals are verified to match the exact mathematical sum of the reported sub-classes

## Assumptions made writing this
- Assuming sub-class labels are standardized across campaign and reckoning tools
- Assuming missing sub-class counts in a summary are treated as reporting defects
