---
generated-by: tailings
tailings-sources: [A283]
reckon-sources: [REQ-045, REQ-130]
status: to-triage
---
# A gate that loses which check failed

- origin: tailings pass over Wave 27 · 2026-08-25
- audience: Whoever has to act on a red gate they did not watch run
- platforms: n/a
- proposed-by-ai: false

## What and why
A standing gate reported one failure out of several hundred checks, then reported none on three consecutive re-runs. Which check failed could not be established: the gate prints its failures to the terminal and keeps nothing, and the line had already scrolled. So the run is known to have gone red and is not known to have gone red about anything.

Two faults sit together here and only one of them is flakiness. A gate that keeps no record of its own failures makes every intermittent result unexplainable, and an unexplainable red is the one people learn to re-run rather than read. Keeping the failing check's identity costs a file; not keeping it costs the next person the whole investigation.

## Acceptance sketch
- A failing check is written to a durable record naming which check it was, not only to the terminal
- A run that passes after a failure leaves both records, so an intermittent result is visible as one
- The record carries enough to re-run the single failing check on its own
- A gate that has gone red and green over the same tree is reported as unreproducible rather than as green
- The count of unreproducible results is published rather than smoothed away by a re-run

## Assumptions made writing this
- Assuming the record is per-run rather than overwritten, since an overwritten record loses exactly the intermittent case
- Assuming re-running is not treated as resolution, because a re-run that passes is not evidence the first result was wrong
