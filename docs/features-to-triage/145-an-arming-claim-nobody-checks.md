---
generated-by: tailings
tailings-sources: [A100]
reckon-sources: [REQ-046, REQ-130]
status: to-triage
---
# An arming claim nobody checks

- origin: tailings pass over Wave 27, finding A100 · 2026-08-25
- audience: Anyone reading a Done column and deciding whether to trust it
- platforms: n/a
- proposed-by-ai: false

## What and why
Every case in the campaign carries an `armedBy` string saying what was done to make it fail, and nothing reads one. A case was found naming a test as its arm where that test passes with the fix removed — the defect was real, the fix was real, the suite as a whole did bite, and the named test did not. An arming claim is the sentence a reader trusts when deciding whether a green case means anything, and it is currently prose.

The claim is checkable by construction rather than by review. An arm names a change and a test; applying the change and running that test should produce red. Where it does not, the case is resting on an arm it does not have, which is indistinguishable from a case nobody armed.

## Acceptance sketch
- Every case's arming claim is machine-readable enough to name what to change and what to run
- Applying the named change and running the named test produces a red result
- A claim whose named test stays green is reported with both, rather than counted as armed
- A claim that cannot be mechanically applied is reported as unverifiable rather than as armed
- The count of verified arms is published with its denominator beside the armed ratio

## Assumptions made writing this
- Assuming the arm is expressed as a change plus a test to run, rather than as free prose
- Assuming a claim that cannot be applied is reported rather than dropped, since a silently skipped claim is the failure being fixed
