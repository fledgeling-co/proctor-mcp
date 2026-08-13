# Vision-capture normalisation + reported scale factor

**Status:** untriaged · **Value:** medium · **Effort:** easy · **Source:** domdomegg/computer-use-mcp
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
An optional `capture` variant that pre-scales the image to the vision-API ceiling (~**1568px** long edge / **1.15MP**) before returning it, and reports the **exact scale factor** applied.

## Why (for computer use / testing)
When an oversized frame is handed to a vision model, the API **silently downsamples it**, and any coordinate the model returns is then in a different space from the pixels Proctor measured. That drift quietly corrupts pixel-plane assertions and tri-observer geometry. Doing the scaling ourselves, and reporting the factor, keeps the coordinate round-trip exact.

## Proposed approach on Proctor
- After the SCK capture, if either dimension exceeds the ceiling, downscale to fit and record `scale = out/in`.
- Return the scale factor next to the existing freshness metadata (frame status, dirty rects, content rect).
- Callers (and the set-of-marks step, 02) use the factor to map model coordinates back to logical/native space before asserting.

## Scope
- In: optional normalisation, reported scale factor, coordinate round-trip helper.
- Out: changing the default capture (normalisation is opt-in; raw capture stays the default so pixel assertions keep native resolution when they want it).

## Success looks like
A capture fed to a vision model comes back with coordinates that map exactly onto Proctor's native geometry, with no silent-downsample drift.

## Dependencies / notes
- Small, self-contained addition to the `capture` path.
- Prerequisite-adjacent to 02 (set-of-marks) and 07 (zoom) staying coordinate-honest.
- Licensing: reimplement; MIT source.
