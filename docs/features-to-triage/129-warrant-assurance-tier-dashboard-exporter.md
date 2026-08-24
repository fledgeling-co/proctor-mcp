---
generated-by: reckon
reckon-sources: [SURF-025, REQ-102]
status: retired
---

# Warrant Assurance Tier Dashboard Exporter

- origin: docs/features-to-triage/.ideation/reckoning-intake-round3-trawl.md · 2026-08-24
- audience: Release managers and quality leads monitoring multi-class charter assurance levels
- platforms: mac
- proposed-by-ai: true

## What and why
Tracking defect charter progress across multiple assurance classes requires inspecting complex JSON report files across different tools. Without an integrated dashboard, release stakeholders must manually correlate assay results, oracle coverage, and figure sourcing rates. A standalone dashboard exporter generates a self-contained visual status summary showing class tiers, promotion blockers, and ratchet trends.

## Acceptance sketch
- Dashboard exporter reads charter configurations, health records, and promotion proposals
- Interactive visual cards display current tier status and figure sourcing percentages for each class
- Promotion blockers are highlighted with specific corrective actions for each blocked class
- Historical ratchet progression is visualized as a trend line across recent campaign runs
- Standalone report generates as a single portable file with zero external network dependencies

## Assumptions made writing this
- Assuming dashboard generation operates as a read-only post-processing step after campaign runs
- Assuming visual styling adheres to project theme and design token palettes
