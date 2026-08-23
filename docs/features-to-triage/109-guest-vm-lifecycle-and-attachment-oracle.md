---
sources: [REQ-037, REQ-038, REQ-039, REQ-040]
---
# Guest VM Lifecycle and Multi-Session Attachment Oracle

- origin: intake sweep over REQ-037..REQ-040 and VM queueing requirements · 2026-08-24
- audience: multi-agent test fleets running concurrent macOS VM tests
- platforms: mac
- proposed-by-ai: true

## What and why
Proctor supports macOS guest VM testing over `lume`, `tart`, and `prlctl` with a two-slot concurrency cap. While basic guest attachment was settled live on a lume guest in Wave 10, multi-session queueing under contention (REQ-038) and never-evicting queue policies (REQ-039) currently stand on unit mocks. Providing an end-to-end simulated two-slot queue harness will witness concurrent session queuing, socket forwarding, and fair release without requiring physical second VM boots.

## Acceptance sketch
- A multi-session queue test simulates 3 concurrent session requests against a 2-slot guest lane.
- First two sessions acquire guest attachments; the third waits cleanly and acquires upon release without eviction.
- Guest platform detection correctly assigns the native witness tier when provider reports `darwin`.
- REQ-037, REQ-038, REQ-039, and REQ-040 transition from self-reported to observed.

## Assumptions made writing this
- Assuming multi-session queue testing can run with simulated socket endpoints in CI/headless suites.
- Assuming live VM boots are reserved for full integration passes.
