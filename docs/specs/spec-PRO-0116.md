# PRO-0116: Native OCR and High-DPI Visual Region Inspector for Zoom Assertions

**ID:** PRO-0116
**Status:** Developer Review
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/108-native-ocr-and-high-dpi-zoom-inspector.md`
**Defects:** DEF-315
**Requirements:** REQ-190
**Cases:** CASE-0730..CASE-0734
**Surfaces:** SURF-037

## Feature description

Extend `proctor_zoom` to support optional native Apple Vision-framework text recognition (OCR) and high-DPI contrast checks for rendered text in custom canvas views where the accessibility tree is unpopulated:

1. **Native Apple Vision OCR (`VisionOCR.swift` & `SessionZoom.swift`):** Integrates Apple's native `VNRecognizeTextRequest` to extract recognized text strings, confidence scores, and exact bounding boxes from cropped pixel regions without third-party dependencies.
2. **High-DPI Retina Scale Preservation:** Preserves display scale factor (e.g. 2.0 on Retina displays) and maps normalized Vision bounding boxes to both native pixel coordinates (`boundingBox`) and window points (`pointBox`).
3. **High-DPI Text Contrast Verification:** Employs `PixelProbe` to sample dominant background and contrasting text foreground colors in each recognized bounding box, computing WCAG contrast ratios and evaluating compliance against standard thresholds.
4. **Bounded Execution Timeout (< 500ms):** Bounded execution monitoring ensures OCR completes within strict timeouts (< 500ms) suitable for interactive agent inspection loops.
5. **Tool Schema & Dispatch Integration:** Adds `recognize_text` (and alias `recognizeText`) to `proctor_zoom` input schema in `ToolCatalogue.swift` and `ToolOutputSchemas.swift`, maintaining backward compatibility and zero overhead when disabled.

## Acceptance sketch

- `proctor_zoom` accepts optional `recognize_text: true` returning text bounding boxes and strings.
- Uses native `VNRecognizeTextRequest` with bounded timeouts (< 500ms).
- High-DPI scale factor is preserved and reported in zoom payloads.
- High-DPI contrast check measures foreground/background luminance and computes WCAG contrast ratio for recognized text blocks.

## Assumptions made writing this

- Assuming Vision OCR runs synchronously within bounded timeouts (< 500ms for region crops).
- Assuming OCR recognition is an optional tool enhancement that degrades gracefully if disabled.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-315 | Missing native Vision OCR and high-DPI text contrast verification in zoom crops for unpopulated accessibility trees and custom canvas views | fixed |
