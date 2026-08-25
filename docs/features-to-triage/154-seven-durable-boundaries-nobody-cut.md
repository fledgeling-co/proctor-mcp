---
generated-by: test-campaign
campaign-sources: [campaign.check.journeys]
reckon-sources: [REQ-035, REQ-039]
status: to-triage
---
# Seven durable boundaries nobody cut

- origin: full campaign run, the journey ledger · 2026-08-25
- audience: Anyone relying on a multi-step task surviving an interruption
- platforms: mac
- proposed-by-ai: false

## What and why
Ten journeys are modelled and forty-three of fifty durable boundaries are cut. The seven that are not sit across four journeys, and those four are recorded as non-critical for exactly that reason — not because the work matters less, but because claiming critical without the cuts would be claiming a completeness the evidence has not got.

An uncut journey proves the happy path and says nothing about partial completion, which is where the measured fault corpus for this shape lives. The four affected are the ones where a run can stop halfway: the audit trail with no independent witness of its bytes on disk and nothing reading its verdict off a surface, the guest lane whose refusal never reaches a person, the background actuation nobody sees, and the simulator lane whose live half ran once.

## Acceptance sketch
- Each uncut boundary is either cut or recorded as structurally uncuttable with the reason
- A journey whose five cuts exist is promoted to critical, and the promotion is evidenced rather than asserted
- A cut names the observable it reads and the channel, distinct from the one that performed the step
- The boundaries-cut fraction is published on every run whether it moved or not
- A journey that cannot reach a boundary says which and why, permanently

## Assumptions made writing this
- Assuming critical is earned by the cuts existing rather than declared by importance, since the flag's meaning in this vocabulary is what it owes
- Assuming a structurally uncuttable boundary is recorded rather than the journey being demoted, because demotion hides the gap
