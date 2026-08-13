# Plan — PRO-0002: Set-of-marks annotated captures

**Spec:** docs/specs/spec-PRO-0002.md (Status: Ready for Plan)
**Branch:** ai/pro-0002
**Gate:** `swift build && swift test` from the worktree root (Swift package; no web/e2e stages).
**Plan size:** Small — one opt-in variant on an existing tool, one new pure-geometry unit, one CoreGraphics renderer. No new plane, no new tool, no transport change.

## Goal

Add an opt-in annotation variant to `proctor_capture` that burns **numbered marks** over
interactable accessibility elements — and optional **grid reference lines** — into a sibling
PNG, and returns a **mark → AX-node-id map** so a vision model can actuate by mark id
("click mark 7" resolves to a real element). The un-annotated capture and its freshness
metadata are unchanged; annotation is purely additive.

## Design decisions (grounded in the codebase)

The existing split is: **testable geometry lives in `ProctorCore`** (see `PointerPath`,
`RegionDirt` in `Geometry.swift`), the **mechanical OS-touching step lives in the agent**
and is not unit-tested (see the `CGEventPost` actuation behind `PointerPath`). This feature
follows that split exactly.

1. **Pure placement/culling/grid math → `Sources/ProctorCore/SetOfMarks.swift` (new).**
   Given element frames (screen points, with ids/roles/labels), the window frame, the image's
   pixel dimensions + scale, an optional content rect, grid options and a mark cap, it produces
   the numbered `[Mark]` (each with the AX node id and both a points frame and a pixel rect) and
   an optional `GridOverlay`. This is the load-bearing part — a wrong transform or unstable
   numbering makes the whole feature useless — so it is where the red→green tests land.

2. **Wire types → `Sources/ProctorCore/Wire.swift`.** Add `Mark`, `GridOverlay`,
   `MarkAnnotation`, and one optional field `annotation: MarkAnnotation?` on `CaptureResult`
   (default `nil`). Optional-and-nil means the un-annotated JSON shape is byte-identical to
   today's — "freshness metadata unchanged" holds literally. This is the only shared-surface
   edit (`Wire.swift` / catalogue) the orchestrator may need to merge.

3. **Compositing → `Sources/ProctorAgent/Capture/MarkRenderer.swift` (new).** Loads the
   un-annotated PNG already written to `CaptureResult.path` (mirroring `PixelProbe`'s
   `CGImageSourceCreateWithURL` load), draws grid lines, then each mark's box + numbered badge
   with CoreGraphics/CoreText into a bitmap context, and writes the annotated PNG. It never
   touches `CaptureEngineImpl` and never threads pixels through the capture path — the PNG on
   disk is the hand-off, consistent with how `PixelProbe` already re-reads it.

4. **Orchestration → `Sources/ProctorAgent/Session/Session.swift`.** `captureWindow` gains
   annotate/annotateAll/grid/gridSpacing/maxMarks. When annotation is requested it: captures as
   today → walks the window tree (`walk(window:)`) → flattens markable nodes (default
   `TriObserver.isActionable`, or all framed nodes when `annotateAll`) → `SetOfMarks.plan(...)`
   → `MarkRenderer.render(...)` → attaches `MarkAnnotation`. The `CaptureResult` fields keep
   describing the original frame untouched.

5. **Schema + arg decode → `ToolCatalogue.swift` (capture schema) + `Dispatch.swift`.**

### Numbering & stability
Marks are numbered in reading order — sort by frame `y` (quantised to `Canonical`'s point
grain) then `x`, ties broken by node id. Same tree revision → same ordering → same ids,
satisfying the binding assumption "mark ids are stable within a snapshot revision."

### Coordinate transform
Screen points → frame pixels reuses the exact convention already in `TriObserver.imageRect`:
`((x - window.frame.x) * scale, (y - window.frame.y) * scale, w*scale, h*scale)`, with
`scale = CaptureResult.scale` (the effective pixel scale). Elements whose pixel rect does not
intersect the image bounds are culled (you cannot mark what was not captured); partially-visible
elements are marked with the box clamped to the image.

### Grid
When `grid` is on, verticals at `x = k·gridSpacing·scale` and horizontals at
`y = k·gridSpacing·scale` within the image, plus their point coordinate as an edge label.
`grid` and marks are independent — a grid can be requested without marks.

## Scope

**In:** numbered interactable/window marks, grid lines, mark→id map, opt-in flags on
`proctor_capture`, un-annotated capture preserved.
**Out:** OCR / detecting elements the AX tree does not expose; a new tri-observer disagreement
kind (assert already owns that). The annotated artifact + freshness metadata + mark map
together already surface any tree-vs-pixels disagreement, which is the spec's "fourth channel"
value; no new `Disagreement.Kind` is needed.

## Files

| File | Change |
|---|---|
| `Sources/ProctorCore/SetOfMarks.swift` | NEW — pure numbering/transform/culling/grid |
| `Sources/ProctorCore/Wire.swift` | `Mark`, `GridOverlay`, `MarkAnnotation`; `CaptureResult.annotation` |
| `Sources/ProctorCore/ToolCatalogue.swift` | capture schema: `annotate`, `annotateAll`, `grid`, `gridSpacing`, `maxMarks`; description |
| `Sources/ProctorAgent/Capture/MarkRenderer.swift` | NEW — CoreGraphics compositing → annotated PNG |
| `Sources/ProctorAgent/Session/Session.swift` | `captureWindow` orchestration |
| `Sources/ProctorAgent/Dispatch.swift` | decode new capture args |
| `Tests/ProctorCoreTests/ProctorCoreTests.swift` | `@Suite("Set of marks")` red→green tests; capture-schema advertises `annotate` |

## Test plan (Swift-shaped, per acceptance clause)

Unit tests on `SetOfMarks` (pure, no window/grant needed):
- transform: an element at a known screen frame maps to the expected pixel rect at scale 2.
- numbering is reading-order and **stable**: same input twice → identical ids; a re-sorted input
  yields the same id per node.
- culling: an element entirely outside the image gets no mark; one partially in is kept, box
  clamped to bounds.
- mark→id map: every emitted mark carries its source node id.
- cap: `maxMarks` truncates in numbering order and reports `markedCount` < `elementsConsidered`.
- grid: line positions match `k·spacing·scale` within bounds; no grid when disabled.
- catalogue: `proctor_capture` advertises `annotate` and stays read-only; tool count stays 11.

Gate: `swift build && swift test` green in the worktree; affected-test sweep = the full
`ProctorCoreTests` target (only target that compiles the changed `ProctorCore`).

## Non-breaking / risk notes
- `CaptureResult.init` gains a trailing `annotation: MarkAnnotation? = nil` — existing call in
  `CaptureEngineImpl` compiles unchanged.
- Tool count unchanged (11) — no catalogue-count test churn.
- Renderer is headless CoreGraphics (bitmap context + CoreText), no AppKit, no display.
