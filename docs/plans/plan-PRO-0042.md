# Plan — PRO-0042: Backfill `horizontalAlignment` on `proctor_assert`

**Spec:** `docs/specs/spec-PRO-0042.md`
**Tier:** Small
**Branch / worktree:** `ai/pro-0042` in `.worktrees/PRO-0042`

## Intent

Give the shipped `horizontalAlignment` kind the spec it never had, then make the
code match that spec rather than the reverse. Five of the six decisions in the
spec change behaviour; two more changes came out of reading the code. The
classification moves to `ProctorCore` so it can be tested without a window
server, following `RegionCrop` and `RegionDirt`.

## The one structural decision

The classifier is pure arithmetic over two rectangles and every wrong answer it
gives is indistinguishable from a right one, so it lives in Core and is tested
there exhaustively. `SessionAssert` keeps what needs the AX plane — resolving the
subject, resolving the container, falling back to the window — and the shaping of
the `Outcome`. Nothing else moves; `Rect.maxX`/`centerX` stay in
`Sources/ProctorAgent/Session/Predicates.swift` and Core computes its own from
`x + w`, so no existing file changes shape.

## Steps

### 1 — Core: `HorizontalPlacement`, the pure classifier

New file `Sources/ProctorCore/HorizontalPlacement.swift`.

- `public enum HorizontalPlacement: String, Sendable, Equatable, CaseIterable`
  with `left`, `center`, `right` — raw values are the reported observation
  (decision 2).
- `public static func parse(_ word: String) -> HorizontalPlacement?` —
  case-insensitive, trimmed, mapping `left`/`leading` → `left`,
  `center`/`centre` → `center`, `right`/`trailing` → `right`. Returns nil for
  anything else so the caller can skip rather than fail (decision 2).
- `public static let acceptedWords: String` — the list a skip reason prints.
- `public struct Reading: Sendable, Equatable` carrying `candidates:
  [HorizontalPlacement]` (those within tolerance, in left, center, right order),
  `leftOffset`, `rightOffset`, `centreOffset` and `tolerance`; computed
  properties `placement` (the nearest candidate, nil when there is none or when
  the nearest is tied), `tied: [HorizontalPlacement]` and `isCustom` (no
  candidate at all).
- `public static func read(element: Rect, container: Rect, tolerance: Double)
  -> Reading` — offsets are `element.x - container.x`,
  `(element.x + element.w) - (container.x + container.w)` and the same on
  centres; a placement is a candidate when its offset's magnitude is `<=`
  tolerance. One tolerance everywhere, no multiplier (decision 1). Among the
  candidates the smallest magnitude wins; candidates whose magnitude is within
  `tieWindow` (0.5pt, one device pixel at 2x, deliberately smaller than the
  default tolerance so the ranking still runs there) of that smallest are
  tied and leave `placement` nil (decision 3). A negative tolerance is clamped to
  0 so it cannot match everything.
- `public static func isMeasurable(_ rect: Rect) -> Bool` — `x` and `w` finite and
  `w >= 0`. A NaN makes every comparison false, so without this an unreadable
  frame classifies as a confident `custom` and a finite origin beside a NaN width
  as a confident `left`. Only the two fields the classification reads are
  checked.
- `Reading.describeOffsets()` — the sentence fragment the `custom` reason and the
  tie reason both need, so the wording lives in one place next to the arithmetic
  it describes (decision 6).

### 2 — Agent: rewrite `horizontalAlignment` in `SessionAssert.swift`

Replace the body. Order of gates, each returning `skipped` with a reason:

1. no subject → `fail` (unchanged, matches the file's other geometry kinds).
2. subject exposes no frame → `skipped` (unchanged).
3. `expected` absent or not a string → `skipped`, but only after the container
   and the reading resolve, so the entry still carries the observed
   classification (decision 8).
4. `expected` present and unparseable → `skipped` with `acceptedWords`
   (decision 2).
5. `container` supplied but not resolvable → `skipped`; container absent → the
   window frame, and `skipped` if that does not resolve either (decision 7).
   Distinguish absent from unresolvable by testing `spec["container"]` for nil
   and for `.null` before calling `referenceRect`.
6. the reading is tied → `skipped` naming the tied placements and the offsets
   (decision 3).
7. otherwise `pass`/`fail` against the nearest placement, or `custom` when there
   is no candidate.

`observed` is the physical word, or `.string("custom")`, or for the tied case an
array of the tied words. `expected` echoes the parsed placement's word so an
assertion written as `leading` reports `expected: "left"` against
`observed: "left"`. `detail` gains `tolerance`, the three offsets, the container
rect, `containerNode` when one was named, and `containerDefaultedToWindow`.
Reason strings stay lowercase sentence fragments, as everywhere else in the file.
The call site's `tolerance ?? 8.0` becomes `tolerance ?? 1.0` (decision 4).

### 3 — Core: the tool description states the boundary and the shared default

`Sources/ProctorCore/ToolCatalogue.swift`, `proctor_assert`'s description only —
the enum already lists the kind, so the tool count and the schema shape do not
move. Add a paragraph naming what `horizontalAlignment` classifies, that its
terms are physical rather than layout-direction-aware, that it defaults the
container to the window, and how it differs from `alignedWith` (decision 5). Both
now default to a 1.0pt tolerance, so the description says that once for the
geometry kinds rather than per kind (decision 4). Reflow the existing geometry
sentence so alignment is not described twice.

### 4 — Tests

New `Tests/ProctorCoreTests/HorizontalPlacementTests.swift` for clauses 1–7 of
the spec: the tolerance boundary at, on and just past `tolerance` on each of the
three offsets; symmetry between the left and right edges; the alias table
including case; the unknown word; the nearest fit resolving a compact container
(28 in 36 reads `left`); the tie skipping when an element fills its container;
the offset description carrying all three numbers.

`Tests/ProctorAgentTests/HorizontalAlignmentAssertionTests.swift` for the clauses
that are about the `Outcome`: unresolvable container, absent expectation, the
`custom` reason's content and its conditional container hint, and that the window
fallback still happens when no container was asked for. These need the assertion
path reachable without a window server — check what `Fakes.swift` already
provides for `ax` and follow the harness the existing wiring tests use; where the
`Session` actor cannot be driven without a grant, drive the same decision through
the Core reading plus a direct check of the reason builder rather than asserting
by code reading.

Tool-surface clause 11 is already covered by `theToolSurfaceGainsNoVerb`; confirm
it still passes rather than adding a second copy.

### 5 — Changelog

One entry under `## [Unreleased]`, written through `/create-luke-content` in
`marketing` format. It is a behaviour change to a kind that shipped a day ago, so
it says what the kind does and that its tolerance, vocabulary and ambiguity
handling changed.

## Acceptance criteria

Every spec clause maps to a named test:

| Clause | Test |
|---|---|
| 1 one tolerance | `toleranceAppliesEquallyToEdgesAndCentre` |
| 2 aliases | `aliasesParseToPhysicalWords` |
| 3 unknown word | `anUnknownWordParsesToNothing` + (Agent) skip with the list |
| 4 nearest fit | `theNearestPlacementWinsInACompactContainer`, `rankingSurvivesAtTheDefaultTolerance` |
| 5 tie | `anElementFillingItsContainerIsATie`, `theTieWindowIsTheRoundingAllowance` |
| 6 one default | (Agent) `theDefaultToleranceIsOnePoint` |
| 7 custom reason | `customNamesEveryOffset` + (Agent) `theHintIsConditional`, `aFailureNamesWhatItIsInstead` |
| 8 reference resolution | (Agent) `aContainerThatDoesNotResolveIsSkipped`, `anUnmeasurableContainerIsSkipped`, `aContainerCanBeARectangle`; `nonFiniteFramesAreRejected` + (Agent) `anUnmeasurableSubjectIsSkipped` |
| 9 absent expectation | (Agent) `noExpectationIsSkippedButStillObserves` |
| 10 no frame / no reference | (Agent) `aSubjectWithNoFrameIsSkipped`, `aWindowWithoutAFrameIsSkipped` |
| 11 tool surface | `theToolSurfaceGainsNoVerb`, unchanged |

Gate: `swift build` clean, then
`swift test --skip ObscuraPresenceWiringTests --skip BrowserLaneWiringTests`
(PRO-0041). Baseline on main today is 735 tests in 87 suites; the count must rise
by the new tests and nothing existing may go red.

Filters are read back with their `with N tests` count before any filtered green is
believed — `--filter` matches the Swift function name, not the `@Test` string.

## Not machine-witnessable

Whether 1.0pt is the right strictness against real macOS layouts. It is a
judgement recorded in spec decision 4, not a fact a test can settle.

## Plan review gate

The spec's own review ran out of family on grok and changed decisions 3 and 4
before this plan was written; the record is in the spec's Gates section. The plan
below it is a mechanical consequence of those decisions, so it carries that
review rather than buying a second one on the same evidence.
