# PRO-0116: Native OCR and High-DPI Visual Region Inspector for Zoom Assertions

**ID:** PRO-0116
**Status:** Ready for Plan
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/108-native-ocr-and-high-dpi-zoom-inspector.md`

## Feature description

Extend `proctor_zoom` to support optional native Apple Vision-framework text recognition (OCR) and high-DPI contrast checks for rendered text in custom canvas views where the accessibility tree is unpopulated.

## Acceptance sketch

- `proctor_zoom` accepts optional `recognize_text: true` returning text bounding boxes and strings.
- Uses native `VNRecognizeTextRequest` with bounded timeouts (< 500ms).
- High-DPI scale factor is preserved and reported in zoom payloads.

## Assumptions made writing this

- Assuming Vision OCR runs synchronously within bounded timeouts.
