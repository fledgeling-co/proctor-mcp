# PRO-0034: Scroll moves by what was asked

**ID:** PRO-0034
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-17
**Branch:** `ai/pro-0034`

## Feature description

Make a scroll delta mean lines instead of a crude `delta / 100` fraction, and order the rungs so precise bar writes outrank the coarse by-page action unless the caller specifically requested a page-sized move.

## What was built

1. **Units are lines, not percent.** A bar's `AXValue` is a fraction of the document `0.0 ... 1.0`. A line is mapped to `1.0 / linesPerPage`, where `linesPerPage` is derived from the enclosing scroll area's viewport height divided by line height (falling back to 16 lines per page). Line height is read from the element's frame if it is between 8 and 40 pt, otherwise defaulting to 16 pt.
2. **Precise bar writes outrank page actions.** `writeBar` and `scrollEnclosingArea` are attempted before checking for `AXScrollDownByPage` / `AXScrollUpByPage`. The page action is only preferred if the requested delta is at least half a page (`abs(delta) >= linesPerPage * 0.5`).
3. **Synthetic wheel fallback uses the same line height.** `wheelPixels(delta, lineHeight)` maps `delta * lineHeight` into pixels, ensuring a delta of 3 lines corresponds to the same distance whether executed via the accessibility plane or the synthetic wheel event.

## Evidence

`BackgroundRouteTests.swift` (`ActuationRuleTests`):
- `scrollFractionClamps`: clamping at 0 and 1.
- `lineAndPageDerivation`: line height estimation, lines per page calculation, page action threshold, and wheel pixel mapping.

Gate: run `./scripts/test.sh`.
