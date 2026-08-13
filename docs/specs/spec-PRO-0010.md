# PRO-0010: Pointer overlay in captures

**ID:** PRO-0010
**Status:** Ready for Plan
**Created:** 2026-08-13
**Last updated:** 2026-08-13

## Feature description

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

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S0 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible in the product UI — adds an opt-in target marker to flow/stability capture artifacts.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Experience]` Framed as “where the step acted”, never a live cursor — Proctor does not move the system cursor. (honest framing)
- `[Data & scope]` Shares the set-of-marks overlay path; cheapest after PRO-0002. (soft dependency)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0010` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).
