# PRO-0002: Set-of-marks captures

**ID:** PRO-0002
**Status:** In Review
**Created:** 2026-08-13
**Last updated:** 2026-08-13
**Plan:** docs/plans/plan-PRO-0002.md

## Feature description

# Set-of-marks annotated captures

**Status:** untriaged · **Value:** high · **Effort:** medium · **Source:** zavora-ai/computer-use-mcp (`snapshot use_annotation / grid_lines`)
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
An optional capture variant that burns **numbered marks** over windows / AX elements, plus optional **grid reference lines**, directly into the capture pixels. Each mark carries an id that maps back to the AX node it labels.

## Why (for computer use / testing)
Set-of-marks is the standard way a vision model grounds a click: it references a numbered box instead of guessing raw coordinates, which is markedly more reliable. For Proctor specifically it also becomes a **fourth tri-observer channel** — marks derived from AX geometry, drawn onto the pixel plane, make a tree-vs-pixels disagreement visible in a single artifact.

## Proposed approach on Proctor
- Take the pruned AX snapshot (roles, frames, stable ids) already produced by `snapshot`.
- Composite numbered boxes at each element's frame onto a ScreenCaptureKit capture; optional grid overlay.
- Return the mark→AX-id map alongside the annotated image so a model's "click mark 7" resolves to a real element.
- Keep the un-annotated capture available (annotation is opt-in; freshness metadata unchanged).

## Scope
- In: numbered element/window marks, grid lines, mark→id map, opt-in flag on capture/snapshot.
- Out: OCR / detecting elements the AX tree doesn't expose (that's a separate vision concern).

## Success looks like
A vision model reliably actuates by mark id on a dense window, and a tri-observer artifact shows a labelled disagreement between the marked geometry and the captured pixels.

## Dependencies / notes
- Builds on existing `snapshot` (AX geometry) + `capture` (SCK) — no new plane.
- Pairs naturally with 06 (vision-capture normalisation) so marks stay legible after scaling.
- Site-relevant once shipped: strengthens the vision / testing story.
- Licensing: reimplement the overlay step; MIT source.

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible in the product UI — this annotates capture images returned to callers. Adds numbered marks + grid + a mark→AX-id map to snapshot/capture output.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Data & scope]` Marks derive from the existing pruned AX snapshot geometry. (reuses snapshot)
- `[Experience]` Annotation is opt-in; the un-annotated capture and freshness metadata are unchanged. (non-breaking)
- `[Operations]` Mark ids are stable within a snapshot revision. (consistent with since-revision diffs)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0002` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).
