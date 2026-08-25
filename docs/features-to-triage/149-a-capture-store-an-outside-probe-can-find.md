---
generated-by: tailings
tailings-sources: [A277, R4]
reckon-sources: [REQ-111, REQ-113]
status: retired
triaged-as: PRO-0157
validated-by: REQ-111, REQ-113 via CASE-0472, CASE-0475, CASE-0476, CASE-0479, CASE-0480, CASE-0801
validated-rungs: metamorphic, outcome
validated-provider: none
---
# A capture store an outside probe can find

- origin: tailings pass over Wave 27, findings A277 and the standing R4 · 2026-08-25
- audience: Any audit run against this repository that did not write its own conventions
- platforms: n/a
- proposed-by-ai: false

## What and why
An external audit reports that this repository has no capture directory, over a tree holding fifty-four images. The probe tries a handful of conventional names at the repository root and reads no project configuration, and this repository keeps its captures somewhere else. The population was subsequently declared in the campaign's own configuration, which answered the question for this repository's own instruments and did nothing for anybody else's — a claim that it closed the external probe was made in the same session and was wrong.

The gap is discovery rather than data. A store that can only be found by reading a project's own config is a store that every outside reader reports as absent, and an audit that reports absent is one nobody can act on.

## Acceptance sketch
- The capture store is reachable from a conventional location without reading project configuration
- An outside probe following convention finds the same population the project's own instruments count
- The conventional location stays in step with the real one rather than drifting into a second copy
- A probe that still cannot find it reports the paths it tried
- Nothing is duplicated on disk to achieve this

## Assumptions made writing this
- Assuming discovery by convention rather than teaching each external probe, since the probes are not this project's to change
- Assuming the real location stays where it is and the conventional one points at it, rather than moving the store
