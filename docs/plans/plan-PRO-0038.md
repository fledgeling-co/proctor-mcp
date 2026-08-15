# Implementation plan — PRO-0038: Stability knows when it is scoring a page

**Spec:** `docs/specs/spec-PRO-0038.md`
**Branch:** `ai/pro-0038` (worktree `.worktrees/PRO-0038`)
**Plan size:** Small
**Baseline:** `swift build` green; `./scripts/test.sh` = **1293 tests in 140 suites passed**

## Shape of the change

Two facts get produced where they can be measured honestly, and consumed where a
determinism claim is read from.

1. **At the step, in the one shared step loop:** which side of the browser page
   boundary this step's target fell on. Written onto `StepResult`.
2. **At the fold, in the sweep:** a hash Proctor cannot vouch for is not folded, and
   every step's entry says what its number was taken over and what it was computed
   from.

Nothing new detects a browser. `BrowserCatalogue.identify`, `AXEngine.webContent` and
`WebContentProbe.contains` are PRO-0020's and are consumed unchanged.

## Files

| File | Change |
|---|---|
| `Sources/ProctorCore/BrowserTarget.swift` | add `HashSubject` enum beside the existing boundary vocabulary |
| `Sources/ProctorCore/Wire.swift` | `StepResult.hashSubject`; `StabilityStepBasis`; `PageContentDisclosure`; two fields on `StabilityReport` |
| `Sources/ProctorAgent/Session/SessionAct.swift` | split `browserTargets` into a per-step primitive; classify each step in `runSteps` |
| `Sources/ProctorAgent/Session/SessionFlow.swift` | withhold an unvouched hash; collect subjects and withheld counts; assemble the two new report fields |
| `Sources/ProctorCore/ToolCatalogue.swift` | `proctor_stability` description says a score can be taken over page content |
| `Tests/ProctorAgentTests/Fakes.swift` | `FakeAX.failPerformWith` so a test can make a step indeterminate |
| `Tests/ProctorCoreTests/StabilityDisclosureTests.swift` | new — wire shapes, Codable tolerance, the fold's thin-column rule |
| `Tests/ProctorAgentTests/StabilityPageContentTests.swift` | new — end-to-end wiring through a real `Session` |
| `CHANGELOG.md` | `## [Unreleased]`, prose through `/create-luke-content` |

## Step 1 — `HashSubject` (BrowserTarget.swift)

Beside `BrowserSurface`, because it is the same boundary's vocabulary.

```swift
public enum HashSubject: String, Codable, Sendable, Equatable {
    case pageContent      // inside a web area: the hash is over a render tree
    case browserChrome    // outside every web area: the application's own tree
    case unclassified     // a browser window, and the step named no resolvable target
}
```

`unclassified` is a value rather than an absence because absence has to mean one thing
(spec A10). Absence means *no browser renders this window*.

## Step 2 — the wire (Wire.swift)

On `StepResult`, below the "omitted when nil" line, so a native step encodes exactly as
before:

```swift
public var hashSubject: HashSubject?
```

Set through the existing initialiser's new defaulted parameter — **not** through
`carry(_:)`, which folds facts off `Actuation` and this is not one of them.

Two new types and two new fields on `StabilityReport`. **Optional is what makes `Codable`
tolerate a missing key; omitting the `init` default is a separate decision** — it forces
all three existing construction sites to state the value, so a site that forgot one
cannot assert the wrong thing silently. PRO-0051 established both and the first draft of
this plan ran them together; the gate was right to separate them.

```swift
public struct StabilityStepBasis: Codable, Sendable, Equatable {
    public var step: Int
    /// Every distinct subject the repeats produced, in first-seen order. More
    /// than one means the repeats disagreed about which side of the boundary
    /// this step fell on, which is a finding about the flow rather than about
    /// the application. Absent when no browser rendered the window.
    public var subjects: [HashSubject]?
    /// Repeats that contributed a hash to this step's score. Taken from the
    /// fold's own column count — never recomputed here.
    public var samples: Int
    /// Repeats whose hash was withheld because Proctor could not vouch the step
    /// happened. Omitted when none were.
    public var withheld: Int?
    /// This step's instability — absent below two samples, because
    /// `Canonical.instability` returns 0.0 for a column of one hash and a step
    /// measured once must not read as five agreeing repeats.
    public var instability: Double?
}

public struct PageContentDisclosure: Codable, Sendable, Equatable {
    public var browser: String
    public var bundleId: String
    /// Steps measured over a render tree in **at least one** repeat. A step that
    /// was page content in one repeat and browser chrome in another appears
    /// here and also carries two `subjects`, which is what says its number is
    /// attributable to neither side. Erring toward disclosing is the direction
    /// `BrowserTarget` already states as the safe one for an advisory.
    public var steps: [Int]
    public var evidence: String  // BrowserTarget.evidence, verbatim
}
```

```swift
public var stepBasis: [StabilityStepBasis]?
public var pageContent: PageContentDisclosure?
```

`stepBasis`, when present, holds one entry per step `0..<stepCount` so a reader can index
it in parallel with `stepInstability`. It is nil only when there is nothing to disclose:
no browser rendered the window **and** no repeat withheld a hash.

## Step 3 — classify at the step (SessionAct.swift)

**Split the existing resolver rather than writing a second one.** `browserTargets`
currently resolves a whole batch with an internal frame cache; extract the per-step half:

```swift
private final class TargetCache { var frames: [String: Rect?] = [:] }

private func browserTarget(for step: ActionStep, window: WindowHandle,
                           cache: TargetCache? = nil) -> Rect?
```

`browserTargets(for:window:)` keeps its cache and its exact current behaviour by passing
one. **`runSteps` passes none** — a frame resolved before an earlier step ran is exactly
the staleness spec A2 exists to remove, so per-step classification re-resolves.

Once per `runSteps` call, beside where `app` is already bound:

```swift
// The catalogue lookup runs first, so a window no browser renders costs one
// dictionary lookup and no accessibility traffic — the rule browserHandoff
// already follows.
let renderedBy = BrowserCatalogue.identify(bundleId: app?.bundleId)
```

Per step, next to `hashBefore` (line ~401), which is the last thing read before the step
acts:

```swift
private func hashSubject(for step: ActionStep, window: WindowHandle) -> HashSubject {
    guard let rect = browserTarget(for: step, window: window) else { return .unclassified }
    guard let probe = try? ax.webContent(window: window.id), !probe.areas.isEmpty
    else { return .browserChrome }
    return probe.contains(rect) ? .pageContent : .browserChrome
}
```

The value is carried onto **both** exits that produce a `StepResult` with a hash: the
success path (~line 549) and the indeterminate path (~line 480). The refusal and
generic-failure paths carry it too, so a browser window's step is never silently absent.

Cost, stated because it is real: on a browser window this is one `ax.node(id:)` and one
`ax.webContent(window:)` per step. Both are bounded walks and both are paid only by
browser windows.

## Step 4 — withhold the unvouched hash (SessionFlow.swift)

In `stabilityInLane`'s hash-collection loop, before the tile branch:

```swift
// A hash taken after an action Proctor cannot vouch happened is not a sample
// of that step's post-state. Judged on the backend's own flag and NEVER on the
// error code — PRO-0045's rule, because a code can arrive from another domain.
// The hash stays on the StepResult and in the trail as evidence; only the score
// refuses it. PRO-0049 settles the same question the same way for a repeat that
// never reached the app.
if run.results[index].error?.indeterminate == true {
    withheld[index, default: 0] += 1
    notes.append("Run \(runIndex) step \(index): the backend could not say whether this "
               + "step happened, so its post-state was withheld from the score and kept "
               + "as evidence on the step.")
    break
}
```

`break`, not `continue`: an indeterminate step sets `failedAt` and ends its repeat, so
there is nothing after it, and `continue` would left-shift the later hashes and compare
the wrong steps. **That truncation is load-bearing and is pinned by its own test**
(`anIndeterminateStepIsTheLastResultInItsRepeat`) — the gate was right that the `break`
becomes lossy the day something lets such a step continue, and an assumption that costs
one test is not worth carrying unpinned.

The short column is what already makes `complete` false and keeps `deterministic`
withheld — spec A8b, now pinned.

### One fold, three consumers — no second write path

The gate's sharpest point on the plan was that `stepInstability` and the entry's
`instability`/`samples` are the same fact written twice, and would drift the moment
`samples` came to mean something other than the folded column's length.

So they are not written twice. **`StabilityScore.Fold` gains `samples: [Int]`**, computed
in the one loop that already computes `column`, beside `stepInstability`. The report's
entry reads `score.samples[i]` and `score.stepInstability[i]`; the legacy array is the
same `score.stepInstability`. There is one computation and no arithmetic outside the
fold, so the two surfaces cannot disagree by construction rather than by test. The
agreement test stays as a regression guard, not as the mechanism.

`stabilityReport(...)` gains `withheld`, `subjects` and `browser` parameters and builds
the two new fields. `instability` on an entry is `score.stepInstability[i]` when
`score.samples[i] >= 2` and nil otherwise.

## Step 5 — the catalogue (ToolCatalogue.swift)

One paragraph on `proctor_stability`: a state hash inside a browser's web area is taken
over the page's render tree, the report says per step when that happened, and a step
whose outcome could not be established is withheld from the score rather than folded
into it.

## Tests, one per acceptance clause

Filter on the Swift **function** name, never the `@Test` display string, and read the
`with N tests` count back.

| Clause | Test |
|---|---|
| A1 one detection | `nonBrowserWindowReadsNoWebContent` — `FakeAX` on a native bundle id; assert `hashSubject` absent and `webContent` never consulted |
| A2 classified at the step | `aWebAreaThatAppearsMidFlowIsStillClassified` — probe nil for step 0, set before step 1; step 1 reports `pageContent` |
| A3 per step | `aFlowTouchingChromeThenPageReportsBoth` — two steps, two frames, two subjects by index |
| A4 score still returned | `pageContentStillScoresAndStillVerdicts` — a page-content sweep returns `stepInstability`, `firstDivergence` and `deterministic: true` |
| A5 one sentence, once | `theDisclosureNamesTheBrowserAndCarriesTheEvidence` — equals `BrowserTarget.evidence` |
| A6 unvouched not folded | `anUnvouchedHashIsNotFolded` — **red-to-green**: with the withhold removed the score changes |
| A7 evidence survives | `theWithheldHashStaysOnTheStep` — `StepResult.stateHash` still present |
| A8 thin column not published | `aScoreOnOneSampleIsNotPublishedAsANumber` — `samples == 1`, `instability == nil`, legacy array still `0.0` |
| A8b verdict withheld | `aSweepHoldingAnUnscoredStepIsNotDeterministic` |
| A9 disagreement reported | `repeatsThatDisagreeAboutTheBoundaryReportBoth` |
| A10 absence means one thing | `everyStepOfABrowserWindowCarriesASubject` — including `unclassified` for a targetless step |
| A11 old records decode | `stabilityReportWithoutTheNewFieldsStillDecodes`, `aNativeSweepEncodesNoNewKeys` |
| A12 catalogue | asserted on the description string containing the page-content sentence |
| agreement | `entryInstabilityAgreesWithTheLegacyArray` — a regression guard on a value the fold now computes once |
| truncation | `anIndeterminateStepIsTheLastResultInItsRepeat` — pins the assumption the `break` in step 4 rests on |

## Out-of-family plan review — grok-4.6, xhigh, read-only

Run on the plan with the fold's arithmetic and the existing shapes inlined, asked for
compile breaks and functional errors rather than style. Six findings; four accepted, two
rejected on measurement.

**Rejected — `identify(bundleId: app?.bundleId)` will not compile.** Measured:
`BrowserCatalogue.identify` takes `String?`. It compiles.

**Rejected — a handwritten `CodingKeys`/`init(from:)` would need the new properties.**
Measured: the only custom `init(from:)` in `Wire.swift` is `JSONValue`'s. `StepResult`
and `StabilityReport` both use synthesised `Codable`. Worth having checked.

**Accepted — Optional and "no init default" do different jobs**, and the plan ran them
together. Optional is what makes `Codable` tolerate a missing key; the absent default is
what forces the three construction sites to be explicit. Both are wanted; the reason
given for the second was the reason for the first. Corrected in step 2.

**Accepted — the `break` is only safe because `runSteps` truncates.** True today and now
pinned by a test rather than asserted in a comment.

**Accepted — two write paths for one number will drift.** The strongest finding on the
plan. Answered structurally: the fold gains `samples: [Int]` and every consumer reads the
one computation, so drift is impossible rather than merely tested for.

**Accepted — a mixed-subject step leaves the disclosure undefined**, and both obvious
choices are wrong. `PageContentDisclosure.steps` is now defined as page content in at
least one repeat, with the entry's two `subjects` carrying the fact that the number is
attributable to neither side.

## Risks

- **`webContent` per step on a browser window** is the only new per-step cost. Bounded
  (4000 nodes, depth 40, stops at each web area) and paid by browser windows alone.
- **`Fakes.swift` is shared.** `failPerformWith` is additive with a default, so no
  existing suite changes behaviour.
- **`runSteps` is the shared path** for `act`, `flowReplay` and `stability`. The new
  field is additive and nil for every native window, so `act`'s golden output is
  unchanged — pinned by `aNativeSweepEncodesNoNewKeys`.
