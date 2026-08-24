---
generated-by: reckon
reckon-sources: [SURF-019, REQ-020]
status: to-triage
---

# iOS Simulator Boot Fixture Harness

- origin: docs/reckoning/2026-08-24-final/reckoning.md · 2026-08-24
- audience: Test campaign operators running mobile testing without physical iOS devices
- platforms: mac
- proposed-by-ai: false

## What and why
Test campaign verification for iOS device automation requires a running simulator instance to observe real app execution. Currently, tests run in environments without a booted simulator and cannot verify mobile UI actions on live view hierarchies. Providing a dedicated simulator fixture allows mobile automation tools to execute against simulated hardware without requiring physical connected devices.

## Acceptance sketch
- Simulator fixture detects when an existing device runtime is available
- Missing device runtimes produce a clear environment note rather than silent test skipping
- Simulator boot state transitions from shutdown to booted under automated control
- Test runs target the simulated device without affecting host system state
- Simulator teardown cleanly terminates the instance upon test completion

## Assumptions made writing this
- Assuming simulator lifecycle is managed via standard platform developer tools rather than custom virtualization engines
- Assuming tests execute against existing installed system runtimes rather than downloading runtime packages on demand
