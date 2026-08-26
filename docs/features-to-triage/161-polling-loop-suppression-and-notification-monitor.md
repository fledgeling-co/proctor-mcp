---
generated-by: tailings
tailings-sources: [T13]
reckon-sources: [REQ-045, REQ-130]
status: triaged
---
# Polling Loop Suppression and Notification Monitor

- origin: tailings audit probe T13 · 2026-08-25
- audience: Operators and automated agents executing long-running builds and asynchronous tests
- platforms: n/a
- proposed-by-ai: false

## What and why
Automated agents frequently execute repetitive shell polling loops to wait for background tasks or build completions. These tight polling loops consume turn budgets, generate high command volume, and clutter transcripts without providing new information. A polling loop suppression and notification monitor replaces blind polling with event-driven until-loops and background monitors that stream only actionable state transitions.

## Acceptance sketch
- Asynchronous task monitors stream notifications only when target state transitions occur
- Repetitive polling loops in shell scripts are replaced with bounded until-loops
- Background task completion hooks notify the calling agent directly upon process exit
- Identical repetitive poll outputs are suppressed from the conversation transcript
- Telemetry records the reduction in unnecessary polling commands across long-running runs

## Assumptions made writing this
- Assuming the runtime environment supports background process monitoring and exit notifications
- Assuming until-loops include appropriate backoff intervals to prevent resource contention
