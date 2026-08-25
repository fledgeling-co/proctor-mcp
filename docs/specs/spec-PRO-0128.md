# Spec PRO-0128 — Native OCR and High-DPI Inspection Fixture

**Brief:** `docs/features-to-triage/120-native-ocr-and-high-dpi-inspection-fixture.md`
**Status:** Merged
**Created:** 2026-08-24
**Surfaces:** SURF-007
**Defects:** BLOCK-0006

## Context & Purpose
Provide a high-density visual inspection fixture with deterministic OCR element bounding box normalization across single and double scale factor displays, resolving unmeasured zoom and inspect cases in test campaigns.

## Acceptance Criteria
1. OCR engine processes screen captures across 1x and 2x backing scale factors.
2. Element text recognition returns bounding box coordinates in normalized points.
3. Zoom region queries extract pixel-accurate sub-rectangles for visual assertion.
4. Visual inspection errors provide diagnostic coordinate overlays.
