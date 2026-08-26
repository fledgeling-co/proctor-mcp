---
generated-by: tailings
tailings-sources: [continuous-audit]
reckon-sources: [REQ-045, REQ-046]
status: triaged
---
# Autonomous Audit Worklist Continuous Verifier

- origin: tailings audit companion proposal · 2026-08-25
- audience: Repository maintainers who need continuous verification of transcript and registry integrity
- platforms: n/a
- proposed-by-ai: true

## What and why
The tailings audit tool provides comprehensive closed-world reconciliation of session assertions against repository facts, but typically runs only at session close. Claim drifts, unverified numbers, and contradictory statements can accumulate unnoticed across long multi-wave runs. An autonomous audit worklist continuous verifier executes background sanity checks across newly touched artifacts and registries, surfacing claim discrepancies in real time before they propagate into downstream planning files.

## Acceptance sketch
- Continuous verifier monitors modified durable artifacts after each wave completion
- Assertion claims in updated delivery notes are cross-referenced against live registry counts
- Contradictory statements or drifted numbers trigger immediate actionable warnings
- Audit worklist state is maintained incrementally rather than reconstructed from scratch
- Pre-merge checks verify that all newly introduced claims are substantiated by repo facts

## Assumptions made writing this
- Assuming the verifier operates as a fast, non-blocking check following wave merges
- Assuming claim validation relies on deterministic registry lookups rather than model inference
