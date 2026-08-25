---
generated-by: tailings
tailings-sources: [T15]
reckon-sources: [REQ-065, REQ-130]
status: to-triage
---
# Instrument Availability Disclosure Reporter

- origin: docs/.ideation/tailings-intake-round1-trawl.md · 2026-08-25
- audience: Operators who name a tool and need to know whether it was available or silently skipped
- platforms: mac
- proposed-by-ai: true

## What and why
When an operator names a specific instrument and that instrument is absent from the running session, the absence can pass unmentioned while adjacent work continues. The operator then believes the named instrument ran. An availability disclosure reporter records every instrument named in a request, whether it resolved, and what stood in for it when it did not.

## Acceptance sketch
- Reporter extracts instrument names from operator requests during a session
- Each named instrument is checked for availability in the running environment
- Unavailable instruments are disclosed explicitly rather than passed over silently
- Substitutions record the fallback that ran and the reason the primary was unavailable
- Disclosure records distinguish environment failures from deliberate routing decisions

## Assumptions made writing this
- Assuming instrument resolution checks the session manifest rather than assuming presence
- Assuming disclosure appears in the operator-facing reply rather than only in a log file
