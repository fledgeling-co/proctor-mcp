# Native OCR and High-DPI Visual Region Inspector for Zoom Assertions

- origin: intake sweep over visual inspection tools and PRD Section 1 · 2026-08-24
- audience: models verifying small UI elements, text labels, and canvas renders
- platforms: mac
- proposed-by-ai: true

## What and why
`proctor_zoom` provides native-resolution region crops from ScreenCaptureKit frames. Extending the zoom capability to include optional native Vision-framework text recognition (OCR) and high-DPI contrast checks allows models to verify rendered text inside custom canvas views or non-standard AppKit controls where the accessibility tree is unavailable or unpopulated.

## Acceptance sketch
- `proctor_zoom` accepts an optional `recognize_text: true` parameter returning recognized text bounding boxes.
- Optical recognition leverages Apple's native `VNRecognizeTextRequest` without external dependencies.
- High-DPI Retina scale factor is preserved and reported in zoom responses.
- Tested across native AppKit text fields, custom canvas renders, and dark/light system themes.

## Assumptions made writing this
- Assuming Vision OCR runs synchronously within bounded timeouts (< 500ms for region crops).
- Assuming OCR recognition is an optional tool enhancement that degrades gracefully if disabled.
