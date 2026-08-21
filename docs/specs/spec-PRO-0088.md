# PRO-0088: a capture that came back empty, and the overlay nobody counted

**ID:** PRO-0088 · **Status:** To Do · **Created:** 2026-08-21
**Brief:** `docs/features-to-triage/81-the-capture-path-reports-frames-it-did-not-get.md` (Wave 13)
**Branch:** `ai/pro-0088` off `ai/wave-9` · **Lane:** headless `./scripts/test.sh`, plus the glass lane
**Requirements:** REQ-061, REQ-062 · **Defects:** DEF-095..DEF-099 · **Cases:** CASE-0120..CASE-0129
**Ledger id:** allocated by the orchestrator. This item does not write `docs/feature-specs/LEDGER.md`.

## Ready for implementation plan

**What a caller gets today.** Ask `proctor_capture` for a picture of a window Proctor owns and it
returns `status: complete, trustworthy: true` over a PNG in which every one of 2,942,720 pixels is
`RGBA(0,0,0,0)`. The exclusion worked — Proctor keeps its own windows out of its own captures on
purpose — and nothing between ScreenCaptureKit's status bit and the returned verdict asked whether
the frame it was vouching for had anything in it. `SCFrameStatus complete` means a frame was
delivered, not that it depicts something.

**What they get after this.** The same capture comes back `trustworthy: false` with the reason
stated in plain words: *this window is excluded from capture, so nothing was going to be in it*.
The reply carries a small `content` block — how many pixels were looked at, the highest alpha seen,
how many distinct colours — so a caller can tell an excluded window from a genuinely blank one
without opening the file. Every other capture is unchanged, including a real frame that happens to
be mostly one colour.

**The second half a reader could not see.** Sampling the window server from a separate probe found
a third agent-owned window at layer 0 reporting `sharingState 1` next to the two overlays recorded
at 0. It is the drawn pointer. `CursorOverlay` moves its panel between the normal band and the
screen-saver band at runtime and never set `sharingType` at all on this lineage, so the one surface
whose whole job is to be drawn over somebody else's window was the one capturable by anybody. It is
fixed here, and CASE-0032's population is re-derived by counting rather than by repeating the
number the case was written with.

### The honest edge

A legitimately blank window exists, and calling that a defect would be its own false positive. The
distinguishing fact this path already holds is ownership: the target's `owningApplication` bundle
identifier. When it is `app.fledgeling.procter` the path can state the mechanism rather than infer
from pixels. When it is not, an empty frame is reported as *not established* with what was measured
attached — never as a defect in the target, and never as `complete` + `trustworthy`.

### Assumptions

1. **`trustworthy` is the verdict that moves; `status` stays truthful.** `status` reports what
   ScreenCaptureKit said and keeps reporting it, because a path that rewrote SCK's own word would
   destroy the evidence the caveat is drawn from. The brief's "inconclusive" is `trustworthy:
   false` plus a reason, which is the shape every other caveat in this file already takes and the
   shape `TriObserver`, `SessionAssert` and `TriObserverAdapter` already refuse on.
2. **Emptiness is measured over the frame that was written, not the one that arrived.** The summary
   is taken from the same `FramePixels` the PNG is encoded from, so what the verdict is about and
   what a person opens are the same bytes.
3. **A uniform frame is downgraded only when it is also fully transparent, or when the target is
   one Proctor excludes.** Rather than downgrading every single-colour frame: an opaque one-colour
   window is a real thing an app can draw, the campaign has cases that capture solid fills, and a
   verdict that fires on them would be the false positive the brief warns against. The `content`
   block still reports `distinctColours` for a caller that wants to make that call itself, so the
   fact is published without the verdict being spent on it.
4. **The drawn pointer's exclusion is set with every level assignment, not once at build.** Rather
   than once in `build(for:)`: measured on macOS, assigning `NSWindow.level` resets `sharingType`,
   which is exactly why this panel — the only overlay that changes band at runtime — was the one at
   `sharingState 1`.
5. **The minimal exclusion, not a port of the capture switch.** `main` carries the same fix at
   `15f86ea` wrapped in a `PROCTOR_OVERLAY_CAPTURE` switch and an `OverlayCapture` type that does
   not exist on `ai/wave-9`. Under both readings the default behaviour is identical; porting the
   switch would duplicate a type the eventual merge brings anyway. Recorded so the merge resolves
   this file in `main`'s favour knowingly rather than by accident.

### Pipeline record

Sentinel tier **S1** — a developer-facing tool surface and a window property; no user data, no
access-control default, no external dependency added. No Essential Questions survived the
divergence test.

**Out-of-family spec review.** The codex lane (`gpt-5.6-sol`) was recorded down to Aug 27 on the
previous item and was not retried. `grok-4.6` refused with *"API error (status 402 Payment
Required): Grok Build usage balance exhausted"*. The `agy` lane failed once on repository
exploration (*"Find command timed out"*) and answered on the second attempt with the material
inlined: **Google family, `gemini-3.7-flash-high`**, transcript
`docs/test-campaign/evidence/PRO-0088/spec-review-gemini.md`. Verdict **0 Critical, 1 High,
1 Medium, 2 Low**. Tally **2 accepted, 1 rejected, 1 recorded**:

- *High — strided alpha sampling can report a sparse window as empty.* **Accepted, and it was a
  real defect in the draft.** A square stride over a 3456x2234 frame steps 7-8 pixels, so a
  one-pixel hairline or a focus ring falls between every sample and a window with something in it
  would have been called `allTransparent` — the false positive the whole item is built to avoid.
  Alpha is now read over every pixel and `pixelsSampled` reports the whole frame; only the colour
  histogram keeps a stride, because nothing branches on it. Guarded by CASE-0124b.
- *Medium — the BGRA byte layout is assumed rather than checked.* **Accepted.** `FramePixels`
  carries the `OSType` it was copied from, and a buffer that is not `kCVPixelFormatType_32BGRA` is
  declined as `notMeasured` rather than read with a colour channel mistaken for alpha. Guarded by
  the format test in the same suite.
- *Low — `CursorOverlay` panels built before the first `place()` keep the default sharing type.*
  **Rejected, with the reason:** `build(for:)` already calls `Self.place(panel, at:)` rather than
  assigning `level` directly (`CursorOverlay.swift:558`), so the exclusion is set at construction
  as well as at every band change. CASE-0127 counts the direct assignments and holds it at zero.
- *Low — nested bundle identifiers under a Proctor prefix are not matched.* **Recorded as a
  deliberate choice.** The set is the two identifiers Proctor actually draws windows with —
  measured, not guessed: `SCShareableContent` reports the UI as `app.fledgeling.procter` and the
  agent as `app.fledgeling.procter.agent`. A prefix test would also claim any future identifier
  that happened to start the same way, so the match is exact and the set is named.

## Requirements

| Id | Text |
|---|---|
| REQ-061 | A capture whose frame carries no content is never reported `trustworthy`, and says which of the two reasons applies: the target is one Proctor excludes from capture, or the frame arrived empty from a window Proctor does not own |
| REQ-062 | The drawn pointer's capture exclusion survives a level change, so all of the agent's overlay panels report `sharingState 0` at the default — counted, not asserted |

## Defects

| Id | What |
|---|---|
| DEF-095 | `CursorOverlay` never set `sharingType`, so the drawn-pointer panel reported `sharingState 1` while the run HUD and the takeover statement reported 0 |
| DEF-096 | CASE-0032 claims "all three overlays" against a population it never counted; the agent process owns three windows during a run and the case's evidence file records the pointer at `sharingState 1` |
| DEF-097 | `CaptureResult.trustworthy` was computed from `SCFrameStatus` and a non-empty content rect alone, so a fully transparent frame passed both |
| DEF-098 | The reply gave a caller no way to tell an empty frame from a full one without decoding the PNG: `dirtyArea 0` sat next to `dirtyRectCount 1`, which reads as though something changed |
| DEF-099 | REQ-028 cites `Sources/ProctorCore/OverlayCapture.swift`, a file this branch does not contain — the registry was written against `main` while the lineage under test lacked the fix |

## Non-goals

It does not change what `be-my-witness` judges. It does not make Proctor's overlays appear in
Proctor's own captures — `sharingType = .none` on the HUD and the takeover statement is correct and
is left exactly as it is. Evidence must not change because somebody was watching.
