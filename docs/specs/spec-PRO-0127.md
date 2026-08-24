# Spec PRO-0127 — Guest VM Health Telemetry and Live Socket Probe

**Brief:** `docs/features-to-triage/119-guest-vm-health-telemetry-and-socket-probe.md`
**Status:** Ready for AI
**Created:** 2026-08-24
**Surfaces:** SURF-013
**Defects:** none

## Context & Purpose
Provide lightweight health telemetry and live socket heartbeat probes for guest VM instances to detect guest stalls and dropped SSH tunnels early during long-running campaigns.

## Acceptance Criteria
1. Periodic heartbeat probe checks guest agent responsiveness over unix socket stream forwarding.
2. Unresponsive guest queries trigger structured timeout diagnostics before runner deadlines fire.
3. Reconnection logic attempts channel recovery on transient network interruptions.
4. Guest health status metrics are exposed via `proctor_doctor` diagnostic output.
