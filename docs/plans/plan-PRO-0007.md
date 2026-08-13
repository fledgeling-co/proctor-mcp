# Plan — PRO-0007: Zoom native-resolution region crop

**Spec:** docs/specs/spec-PRO-0007.md · **Branch:** ai/pro-0007 · **Tier:** Small
**Gate:** `swift build` + `swift test` (Swift Package; no web/e2e stages).

## Decision

A new read-only tool **`proctor_zoom`** that returns a native-resolution PNG crop of a
region (window-relative points) or a resolved AX element, carrying the *same freshness
metadata* as `proctor_capture`. One tool per decision — reading small detail is its own
decision — matching the catalogue idiom. Tool count 17 → **18**.

The crop is **layered on a normal capture**, exactly as set-of-marks annotation is: `zoom`
runs a standard native-scale window capture, then crops the written PNG to the region's
pixel rect. The full capture's freshness fields (`status`, `contentRect`, `dirtyRectCount`,
`dirtyArea`, `capturedAt`, `framesWaited`, `trustworthy`, `caveat`) describe the same frame
and pass through unchanged. This needs **no change to the `CaptureEngine` protocol or its
tests** — the crop is a pure image op in the agent.

The load-bearing, grant-free arithmetic (points→native pixels, clamp, element→region)
lives in `ProctorCore.RegionCrop` (Geometry.swift), mirroring `SetOfMarks.toPixels` and
`RegionDirt`. That is what the red→green unit tests exercise without a window or grant.

## Coordinate convention

`region` is `[x, y, w, h]` in points relative to the window's top-left — identical to
`proctor_wait`. A region maps to frame pixels as `point * scale` (scale = display backing
scale = native), the same transform `SetOfMarks.toPixels` uses. Integer-align by flooring
the origin and ceiling the extent so the region is always fully inside the crop, then clamp
to the image bounds.

## Changes

**ProctorCore (shared):**
- `Geometry.swift` — add `enum RegionCrop`: `place(regionPoints:imageWidth:imageHeight:scale:) -> Result<Placement, Failure>`
  (`Placement{pixelRect, clamped}`; `Failure{emptyRegion, noFrameGeometry, outsideFrame}`),
  `regionForElement(elementFrame:window:padding:)`, `pad(_:by:)`.
- `Wire.swift` — add `struct CropRegion` (Codable) and an optional `crop: CropRegion?` on
  `CaptureResult` (defaulted nil in init, like `annotation`), so normal captures are
  byte-identical.
- `ToolCatalogue.swift` — add the `proctor_zoom` spec; append to `all`.
- `ToolProfiles.swift` — add `proctor_zoom` to the `core` cluster (pairs with capture);
  nesting ax ⊂ core ⊂ scripting ⊂ full preserved.
- `ToolOutputSchemas.swift` — bespoke schema documenting the freshness fields + `crop`.

**ProctorAgent:**
- `Session/SessionZoom.swift` (new) — `Session.zoom(...)`: resolve region (from `region` or
  from `ax.node(id:)` frame minus window origin, + optional `padding`), run `capture.capture`
  at native scale, `RegionCrop.place`, crop the PNG (CGImageSource → `cropping(to:)` →
  CGImageDestination), return a `CaptureResult` with the crop path/dims + `crop` descriptor
  and passthrough freshness. A `RegionCrop.Failure` becomes a reasoned `AgentError`.
- `Dispatch.swift` (shared) — add the `case "proctor_zoom"` route.

**Tests (shared, ProctorCoreTests):**
- New `@Suite("Zoom region crop")`.
- Bump the count assertion 17 → 18 and add `proctor_zoom` to the read-only / profile
  assertions.

## Acceptance clauses → proving tests

1. **Tool present & well-formed** — `proctor_zoom` in `all`, read-only, description > 200,
   input schema object exposing `region` and `node`, object output schema documenting
   `path`/`trustworthy`/`crop`; advertised in `core` (and thus scripting/full), not `ax`.
   → catalogue/profile/output-schema tests.
2. **Native-pixel crop math** — a region in points maps to the exact integer pixel rect at
   native scale (identity at 1×, ×2 at retina, rounds outward for sub-pixel). → `RegionCrop.place` tests.
3. **Element → region** — an element's screen-point frame converts to a window-relative
   region (with padding), so `find → zoom` targets it. → `RegionCrop.regionForElement` tests.
4. **Reasoned failure / clamp** — empty, out-of-frame and no-geometry regions fail with a
   named reason; a partly-outside region clamps to visible pixels and reports `clamped`.
   → `RegionCrop.place` failure/clamp tests.
5. **Same freshness as capture** — the crop reuses `CaptureResult` with freshness passthrough;
   the optional `crop` field is nil for normal captures (byte-identical) and round-trips via
   Codable; the output schema documents the freshness fields + `crop`. → CaptureResult/CropRegion
   Codable + schema tests.

## Out of scope

OCR / text extraction of the crop (spec: left to the caller). No change to capture's own
contract or the mock capture engine.
