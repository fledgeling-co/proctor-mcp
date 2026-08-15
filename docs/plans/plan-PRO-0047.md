# plan-PRO-0047: The run has a history you can read

**Spec:** [docs/specs/spec-PRO-0047.md](../specs/spec-PRO-0047.md)
**Branch:** `ai/pro-0047` · **Worktree:** `.worktrees/PRO-0047`
**Tier:** Large — three processes touched (Core, Agent, UI), one on-disk format extended,
one destructive operation added.

The spec carries the reasoning and the boundaries. This is the build order, the shape of
each piece, and what proves it.

## The shape, in one paragraph

`AuditRecord` gains six optional fields so a record can be grouped and read. A run id is
minted at the dispatcher's existing choke point and carried in a task local, so every
record written during one tool call shares it. `AuditLog` gains rotation, which is both
the retention cap and Clear. A new pure `RunHistory` in Core turns opened records into
runs; a new internal socket verb serves that projection; a new History window in the app
draws it. Everything decidable is pure and lives in Core, because `swift test` has no
window server.

## Phase 1 — Core: the record and the wording

**`Sources/ProctorCore/Policy.swift`**

`AuditRecord` gains, all optional and all after the existing fields so old sealed
entries decode unchanged:

| Field | Type | What |
|---|---|---|
| `run` | `String?` | The call this record belonged to. Nil for a record written outside one. |
| `seq` | `Int?` | Position within the run, 0-based. |
| `ms` | `Int?` | What the step cost, milliseconds. |
| `plane` | `String?` | Which plane it travelled. A raw string, not an enum, so an unrecognised value from a later actuation lane renders rather than fails to decode. |
| `act` | `String?` | Proctor's own past-tense verb phrase. Authored by Proctor, never fenced. |
| `obj` | `AuditRecord.Object?` | The object the phrase acted on: `{ text: String, supplied: Bool }`, sanitised at write. Foreign text; always fenced. |

`forStep` gains matching parameters with defaults, so its four existing call sites keep
compiling and only the ones that have the facts pass them.

**`Sources/ProctorCore/StepDescription.swift`**

- `sanitised(_:limit:)` — the existing routine gains a cap parameter defaulting to
  `objectLimit` (48). One implementation, two caps.
- `historyObjectLimit = 120` — the cap history persists at.
- `public static func pastVerb(for kind:) -> String` and
  `pastVerbAlone(for kind:) -> String` — the verb half of `completedLine`, so a caller
  can render the verb and the object separately.
- `public static func object(for step:node:limit:) -> (text: String, supplied: Bool)?` —
  the object half, **unquoted**, with its provenance. The existing quoted `objectText`
  is untouched; the HUD keeps it.
- `completedLine` is refactored to compose from the two new pieces rather than
  duplicating them, so the HUD's line and the record's two fields cannot drift.

**Tests** (`Tests/ProctorCoreTests/StepDescriptionTests.swift`, extended): the verb plus
the fenced object reproduce `completedLine` exactly for every kind; the longer cap
applies at the longer limit and still strips control, bidi and markup; the unquoted
object never contains a quotation mark it did not survive sanitisation with.

## Phase 2 — Core: the projection

**`Sources/ProctorCore/RunHistory.swift`** (new, pure)

```
public struct HistoryObject   { text: String; supplied: Bool }        // fenced by the UI
public struct HistoryStep     { seq, at, kind, act, obj, plane, ms, outcome, reason }
public struct HistoryRun      { id, tool, bundleId, startedAt, endedAt, outcome,
                                steps, recommendation, unreadable }
public enum   HistoryOutcome  { ok, failed, refused, halted, recommended, mixed }
public enum   RunHistory {
    static func runs(from: [Entry], limit: Int) -> [HistoryRun]
}
```

`Entry` is either a decoded `AuditRecord` or an `unreadable` marker, so an entry the
agent could not open is counted in place rather than dropped.

Grouping rules, each its own test:

- Records sharing a `run` become one run, ordered by `seq` then timestamp.
- A record with no `run` becomes a run of one — that is a person's Stop, a hold, or any
  record written before this shipped.
- The run's tool and bundle id come from its records; a run whose records disagree about
  the bundle id keeps the first and is not merged with anything else.
- Outcome reduction: `refused` if any record is refused and none is ok; `halted` when the
  refusal reason is the person-halted code; `failed` if any failed; `recommended` for a
  lone recommendation; `ok` when all are ok; `mixed` otherwise.
- Span is first timestamp to last; a single-record run has a zero span and shows no
  duration rather than "0 ms".
- Newest run first; steps oldest first inside it.

Nothing here reads a file, a clock it is not given, or the keychain.

## Phase 3 — Core: the retention decision

**`Sources/ProctorCore/HistoryRetention.swift`** (new, pure)

```
public struct RetentionCaps { days: Int; entries: Int
                              static func read(from env:) -> RetentionCaps }   // clamped
public enum RetentionDecision { case keep, rotate(Reason) }
public enum RetentionReason   { case age(days: Int), size(entries: Int), person }
public static func decide(entries: Int, oldest: Double?, now: Double,
                          caps: RetentionCaps) -> RetentionDecision
public static func rotationNote(...) -> String     // the attested wording
```

`PROCTOR_HISTORY_DAYS` clamps to 1…90 (default 14); `PROCTOR_HISTORY_ENTRIES` clamps to
100…100,000 (default 10,000). An unset, empty, non-numeric or out-of-range value takes
the default or the nearer bound — there is no value meaning "unbounded".

**Tests:** each cap fires on its own; a nil `oldest` (an anchor written before this
ships) leaves the age cap dormant and the entry cap live; every clamp boundary; a clock
moved backwards does not rotate; the wording names which cap and how many entries.

## Phase 4 — Agent: run identity

**`Sources/ProctorAgent/RunIdentity.swift`** (new)

```
enum RunIdentity { @TaskLocal static var current: String? ; static func mint() -> String }
```

**`Sources/ProctorAgent/Dispatch.swift`** — `handle` wraps its existing `route(request)`
call in `RunIdentity.$current.withValue(mint())`. One place. Task locals follow the task
across actor hops, and every audited write in a call happens on that task, so a gate
refusal, each step and a recommendation all land in the same run without any call site
knowing about it.

`proctor_history` and `proctor_history_clear` route to the new session methods and are
**not** added to `ToolCatalogue`, matching `proctor_recent_activity` and `proctor_hud`.

**`Sources/ProctorAgent/Session/SessionPolicy.swift`** — `auditStep` gains `seq`, `ms`,
`plane`, `act`, `obj`; every `AuditRecord` built in this file picks up
`RunIdentity.current`.

**`Sources/ProctorAgent/Session/SessionAct.swift`** — the two `auditStep` call sites pass
the index, `elapsed()`, the plane and the wording derived from the step and the resolved
node. This is the only place with all five in scope, which is why it is the only place
that changes.

**Tests** (`Tests/ProctorAgentTests/RunHistoryWiringTests.swift`, new): a fake audit sink
proves that two records written inside one dispatched call share a run id and carry
ascending `seq`; that a record written outside one carries none; that a step's record
carries the plane and a non-zero `ms`; that the wording on the record matches
`StepDescription` for the same step and node.

## Phase 5 — Agent: rotation

**`Sources/ProctorCore/AuditChain.swift`** — `Anchor` gains `startedAt: Double?`,
defaulted in its initialiser so existing call sites and stored anchors are unaffected.
It is where the trail's own start time can live out of reach of file access, and the
anchor is already loaded on every append.

**`Sources/ProctorAgent/Session/PolicyStore.swift`** — `AuditLog` gains:

- `rotateIfNeeded()` — the cap check, called at the **start of a tool call**, not from
  `append`. Reads the count and the anchor's `startedAt`; asks `HistoryRetention`.
- `rotate(reason:)` — the operation, under the existing `withAuditFileLock`:
  1. Read the current count, trail id and the hash of the final record.
  2. Write `audit.rotating` — a small marker holding the new trail id and the discard
     summary. This is what makes an interruption completable.
  3. Save a fresh anchor: new trail id, `count: 0`, empty head, `preChainCount: 0`,
     `startedAt: now`.
  4. Atomically replace the trail with an empty file.
  5. Append the rotation record through the ordinary seal-sign-anchor path, so it is a
     genuine genesis entry and not a special case.
  6. Remove the marker.
- `completeInterruptedRotationLocked()` — called at the top of every append. A marker
  present means steps 3 to 6 are re-run from the summary it holds. The window between
  3 and 4 is the only inconsistent one and the marker is what resolves it.
- `clear()` — `rotate(reason: .person)`.
- `status()` gains `rotated`, so the trail's status carries that it happened; a rotation
  also writes a line to stderr, as the one-time conversion already does.

The rotation record is an ordinary `AuditRecord` with `tool: "proctor_history"`,
`outcome: "ok"` and a `reason` naming the cap or the person, the discarded count, the
span, the discarded trail id and its final head hash.

**Tests** (`Tests/ProctorAgentTests/AuditRotationTests.swift`, new — with an injected
directory and an injected signer, never the real key store): a trail past the entry cap
rotates and the new trail holds exactly one record; the rotation record carries the
discarded count and head hash; `verify()` on the rotated trail is clean rather than
faulted; a marker left behind is completed on the next append; a rotation leaves no
`.bak`, `.orig` or sidecar in the directory; `clear()` on an empty trail is a no-op that
does not write a rotation record for nothing.

## Phase 6 — Agent: the projection verb

**`Sources/ProctorAgent/Session/SessionHistory.swift`** (new)

- `history(limit:)` — `AuditLog.openedTail(n)` → decode → `RunHistory.runs` → JSON. It
  reads a bounded tail (runs × a per-run allowance, capped), returns at most `limit` runs
  (default 20, hard cap 100), and carries the header block: entries held, the caps, how
  much of the window remains, the trail's verdict from `AuditLog.verify()`, the dropped
  count, and the unreadable count in view.
- `clearHistory()` — calls `AuditLog.clear()` and returns the new header.

Neither is in `ToolCatalogue`. Nothing on the 0.5s or 2s poll path calls either.

**Tests:** the projection carries no `value`, `script`, `postStateHash`, `kid`, `skid`,
`sig`, `app` handle or `window` handle key — asserted by walking the emitted JSON for
those key names, so a later field added to `AuditRecord` cannot leak by being forgotten.
This is the test that keeps the boundary honest as the record grows.

## Phase 7 — UI: the window

**`Sources/ProctorUI/HistoryModel.swift`** (new) — one socket call on open and on
refresh, decoding into the Core types. Holds the runs while the window is open and
clears them when it closes.

**`Sources/ProctorUI/HistoryWindow.swift`** (new) — the status window's own language:
`Card` on `controlBackgroundColor`, `SectionTitle` uppercase monospaced, system tints.
Not the HUD's graphite; not the rejected porcelain. A header (entries held, window
remaining, verdict, Clear), then run rows newest first, each expanding to its steps.

- `Fence` — the one view that may render foreign text. It takes a `HistoryObject`,
  renders `Text(verbatim:)` inside a bordered tinted run at a fixed maximum width, and
  is the only place in the file that touches trail-derived strings.
- Row shape is fixed: outcome mark, Proctor's verb, the fence, the plane, the time.
- The window sets `sharingType = .none` on appear.
- Empty, unreadable, unreachable and cleared are four distinct states with four
  sentences.
- Clear is destructive-styled and confirms first, saying the record cannot be brought
  back.

**`Sources/ProctorUI/ProctorUIApp.swift`** — a `Window("History", id: "history")` scene
and a menu-bar item beside "Proctor Status…".

**`Sources/ProctorUI/MainWindow.swift`** — a "Show history" button on the Activity card.

Views are not machine-witnessable here; everything they decide is in Core and tested
there. What the views own is arrangement.

## Phase 8 — Changelog

One `## [Unreleased]` entry, prose through `/create-luke-content` (format `marketing`).
No other section of `CHANGELOG.md` is touched.

## Acceptance clauses

| Clause | Proved by |
|---|---|
| A run's records group into one run, in order | `RunHistoryTests.groupsByRun`, `.ordersStepsBySeq` |
| A record outside a call is its own run | `.recordWithNoRunIsARunOfOne` |
| Old records still read | `.recordsWithoutRunFieldsStillRender` |
| The run's outcome is reduced, not guessed | `.outcomeReduction*` (one per outcome) |
| The projection carries nothing it does not draw | `SessionHistoryTests.projectionOmitsSecrets` |
| Foreign text is sanitised at the source, one routine | `StepDescriptionTests.historyCapUsesTheSameSanitiser` |
| Verb and object are separable and recompose | `.verbPlusObjectEqualsCompletedLine` |
| The entry cap rotates | `AuditRotationTests.entryCapRotates` |
| The age cap rotates, and a backwards clock does not | `HistoryRetentionTests.ageCap`, `.clockMovedBack` |
| Caps are clamped, with no unbounded value | `HistoryRetentionTests.clamp*` |
| Rotation attests what it discarded | `AuditRotationTests.rotationRecordCommitsToTheHead` |
| A rotated trail verifies clean | `.rotatedTrailVerifiesClean` |
| An interrupted rotation completes | `.interruptedRotationIsCompleted` |
| Rotation leaves no readable copy | `.rotationLeavesNoSidecar` |
| Clear is the same operation | `.clearRotatesNow` |
| A step's record carries plane, cost and wording | `RunHistoryWiringTests.stepRecordCarriesTheFacts` |
| Run ids come from one place | `RunHistoryWiringTests.oneCallOneRun` |

## Risks

- **Task-local propagation.** If any audited write happens on a task detached from the
  dispatched one, it loses the run id and becomes a run of one. That is the correct
  reading for the panel's own records; `RunHistoryWiringTests` pins which is which so a
  later detachment shows up as a failing test rather than as scattered history.
- **`Anchor` gaining a field.** Existing anchors decode with `startedAt: nil`, which
  leaves the age cap dormant until the next rotation. Named in the spec; tested.
- **Test isolation.** `AuditLog` has an interlock that refuses to write in a test process
  without an injected directory. Every rotation test injects both a directory and a
  signer; none may reach the real key store.
