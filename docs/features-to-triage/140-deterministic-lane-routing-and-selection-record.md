---
generated-by: tailings
tailings-sources: [T9]
reckon-sources: [REQ-130, REQ-151]
status: retired
---
# Deterministic Lane Routing and Selection Record

- origin: tailings audit T9 (18 reviewer lanes chosen without lane_pick.py) · 2026-08-25
- audience: Pipeline operators requiring auditable model lane selection across verification stages
- platforms: mac
- proposed-by-ai: false

## What and why
Verification and review stages route work to different model families for independent judgment. When lane selection happens by direct invocation rather than through a deterministic selector, the reasoning behind each routing decision goes unrecorded and cross-family independence cannot be audited afterward. A deterministic lane routing record captures which lane was selected, why it was chosen, and whether it was in-family or out-of-family.

## Acceptance sketch
- Lane selection produces a structured record naming the chosen family and the task shape
- In-family selections are flagged explicitly when independence was expected
- Fallback substitutions record the primary lane that was unavailable and the reason
- Selection records are persisted alongside verification evidence bundles
- Audit passes can reconstruct the routing chain for any verification verdict

## Assumptions made writing this
- Assuming lane selection uses a deterministic selector rather than ad-hoc direct invocation
- Assuming routing records are machine-readable for automated audit consumption

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-130, REQ-151
- surface: SURF-022, SURF-026, SURF-027, SURF-030
- cases: CASE-0063, CASE-0072, CASE-0073, CASE-0150, CASE-0151, CASE-0152
- rungs reached: effect-witness, metamorphic, outcome
- provider: none
