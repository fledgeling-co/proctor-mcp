---
sources: [REQ-097, REQ-098, REQ-099]
status: retired
---
# The reckoning tool mis-read this registry three ways

- origin: running the reckoning against proctor-mcp for the first time · 2026-08-22
- audience: every project on this machine that will run a reckoning after this one
- platforms: n/a — shared tooling, outside this repository
- research: none; each fault was measured against this repo's own registry

## What and why

The first reckoning run against this project produced a headline of "218 pieces of work remain — 183
product". That number is wrong, and the way it is wrong matters more than the number: it
over-reported, which is the opposite of the failure the tool exists to prevent, so nothing about its
own design would have caught it.

Three faults, each found by reading the rows rather than the summary. It crashed outright on a field
whose shape it did not expect — this registry carries evidence as a list of paths where the tool
assumes a string. It classed every defect record as broken without reading status, when 88 of 96 are
fixed. And it classed 75 briefs as unbuilt because they failed to join, when every one of them names
an item that shipped.

The second and third share a root worth naming: **an entity absent from the evidence is treated as an
entity that failed**, and those are different things. That is the same confusion the tool was built
to fix, arriving from the other direction.

This is shared tooling. The faults will reach whoever runs it next, and the crash means they will not
get a report at all.

## Acceptance sketch

- A reckoning run against a registry whose fields vary in shape produces a report rather than a
  traceback.
- A defect that has been fixed is not counted as remaining work.
- A brief whose item shipped is not counted as unbuilt, whether or not the join found it.
- A run whose join is weak says which items it therefore cannot class, rather than assigning them a
  class the join does not support.
- The headline figure is one somebody can act on without re-deriving it from the rows.

## Assumptions made writing this

- Assuming the fix belongs in the shared tool rather than in a per-repo adapter, because the next
  project to hit it will not know to write one.
- Assuming "unjoined" needs to be its own visible outcome rather than folded into unbuilt, since the
  two carry opposite conclusions and the reckoning's own report has to distinguish them.
- Assuming the crash is worth fixing even though a local patch already exists here, because a local
  patch is invisible to every other repository.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-097, REQ-098, REQ-099
- surface: SURF-023
- cases: CASE-0410, CASE-0411, CASE-0412, CASE-0413, CASE-0414, CASE-0415
- rungs reached: outcome
- provider: none
