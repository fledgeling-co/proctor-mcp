---
sources: [REQ-005]
status: retired
---
# Zoom native-resolution region crop

**Status:** untriaged · **Value:** medium · **Effort:** easy · **Source:** zavora-ai/computer-use-mcp (`zoom`)
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
A `zoom` action that returns a **native-resolution crop** of a named region or element, for reading small text or fine detail that's illegible in a whole-window capture (especially after vision-normalisation downscaling).

## Why (for computer use / testing)
A downscaled full capture loses the pixels a model needs to read a small label, a status glyph, or a numeric field. A native-res crop of just the region of interest restores that detail cheaply, without shipping a full 2x screenshot every time.

## Proposed approach on Proctor
- Accept a region (rect) or an AX element id; resolve to a frame.
- Return an SCK crop of that frame at native resolution, with the same freshness metadata as `capture`.
- Compose with `find` (locate the element) → `zoom` (read it) → `assert`.

## Scope
- In: region/element crop at native resolution, freshness metadata.
- Out: OCR of the crop (leave text extraction to the model / a separate concern).

## Success looks like
An element too small to read in a normalised full capture is legible in a `zoom` crop, and an assertion reads its value reliably.

## Dependencies / notes
- Thin addition over the existing `capture` / SCK path; pairs with 06.
- Licensing: reimplement; MIT source.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-005
- surface: SURF-001, SURF-006, SURF-007
- cases: CASE-0001, CASE-0005, CASE-0006, CASE-0007, CASE-0038, CASE-0064
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: none
