# PRO-0007: Zoom region crop

**ID:** PRO-0007
**Status:** Merged
**Created:** 2026-08-13
**Last updated:** 2026-08-13
**Plan:** docs/plans/plan-PRO-0007.md

## Feature description

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

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S0 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible — behind the scenes. Adds a native-resolution crop of a region or element for reading small detail.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Data & scope]` Reuses the existing SCK capture path with the same freshness metadata. (thin addition)
- `[Experience]` OCR/text extraction is left to the caller, out of scope here. (crop, not read)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0007` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).
