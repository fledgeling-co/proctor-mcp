# PRO-0117: Guest VM Lifecycle and Multi-Session Attachment Oracle

**ID:** PRO-0117
**Status:** Ready for Plan
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/109-guest-vm-lifecycle-and-attachment-oracle.md`

## Feature description

Multi-session queue testing harness for REQ-037..REQ-040 simulating concurrent session queueing, non-evicting queue policies, and fair slot release without requiring physical secondary VM boots.

## Acceptance sketch

- Multi-session queue test simulates 3 concurrent requests against a 2-slot guest lane.
- First 2 acquire attachments; third waits cleanly and acquires upon release without eviction.
- Provider reporting `darwin` assigns native witness tier.
- REQ-037, REQ-038, REQ-039, and REQ-040 transition to observed.

## Assumptions made writing this

- Assuming multi-session queue testing runs with simulated socket endpoints in CI/headless suites.
