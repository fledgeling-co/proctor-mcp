### Judgements

1. **Diagnosis is Correct:** Accurately identifies that ScreenCaptureKit’s `SCFrameStatus.complete` certifies frame delivery rather than frame content. It also correctly diagnoses that AppKit `NSWindow.level` mutations reset `sharingType` to default (`.readOnly` / `sharingState: 1`), and that `PixelProbe` drops alpha channels via `premultipliedLast`.
2. **Assumption 3 is the Right Call:** Demoting opaque single-colour frames would cause immediate false positives on legitimate solid backgrounds and test fixtures. Exposing `distinctColours` and `maxAlpha` in `FrameContentSummary` allows specialized assertions to enforce stricter uniformity thresholds without breaking base capture validity.
3. **Keeping `SCFrameStatus` Truthful is Correct:** Transport-level telemetry (`status`) must remain distinct from semantic frame payload validity (`trustworthy`). Synthesizing a fake SCKit status would destroy diagnostic visibility into the capture pipeline.
4. **Caller Impact is Correct / Desirable:** Callers (`TriObserver`, `SessionAssert`, `SessionZoom`, etc.) *should* refuse empty frames. Passing 0-alpha buffers as `trustworthy: true` previously masked failures and led to bogus assertions.
5. **What is Missing:** Documented in the findings below (strided aliasing risks, pixel format assumptions, and initial overlay creation).

---

### Findings

#### `[HIGH]` Strided sampling aliasing can mark sparse UI as empty
`FramePixels.contentSummary()` strides sampling by $\lceil\sqrt{cells / 65536}\rceil$ (a step of 7–8 px on 4K/5K displays). If a target window contains only a 1px divider, single-pixel hairline focus ring, or small loading indicator, every sample point can miss the pixels, resulting in `maxAlpha == 0` and an erroneous `allTransparent: true` verdict on non-empty foreign frames.

#### `[MEDIUM]` Unchecked 32-bit BGRA format assumption
`contentSummary()` assumes 4-byte packed little-endian 32BGRA where byte 3 is alpha (`px[3]`). If ScreenCaptureKit delivers wide-gamut/HDR buffers (e.g. `kCVPixelFormatType_64RGBAHalf`) or non-BGRA alignments, checking `px[3]` misreads colour channels as alpha, causing either transparent frames to pass or valid frames to be misidentified.

#### `[LOW]` `CursorOverlay` initial window creation
`place()` encapsulates level transitions, but `NSPanel` instances initialized before the first `place()` call will remain at default `sharingType` until their first level update. `sharingType = .none` must also be enforced in the panel initializer/factory.

#### `[LOW]` Nested bundle identifier matching
`CaptureContentGate.isProctorOwned` performs an exact equality check against `Wire.bundleIdentifier`. If Proctor helpers or XPC services render UI under sub-bundle identifiers (e.g., `app.fledgeling.proctor.helper`), empty frames from these processes will be categorized as `.emptyFrame` rather than `.excludedTarget`.
