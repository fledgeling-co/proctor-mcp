# Guest VM Health Telemetry and Socket Probe

- origin: docs/features-to-triage/.ideation/reckoning-intake-trawl.md · 2026-08-24
- audience: Fleet orchestrators monitoring virtual machine guest responsiveness and connection health
- platforms: mac
- proposed-by-ai: true

## What and why
Long-running UI test campaigns on virtual machines can experience silent guest stalls, SSH connection drops, or agent crashes inside the guest OS. When a guest becomes unresponsive, test runners can hang indefinitely waiting for tool responses. A lightweight health telemetry probe continuously validates socket responsiveness and agent health to detect hung guests early and trigger automated restarts.

## Acceptance sketch
- Telemetry probe periodically queries guest agent liveness over the established communication channel
- Unresponsive guests trigger a structured timeout event before test runner deadlines expire
- Health status metrics record response latency and memory pressure indicators from the guest
- Connection recovery attempts to re-establish dropped communication channels transparently
- Persistent guest failures mark the virtual machine instance as unhealthy and alert the orchestrator

## Assumptions made writing this
- Assuming health checks use lightweight ping payloads to avoid interfering with active UI tests
- Assuming probe thresholds are configurable based on workload intensity and virtualization backend
