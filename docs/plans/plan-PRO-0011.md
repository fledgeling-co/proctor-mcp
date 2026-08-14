# plan-PRO-0011: Pointer marker in stability per-step artifacts

**Spec:** docs/specs/spec-PRO-0011.md · **Branch:** ai/pro-0011 · **Tier:** Small

## What ships

`proctor_stability` gains two opt-in switches, `captureEach` and `pointerMarks`,
both defaulting to false. With `captureEach` on, every step of every replay writes a
PNG through the shared step-running path; with `pointerMarks` on as well, each of
those frames gets the PRO-0010 marker composited at the point that step acted on.
The report gains a `captures` ledger whose every entry names its replay index, its
step index and its file locations, so one step can be compared across replays.

Nothing about the scoring changes: `firstDivergence`, `stepInstability`,
`deterministic` and `divergenceDetail` are computed exactly as they are today, from
the same tree (and optionally tile) hashes. No new tool. No change to the stored
recording format. A caller who passes neither switch gets today's output, byte for
byte, at today's speed.

## Grounding — what already exists

- `Session.runSteps(_:window:settle:foreground:captureEach:diffEach:audit:pointerMarks:)`
  (`Sources/ProctorAgent/Session/SessionAct.swift`) already captures per step and
  already composites the marker: `captureForStep` calls `capture.capture(...)` then,
  when `pointerMarks`, sets `frame.pointer = pointerOverlay(for:window:capture:)`.
  Both switches are plumbed for `proctor_act` and `proctor_flow` replay.
- `Session.stability(flow:runs:window:resetBetween:includeTiles:)`
  (`Sources/ProctorAgent/Session/SessionFlow.swift:186`) calls `runSteps` with
  `captureEach: false, diffEach: false` — hardcoded. That is the whole gap.
- `includeTiles` captures in a loop **after** the replay result is in hand
  (`SessionFlow.swift:229-248`), so those frames all show the end state and are not
  per-step images. Left exactly as it is; the new per-step frames come from
  `runSteps`, which is what makes them per-step. (Spec grounding note.)
- `Session.pointerOverlay(for:window:capture:)`
  (`Sources/ProctorAgent/Session/SessionPointer.swift`) is best-effort by design: a
  step with no explicit point and no framed element yields no overlay rather than
  failing the capture.
- `PointerOverlay` (`Wire.swift:297`) carries `annotatedPath`, the marked sibling
  PNG; the un-marked PNG stays at `CaptureResult.path`.
- `StabilityReport` (`Wire.swift:550`) is the wire shape returned by
  `Dispatch.stability`.
- Only `ProctorCoreTests` exists and it depends on `ProctorCore` alone
  (`Package.swift`). So every red→green test lands in Core, and any logic worth
  proving must be pure and live there. This is the pattern PRO-0010 set: the
  checkable placement maths went to `ProctorCore/PointerMarker.swift`, the drawing
  stayed in the agent.

## Architecture

### 1. Core — `Sources/ProctorCore/StabilityCaptures.swift` (new, tested)

Three pure pieces, no window, no disk, no grant:

- **`StabilityCapture`** — one ledger entry: `run`, `step`, `path?`,
  `markedPath?`, `note?`. `run` and `step` together are the identity the spec
  requires; a flat per-step list could not say which replay a frame came from.
  `note` is where a step that produced no frame, or no marker, says so.
- **`StabilityCaptureOptions.resolve(captureEach:pointerMarks:)`** — reconciles the
  two switches and returns `(captureEach, pointerMarks, notes)`.
  - both off → `(false, false, [])`, so the default run is unchanged in output and
    in cost.
  - `pointerMarks` on with `captureEach` off → returns `captureEach: true` plus a
    note saying capture was switched on because a marker needs a frame to be drawn
    on. The spec is explicit that this must not be silently ignored the way the
    replay tool ignores it today.
  - capture on (asked for, or forced) → a note that per-step capture adds time to
    every step, so this run's timings are not comparable with a run captured off and
    its determinism score should not be compared against one either.
- **`StabilityCaptureOptions.entry(run:step:capture:failure:pointerMarksRequested:)`**
  — derives one `StabilityCapture` from what a step actually produced:
  - a capture with a `pointer` → `path` and `markedPath` both set.
  - a capture with no `pointer` and marks requested → `path` set, `markedPath` nil,
    `note` explaining the marker had no target (a `type` or `key` step carries
    neither an explicit point nor a framed element).
  - a capture with no `pointer` and marks not requested → `path` only, no note.
  - no capture → `note` carrying the failure reason, no paths. The run continues and
    the score is untouched; a failed frame is carried alongside the step exactly as
    a failed capture already is elsewhere.

### 2. Agent — typed per-step captures on `StepRun`

`StepRun.captures` is `[JSONValue]` today, which stability cannot read paths out of
without re-parsing JSON. Replace the stored array with a typed one and make the
JSON a projection of it:

- new `Session.StepCapture { index, result: CaptureResult?, error: AgentError?,
  errorText: String? }` with a `json` property that reproduces today's three shapes
  exactly (`{step, capture}`, `{step, error: <encoded>}`, `{step, error: "<text>"}`).
- `StepRun.stepCaptures: [StepCapture]` stored; `StepRun.captures: [JSONValue]`
  becomes computed as `stepCaptures.map(\.json)`, so `proctor_act` and
  `proctor_flow` replay emit byte-identical output and neither call site changes.
- `captureForStep` returns `StepCapture` instead of `JSONValue`.

### 3. Agent — `Session.stability` carries the switches

`stability(flow:runs:window:resetBetween:includeTiles:captureEach:pointerMarks:)`:

- resolve the switches once, up front, and seed `notes` with what `resolve` returned.
- pass the resolved `captureEach` / `pointerMarks` into the per-run `runSteps` call.
  The reset sequence between replays keeps `captureEach: false` — a reset is
  scaffolding to return the app to its start state, not a step of the flow being
  measured, so photographing it would put frames in the ledger for steps that are
  not in the flow.
- after each run, when capture is on, append one `StabilityCapture` per attempted
  step from `run.stepCaptures`, via the Core `entry` function, with the run index.
  Steps a run never reached (it ended early) get no entry: they were not attempted,
  so reporting them as having failed to produce a frame would be a different and
  false claim.
- hand the accumulated ledger to `StabilityReport.captures`, nil when capture was
  off.

### 4. Wire — `StabilityReport.captures`

`public var captures: [StabilityCapture]?`, added to the init with a `= nil`
default so the single existing call site is unaffected and an off run encodes to
exactly the same JSON as today (a nil optional is omitted).

### 5. Surface — catalogue and output schema

- `ToolCatalogue.stability` inputSchema gains `captureEach` and `pointerMarks`. The
  `captureEach` description names the volume cost the spec asked for: roughly
  `runs × steps` PNGs, doubled where a marker is drawn, with no clean-up. The
  `pointerMarks` description carries the honesty caveat verbatim in spirit — it
  annotates where the step acted, not a live cursor — and says it turns capture on
  when capture is off.
- `ToolOutputSchemas` `proctor_stability` gains `"captures": p("array")`.

### 6. Explicitly not in scope

Divergence/hash logic, `includeTiles` behaviour, retention or size limits, a live
cursor sprite, and the policy/audit gating of this tool (PRO-0012 owns that).

## Files

| File | Change |
|---|---|
| `Sources/ProctorCore/StabilityCaptures.swift` | **new** — `StabilityCapture`, `StabilityCaptureOptions.resolve`, `.entry` |
| `Sources/ProctorCore/Wire.swift` | `StabilityReport.captures: [StabilityCapture]?` |
| `Sources/ProctorCore/ToolCatalogue.swift` | two new properties on the stability input schema |
| `Sources/ProctorCore/ToolOutputSchemas.swift` | `captures` on the stability output schema |
| `Sources/ProctorAgent/Session/SessionAct.swift` | `StepCapture`; `StepRun.captures` computed; `captureForStep` returns typed |
| `Sources/ProctorAgent/Session/SessionFlow.swift` | `stability` takes and honours the two switches, builds the ledger |
| `Sources/ProctorAgent/Dispatch.swift` | read the two args |
| `Tests/ProctorCoreTests/ProctorCoreTests.swift` | new suite, one test per acceptance clause |

## Acceptance clauses → the test that proves each

| # | Clause | Test |
|---|---|---|
| A1 | Both switches off by default; an unset run behaves and encodes exactly as today | `resolve` with both off returns no notes and no capture; `StabilityReport` with nil `captures` encodes without the key |
| A2 | `pointerMarks` with capture off turns capture on and says so | `resolve(captureEach: false, pointerMarks: true)` returns `captureEach == true` and a note naming the reason |
| A3 | A capture-on run reports that timings shifted | `resolve` with capture on returns a note about timings and comparability |
| A4 | Every entry carries its replay number, its step number and its file locations, for every step a replay *attempted* | `entry` sets `run`, `step`, `path`, `markedPath`; a two-run ledger round-trips through Codable keeping run identity |
| A5 | A step whose frame or marker could not be produced is reported as such, without failing the run or changing the score | `entry` with no capture yields a note and no paths; `entry` with a capture but no overlay and marks requested yields `path`, nil `markedPath` and a note |
| A6 | Scoring is untouched | `StabilityReport` still encodes `firstDivergence` / `stepInstability` / `deterministic` / `divergenceDetail` unchanged with the ledger present |
| A7 | The volume cost is stated on the switch, and the marker is described as where the step acted rather than a cursor | `ToolCatalogue.stability` schema test asserts both properties exist and the descriptions carry the cost and the caveat |
| A8 | The ledger is advertised on the output schema | `ToolOutputSchemas` test asserts `captures` |

## Gate

`swift build` + `swift test`. 173 tests / 24 suites green at HEAD; the new suite adds
to that and the existing count must not drop.

## Out-of-family plan review — 2026-08-14

Ran on grok (`grok-4.6`, effort `xhigh`, read-only, 240s alarm) per the repo's
external-CLI policy, with the spec assumptions, the current code and the plan all
inlined into the prompt. Codex is off in this repo and was not invoked. Verdict:
"well grounded … not locked to the spec as written", with three High, three Medium
and one Low. Dispositions:

- **H1 — "every step of every replay" was untestable** (ledger assembly sat in the
  agent, which `ProctorCoreTests` cannot see). **Accepted.** `StabilityCaptureOptions.ledger`
  moved into Core; a 2-replay × 3-step fixture asserts six rows in `(run, step)` order.
- **H2 — A5/A6 did not prove what they claimed** (the "does not fail the run or
  change the score" half is computed in the agent from `perRun` hashes).
  **Accepted in part.** Extracting the whole score fold into Core is a larger
  refactor than this item earns, so the claim is narrowed instead of overstated:
  A5/A6 now assert what Core can prove — an all-failed ledger yields entries with
  no paths, and the report's scores are untouched alongside it. The other half is
  structural rather than tested: the ledger is built from `stepArtifacts`, a
  different array from `results`/`hashes`, and `runSteps` sets `failedAt` only from
  actuation, never from capture, which happens after `completed += 1`. Recorded
  here as a known limit of the gate rather than claimed as proven.
- **H3 — the "byte-identical act/flow output" claim had no witness.** **Accepted.**
  The three-shape per-step encoder moved to Core as `StepArtifact.json`, with golden
  tests for all three shapes; the agent type was deleted rather than duplicated.
- **M1 — the missing-marker note overclaimed** ("no target" is a lie when the draw
  failed). **Accepted.** Reworded to "no target point, or the marker could not be
  drawn".
- **M2 — the `failedAt` step was attempted and silently omitted.** **Accepted.**
  `ledger` takes `failedStep` and emits a no-path entry for it; steps after it still
  get none, because they were never attempted.
- **M3 — "byte for byte when unset" was encoder-specific.** **Accepted.** The
  omission is now asserted through `JSONValue.encode`, the encoder the dispatcher
  actually returns the report with, as well as through `JSONEncoder`.
- **L1 — the dispatcher's argument keys were untested.** **Accepted.** The two names
  are constants in Core, used by both the catalogue and the dispatcher, and asserted.


## Out-of-family completeness critic — 2026-08-14

Two passes on grok (`grok-4.6`, `xhigh`, read-only). The first inlined `git diff HEAD`,
which omitted the untracked new Core file, so its "does not compile" line is an artifact
of that prompt defect; its other findings were read against the tests and stand. The
second pass ran on the full source and confirmed "the Core + agent wiring implements
A1-A8", with the objections aimed at the proof rather than the behaviour. Codex was not
invoked. Dispositions:

- **A6 was vacuous** (both passes). `scoringUntouched` round-tripped a hand-built report,
  so an agent that folded capture failures into the score would still have passed.
  **Accepted.** The score fold is extracted to `StabilityScore.fold(perRun:stepCount:runs:)`
  in Core, unchanged in maths. It takes hash columns and nothing else, so there is now no
  parameter through which a frame, a marker or a failed capture could reach a score, and
  `foldTakesHashesOnly` / `foldReportsShortRuns` prove the numbers directly.
- **`entry` wrote a `markedPath` for an overlay with an empty `annotatedPath`.**
  **Accepted.** An overlay with no file on disk is now reported as a missing marker.
- **The per-step golden tests were spot checks, not literals.** **Accepted.** All three
  shapes are now asserted by full equality against the object act and flow replay emitted.
- **A4 overstated coverage** ("every step of every replay"; steps after a failure are not
  photographed). **Accepted.** The clause, the schema description and the changelog now
  say every step that *runs*, and say what a broken replay reports instead.
- **The output schema advertised a bare `captures` array.** **Accepted.** It now describes
  the entry object (`run`, `step`, `path`, `markedPath`, `note`), asserted per field.
- **`StepArtifact`'s doc comment overclaimed** that all three tools emit the same JSON.
  **Accepted.** Reworded: the typed artifact is shared, only act and flow replay emit
  `json`, and stability encodes `StabilityCapture` because its report must name the replay.
- **A1/A4/A5 would stay green if `Session.stability` regressed.** **Accepted as a real
  limit, not closed here.** Every test lives in `ProctorCoreTests`, which depends on
  `ProctorCore` alone; `ProctorAgent` is an `executableTarget` and SwiftPM cannot link one
  into a test target. Covering the agent wiring means splitting `ProctorAgent` into a
  library plus a thin `main`, which is a repo-wide change touching every feature and is
  the orchestrator's call, not this item's. Logged as discovered child work. Extracting the
  fold shrank the uncovered agent surface to argument passing and ledger accumulation.
