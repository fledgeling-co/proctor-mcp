# Plan — PRO-0088: ask whether the frame has anything in it, and count the overlays

**Spec:** `docs/specs/spec-PRO-0088.md` · **Branch:** `ai/pro-0088` off `ai/wave-9`
**Tier:** Small. One new Core file, three production files edited, two new test files.
**Design stage:** skipped — no rendered surface changes. One of the two fixes is a property of a
window that exists to be invisible, and the other is a JSON field a model reads.

## Ordering

| Phase | Work |
|---|---|
| 1 | `FrameContent` in `ProctorCore`: the summary type and the pure gate that turns it into a verdict |
| 2 | `CaptureEngineImpl` computes the summary off `FramePixels` and calls the gate |
| 3 | `CursorOverlay` sets level and sharing type together |
| 4 | Tests, and what arms each one |
| 5 | Glass-lane measurement, CASE-0032 re-derived, registries and CHANGELOG |

## Phase 1 — the gate, pure and in Core

New file `Sources/ProctorCore/FrameContent.swift`. It goes in Core rather than the agent because
the decision has to be drivable without ScreenCaptureKit, a window, or a Mac with a display — which
is what makes the test in phase 4 a test of the production decision rather than of a copy of it.

```swift
public struct FrameContentSummary: Codable, Sendable, Equatable {
    public var pixelsSampled: Int      // how many pixels the summary actually looked at
    public var maxAlpha: Int           // 0...255, the highest alpha seen
    public var distinctColours: Int    // RGBA buckets seen, capped
    public var allTransparent: Bool    // maxAlpha == 0 over a non-empty sample
}

public enum CaptureContentVerdict: String, Codable, Sendable {
    case content          // something is in the frame
    case excludedTarget   // empty, and the target is one Proctor excludes by design
    case emptyFrame       // empty, and the target is not one Proctor excludes
    case notMeasured      // no sample was taken
}

public enum CaptureContentGate {
    public static func verdict(summary: FrameContentSummary?,
                               targetIsProctorOwned: Bool) -> CaptureContentVerdict
    public static func caveat(for: CaptureContentVerdict, window: String) -> String?
}
```

`verdict` is total and has no I/O: `nil` summary → `.notMeasured`; `allTransparent` plus ownership
picks `.excludedTarget` or `.emptyFrame`; anything else is `.content`. `caveat` returns `nil` for
`.content` and `.notMeasured`, the mechanism sentence for `.excludedTarget`, and the measurement
for `.emptyFrame`.

Assumption 3 lands here: `distinctColours` is carried and reported, and no branch keys off it. An
opaque single-colour frame is `.content`.

## Phase 2 — the agent computes the summary and spends the verdict

`Sources/ProctorAgent/Capture/StreamCapture.swift` gains one method on `FramePixels`:

```swift
func contentSummary(maxSamples: Int = 65_536) -> FrameContentSummary
```

Strided over the BGRA buffer the same way `PixelProbe.stats` strides, so a 3-megapixel frame costs
what a small one does. It reads alpha, which `PixelProbe` cannot — `PixelProbe` decodes with
`premultipliedLast` and drops the channel, so a fully transparent frame reads to it as black and
would be indistinguishable from a real dark window.

`Sources/ProctorAgent/Capture/CaptureEngineImpl.swift`, at the verdict (currently line 146):

```swift
let contentRectIsReal = (meta.contentRect?.w ?? 0) > 0 && (meta.contentRect?.h ?? 0) > 0
let summary = pixels.contentSummary()
let ownedByProctor = scWindow.owningApplication?.bundleIdentifier == Wire.bundleIdentifier
let content = CaptureContentGate.verdict(summary: summary, targetIsProctorOwned: ownedByProctor)
let trustworthy = meta.status == .complete && contentRectIsReal && content == .content
```

The existing caveat ladder keeps its order and gains the content branch beneath the freshness ones,
because a frame that is both stale and empty should say the staleness first — that is the caveat
the caller can act on.

`Sources/ProctorCore/Wire.swift`: `CaptureResult` gains `public var content: FrameContentSummary?`
and `public var contentVerdict: CaptureContentVerdict?`, both defaulted `nil` in the initializer so
every existing call site compiles unchanged and a synthesized `encodeIfPresent` keeps an
un-measured result byte-identical. `Sources/ProctorCore/ToolOutputSchemas.swift` gains the two
properties next to `trustworthy`.

`SessionZoom.swift:109` copies `trustworthy` and `caveat` onto a crop already; it copies the two new
fields with them, because a crop inherits its parent's freshness and now inherits its emptiness.

## Phase 3 — the pointer keeps its exclusion across a band change

`Sources/ProctorAgent/Overlay/CursorOverlay.swift`. Four sites assign `panel.level` (lines 288, 290,
337, 538 on this branch). All four go through:

```swift
/// Move a panel between bands and re-apply the capture exclusion. Measured
/// 2026-08-20: this panel reported sharingState 1 while the run panel and the
/// takeover tint reported 0. It is the only overlay that changes level at
/// runtime, and the sharing type does not survive the change.
private static func place(_ panel: NSPanel, at level: NSWindow.Level) {
    panel.level = level
    panel.sharingType = .none
}
```

Nothing else in the file changes. The exclusion is unconditional, matching `RunHUDPanel.swift:374`
and `TakeoverOverlay.swift:705`.

## Phase 4 — tests, and what arms each

New `Tests/ProctorCoreTests/FrameContentTests.swift` and
`Tests/ProctorAgentTests/CaptureContentWiringTests.swift`.

| Case | What it drives | Armed by |
|---|---|---|
| CASE-0120 | An all-zero RGBA sample over a Proctor-owned target → `.excludedTarget`, caveat names the exclusion | Flip ownership to false and the verdict becomes `.emptyFrame` with a different sentence |
| CASE-0121 | An all-zero sample over a foreign target → `.emptyFrame`, caveat carries the measured pixel count | Give one pixel alpha 1 and it becomes `.content` with no caveat |
| CASE-0122 | An opaque single-colour frame → `.content`, `distinctColours == 1`, no caveat | Assumption 3's guard: the test fails if a uniform-colour branch is ever added |
| CASE-0123 | `nil` summary → `.notMeasured`, and `.notMeasured` produces no caveat | Pass a real summary and the verdict moves off `.notMeasured` |
| CASE-0124 | `FramePixels.contentSummary()` over a synthesised all-transparent BGRA buffer reports `maxAlpha 0`, `allTransparent true`, `pixelsSampled > 0` | Write one non-zero alpha byte into the same buffer: `maxAlpha` becomes non-zero. This is the "confirm the instrument could report non-zero" control |
| CASE-0125 | The same summariser over a buffer with real content reports `allTransparent false` and `distinctColours > 1` | Zero the buffer and both invert |
| CASE-0126 | The production verdict expression in `CaptureEngineImpl` conjoins the content gate — source analysis over the file, asserting `content == .content` is a term of `trustworthy` and that `CaptureContentGate.verdict` is called with the ownership test | Delete the term in a scratch copy and the assertion fails. Source analysis: buys no effect credit |
| CASE-0127 | `CursorOverlay` assigns `sharingType` everywhere it assigns `level` — source analysis counting `panel.level =` sites outside `place` and asserting the count is 0 | Restore one direct `panel.level =` in a scratch copy and the count is 1 |
| CASE-0128 | Glass lane: with the fixed build running, every window `CGWindowListCopyWindowInfo` attributes to the agent pid reports `sharingState 0`; the population is `len()` of the rows filtered by pid, and the count is written into the evidence | The pre-fix build measured in the same way reports one row at 1. Both runs published |
| CASE-0129 | Glass lane: `proctor_capture` against a Proctor-owned window returns `trustworthy: false` with the exclusion caveat, and against a foreign window returns `trustworthy: true` with content | The foreign-window leg is the sabotage: a real frame still passes |

CASE-0126 and CASE-0127 are source analysis and are recorded as such — they establish the
production path calls the gate, and CASE-0128/0129 establish what happens when it runs.

## Phase 5 — the glass lane, and the registries

Build with `PROCTOR_SIGN_IDENTITY='Developer ID Application: Luke Rhodes (H4HGFL52W7)' bash
scripts/build-app.sh`; launch with `open -n --env …` from `.build/Proctor.app`; never install over
`/Applications/Proctor.app`. Probe the window server from a **separate** process, as DEF-028 was
found, so the measurement is not taken by the process being measured.

Evidence lands under `docs/test-campaign/evidence/pro0088/`. CASE-0032's note is corrected against
the counted population and its evidence list gains the two probes. The five defects and two
requirements are appended to `docs/test-campaign/inventory.json`, the ten cases to `cases.json`;
neither file is reformatted or re-sorted, and no row this item did not create is rewritten.
`CHANGELOG.md` gains its entry under `## [Unreleased]`.

`./scripts/test.sh` owns the verdict. Its output is redirected to a file and the exit code read off
the script, never off a pipe.
