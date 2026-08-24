# PRO-0117: Guest VM Lifecycle and Multi-Session Attachment Oracle

**ID:** PRO-0117
**Status:** Developer Review
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/109-guest-vm-lifecycle-and-attachment-oracle.md`
**Defects:** DEF-320
**Requirements:** REQ-037..REQ-040, REQ-195
**Cases:** CASE-0750..CASE-0754
**Surfaces:** SURF-038

## Feature description

Multi-session queue testing harness for REQ-037..REQ-040 simulating concurrent session queueing, non-evicting queue policies, and fair slot release without requiring physical secondary VM boots:
1. **Multi-Session 3-Caller Queue Simulation (`GuestMultiSessionQueueWitnessTests.swift`):** Simulates 3 concurrent requests against a 2-slot macOS guest lane. Asserts that the first two acquire attachments while the third cleanly joins the waiting queue.
2. **Fair Slot Release & Non-Evicting Policy Enforcement:** Asserts that when an active session releases its attachment, the waiting session cleanly acquires the freed slot without any running VM being evicted or stopped.
3. **Darwin Platform & Native Witness Tier Derivation:** Validates that provider reporting `darwin` maps to macOS platform and assigns the native witness tier, enabling AX tree assertions to evaluate without being skipped as delegated.
4. **Isolated Guest Socket Forwarding:** Asserts that concurrent sessions forward tool calls to their respective guest links independently while the host actuator performs zero steps.
5. **Elevating REQ-037..REQ-040 to Observed:** Transitions REQ-037, REQ-038, REQ-039, and REQ-040 from self-reported/unit-mocked to observed with explicit test witnesses.

## Acceptance sketch

- Multi-session queue test simulates 3 concurrent requests against a 2-slot guest lane.
- First 2 acquire attachments; third waits cleanly and acquires upon release without eviction.
- Provider reporting `darwin` assigns native witness tier.
- REQ-037, REQ-038, REQ-039, and REQ-040 transition to observed.

## Progress — PRO-0117

**Defects:** DEF-320
**Requirements:** REQ-037..REQ-040, REQ-195
**Cases:** CASE-0750..CASE-0754
**Surfaces:** SURF-038

- Implemented `Tests/ProctorAgentTests/GuestMultiSessionQueueWitnessTests.swift` simulating 3 concurrent callers against a 2-slot guest lane.
- Asserted fair acquisition, clean waiting queue entry, and acquisition upon slot release without VM eviction.
- Asserted that provider reporting `darwin` assigns macOS platform and native witness tier, allowing full AX tree assertion evaluation.
- Verified socket forwarding isolation across concurrent guest sessions with zero host actuations.
- Registered SURF-038, REQ-195, DEF-320, and CASE-0750..CASE-0754, transitioning REQ-037..REQ-040 to observed.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-320 | Multi-session guest VM queue contention, never-evicting policy under slot exhaustion, and darwin native witness tier assignment lacked an end-to-end multi-session queue witness harness | fixed |
