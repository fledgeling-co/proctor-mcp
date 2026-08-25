---
sources: [REQ-006, REQ-028]
status: retired
validated-by: REQ-006, REQ-028 via CASE-0008, CASE-0030, CASE-0032, CASE-0065, CASE-0089
validated-rungs: effect-witness, outcome
validated-provider: NSPanel over the window server in Sources/ProctorAgent/Overlay/RunHUDPanel.swift, readable back through CGWindowListCopyWindowInfo
---
# Pointer / target overlay in captures

**Status:** untriaged · **Value:** low-med · **Effort:** low · **Source:** both surveyed repos (domdomegg crosshair-in-screenshot; zavora `agent_pointer`)
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
Composite the action's **target point** (the element/coordinate a step acted on) into `flow` and `stability` capture artifacts, as a small overlay marker.

## Why (for computer use / testing)
ScreenCaptureKit omits the system pointer, so a captured artifact gives no visual answer to "where did that step act?". Drawing the target point into the artifact makes a flow/stability recording legible to a human reviewer and to a vision consumer diffing runs.

## Important caveat (don't overclaim)
Proctor drives via AX / Apple Events and **does not move the system cursor**. So this is a **pixel-plane annotation of the intended target**, not a picture of a real moving cursor. Frame it honestly as "where the step acted", never as a live cursor.

## Proposed approach on Proctor
- When `act` resolves a step's target frame/point, record it.
- In `flow` / `stability` capture output, composite a small marker at that point onto the frame (opt-in), reusing the set-of-marks overlay path (02) if built.

## Scope
- In: target-point marker in flow/stability artifacts, opt-in.
- Out: synthesising a fake cursor sprite; moving the real cursor.

## Success looks like
A stability recording of a divergent run shows, per step, exactly where Proctor acted, making the divergence easy to locate.

## Dependencies / notes
- Cheapest if 02 (set-of-marks overlay) lands first; shares the compositing path.
- Lowest priority of the set; cosmetic rather than capability.
- Licensing: reimplement; MIT source.
