---
sources: [REQ-023]
status: retired
validated-by: REQ-023 via CASE-0025, CASE-0088
validated-rungs: effect-witness, outcome
validated-provider: ProctorReflector in ProctorReflector/ProctorReflector.swift
---
# Backfill: `horizontalAlignment` on `proctor_assert`

## Why this brief exists

The code already shipped. Commit `2b917ed` added a `horizontalAlignment` assertion
kind to `proctor_assert` and its catalogue entry, straight to main, with no spec,
no plan, no tests and no changelog entry. The reader's decision on 2026-08-15 was
to keep it and backfill rather than revert, so this item writes the spec, adds the
tests, and fixes whatever the spec turns out not to be able to defend.

**Write the spec you would have written, not one shaped to ratify the code.** The
whole risk of a backfill is that the spec becomes a description of an
implementation instead of a decision about behaviour. Where the shipped code
cannot be defended, change the code.

## What it does today

`Sources/ProctorAgent/Session/SessionAssert.swift` resolves the subject's frame and a reference rect (an
explicit `container` from the spec, else the window frame), then:

```swift
let wanted = expected.stringValue?.lowercased() ?? "leading"
let isCentered = abs(frame.centerX - refRect.centerX) <= tolerance
let isLeading  = abs(frame.x    - refRect.x)    <= (tolerance * 3.0) && !isCentered
let isTrailing = abs(frame.maxX - refRect.maxX) <= (tolerance * 3.0) && !isCentered
let observedAlignment = isCentered ? "center" : (isLeading ? "leading" : (isTrailing ? "trailing" : "custom"))
let ok = (wanted == observedAlignment) || (wanted == "left" && isLeading)
```

Default tolerance is `8.0`. It returns `skipped` when the node exposes no frame
and when neither a container nor a window frame resolves.

## The questions the spec has to answer

Each of these is a real decision the code took silently:

- **Why `tolerance * 3.0` for the edges and plain `tolerance` for the centre?**
  Three is a magic number with no stated reasoning, and it makes an edge match
  three times looser than a centre match. Either justify it or make it one
  tolerance.
- **`"left"` is accepted as an alias for leading, and `"right"` is not accepted
  for trailing.** That asymmetry is almost certainly an oversight. Decide whether
  the vocabulary is leading/trailing (which respects right-to-left layouts and is
  what AppKit means) or left/right (which is what a person looking at a screen
  means), and then support one of them properly rather than one and a half.
- **`isCentered` pre-empts both edges.** In a container barely wider than the
  element, centre, leading and trailing are all true at once and the code silently
  reports `center`. Is that right? Say so, or report the ambiguity.
- **The default tolerance is `8.0` while the neighbouring `alignedWith` kind
  defaults to `1.0`.** Two alignment assertions on one tool with defaults eight
  times apart is a trap. Reconcile them or say why they differ.
- **How does this relate to `alignedWith`, which already exists?** If the answer
  is "`alignedWith` compares two elements and this compares an element to its
  container", that is a good answer and belongs in both the spec and the tool
  description. If the answer is that they overlap, one of them should go.
- **`"custom"` as an observed value.** It reads as a state rather than a failure.
  Check that a failure against `custom` produces a message a person can act on,
  since the reason string is what a model will relay.

## Scope

Spec, plan, tests, changelog, and whatever code changes the spec's answers
require. The acceptance bar is the repo's usual one: a red-green `swift test` per
acceptance clause. The kind is already advertised in `ToolCatalogue`, so the tool
count stays 19 and `theToolSurfaceGainsNoVerb` should keep passing.

## Worth knowing

- The suites `ObscuraPresenceWiringTests` and `BrowserLaneWiringTests` currently
  hang (PRO-0041). Gate with
  `swift test --skip ObscuraPresenceWiringTests --skip BrowserLaneWiringTests`
  and say so in the progress note.
- Geometry assertions have an existing house style in `Sources/ProctorAgent/Session/SessionAssert.swift`
  (`Outcome` with `observed`, `expected`, `reason`, `node`, `detail`). Match it.
