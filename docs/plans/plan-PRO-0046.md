# Plan — PRO-0046: Supervision survives delegation

**Spec:** `docs/specs/spec-PRO-0046.md`
**Plan size:** Standard
**Branch:** `ai/pro-0046` · **Worktree:** `.worktrees/PRO-0046` (off `main` at `0ea6f88`)
**Gate:** `swift build` + `./scripts/test.sh`. Never a bare `swift test`, never piped.
New swift-testing tests per acceptance clause.

## What changes

Four supervision mechanisms learn about a lane where Proctor is not the thing posting.
No mechanism is replaced; three gain one term that reads `native` today, one gains a
process-wide keeper of its own, and one new pure decision moves into Core.

The proof that the native lane is untouched is the same shape PRO-0044 used and is
checkable rather than asserted: **every new parameter defaults to the value that
reproduces today's behaviour**, so no existing call site and no existing test is edited.
The finalize gate checks `git diff main...HEAD -- Tests/` contains no deletion or
modification of an existing test body.

## Parity inventory — the delegated lane against the native one

The delegated lane is a parallel path for a flow the product already serves, so every
load-bearing supervision behaviour on the native path is accounted for here. A new path
that silently loses a guard is the classic engine-swap regression, and it ships green
because nothing asserts an absence.

| Native behaviour | On the delegated lane | Where |
|---|---|---|
| `isAPerson` decides whether an event holds the run | **keep, unchanged** — already excludes anything carrying a pid | S2 test only |
| `isOurs` decides whether an event reaches the application | **port, widened by one corroborated pid** | S2, S3, S4 |
| The panel refuses to actuate a control on one of our own events | **port, same predicate** — the finding that would have shipped | S3 |
| `SyntheticPost.declare()` before a post | **drop, with rationale** — another process posts; there is nothing to declare, and joining would clear a concurrent native poster's state | S8 |
| The in-flight window suppresses the Stop rectangle | **drop, with rationale** — bounded to 250ms from a declaration, and a delegated post happens at an unknown moment inside an RPC, so it cannot be placed where the post is; identity carries it instead | S8 |
| The grace window opens before a post | **drop, with rationale** — does not insure against the threat it names, and `ContentionMonitor` is a singleton so it would blind a concurrent native run | not built |
| The takeover statement is raised before the first post | **port, late** — raised on the first measured foreground path. A named regression, disclosed on the panel and in the run's note | S9, S10 |
| The input block arms per posting step | **port, pessimistic after the first escalation; the lane serialises and arms nothing when the driver is unrecognised** | S5, S10 |
| The panel's mouse gate steps aside for a post under it | **keep** — already true for every delegated kind, because all of them report `.maybe` | none |
| A pointer is drawn for the step | **port, exclusive** — exactly one of the two draws | S6 |
| The step description is derived, never supplied | **keep, plus fencing** for driver prose reaching a person | S7 |
| Reduce Motion, Reduce Transparency, one panel per screen | **keep, unchanged** | S11 regression tests |
| Contention arms on a measured `.syntheticEvent` | **keep** — already fires for a delegated escalation | S11 |
| `ForegroundReport` measured / unproven / escalation counts | **keep** — PRO-0044 shipped them | S11 |

## Slices

### S1 — The delegated-actuation keeper

**New:** `Sources/ProctorAgent/Actuation/DelegatedPost.swift`.

A process-wide `final class DelegatedPost: @unchecked Sendable` with `static let shared`,
built exactly like `SyntheticPost` in
`Sources/ProctorAgent/Overlay/RunHUDGeometry.swift`: one `NSLock`, every accessor
lock-and-return, nothing held across work, no lock shared with anything that hops to
main. That shape is mandatory rather than stylistic — the tap's `.defaultTap` callback
reads it, and a callback that waits freezes the deadline timer and the release chord
(PRO-0033's A14).

State, and it is retained per pid rather than flagged, because two delegated runs overlap
(both hold only an app lane) and may be delegating to the same driver:

- `outstanding: Int` — delegated calls in flight.
- `unrecognised: Int` — of those, how many could not corroborate a driver pid.
- `entries: [Int64: (retain: Int, lapse: Double)]` — a per-pid retain count and the time its
  membership expires.

API: `begin(pid:) -> Token`, `end(_:)`, `var recognisedPids: Set<Int64>`,
`var hasUnrecognised: Bool`, plus `var now: @Sendable () -> Double`, injectable, as
`SyntheticPost` has.

**The accounting rules, written down because the plan gate found the draft's version
ambiguous in three ways:**

- `begin` increments `retain` for the pid and clears its lapse; `end` decrements `retain`
  and, at zero, sets `lapse = now() + PersonInput.graceSeconds`.
- `outstanding` and `unrecognised` move **only** on `begin`/`end`. Expiry never touches
  them, so there is no path where a timer and a call both decrement the same counter.
- `recognisedPids` filters on read — an entry is a member while `retain > 0` **or**
  `now() < lapse` — so no sweeper is needed and the tap, which may not wait, never runs one.
  Without the retain half, two overlapping calls on one pid would let the first `end` set a
  lapse while the second call is still in flight, dropping the pid mid-gesture.
- Every entry also carries a hard ceiling of `Takeover.ceilingSeconds` from its `begin`.
  A `perform` that hangs, a cancelled task, or a driver that dies mid-call would otherwise
  leak `outstanding` forever, and a leaked entry leaves a reused pid exempt from the block
  indefinitely. `Session` releases in a `defer`, which covers a throw; the ceiling covers
  the rest, in the same spirit as `InputBlocker`'s own deadline (PRO-0026 A7).

`begin` is called **before** the request goes out, not around the wait: it brackets the
whole `actuator.perform(...)` call, which contains the send. An event posted between the
request leaving and the bracket opening would be classified as foreign.

### S2 — Core: one predicate, one new defaulted parameter

**Edit:** `Sources/ProctorCore/Takeover.swift`.

```swift
static func isOurs(sourcePid: Int64?, userData: Int64?, ourPid: Int64,
                   delegated: Set<Int64> = []) -> Bool
```

after the two existing tests: `if let sourcePid, delegated.contains(sourcePid) { return true }`.
`Gate.decide` gains the same defaulted parameter and passes it through.

The default is what keeps the native lane byte-identical, and it is also what keeps this
narrow: an empty set is today's rule exactly. `sourcePid != 0` is never a pass — the
membership test is against a set Proctor built from one corroborated pid, which is why
PRO-0026's remapper hole stays closed.

`PersonInput.isAPerson` is **not** touched. A test pins that a driver-pid event is not a
person, because the property is now load-bearing for a second reason and an inversion
would be silent.

### S3 — Both readers take the set

**Edit:** `Sources/ProctorAgent/Overlay/TakeoverOverlay.swift` (the tap callback, beside
where it already reads `RunHUDGeometry.shared.stopRect` and `SyntheticPost.shared.inFlight`)
and `Sources/ProctorAgent/Overlay/RunHUDContentView.swift` (`isOurs(_ event:)`, line 242).

Both read `DelegatedPost.shared.recognisedPids` and pass it as `delegated:`.

**The second one is the defect that would have shipped.** `RunHUDContentView.mouseDown`,
`mouseUp` and `mouseDragged` each `guard !isOurs(event)`, which is PRO-0033's A11. Widen
only the tap and a *passed* driver click reaches the Stop `NSButton` and presses it in
AppKit — defect 1 arriving by a different road. Because both call the same Core
predicate, one change covers both, and a test asserts the panel path specifically so a
future reader cannot widen one without the other.

### S4 — Learn the driver's pid, and corroborate it

**Edit:** `Sources/ProctorAgent/Actuation/CuaTransport.swift` — `CuaResponse` gains
`actuatingPid: Int32?`.
**Edit:** `Sources/ProctorAgent/Actuation/CuaPreflight.swift` — stage 5 (`verb: .health`,
line 174) reads it; `CuaLaneReport` gains `actuatingPid: Int64?` and
`pidCorroborated: Bool`.
**Edit:** `Sources/ProctorAgent/Actuation/ActuationBackend.swift` — the protocol gains
`var actuatingPid: Int64? { get async }` with a `nil` default extension, mirroring
`laneHealth`'s shape and its rule: **asking never establishes anything**, it reads what
preflight left behind.
**Edit:** `Sources/ProctorAgent/Actuation/CuaActuationBackend.swift` — implements it from
`LaneState`.

Corroboration: the pid is the driver's own claim, and it is accepted only when the process
bearing it is the identity the lane already verified — `NSRunningApplication(processIdentifier:)`
whose `bundleIdentifier` equals `CuaPreflight.expectedIdentifier`, or, when that returns
nil for a non-GUI process, the same `SecStaticCodeCheckValidity` requirement the signature
check at `CuaPreflight` already builds, applied to that process's executable path. An
uncorroborated pid is stored as nil with `pidCorroborated = false`.

**`0` and Proctor's own pid are refused before corroboration is even attempted**, and this
is not a formality: a health reply of `0` landing in the set would make every hardware
event "ours", so the block would pass the whole of the person's input while claiming to
hold it — the exact inversion the pass rule exists to prevent. Proctor's own pid is refused
for symmetry, since it is already covered by the `ourPid` test and admitting it twice would
hide a driver misreporting itself.

The set is populated from preflight and read only while a call is outstanding, so a stale
pid cannot persist past the lane. This is weaker than an audit token and stronger than a
number, and the spec says which: a recognition rule, not a security boundary.

### S5 — The session brackets the call; an unrecognised driver serialises

**Edit:** `Sources/ProctorAgent/Session/SessionAct.swift`, in `runSteps`, around the
`actuator.perform(...)` call at line 389 — the same `do`/`defer` that already brackets
`takeoverArm`/`takeoverRelease` and `syntheticPost.endStep()`.

When `actuator.id != .native`:

```
let token = DelegatedPost.shared.begin(pid: await actuator.actuatingPid)
defer { DelegatedPost.shared.end(token) }
```

**Edit:** `Sources/ProctorAgent/Session/SessionQueue.swift` — `lanes(for:window:foreground:)`
adds `.global` when the selected backend is delegated and its `actuatingPid` is nil.

**Why the lane and not a suspension.** The draft had the block *release* while an
unrecognised delegated call was outstanding, reasoning that arming is a process-wide count
so declining to arm does nothing when a native run armed the tap first. The premise is
right and the remedy was wrong: releasing a process-wide hold because *this* run cannot
identify *its* driver lifts the hold a **concurrent native run** is keeping, so the person's
input reaches the application that run is driving. That is PRO-0053's cross-run clear in a
different costume, and the plan gate caught it.

Taking `.global` makes the overlap impossible instead of arbitrating it. Only a posting
native batch arms the block, and such a batch holds `.global`, which is exclusive against
itself — so an unrecognised delegated batch holding `.global` cannot coexist with an armed
tap, and it arms none of its own. **No suspend/resume, no second counter, and no new
`TakeoverRelease` case.** `takeoverStatus()` reports that the lane serialises and holds
nothing, and why.

The cost is a slower lane for an operator whose driver cannot be identified, stated in the
spec and in the doctor's own words.

### S6 — Exactly one pointer

**New (Core):** `Sources/ProctorCore/PointerOwner.swift` — a pure decision so the part
that can be tested is:

```swift
public enum PointerOwner: String, Sendable { case proctor, deferredToDriver }
public enum PointerOwnership {
    public static func decide(delegated: Bool, driverSuppressible: Bool) -> PointerOwner
}
```

`proctor` on the native lane, and on the delegated lane when the driver can be asked to
stand down; `deferredToDriver` otherwise. That asymmetry is the guarantee: Proctor can only
*certainly* switch its own off, so the fallback is the one it can enforce. The second case
is named for what Proctor knows — it stood down — rather than for what the driver then did,
because a build that reports no cursor control and also draws nothing leaves no pointer at
all, and claiming "the driver drew" would be a fact Proctor never observed.

**The decision is made once per run, at `runBegan`, and held on the run**, not consulted
per step from a process-wide value. The plan gate found the draft's version would flip
between a native run's step and a concurrent delegated run's step, because the two
genuinely overlap. `StepRun` carries it; `showCursor(for:window:)` reads it.

**Edit:** `Sources/ProctorAgent/Actuation/CuaTransport.swift` — `CuaRequest` gains
`suppressCursor: Bool = true`, sent on **every** `.act` rather than assumed from the
capability probe, because "can be asked" is not "has stood down" and a probe answered once
does not bind the tenth step; `CuaResponse` gains `cursorSuppressible: Bool?` read from the
capabilities reply at `CuaPreflight` line 155, alongside the vocabulary probe already there.
**Edit:** `CuaLaneReport` gains `cursorSuppressible: Bool` (default false — fail closed:
an installed build that says nothing is treated as unable, so Proctor stands down rather
than risking two).
**Edit:** `Sources/ProctorAgent/Session/SessionCursor.swift` — `showCursor(for:window:)`
returns early when the run's owner is `deferredToDriver`, before the window-list read, so
the deferred case costs nothing exactly as `PROCTOR_CURSOR=0` does (PRO-0025 A10).
**Edit:** `Sources/ProctorCore/Wire.swift` — `ActResult` gains `pointerDrawnBy: String?`,
**nil when Proctor drew**, so every existing result encodes byte-identically.
**Edit:** `Sources/ProctorAgent/Session/SessionDoctor.swift` — states that
`PROCTOR_CURSOR` does not reach the driver's cursor.

`PROCTOR_CURSOR=0` is unchanged: Proctor draws nothing anywhere. The suppression flag
still rides the request that was being sent anyway, so it costs nothing.

### S7 — Fence the driver's prose where a person reads it

**Edit:** `Sources/ProctorCore/StepDescription.swift` — add
`static func fenced(_ text: String?, from source: String, cap: Int = 200) -> String?`:
collapse to a single line, strip control characters and markup with the existing
sanitiser's rules, attribute (`cua-driver said: "…"`), grapheme-safe cut at `cap`. Not
`sanitised`'s 48-character cut, which exists for a line designed never to ellipse and
would destroy a diagnostic.

**Edit:** `Sources/ProctorAgent/Actuation/CuaActuationBackend.swift` — the two
`AgentError` sites that embed `reply.message` (line 188 and the refusal path) use it.

The HUD needs no change: `Sources/ProctorCore/RunHUD.swift` lines 384 and 392 already build the refused and
failed lines from `StepDescription.line(for:node:outcome:)`, which takes the step and
Proctor's own node and nothing else. A10's test asserts that property directly against a
hostile driver message so it cannot regress silently.

### S8 — A delegated run leaves the declaration keeper alone

**Edit:** `Sources/ProctorAgent/Session/SessionAct.swift` line 268:

```
let participates = demand.mightPost && foreground && actuator.id == .native
```

with the comment extended to say why: PRO-0053's predicate was `mightPost && foreground`
because those were the runs that could post, and a delegated run cannot. Both halves of
`SyntheticPost` are left alone, so a concurrent native poster's `declared` and `declaredAt`
survive a whole delegated batch. PRO-0053's four tests stay green unmodified, which is the
check that this is a widening of its rule rather than a reversal.

### S9 — The disclosure says the lane

**Edit:** `Sources/ProctorCore/ForegroundDemand.swift` — `notice(app:known:)` (line 133)
gains `delegated: Bool = false` and a fourth phrasing beside the three at lines 148–153.
One row, one wording function — PRO-0019's A-iii is not reopened, so no second row, no
chip, no new colour.
**Edit:** `Sources/ProctorAgent/Session/Session.swift` — `recentActivity` (line 267)'s
foreground block gains the backend id.
**Edit:** `Sources/ProctorAgent/Session/SessionHUD.swift` / the `runBegan` reducer — passes
the flag through.

What Proctor knows before a delegated run starts is therefore said from `runBegan`; only
the full-screen statement waits, which is the split the assumptions gate asked for.

### S10 — The block follows the statement on the delegated lane

**Edit:** `Sources/ProctorAgent/Session/SessionAct.swift` lines 373–384. Today the arm
fires on `synthetic || stepsAside`. On a delegated lane it also fires once `takeoverShown`
is true, because a delegated batch predicts nothing and the safe direction is to hold.

**The pairing does not change.** `takeoverArm(for:)` before the call and
`takeoverRelease(.stepEnded)` in the same `defer`, once per step, exactly as the native
path does — only the condition widens. An arm without its matching release leaks the
process-wide count and leaves the tap holding somebody's keyboard, which is why this is
spelled out rather than left to "arm for the rest of the batch". `takeoverEnd` still calls
`stopAll` at the run's end as the existing backstop.

**Ordering: S10 lands last of the behaviour slices, and only after S2, S3, S4 and S5.**
Arming the block on a delegated lane before the pass rule can recognise the driver would
swallow the driver's own `mouseDown`/`keyDown` and leave buttons stuck — it would build the
exact defect the rest of this plan removes. The dependency is stated here because the slice
order is otherwise readable as a preference.

`noteSyntheticPost()` is **not** added to the delegated path — see the Parity inventory's
drop-with-rationale row.

### S11 — Tests

New suites in `Tests/ProctorCoreTests/` and `Tests/ProctorAgentTests/`, and no existing
test body edited. Filters match the Swift **function** name, not the `@Test` display
string, and the `with N tests` count is read back before believing any filtered green.

## Acceptance clauses → what proves each

| Clause | Test |
|---|---|
| A1 native untouched | the whole existing suite green with no edited test; a finalize-gate `git diff` over `Tests/` showing additions only |
| A2 delegated run leaves the keeper alone | `aDelegatedRunNeverParticipates`; `aNativePostersStateSurvivesADelegatedBatch` |
| A3 driver never presses Stop | `aRecognisedDriverPassesBeforeTheRect`; `thePanelRefusesADriverEvent`; `anUnrecognisedDriverMeetsASuspendedBlock` |
| A4 a person still reaches Stop, still heard | `hardwareStillStopsOnTheUp`; `hardwareStillYields`; `escapeStillStopsAnArmedRun`; `panicChordsStillPass` |
| A5 driver's events never hold the run | `aDriverPidIsNotAPerson`; `aDelegatedBatchYieldsZeroTimes`; `aSuppressedSwallowIsNotPersonInput` |
| A6 one pid, corroborated, counted, bounded both sides | `onlyTheDriversPidPasses`; `aRemapperPidIsStillHeld`; `zeroIsNeverAdmitted`; `ourOwnPidIsNeverAdmitted`; `theWindowOutlivesTheCallByTheGrace`; `aTrailingUpIsNotStripped`; `twoCallsOnOnePidAreRetained`; `aHungCallExpiresAtTheCeiling` |
| A7 unrecognised ⇒ serialise, arm nothing | `anUnrecognisedDelegatedBatchTakesTheGlobalLane`; `itArmsNothing`; `doctorSaysWhyTheBlockIsOff` |
| A7b nothing releases another run's hold | `aDelegatedBatchLeavesANativeHoldAlone`; `theArmCountIsOnlyDecrementedByItsOwner` |
| A8 exactly one pointer, decided per run | `pointerOwnerIsProctorWhenTheDriverCanStandDown`; `pointerOwnerDefersOtherwise`; `unknownSuppressibilityFailsClosed`; `theOwnerIsHeldOnTheRunNotTheProcess`; `suppressionRidesEveryAct`; `cursorOffStillDrawsNothing`; `theResultSaysWhatProctorDecided` |
| A9 character unchanged | `theCharacterStatesAreUnchangedOnBothLanes` |
| A10 no driver string reaches the panel | `aHostileDriverMessageCannotChangeTheLine`; `theTrailRowIsDerived`; `theTakeoverLabelIsDerived` |
| A11 a driver string a person reads is fenced | `driverProseIsFencedAndAttributed`; `fencingIsGraphemeSafe`; `markupAndControlCharactersDoNotSurvive` |
| A12 the lane is on the panel and the menu bar | `theDelegatedPhrasingIsOneRow`; `theMenuBarCarriesTheBackend` |
| A13 escalation stated live, lateness admitted | `aLateEscalationRaisesTheStatement`; `theNoteSaysTheWarningWasLate`; `whatWasKnowableIsSaidUpFront` |
| A14 Reduce Motion / Transparency, one panel per screen | the existing `accessibilitySettingsApply` and the per-screen construction, asserted on both lanes |
| A15 the whole lane without the binary | the `FakeCuaTransport` and a fake `TakeoverDriving`, driving every row above |

## What a `swift test` cannot witness here

Named rather than implied, in the house pattern. `swift test` has no window server and no
event tap, so none of these is proved by the suite: a real driver event arriving at a real
tap and being passed, the panel receiving one, the block actually suspending in the window
server's delivery path, either pointer drawing or not drawing, and the driver honouring or
ignoring the suppression request. The decisions, the keeper's arithmetic, the ordering, the
counting, the trailing grace and the wording are all values and are tested.

And the whole delegated lane is a documentary reading: `cua-driver` is not installed and
PRO-0023 forbids installing it as a side effect, so the two new wire fields
(`actuatingPid`, `cursorSuppressible`) are unverified against the shipped binary. Both fail
closed — an absent pid suspends the block, an absent suppressibility flag stands Proctor's
pointer down — so being wrong produces a stated capability loss rather than a wrong guard.

## Risks

- **The keeper's accounting is the one place a bug is expensive.** A leaked `outstanding`
  leaves a reused pid exempt from the block indefinitely; a double-decrement drops a pid
  mid-gesture. Counted on `begin`/`end` only, expiry drops keys and never counters, retained
  per pid, and ceilinged at `Takeover.ceilingSeconds` so a hung call cannot leak.
- **The trailing grace is a window in which a driver pid passes with no call outstanding.**
  Bounded at `PersonInput.graceSeconds`, and the alternative is a stripped gesture, which
  outlives the process.
- **The pessimistic arming after a first escalation holds input across accessibility-plane
  steps.** Bounded per arming, paired per step, and stated in the spec rather than smoothed.
- **The `.global` lane for an unrecognised driver is a real slowdown.** It serialises that
  operator's runs against everything needing the front. It is the cost of not arbitrating a
  hold two runs share, it is disclosed by `proctor_doctor`, and it disappears the moment the
  driver reports a pid Proctor can corroborate.

## Plan review gate — grok-4.6, xhigh, read-only

**Mechanical path check: pass.** Every backtick-quoted path in this plan resolves in the
worktree except the two marked `New:` (`DelegatedPost.swift`, `PointerOwner.swift`).

**Out-of-family review: ran, 21 findings, six changed the plan and five were rejected on the
code.** Codex is off for this repo by instruction, so grok is the out-of-family lane; the
plan was inlined at 36 lines with the measured facts, because a longer prompt kills it.

Accepted and now in the plan:

1. **"Suspending the block is a cross-run clear, which is the S8 bug in other clothes."**
   The most valuable finding in either gate. Releasing a process-wide hold because *this*
   run cannot identify *its* driver lifts a hold a concurrent native run is keeping. Replaced
   by the `.global` lane, which makes the overlap impossible rather than arbitrating it —
   the reviewer's own closing suggestion. **This deleted a mechanism**: no suspend/resume, no
   second counter, no new release case, and it dissolved three of its other findings.
2. **"The keeper cannot bracket two calls that share a pid."** Two `begin(P)` and one
   `end(P)` would set a lapse while a call is still in flight. Retained per pid, with the
   counter/expiry split written down.
3. **"`begin`/`end` have no failure path."** A hung `perform` or a dead driver leaks
   `outstanding` forever. A ceiling now bounds every entry, in the same spirit as
   `InputBlocker`'s own deadline.
4. **"One pointer decision cannot serve two concurrent runs."** The draft consulted a
   process-wide decision per step, which would flip between a native run's step and a
   delegated one's. Decided once per run and held on the run.
5. **"S4 never names pid 0."** A health reply of `0` in the set would make every hardware
   event "ours" — the block would pass the whole of the person's input while claiming to
   hold it. `0` and Proctor's own pid are now refused before corroboration is attempted.
6. **"S10's arming is ambiguous, and it cannot land before the pass rule exists."** The
   arm/release pairing is spelled out, and S10's dependency on S2–S5 is stated rather than
   left to slice order. Also accepted: `begin` brackets the whole call including the send,
   which the draft made readable the other way.
7. **"Fail-closed can mean zero pointers."** True, and it is the cheaper failure — the same
   call PRO-0025 made when it chose to hide rather than dim. The enum case is renamed
   `deferredToDriver` so the record states what Proctor decided rather than claiming the
   driver drew.

Rejected on the code, recorded so they are not re-found:

- **"Stop, the watch and 'a run is active' are declaration side effects S8 drops."** The
  declaration feeds exactly three things, all visible in `runSteps`: the grace window, the
  takeover statement, and `takeoverShown`. Stop binds through `hudRunControlBegin()` /
  `takeoverBind()` / `RunControl`, the watch arms from `demand.takesForeground` and from a
  measured plane, and the panel goes up from `hudRunBegan` — all unconditional and none of
  them via the declaration. A delegated-only run has a working Stop, watch and panel.
- **"S10's arm-after-escalation is circular if escalation is tap-detected."** Escalation is
  read from the step's reported path and its measured plane (PRO-0044's
  `unrequestedForeground`), never from the tap.
- **"A process-wide swallow eats the person's Stop click."** That is what PRO-0033 built:
  `Gate.decide` tests the published Stop rectangle and returns `.stopRun` on the up,
  swallowing rather than delivering. The reviewer's proposed "deliver to our own chrome"
  exemption is the through-click into the driven application PRO-0015 refused outright.
- **"`isAPerson` may be `!isOurs`, in which case every delegated move pauses the run."**
  It is `guard let sourcePid, sourcePid == 0`, and it does not call `isOurs`. The reviewer
  was right that the plan asserted this by silence, so `aDriverPidIsNotAPerson` pins it.
- **"One disclosure row and one menu-bar slot are untruthful under concurrency."** Both are
  already per run: `RunHUDModel` is per panel and `recentActivity`'s foreground state is
  keyed by run token and folded across every run in flight — PRO-0019's own completeness
  critic fixed exactly this.

Its remaining points about a driver actuating Proctor's chrome and about the menu bar
printing an unfenced string are covered: the backend id is Proctor's own enum, not a driver
string, and the chrome case is S3's panel-side predicate.

## Scope-narrowing check

Every "Not in scope" line in the spec traces to another allocated item (PRO-0045, PRO-0050,
PRO-0051) or to a binding design decision, and none of them overlaps a triage assumption.
The three Child-work items are recorded, not planned. No requirement in the spec is absent
from the slices above: A1–A15 each map to at least one slice, and the Parity inventory
covers every native behaviour the delegated lane meets.
</content>
