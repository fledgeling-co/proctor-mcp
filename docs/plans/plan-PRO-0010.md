# plan-PRO-0010: Pointer overlay in captures

**Spec:** docs/specs/spec-PRO-0010.md · **Branch:** ai/pro-0010 · **Tier:** Small

## What ships

An opt-in marker composited onto the per-step capture artifacts of `proctor_act` /
`proctor_flow` replay, drawn at the point the step acted on — honestly framed as
"where the step acted", never a live cursor (Proctor does not move the system
cursor). Reuses the set-of-marks overlay path (MarkRenderer + a Core geometry
module), following the nil-when-absent opt-in shape PRO-0002/0006/0007 established
on `CaptureResult`.

## Where the target point comes from (grounding)

The actuator (`Actuator.pointer`, `Actuator.centre`) resolves a synthetic step's
target as `step.point` if present, else the element's frame **centre**
(`frame.x + w/2, frame.y + h/2`). Both are **global screen points** — `step.point`
is posted straight to `CGEventPost`, and AX frames are screen points. This is the
exact space `SetOfMarks.toPixels` consumes, so the pixel transform is identical:
`(screen − window.origin) × scale`.

## Architecture (mirrors SetOfMarks / RegionCrop)

Only `ProctorCoreTests` exists as a test target, so every red→green test lands in
Core. The load-bearing, checkable geometry lives in Core; the pixel drawing and
agent wiring are mechanical (like `MarkRenderer.render`, which has no unit test).

1. **Core — `Sources/ProctorCore/PointerMarker.swift`** (new, tested)
   - `targetPoint(for step: ActionStep, elementFrame: Rect?) -> Target?` — prefer
     `step.point` (source `.point`), else `elementFrame` centre (source `.element`),
     else nil (a `type`/`key` step with no coordinate marks nothing).
   - `place(x:y:window:imageWidth:imageHeight:scale:) -> Placement?` — screen point
     → frame pixel, same transform as `SetOfMarks.toPixels`; `onFrame` false and the
     pixel clamped to the nearest edge when the target fell outside the frame (an
     off-frame action stays visible at the edge and is flagged, rather than
     vanishing). Nil only when the frame has no pixels.

2. **Wire — `Sources/ProctorCore/Wire.swift`** (tested via round-trip)
   - `PointerOverlay { annotatedPath, pixelX, pixelY, source, node?, onFrame }`.
   - `CaptureResult.pointer: PointerOverlay?` — opt-in, nil default, appended to the
     initialiser with a nil default so a plain capture stays byte-identical.

3. **Catalogue — `ToolCatalogue.swift`** (tested)
   - `proctor_act` and `proctor_flow` gain a `pointerMarks` boolean input: "When
     captureEach is set, composite a marker at each step's target point — where the
     step acted — onto that step's frame. Opt-in." No new tool; **count stays 19**.
   - `proctor_capture` inputs unchanged (a manual capture has no acting step).

4. **Agent (build-only, no unit test)**
   - `MarkRenderer.renderPointer(basePath:width:height:scale:placement:) -> String`
     — composites a ring + crosshair marker, writes a `.pointer.png` sibling; reuses
     the context setup, y-flip and `writePNG` of `render`.
   - `Sources/ProctorAgent/Session/SessionPointer.swift` (new) —
     `Session.pointerOverlay(for:window:capture:) -> PointerOverlay?`: resolves the
     element frame via `ax.node` when the step carries a node, runs
     `PointerMarker.targetPoint` + `place`, renders, returns the overlay. Best-effort
     (nil on any failure — the feature is cosmetic).
   - Thread `pointerMarks: Bool` (default false) through `runSteps` →
     `captureForStep` (SessionAct); attach `.pointer` to each per-step capture when
     set. `act` and `flowReplay` accept it; `Dispatch` reads `args.bool("pointerMarks")`.

## Acceptance clauses → proving tests (all in ProctorCoreTests, new `@Suite`)

1. **Target from an explicit point** → `targetPoint` returns the point, source `.point`.
2. **Target from an element frame** → returns the frame centre, source `.element`,
   when the step has a node and no point.
3. **A coordinate-less step marks nothing** → `type`/`key` step, no point/frame → nil.
4. **Screen point → pixel transform** → `place` subtracts origin and scales, pinned
   to an exact pixel (window origin ≠ 0, scale = 2), `onFrame == true`.
5. **An off-frame target clamps to the edge and is flagged** → `onFrame == false`,
   pixel clamped into bounds.
6. **A frame with no pixels places nothing** → `place` returns nil at 0×0.
7. **`CaptureResult.pointer` defaults nil and round-trips absent** → plain capture
   byte-identical.
8. **`PointerOverlay` round-trips** through the codec with every field.
9. **`proctor_act` / `proctor_flow` advertise `pointerMarks`** and keep their
   existing readOnly/destructive flags; **catalogue still advertises 19 tools**.

## Out of scope (deferred children)

- **Pointer marker in `proctor_stability` per-step artifacts.** Stability emits
  hashes and instability scores, not per-step PNGs, so there is no artifact to
  composite onto without first building per-step PNG emission — a larger change than
  this cosmetic item. Deferred.
- Synthesising a cursor sprite; moving the real cursor (explicitly out per spec).

## Verification

`swift build` + `swift test` from the worktree root. New suite red→green; full suite
green (affected-test sweep is the whole Core suite, one target).
