---
generated-by: reckon
reckon-sources: [SURF-007, REQ-007]
status: to-triage
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
