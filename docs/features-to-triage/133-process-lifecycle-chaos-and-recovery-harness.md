---
generated-by: reckon
reckon-sources: [SURF-012, REQ-079]
status: to-triage
---
# Process Lifecycle Chaos and Recovery Harness

- origin: docs/.ideation/reckoning-intake-round4-trawl.md · 2026-08-24
- audience: Automated test suites evaluating agent resilience under severe process failures
- platforms: mac
- proposed-by-ai: true

## What and why
Evaluating daemon resilience under adverse execution conditions often requires complex manual fault injection. Without an automated harness, process recovery mechanisms remain unexercised during routine continuous integration runs. An automated chaos harness injects controlled process interruptions, descriptor exhaustion, and signal interruptions into test environments.

## Acceptance sketch
- Chaos harness triggers controlled process interruptions during active tool executions
- Daemon supervisor restarts crashed worker processes and restores state machine integrity
- Resource limits prevent cascading descriptor exhaustion across related processes
- Test reports document fault recovery latencies and integrity validation passes
- Post-test health sweeps verify zero orphaned child processes or leaked sockets

## Assumptions made writing this
- Assuming process fault injection operates within temporary sandboxed process trees
- Assuming recovery checks verify state consistency prior to resuming command dispatch
