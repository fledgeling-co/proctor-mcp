# Plan — PRO-0006: Vision-capture normalisation

**Spec:** docs/specs/spec-PRO-0006.md · **Branch:** ai/pro-0006 · **Tier:** Small
**Gate:** `swift build` + `swift test` (Swift-adapted pipeline; no web stages).

## Goal

An opt-in capture variant that pre-scales a frame to the vision-API ceiling
(~1568px long edge / ~1.15 MP) *before* returning it, and reports the exact
scale factor applied, so coordinates a vision model returns map back onto
Proctor's native geometry with no silent-downsample drift. Raw capture stays
the default (pixel assertions keep native resolution).

## Approach (extend, do not add a tool)

Normalisation is an option on `proctor_capture`, not a new tool — matches the
spec ("small, self-contained addition to the `capture` path") and keeps the
catalogue at **17** tools, so the merge stays a union. The checkable logic
(the ceiling decision + the coordinate round-trip) lives in a new pure
ProctorCore file so it is unit-testable with no display and no TCC grant, the
same way `SetOfMarks`, `PointerPath` and `RegionDirt` keep their arithmetic in
Core.

## Changes

1. **`Sources/ProctorCore/VisionCapture.swift` (new)** — pure enum:
   - `defaultMaxLongEdge = 1568`, `defaultMaxPixels = 1_150_000`.
   - `fit(width:height:maxLongEdge:maxPixels:) -> Fit` — the one decision:
     `edgeScale = maxLongEdge/longEdge` when the long edge is over; `pixelScale
     = sqrt(maxPixels/pixels)` when the area is over; `scale = min(edge,pixel)`
     clamped to ≤1. `applied=false` and dims unchanged when already within both
     ceilings. Output dims are `round(dim*scale)`, floored to ≥1.
   - `toNative(_:scale:)` / `toNormalized(_:scale:)` — the coordinate
     round-trip. `toNative` is the exact inverse a caller uses to map a model
     coordinate in the normalised image back to native pixel space (`v/scale`).

2. **`Sources/ProctorCore/Wire.swift`** — add `CaptureNormalization` struct
   (scale, originalWidth/Height, width/height, maxLongEdge, maxPixels) and an
   optional `normalization: CaptureNormalization?` field on `CaptureResult`,
   defaulting to nil — nil keeps a non-normalised result byte-identical to
   today, exactly as `annotation` does.

3. **`Sources/ProctorCore/ToolCatalogue.swift`** — add `normalize`,
   `normalizeMaxLongEdge`, `normalizeMaxPixels` to the capture input schema and
   document them in the description. No new tool; `all` unchanged (17).

4. **`Sources/ProctorCore/ToolOutputSchemas.swift`** — add `normalization` to
   the capture open object.

5. **`Sources/ProctorAgent/Contracts.swift` + `Capture/CaptureEngineImpl.swift`**
   — `capture(...)` gains `normalize`/ceiling params. After the frame is chosen
   and written, if `normalize` was requested compute `fit` from the native
   pixel dims; when it applies, downscale the CGImage into a context of the
   target size and rewrite the PNG at `path`, then set `width/height/scale` to
   the normalised values. Attach the `normalization` block whenever normalise
   was requested (scale=1, applied=false when nothing needed doing — a caller
   who asked still gets the factor). Freshness metadata (status, contentRect,
   dirty, framesWaited, trustworthy) is left describing the frame as captured.

6. **`Sources/ProctorAgent/Session/Session.swift` + `Dispatch.swift`** — thread
   the new params through `captureWindow` and decode them in `capture(_:)`.

## Acceptance clauses → proving tests (Tests/ProctorCoreTests, swift-testing)

- **AC1 long-edge ceiling** — a frame over 1568 long edge scales so the long
  edge ≤ ceiling, aspect preserved, `scale = out/in`, `applied=true`.
- **AC2 pixel-count ceiling** — a frame within long-edge but over 1.15 MP
  scales by the pixel-count factor so `outW*outH ≤ maxPixels`.
- **AC3 within ceiling is a no-op** — a frame under both ceilings returns
  `scale=1`, `applied=false`, dims unchanged (opt-in never upscales/degrades).
- **AC4 exact coordinate round-trip** — `toNative(toNormalized(v)) == v`, and a
  model coordinate in normalised space maps to the correct native coordinate
  via `/scale`. This is the "no silent-downsample drift" guarantee.
- **AC5 result carries the factor** — `CaptureResult` with a `normalization`
  block Codable-round-trips; a nil `normalization` encodes to no key (default
  stays byte-compatible).
- **AC6 no new tool, flag advertised** — `ToolCatalogue.all.count == 17` and
  the capture input schema advertises `normalize`.

## Out of scope

Changing the default capture; upscaling; per-axis (non-uniform) scaling;
anything touching the tri-observer or set-of-marks placement maths beyond
consuming the reported factor.

## Downgrade log

External-model CLIs off on this machine: Codex gpt-5.6-sol executor + the three
out-of-family review gates unavailable. Executor and all gates run in-family
(Claude). Recorded per fleet instruction.
