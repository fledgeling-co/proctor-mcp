---
generated-by: reckon
reckon-sources: [SURF-007, REQ-007]
status: retired
---
# High-DPI Display Scale Factor Injection Helper

- origin: docs/features-to-triage/.ideation/reckoning-intake-round2-trawl.md · 2026-08-24
- audience: Automated test suites verifying UI rendering across diverse display densities
- platforms: mac
- proposed-by-ai: true

## What and why
Testing UI appearance across standard and high-density displays typically requires physical hardware monitors with different pixel densities. When testing on a single CI machine, display scale factors remain fixed, leaving scaling bugs undetected. A scale factor injection helper simulates different display density configurations in memory during headless and visual test runs.

## Acceptance sketch
- Scale factor helper injects synthetic display density settings into rendering test harnesses
- UI layout engines recompute element frames and padding according to the active scale factor
- Visual assertions verify asset selection and pixel snap alignment at fractional scale factors
- Injected scale factor state resets automatically upon test completion
- Density configuration helpers provide standard presets for common desktop and mobile displays

## Assumptions made writing this
- Assuming display scale simulation operates via window server environment overrides where supported
- Assuming visual test assertions compare layout geometry independently from raster resolution

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-007
- surface: SURF-004, SURF-005
- cases: CASE-0004, CASE-0008, CASE-0009, CASE-0010, CASE-0021, CASE-0030
- rungs reached: effect-witness, metamorphic, outcome
- provider: CGEventTap in Sources/ProctorAgent/Session/ContentionMonitor.swift and Sources/ProctorAgent/Overlay/TakeoverOverlay.swift; NSEvent.addGlobalMonitorForEvents
