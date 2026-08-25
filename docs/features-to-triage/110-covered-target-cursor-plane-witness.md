---
sources: [REQ-043, CASE-0087]
status: retired
validated-by: REQ-043 via CASE-0053, CASE-0760
validated-rungs: effect-witness, outcome
validated-provider: none
---
# Covered-Target Cursor Plane Witness

- origin: intake sweep over BLOCK-0002 and REQ-043 (cursor plane over covered windows) · 2026-08-24
- audience: models actuating native windows when background windows may be occluded
- platforms: mac
- proposed-by-ai: true

## What and why
REQ-043 requires that no pointer is drawn over a window the person cannot see: where the pointer's plane cannot be confirmed and something covers the target, nothing draws. Currently CASE-0087 is inconclusive because Proctor cannot observe third-party driver cursor positions. Building an independent window-server layer witness that correlates CGWindowList bounds, occlusion order, and synthetic pointer coordinates will resolve BLOCK-0002 to a verified observable outcome.

## Acceptance sketch
- A window occlusion detector reads CGWindowList bounds and window levels before pointer actuation.
- When an actuation target is occluded by an overlapping window, the drawn pointer is suppressed and the yield/hold event is recorded.
- CASE-0087 transitions from inconclusive to observed with a deterministic test witness.
- BLOCK-0002 is unblocked in reckoning reports.

## Assumptions made writing this
- Assuming window occlusion calculations use CoreGraphics `CGWindowListCopyWindowInfo` without private APIs.
