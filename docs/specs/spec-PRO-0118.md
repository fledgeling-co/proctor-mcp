# PRO-0118: Covered-Target Cursor Plane Witness

**ID:** PRO-0118
**Status:** Ready for Plan
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/110-covered-target-cursor-plane-witness.md`

## Feature description

Provide an independent window-server layer witness that correlates CGWindowList bounds, occlusion order, and synthetic pointer coordinates, asserting that no pointer draws over an occluded window and unblocking BLOCK-0002.

## Acceptance sketch

- Window occlusion detector reads CGWindowList bounds and window levels before pointer actuation.
- When an actuation target is occluded by an overlapping window, the drawn pointer is suppressed and the yield/hold event is recorded.
- CASE-0087 transitions from inconclusive to observed with a deterministic test witness.
- BLOCK-0002 is unblocked in reckon reports.

## Assumptions made writing this

- Assuming window occlusion calculations use CoreGraphics `CGWindowListCopyWindowInfo` without private APIs.
