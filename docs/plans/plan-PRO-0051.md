# Plan — PRO-0051: The native planes stay, chosen deliberately, and the record says so

**Spec:** `docs/specs/spec-PRO-0051.md`
**Plan size:** Small
**Branch:** `ai/pro-0051` (worktree `.worktrees/PRO-0051`, from `main` @ `107cdbb`)
**Gate:** `swift build` + `./scripts/test.sh`

The decision is the deliverable and it is in the spec. The code that follows is small on
purpose: PRO-0044 already built the lane, made it explicit and stopped it changing
mid-run, and measurement showed a second suspected gap did not exist. What is left is a
run-level statement of the lane on the three surfaces that carry a record, one guard
hardened, and three comments that describe the wire or the decision wrongly.

## What is already true, and therefore not built

Recorded so the implementer does not build it twice:

- **`PROCTOR_ACTUATION` unset already selects the native backend** — `main.swift`
  `makeActuationBackend`, one construction site.
- **`Session.actuator` is already `let`** (`Session.swift:26`), so a session's backend is
  already immutable for its life. A2's third mechanism needs a test, not a change.
- **A step that actuated already encodes its backend, including native.** Verified by
  encoding a `StepResult` after `carry(_:)`: `{"backend":"native", …}`. `Actuation.backend`
  defaults to `.native` and `carry` copies it unconditionally.
- **A step that never actuated already carries no backend** — the four
  `StepResult(… ok: false, plane: nil …)` sites in `SessionAct.swift` (289, 340, 413, 433)
  never call `carry`.
- **A cross-backend replay is already refused** — `SessionFlow.requireSameBackend`.
- **A flow already stamps every recorded step** — `appendToFlow` writes
  `result.backend ?? actuator.id`.

## Slices

### Slice 1 — The wire carries a run-level lane (`Sources/ProctorCore/Wire.swift`)

1. **`ActResult` gains `backend: ActuationBackendID?`, with no default in `init`.** The
   optionality and the absent default are each load-bearing and were each forced by the
   plan's out-of-family gate.

   **Optional, because an existing test guarantees an older record still decodes.**
   `ForegroundDisclosureTests.absentBlockDecodes` decodes
   `{"window":"w1","steps":[],"completed":0}` into an `ActResult` under the comment *"an
   act result without the block still decodes, so an older reader is not broken"*. A
   non-optional field breaks that: Swift's synthesised `init(from:)` requires the key
   however the memberwise `init` is defaulted, which is the specific trap the gate named.
   The clause is about what a **record** says, not about what the type permits, and a test
   asserting every emitted record carries the field enforces it exactly.

   **No default, because a default would be a lie rather than a gap.** Defaulting to
   `.native` would let any construction site that forgot to pass one encode `native` under
   a Cua session — a record asserting the wrong lane. With no default every site must
   choose, and a site that somehow produced nothing yields an absent field, which reads as
   "this build did not say" and is detectable. Absent is honest; wrong is not.

2. **`StabilityReport` gains `backend: ActuationBackendID?`**, same shape, same reasoning.

3. **Fix the stale comment above `StepResult.backend`.** It currently reads that every
   field below that line is "omitted when nil, so a step the native backend ran encodes
   exactly as it did before any of this existed". True of `reportedMode`, `effect`,
   `retriedOnStale`, `unrequestedForeground` and `transportMs`; false of `backend`, which
   is the field this item is about. Move the note below `backend` and say what `backend`
   actually does: present when the step actuated, absent when it never did.

Because there is no default, the three existing constructions must pass a value:
`TakeoverTests`, `ContentionTests` (`ActResult`) and `ProctorCoreTests.swift:2133`
(`StabilityReport`). Three lines, and forcing the choice is the point.

### Slice 2 — The three record surfaces state the lane

1. **`SessionAct.swift:126`** — pass `backend: actuator.id` into `ActResult`.
2. **`SessionFlow.flowReplay`** — add `"backend": .string(actuator.id.rawValue)` to the
   `out` dictionary, beside `"flow"` and `"window"`. It is an ad-hoc `JSONValue` object
   rather than a Codable struct, so it is set explicitly.
3. **`SessionFlow.stabilityReport`** — add a `backend: ActuationBackendID` parameter and
   set it on the returned `StabilityReport`. It is `private static`, with four call sites
   (361, 392, 460, 467), all inside `Session` methods where `actuator.id` is in scope.

### Slice 3 — Harden the same-backend guard (`SessionFlow.requireSameBackend`)

Today it takes `recorded.first` and compares. Change it to one rule: **every backend the
tape carries must equal the session's**, rather than only the first one.

The plan's first draft added a second rule — "refuse a tape holding more than one
backend" — and the gate was right that it is both redundant and dangerous. Redundant
because a mixed tape necessarily contains at least one backend differing from the
session's, so the first rule already refuses it. Dangerous because "holds more than one"
reads naturally as a count of backend-bearing steps, and every legitimate multi-step tape
has several — an implementation taking that reading would refuse every real flow. Dropped;
one rule, no cardinality.

Steps carrying no backend are skipped (`compactMap` already does this), so a tape mixing
actuated steps with steps that never actuated is unaffected. Keep the existing behaviour
for a tape carrying no backend at all: replay without complaint, because it was recorded
when the native planes were the only ones there.

Unreachable today by construction (see "already true" above), which is why it is a small
change rather than a project.

### Slice 4 — The code stops calling the decision provisional

Comment-only, no behaviour:

- **`main.swift` `makeActuationBackend`** — currently says "the item that decides the
  native planes' long-term future is a separate one, and until it lands both paths exist".
  Replace with the settled decision: native is the default, kept deliberately, and the
  reasons in one line each (two step kinds Cua cannot perform, windows on another Space,
  a driver never executed here).
- **`CuaDriverTool.laneEnv`** — currently "which stay the default until the item that
  decides their future says otherwise". Replace with the settled statement and note that
  the lane is operator-scoped and fixed for the process.

### Slice 5 — Tests, one per acceptance clause

New file `Tests/ProctorCoreTests/NativePlaneRecordTests.swift` for the wire, and additions
to `Tests/ProctorAgentTests/ActuationSeamTests.swift` for the session wiring (it already
holds the seam's tests and its harness builds a `Session` with an injected backend).

| Clause | Test |
|---|---|
| A1 | existing agent suite green + finalize-gate `git diff` on `Actuator.swift` (no unit test can certify a non-change) |
| A2 | `makeActuationBackend` returns native for an environment without the variable, and for one whose value is not `cua`; a `Session`'s `actuator` is the one it was built with after the environment is mutated |
| A3 | encoding an `ActResult`, a `StabilityReport` and a `flowReplay` result each contains a backend; an `ActResult` whose every step refused before actuation still contains one |
| A4 | a `StabilityReport` carrying `deterministic` carries a backend |
| A5 | a `StepResult` after `carry` encodes `"backend":"native"`; one built for a pre-actuation refusal encodes none |
| A5b | every actuated step's backend in a run equals the run's backend |
| A6 | a `RecordedFlow` with no backends replays; one whose backends are all the other lane refuses; one whose *later* steps differ from the session refuses (the case the old first-only check missed); a legitimate multi-step same-backend tape replays |
| A6b | the passes folded into one `StabilityReport` all carry the session's single backend |
| A7 | not a runtime property — checked by reading the comment at review; noted in the progress table as such rather than given a fake test |
| A8 | same |

Plus one regression guard the gate asked for directly: **`absentBlockDecodes` keeps
passing unchanged**, and a sibling asserts that a `StabilityReport` JSON without
`"backend"` still decodes. Those two are the backwards-compatibility contract this change
is most likely to break.

A7 and A8 are comment changes. Asserting a comment's text in a test pins prose and breaks
on any rewording, which is worse than useless; they are verified at review and the
progress table says so rather than inventing a test that proves nothing.

### Slice 6 — Changelog

One entry under `## [Unreleased]`, prose written through `/create-luke-content` (format
`marketing`). Do not touch released sections, `ORCHESTRATOR.md` or the ledger.

## Verification

`swift build` then `./scripts/test.sh` — never a bare `swift test`, never piped. Read back
the `with N tests` count; a `--filter` matching nothing reports a green run of zero tests,
and `--filter` matches the Swift function name rather than the `@Test` display string.

Baseline before this branch: **1193 `@Test` cases, `swift build` green.**

## Risk, and where it lands

The one real risk is **wire churn**: `backend` becomes a key on every `act` response,
every replay result and every stability report. That is intended — the brief requires the
record to say which plane ran, and an omitted field cannot. It is purely additive: no
existing key changes shape or meaning, and a reader ignoring unknown keys is unaffected.

The risk the gate caught, now designed out rather than mitigated, is the **decode**
direction: a non-optional field would have broken `absentBlockDecodes`, an existing test
whose whole purpose is to prove an older `ActResult` still reads. Optional-with-no-default
keeps that guarantee while forcing every construction site to state the lane.

Nothing here touches `Actuator.swift`, the policy gate, the audit row, key material, the
HUD or the queue. PRO-0046 is in flight on supervision under delegation; the only file
both could plausibly reach is `SessionAct.swift`, and this change is one argument on one
existing constructor call.

## Out-of-family review — grok-4.6, read-only

Run on this plan with the evidence inlined and file reading forbidden, after an earlier
attempt on the spec spent its whole deadline exploring the repo without answering (logged
as a lane failure and retried, never treated as a pass). Three findings, all accepted, and
two of them would have failed the build or a test:

1. **Defaulting the new fields to `.native` is a trap, twice over.** A missed construction
   site would encode `native` under a Cua session — a record asserting the wrong lane —
   and, separately, an `init` default does *not* make `Codable` tolerate a missing key, so
   a non-optional field breaks decoding of any record written before it existed.
   **Verified against the repo:** `ForegroundDisclosureTests.absentBlockDecodes` decodes an
   `ActResult` from JSON with no such key and exists to guarantee exactly that. Slice 1
   redesigned to optional, no default.
2. **Slice 3's second refusal rule was redundant and over-refusing.** "A tape holding more
   than one backend refuses" is subsumed by the first rule, and its natural reading —
   a count of backend-bearing steps — would refuse every legitimate multi-step flow.
   Dropped; one rule.
3. **Exact-JSON and round-trip assertions could break on an added key.** Checked: no test
   asserts a key set or an exact JSON string for these types, and the only
   `StabilityReport` decode is a round-trip of a freshly encoded value. No breakage, and a
   compatibility test is added for both types anyway.

## Not in this plan

Everything in the spec's "Not in scope", plus: no flow-level backend field on
`RecordedFlow`. Every step of every tape this build writes already carries one, so a
flow-level field would be a duplicate rather than new information; slice 3 makes the guard
read all of them instead, which closes the same hole without a format change.
