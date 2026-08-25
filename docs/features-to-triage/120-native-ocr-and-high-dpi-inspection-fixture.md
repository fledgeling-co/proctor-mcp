---
generated-by: reckon
reckon-sources: [SURF-007, REQ-007]
status: retired
---
# Native OCR and High-DPI Inspection Fixture

- origin: docs/reckoning/2026-08-24-final/reckoning.md · 2026-08-24
- audience: Test campaign operators verifying visual element extraction across high-density displays
- platforms: mac
- proposed-by-ai: false

## What and why
Visual inspection tools need to locate text elements and UI controls accurately on Retina and scaled displays. When display scaling differs between test machines, coordinate bounding boxes can drift relative to rendered pixel grids. A high-density visual inspection fixture provides deterministic OCR text matching and bounding box correlation across all supported display scaling ratios.

## Acceptance sketch
- Inspection fixture processes screen captures across single and double scale factors
- Text recognition extracts element labels and bounds deterministically
- Zoomed region queries return pixel-accurate sub-rectangles for visual assertion
- Inspection failures provide element coordinate overlays for rapid diagnosis
- Text detection operates reliably without external internet connectivity

## Assumptions made writing this
- Assuming native system text recognition frameworks are utilized rather than third-party cloud vision services
- Assuming coordinate transforms normalize backing scale factors transparently to caller interfaces

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-007
- surface: SURF-004, SURF-005
- cases: CASE-0004, CASE-0008, CASE-0009, CASE-0010, CASE-0021, CASE-0030
- rungs reached: effect-witness, metamorphic, outcome
- provider: CGEventTap in Sources/ProctorAgent/Session/ContentionMonitor.swift and Sources/ProctorAgent/Overlay/TakeoverOverlay.swift; NSEvent.addGlobalMonitorForEvents
