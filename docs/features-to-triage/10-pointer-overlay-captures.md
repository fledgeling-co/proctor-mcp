---
sources: [REQ-006, REQ-028]
status: retired
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

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-006, REQ-028
- surface: SURF-004, SURF-005
- cases: CASE-0004, CASE-0008, CASE-0009, CASE-0010, CASE-0021, CASE-0030
- rungs reached: effect-witness, metamorphic, outcome
- provider: NSPanel over the window server in Sources/ProctorAgent/Overlay/RunHUDPanel.swift, readable back through CGWindowListCopyWindowInfo
