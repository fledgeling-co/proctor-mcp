---
sources: [SURF-015, REQ-001]
status: retired
superseded-by: docs/specs/spec-PRO-0116.md
---
# Native OCR and High-DPI Visual Region Inspector for Zoom Assertions

- origin: intake sweep over visual inspection tools and PRD Section 1 · 2026-08-24
- audience: models verifying small UI elements, text labels, and canvas renders
- platforms: mac
- proposed-by-ai: true

## What and why
`proctor_zoom` provides native-resolution region crops from ScreenCaptureKit frames. Extending the zoom capability to include optional native Vision-framework text recognition (OCR) and high-DPI contrast checks allows models to verify rendered text inside custom canvas views or non-standard AppKit controls where the accessibility tree is unavailable or unpopulated.

## Acceptance sketch
- `proctor_zoom` accepts optional `recognizeText: true` parameter
- Vision-framework OCR extracts text lines, bounding boxes in points, and confidence scores
- `ZoomOCRResult` is included in the JSON return structure alongside crop metadata
- High-DPI regions are scaled accurately to avoid point-to-pixel offset distortion
- Text contrast ratios (foreground vs background) are calculated for recognized text regions

## Assumptions made writing this
- Assuming native Vision framework is available on macOS 14.0+ without external binary dependencies
- Assuming OCR operates synchronously on the cropped PNG memory buffer within a tight execution budget (<50ms)
