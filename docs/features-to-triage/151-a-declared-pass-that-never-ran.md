---
generated-by: test-campaign
campaign-sources: [vacuity-check.blind]
reckon-sources: [REQ-045, REQ-130]
status: to-triage
---
# A declared pass that never ran

- origin: full campaign run, the vacuity check's blind pass · 2026-08-25
- audience: Anyone reading a gate's green and taking it for the whole gate
- platforms: n/a
- proposed-by-ai: false

## What and why
One of the vacuity check's three passes reported that it had no corpus, for the whole life of this campaign, because the configuration field naming its population was never declared. Its vocabulary had been researched, measured against a sample and defended against an out-of-family reviewer — and it sat beside a pass that was not executing. Every recorded "0 findings" for that instrument was true of two passes out of three, and nothing said so.

A pass that cannot run and a pass that ran and found nothing produce the same line in a summary unless the summary distinguishes them. The instrument here does say NOT RUN when asked directly; what was missing is anything reading that back. A gate whose sub-passes can silently opt out is a gate whose green means less than it appears to, and the amount less is unknowable from the outside.

## Acceptance sketch
- Every pass a configuration declares reports whether it executed and over what population
- A pass that could not run holds the gate rather than contributing zero findings
- The summary a reader sees distinguishes "found nothing" from "could not look"
- A configuration field whose absence disables a pass is reported at the point the pass is skipped
- The population each pass examined is published beside its finding count

## Assumptions made writing this
- Assuming a pass that cannot run should block rather than warn, since a warning in a passing run is the thing that went unread here
- Assuming the check belongs beside the instrument rather than in a wrapper, so a new pass inherits it
