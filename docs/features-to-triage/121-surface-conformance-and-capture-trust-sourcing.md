---
generated-by: reckon
reckon-sources: [SURF-001, REQ-064]
status: to-triage
---

# Surface Conformance and Capture Trust Sourcing

- origin: docs/test-campaign/evidence.html · 2026-08-24
- audience: Quality engineers verifying visual fidelity and capture trustworthiness against design standards
- platforms: mac
- proposed-by-ai: false

## What and why
Quality assurance charters require every rendered UI surface to demonstrate strict conformance to design tokens and trustworthy frame capture. When visual captures lack verified frame status or source attribution, warrant gates cannot promote surface conformance classes to higher assurance tiers. A structured sourcing pass ties all remaining visual evidence figures to verified frame captures and published design tokens.

## Acceptance sketch
- Surface conformance measurements source token colors directly from the design token registry
- Capture trust records verify complete frame status for all published visual artifacts
- Visual comparison metrics report exact longhand styling properties without approximation
- Unsupported visual introspection channels are recorded as unread rather than false matches
- Warrant class rollup reaches full figure sourcing across all evaluated surfaces

## Assumptions made writing this
- Assuming visual comparison relies on deterministic structural and token extraction rather than fuzzy pixel diffing
- Assuming captured frames without complete status are marked unverified rather than treated as passes
