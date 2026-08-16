# PRO-0063: Captures are sized by what they are for

**ID:** PRO-0063
**Status:** In Review
**Created:** 2026-08-16
**Last updated:** 2026-08-16
**Branch:** `ai/pro-0063` (worktree `.worktrees/PRO-0063`)

## The problem

Every `proctor_capture` was normalised to the vision API's ceiling: 1,568px on
the long edge, ~1.15MP. That ceiling is what the API *tolerates*, not what a task
*needs*, and a model is billed on pixel dimensions — Anthropic prices an image at
roughly `width × height / 750` tokens. So a 16in Retina window cost about 1,530
tokens per frame whether the caller was reading a dialog or just deciding which
button to press.

## What the evidence said, including where it corrected the plan

`docs/research/2026-08-14-screenshot-encoding-for-vision-models.md` already had
the numbers, and two of them shaped this:

- **The bifurcated pattern is measured, not just tidy.** A low-resolution
  overview plus an on-demand native crop lifts grounding accuracy on dense
  professional interfaces from under 20% to over 70%. So escalation is not a cost
  compromise; it reads *better* than one large frame.
- **Anthropic's own computer-use reference implementation targets XGA
  (1024×768)** for reliability rather than the ceiling it also publishes.
- **Gemini charges `ceil(w/768) × ceil(h/768) × 258`**, so 769 pixels costs
  double what 768 does.

It also killed an idea before it was built. The research recommends WebP as 25 to
35% smaller than PNG, and that is a real finding about *bytes* and irrelevant
here: `ImageEncoding.swift` already records that Proctor returns a **path, never
bytes**, so file size never reaches the model's context and macOS ships no WebP
encoder anyway. Its header states the rule this item then implements: *a caller
who wants a thumbnail should ask for fewer pixels, not fewer bits per pixel.*

## What was built

`VisionCapture.Purpose` with three tiers, each carrying both a long-edge and a
pixel ceiling for the reason `defaultMaxPixels` exists — a near-square frame can
sit under the long edge on both sides and still be over budget.

| Tier | Long edge | Pixels | For |
|---|---|---|---|
| `targeting` | 768 | 400k | Deciding what to press and where |
| `verify` (default) | 1024 | 750k | Checking what happened |
| `detail` | 1568 | 1.15M | Reading dense text; the old default |

Measured on a 3456×2018 window:

| Tier | Result | Est. tokens |
|---|---|---|
| native | 3456×2018 | 9,299 |
| `detail` | 1403×819 | 1,532 |
| `verify` | 1024×598 | **816** |
| `targeting` | 768×448 | **459** |

So the new default costs 53% of the old one, and a targeting frame 30%.

**`annotate` implies `targeting` on its own.** A frame carrying numbered marks is
being used to pick a target rather than to read anything, and a numeral survives a
downscale that body text would not. This is the rule that makes marks and a small
frame belong together rather than being two separate knobs.

Precedence is explicit: an explicit `normalizeMaxLongEdge`/`normalizeMaxPixels`
wins outright **and clears the tier label**, because once a caller has named the
numbers no tier describes them and reporting one would be a label rather than a
fact. Otherwise a named `purpose` wins. Otherwise `annotate` decides.

`normalization` now reports `purpose` and `estimatedVisionTokens`, taken over what
was actually written rather than over the tier's budget, so a frame already under
the ceiling is not reported as costing more than it does.

## The larger saving is not in this item

The tool description now leads with it: **pixels are usually the wrong instrument
entirely.** `proctor_find` answers "what can I press" as text for a fraction of an
image, and returns a node id that is a more durable target than a coordinate. A
step's own `stateHash` answers "did that change anything" for free, and two
identical hashes are a stronger answer than two screenshots compared by eye.

That is not theoretical: the Apple Developer flow driven this session — sign in,
navigate, fill two fields, register, verify — used **zero** captures for
targeting. Every step resolved through `find` and acted by node id.

## Not in scope

Capturing only the dirty region for a verification frame. Proctor already computes
`dirtyRectCount` and `dirtyArea`, so cropping a verification capture to what
actually changed is the obvious next saving, and it is a separate item because it
changes what a frame *contains* rather than how large it is.

## Evidence

`CapturePurposeTests`, 10 tests: the tier arithmetic, the Gemini boundary, strict
ordering, the measured saving, aspect-ratio preservation across all three tiers,
the pixel ceiling still binding on a near-square frame, parsing refusing an
unknown name rather than guessing, and normalisation never enlarging a frame that
was already small.

Gate: **1447 tests in 160 suites pass in 6.7s**.
