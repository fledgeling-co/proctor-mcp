# PRO-0051: The native planes stay, chosen deliberately, and the record says so

**ID:** PRO-0051
**Status:** In Review (built, gated, green on `ai/pro-0051`; not merged)
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/52-decide-what-happens-to-the-native-planes.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` — wins over any earlier spec
**Evidence:** `docs/research/2026-08-15-dossier-proctor-vs-cua.md`
**Builds on:** PRO-0044 (the actuation seam, merged `d65dc1e`), PRO-0045 (the delegated
row, merged `1bff5c2`), PRO-0050 (per-lane doctor, merged `0ea6f88`)
**Coordinates with:** PRO-0046 (supervision under delegation, in flight — same area,
disjoint diff)
**Branch:** `ai/pro-0051` (worktree `.worktrees/PRO-0051`)

## Feature description

<!-- Verbatim from docs/features-to-triage/52-decide-what-happens-to-the-native-planes.md -->

# Decide what happens to the native planes

**Read `00-WAVE-7-DIRECTION.md` first.** Do not start this before brief 45 has merged.

## The problem

Once Cua performs actuation, Proctor still contains a complete, tested, working
implementation of the same thing: the accessibility plane, the synthetic-event plane,
the Apple Events route, the fallback rungs, and the tests that pin all of it. Leaving
it in place is not free and deleting it is not obviously right.

## The decision this item exists to make

Three readings, and the spec must choose one and defend it:

1. **Delete them.** One actuation path, one set of failure modes, a much smaller
   surface. Loses the ability to run at all on a machine without `cua-driver`, and
   throws away the Apple Events plane, which Cua has no equivalent of.
2. **Keep them as an automatic fallback.** Nothing breaks when Cua is missing or a
   call fails. Costs two paths with different behaviour, and a run that silently
   changes plane mid-flight makes a determinism score meaningless, which is the
   product this repo is pivoting towards.
3. **Keep them, explicitly selected, never automatic.** An operator or a caller
   chooses the lane and the run record says which one it was. Honest, and it means two
   paths stay maintained and tested forever.

**The Apple Events plane is the part that most argues against deletion.** It is a third
actuation route Cua does not have, it needs no foreground and no accessibility tree,
and for scriptable apps it is the most reliable thing in the box.

## The hard parts, named

- **Whatever is chosen, the run record must say which plane ran.** A determinism score
  computed across runs that used different actuation paths is measuring the paths.
- **The test suite is the asset here, not the code.** Several hundred tests pin the
  native planes' behaviour. If the planes go, decide what happens to the tests: some
  of them describe macOS rather than Proctor, and those are worth keeping as a
  characterisation of the platform whatever drives it.
- **Do not decide this by counting lines.** The question is which failure mode a person
  running an unattended campaign would rather have.

---

## The decision

**Reading 3. The native planes stay. They are selected by an operator, never entered
automatically, and native remains the default — and the maintained default, not a
frozen one.**

The rest of this spec is the defence, the two things the out-of-family gate changed,
and the small amount of code that follows.

## Why not reading 1

**Deletion is not available as stated, because "the native planes" are four planes and
Cua replaces two of them.** `Sources/ProctorAgent/AX/Actuator.swift` covers 22 step
kinds across `.accessibility`, `.syntheticEvent`, `.appleEvents` (`NSAppleScript`) and
`.declared` (`/usr/bin/shortcuts`). Cua's mapping table in PRO-0044 §5 covers the first
two. It has no equivalent for the other two, which is why PRO-0044's A2 already refuses
`appleScript` and `shortcut` on the delegated lane. Deleting the native planes deletes
two documented verbs from the published tool catalogue. The brief names the Apple Events
plane as the strongest argument against deletion and it is right: a third actuation
route needing no foreground and no accessibility tree, and for a scriptable app the most
reliable thing in the box.

Two further facts each defeat deletion on their own.

**Nothing here has ever met the binary.** `cua-driver` is not installed on this machine,
PRO-0023 forbids installing it as a side effect, and PRO-0044's own progress note states
plainly that every claim about Cua's wire is a documentary reading enforced by a
capability probe. Deleting a path that demonstrably works, in favour of one that has
never executed once, is not a trade available to this item.

**The delegated lane cannot drive windows the native lane can.** PRO-0044 §4 recorded it
as a capability regression rather than a corner case: Cua returns only a menu bar for a
SwiftUI window on another Space, while Proctor's retained `AXUIElement` references keep
resolving there. Retained references surviving a Space change is the reason `attach`
exists at all. Deletion would remove a capability the product is built on.

## Why not reading 2

The direction file settles it — "a fallback is a decision, not a safety net" — and
PRO-0044 already shipped that refusal twice, once for transports and once for backends.
Re-introducing it a layer down would reverse a landed decision.

The deeper reason is what the failure looks like. **An automatic fallback does not stop;
it hands back a number that looks fine and measures the plumbing.** For a tool whose
output is a determinism verdict, corrupting the instrument silently is strictly worse
than failing loudly, because nothing downstream can tell the difference.

## Which failure mode an unattended campaign would rather have

This is the brief's own test and it decides the item.

- **Reading 1 fails closed and loudly**, at 3am, on a machine nobody is at, on any host
  without the driver, on any window that moved to another Space, and on any step that
  needed the app's own scripting contract.
- **Reading 2 fails silently** and produces a corrupted verdict that survives review.
- **Reading 3 costs the maintainer two paths and costs the operator one deliberate
  choice**, made once, before a campaign starts.

Reading 3 is the only one whose cost falls on the person best placed to pay it, and the
only one whose failure mode is visible at the moment it occurs.

## Two things the out-of-family gate changed

The decision was reviewed on **grok-4.6 at xhigh effort, read-only**, before this spec
was written, with the measured facts inlined. It agreed with reading 3 and with the
native default, and attacked two refinements the first draft carried. Both attacks land,
and both are adopted. The review is recorded here rather than re-run.

### 1. A written reversal condition is a scheduled reading 2 — removed

The first draft named conditions under which the default would flip to Cua. The
objection: this product scores the same flow over time, so a default that flips when a
condition becomes true contaminates the time series exactly as a mid-flight fallback
contaminates a run, and worse — nobody set anything, the record says `cua`, and it looks
honest. The contamination sits across runs rather than inside one, which is the axis this
item was supposed to protect.

**So there is no firing condition, and nothing in the code reads one.** What is written
instead is a checklist a person consults *before deciding*, and the decision would ship
as a release whose notes say the default moved. At minimum it must cover: the driver
executed on a real machine with preflight green; the off-Space regression resolved
upstream or accepted in writing; `appleScript` and `shortcut` answered rather than
refused; and the move of actuation onto a second TCC identity (`com.trycua.driver`)
accepted in writing. Those are upstream facts, not decisions this repo can take alone.

### 2. "Frozen" is wrong while native is the default — withdrawn

The first draft proposed freezing the native lane to bug fixes only, to turn "two paths
maintained forever" into "one path kept working". The objection: native is the path that
actually runs, so freezing it names the path that does not.

**Verified against this repo, and it has already happened once.** PRO-0034
(`docs/features-to-triage/35-scroll-moves-by-what-was-asked.md`) was retired on
2026-08-15 with the reason *"Scroll is Cua's now"*, closing a real, documented defect —
the scroll delta is a fraction of the document, and `AXScrollDownByPage` outranks the
delta actually asked for — in the code path `main.swift` selects whenever
`PROCTOR_ACTUATION` is unset, on a machine that has never executed `cua-driver`. That is
the freeze, already spent, on the default lane.

So the rule is narrower and says what it means:

- **Maintenance continues.** While native is the default it absorbs macOS behaviour
  changes and its defects are fixed, exactly as before. It is the product.
- **Expansion is capped.** No new step kinds and no new routes on the native lane
  chasing parity with Cua. That is a scope rule, and it is the only part of "frozen"
  that survives.

## What the brief assumed that measurement contradicts

Two of the brief's premises were checked rather than inherited, and both are wrong in
ways that matter to anyone re-opening this decision.

**"Several hundred tests pin the native planes' behaviour" is false.** The suite holds
1193 `@Test` cases; **13 references to the native actuator across 3 test files**
(`YieldWiringTests`, `BackgroundRouteTests`, `StopReachabilityWiringTests`). The native
planes are thinly tested, because most of what they do needs a live accessibility tree.
The dense test files — foreground disclosure, the queue, the HUD, the audit chain, the
wire shapes — are lane-independent and survive any of the three readings untouched. This
*weakens* the test-suite argument for keeping the planes; the decision rests on the other
three arguments, which are enough.

**What deletion would actually have destroyed is the written record of how macOS
behaves**, and it lives in code and comments rather than in tests:

- AX reports success for a value write the application then discards, so a write is
  judged by reading it back — the single most valuable sentence in the file.
- A menu item's submenu is built lazily and must be pressed once to populate.
- Writing `AXSelectedText` with no selection *inserts at the caret* rather than
  replacing, so the selection must be read first and put back on failure.
- A scroll bar already at the end reads back unchanged, so "nothing moved" and "the call
  succeeded" are different facts.

Those are facts about macOS, true whatever drives the machine. Under this decision they
stay where they are and no migration is needed. Naming them here is so that a future
deletion knows what it is holding, rather than discovering it afterwards.

## What the code must do, measured rather than assumed

The decision is largely already shipped: PRO-0044 built the lane, made it explicit, and
stopped it changing mid-run. The first draft of this spec claimed a second gap — that a
native step's record omits its backend — and **measurement refuted it**. Encoding a
`StepResult` after `carry(_:)` produces `{"backend":"native", …}`, because
`Actuation.backend` defaults to `.native` and `carry` copies it unconditionally. The
comment above the field in `Sources/ProctorCore/Wire.swift` says every field below that
line is "omitted when nil, so a step the native backend ran encodes exactly as it did
before any of this existed" — true of `reportedMode`, `effect`, `retriedOnStale`,
`unrequestedForeground` and `transportMs`, and **not true of `backend`**. The comment
misdescribes the field this whole item is about, so it is corrected.

What is genuinely missing is a **run-level** statement. Three surfaces produce a record
a determinism claim is read from, and none of them says which lane produced it:

- `ActResult` — what `proctor_act` returns.
- The `flowReplay` result object.
- `StabilityReport` — which carries `deterministic` and `firstDivergence`, the verdict
  the whole pivot is towards.

Per-step `backend` does not cover this. A run whose every step refused before actuation —
a policy block, an unresolved target, a failed preflight — carries no backend on any
step, so the lane is invisible on exactly the runs a reader most needs to place. And a
`deterministic: true` verdict that does not name the actuation path is the measurement
the brief warns about, stated as a conclusion.

Selection stays **operator-scoped**, via `PROCTOR_ACTUATION`, read once in `main.swift`.
The brief allows "an operator or a caller". It is the operator, and that is a decision
rather than an inheritance: a caller choosing per call would let one run mix lanes, which
is the thing this item exists to prevent, and a caller choosing per session would let two
concurrent sessions drive different lanes into one shared driver — already recorded as
child work on PRO-0044.

One existing guard is hardened rather than added to. `SessionFlow.requireSameBackend`
compares the session's backend against the *first* backend a recorded flow carries. A
tape holding more than one would be judged by its first step. That cannot happen today,
because `appendToFlow` records only successful steps and stamps each with
`result.backend ?? actuator.id`, so every tape this build writes is uniform — which is
precisely why it costs one line to close now and would cost a debugging session to close
later.

## What this closes, and the one thing it cannot

The brief's requirement — a determinism number must never be read across two actuation
paths — has three seams, and they close differently. Saying so is better than implying
one clause covers all three.

- **Inside one report:** closed by construction. Every pass folded into a
  `StabilityReport` runs in one session, and A2 makes a session's backend immutable, so
  the passes cannot disagree. A6b pins it.
- **A recording against its replay:** closed by refusal. This is the one place two
  genuinely different runs are compared by machine, and `SessionFlow.requireSameBackend`
  already refuses a cross-backend replay. A6 hardens it from "the first recorded
  backend" to "every recorded backend".
- **One report against another, read by a person:** **not closable here, and not
  claimed.** Proctor can make the actuation path impossible to omit from a verdict, which
  is what A3 and A4 do. It cannot stop a reader ignoring a field. The honest claim is that
  the path is always present, never that a comparison is always valid.

## Acceptance clauses

**A1 — The native planes are still there and still reachable.** `PROCTOR_ACTUATION`
unset selects `NativeActuationBackend`, the whole existing agent suite stays green, and
`Sources/ProctorAgent/AX/Actuator.swift` is unchanged by this branch — checked at the
finalize gate by diff, because no unit test can certify what a change set did not touch.

**A2 — The lane is fixed for the life of the process, and there is one place it is
chosen.** Stated as a mechanism rather than as a universal negative, because "no path
selects Cua automatically" has no oracle and a finite test can miss a path and still
pass. Three checkable facts instead: the backend is constructed at exactly one site
(`makeActuationBackend`), that site returns the native backend for every environment
without `PROCTOR_ACTUATION=cua`, and `Session.actuator` is immutable after `init`, so a
later re-read of the environment cannot switch a running session.

**A3 — Every run record names the lane that actuated it.** `ActResult`, the `flowReplay`
result and `StabilityReport` each carry the session's actuation backend, present whether
or not any step actuated, so a run that refused everything still says which lane refused.

**A4 — A determinism verdict names its actuation path.** A `StabilityReport` carrying
`deterministic` also carries the backend, so a score can never be read without the path
it was measured on.

**A5 — A step that actuated names its backend; a step that never actuated does not.**
The existing behaviour, pinned by a test so a later change cannot quietly make silence
ambiguous. `"backend":"native"` on an actuated native step is asserted rather than
assumed.

**A5b — The run-level lane and the step-level backends agree.** Every actuated step in a
run reports the same backend the run reports. Two fields that could disagree and are
never checked are worse than one field, because a reader has no way to know which to
believe.

**A6 — Records that predate lanes stay readable, and a mixed tape does not slip
through.** A `RecordedFlow` whose steps carry no backend still replays without complaint
on the native lane, and an `ActResult` or `StabilityReport` written before this field
existed still decodes. `SessionFlow.requireSameBackend` today reads only the *first*
recorded backend; it is hardened so that **every** backend the tape carries must equal the
session's, which refuses a tape whose later steps differ while never refusing a legitimate
same-backend flow. Not reachable today — `appendToFlow` records only successful steps and
stamps each with `result.backend ?? actuator.id` — which is exactly why it is cheap to
close now rather than after something makes it reachable.

**A6b — A sweep's passes share one backend by construction, and it is pinned.** Every
pass folded into one `StabilityReport` runs inside one session, and A2 makes a session's
backend immutable, so the passes cannot disagree. That is the property that makes A4's
single run-level backend an honest label for the whole report rather than a label for
one of its passes, so it is asserted by a test instead of left to be re-derived.

**A7 — The wire comment describes the wire.** The `Wire.swift` note above `backend` no
longer claims the field is omitted for a native step, since it is not.

**A8 — The code states the settled decision.** `main.swift` and `CuaDriverTool` no longer
describe the native default as provisional pending this item; they state that native is
the default, chosen deliberately, and that the lane is operator-scoped.

## Not in scope

- **Promoting the Apple Events and declared planes out of the lane** so `appleScript` and
  `shortcut` work while Cua is selected. Considered and declined: PRO-0044's A2 refuses
  them deliberately and the refusal is visible with a remedy, and under the delegated lane
  an operator's model is that actuation is a signature-checked external process — quietly
  running arbitrary AppleScript inside Proctor's own process, which holds Accessibility,
  contradicts that model. Recorded as child work.
- **Stop, yield, event discrimination, the cursor and the HUD under delegation** —
  PRO-0046, in flight in the same area. Coordinated through this spec, not through shared
  actuation code.
- **Un-retiring PRO-0034.** The reasoning above says it was retired on a premise this item
  rejects, but `ORCHESTRATOR.md` and the ledger are the orchestrator's. Recorded as child
  work.
- **Any change to `Sources/ProctorAgent/AX/Actuator.swift`.** Nothing here needs it.
- **Backfilling tests for the native planes.** The decision keeps them; it does not
  commission coverage the brief's false premise implied already existed.

## Child work found

- **PRO-0034 was retired on a premise this item rejects.** It closed a real defect in the
  default actuation path because a replacement lane was expected to own it. Under a
  maintained native default that reasoning does not hold. Whether it returns is the
  orchestrator's call.
- **`appleScript` and `shortcut` are unreachable on the Cua lane.** Whether an app's own
  scripting contract should be lane-independent is a real question this item declines
  rather than answers.
- **`KeyCodes` has no test at all.** The virtual keycode table is a macOS fact table with
  no characterisation behind it, which is the same class of asset this spec argues is
  worth protecting.

## Triage — 2026-08-15 — Ready for Implementation Plan

**Sentinel verdict:** S2. The item settles an architecture decision and changes three
wire shapes; it touches no key material, no gate logic and no audit row. The governance
weight is in the decision, not the diff.

No essential gaps. Every open question was resolvable from the direction file, PRO-0044's
shipped decisions, or measurement against this repo, and each is recorded as an assumption
rather than asked.

### UI & logic preview

**Where it shows up:** nothing customer-facing changes. No panel, menu bar or status
window surface is touched. *(behind the scenes — nothing visible changes)*

**What users will see:** a finished run says which actuation lane produced it, including
a run where nothing actuated. A determinism verdict says which path it was measured on.

**Behaviour changes:**
- Proctor's own planes are confirmed as the default rather than being provisional.
- A repeatability score can no longer be read without the actuation path beside it.
- A run that refused every step still says which lane refused.

### Assumptions

- `[Data & scope]` The native planes stay and remain the default (*deleting a path that works for one never executed once is not a trade available here*).
- `[Data & scope]` The lane is chosen by an operator before the run, never by the software during it (*the direction file: a fallback is a decision, not a safety net*).
- `[Operations]` There is no written condition that flips the default on its own (*a scheduled flip contaminates a score across runs the way a fallback contaminates one within a run*).
- `[Operations]` Moving the default would be a release with notes saying so, after a checklist a person reads (*the checklist informs a decision; it never fires one*).
- `[Operations]` The native lane keeps being maintained while it is the default, and only its expansion is capped (*a frozen default is the path that runs, left to rot*).
- `[Compliance]` Two step kinds — running an app's AppleScript, and running a Shortcut — remain unavailable on the delegated lane, refusing with a remedy (*running arbitrary AppleScript in-process contradicts what selecting an external driver is supposed to mean*).
- `[Experience]` Windows on another desktop remain drivable only on the native lane (*PRO-0044 recorded it as a capability regression, and this is what keeps it reachable*).
- `[Data & scope]` Every run record names its lane, including a run in which nothing actuated (*a lane inferred from steps is invisible on exactly the runs worth placing*).
- `[Data & scope]` A repeatability verdict carries the actuation path (*a score without its path is the measurement the brief warns about, stated as a conclusion*).
- `[Data & scope]` Older recordings with no lane recorded still replay unchanged (*they were made on the native planes, because those were the only ones there*).
- `[Operations]` A caller cannot choose the lane per call or per session (*per call would let one run mix lanes; per session would point two sessions at one shared driver*).
- `[Data & scope]` The lane cannot change while a session is running, whatever happens to the environment afterwards (*a fixed lane is what makes a run-level label honest for every step in it*).
- `[Data & scope]` Proctor guarantees the actuation path is always present on a verdict, never that two verdicts are comparable (*a person reading two reports side by side is outside what any field can enforce*).

*If any of these are wrong, edit the answer inline (or correct an assumption) in this file and re-run `/triage PRO-0051` before the planner picks this up.*

### Out-of-family review — grok-4.6, xhigh, read-only

Run on **the decision itself**, before this spec existed, with the measured facts inlined
rather than by asking it to read files. It agreed with reading 3 and with the native
default, and changed the decision twice — both changes are in "Two things the
out-of-family gate changed" above, and one of them (the freeze) was verified against
PRO-0034's retirement in this repo before being adopted. No key material, gate code or
audit-trail code was sent; the review was scoped to design prose and measured counts.

A second gate ran on this spec's acceptance clauses as an artifact, same lane, evidence
inlined and file reading forbidden after a first attempt spent its whole deadline
exploring the repo without answering. That attempt is recorded as a lane failure and was
retried rather than treated as a pass. Five findings, all accepted:

1. **A2 was unfalsifiable** — a universal negative with no oracle, which a finite test
   can pass while missing a path. Restated as three checkable mechanisms: one
   construction site, a native return for every environment without the variable, and an
   immutable `Session.actuator`.
2. **A later re-read of the environment could switch a running session**, and the
   original A2 would still hold because the variable *is* `cua` at the moment Cua is
   chosen. Closed by the immutability half of the new A2.
3. **The run-level and step-level backends were never required to agree.** Two fields
   that can disagree and are never checked are worse than one. New clause A5b.
4. **`requireSameBackend` reads only the first recorded backend**, so a tape holding more
   than one would be judged by its first step. Not reachable today, and cheap to close
   before something makes it reachable. Folded into A6.
5. **A3 alone does not stop a determinism number crossing two paths.** Correct, and it
   prompted the "What this closes, and the one thing it cannot" section above: two of the
   three seams close by construction and by refusal, and the third — a person comparing
   two reports — is stated as a limit rather than claimed as covered. A6b pins the seam
   that A4's single run-level label depends on.

One finding is noted rather than acted on: A1 pins one file rather than all native
behaviour. That is deliberate and matches PRO-0044's A1 — its job is to prove the
extraction did not touch the actuator, not to freeze the lane, which this item explicitly
declines to do.

## Plan — 2026-08-15

Implementation plan: `docs/plans/plan-PRO-0051.md` (Plan size: Small).

The plan's out-of-family gate changed the design once, and it would otherwise have failed
the build: the new run-level field was to be non-optional with an `init` default of
`.native`, and an `init` default does not make `Codable` tolerate a missing key. Verified
against `ForegroundDisclosureTests.absentBlockDecodes`, which exists to guarantee an older
`ActResult` still decodes. Optional with no default keeps that guarantee and, separately,
stops a construction site that forgot the lane from asserting the wrong one. The gate also
removed the plan's second refusal rule on the same-backend guard as redundant and
over-refusing; the spec's A6 was narrowed to match.

## Progress — 2026-08-15

**Status:** In Review. Branch `ai/pro-0051`, worktree `.worktrees/PRO-0051`. Not merged;
finalization is the orchestrator's.

**Gate:** `swift build` green; `./scripts/test.sh` **1216 tests in 133 suites passed**,
against a **1193**-test baseline at `main` — exactly the 23 tests added here.

### Acceptance clauses, and what proves each

| Clause | Proof | Result |
|---|---|---|
| A1 native planes still there and reachable | `git diff main -- Sources/ProctorAgent/AX/Actuator.swift` is empty; `ActuationSeamTests.defaultsToNative` and the whole existing suite green with no edit to any `Session(...)` construction | pass |
| A2 lane fixed, one construction site | `NativePlaneLaneTests.laneIsSelectedOnlyByName` (seven environments, including `""`, `native`, `cuadriver` and a leading space); `.laneIsFixedForTheLifeOfTheSession` mutates the environment mid-session and asserts the lane and the actuator both hold | pass |
| A3 every run record names its lane | `NativePlaneRecordTests.actResultNamesItsLane`, `.stabilityReportNamesItsLane`, `.runWithNoActuationStillNamesItsLane`; `NativePlaneLaneTests.actNamesItsLane`, `.delegatedRunNamesItsLane`, `.refusedRunStillNamesItsLane` | pass |
| A4 a verdict names its path | `NativePlaneRecordTests.determinismVerdictCarriesItsPath` (both verdicts) | pass |
| A5 actuated names its backend, unactuated does not | `NativePlaneRecordTests.actuatedNativeStepNamesItsBackend`, `.unactuatedStepCarriesNoBackend`, `.delegatedStepNamesItsBackend` | pass |
| A5b run lane and step backends agree | `NativePlaneRecordTests.stepBackendsAgreeWithTheRun`; `NativePlaneLaneTests.stepsAgreeWithTheRun` | pass |
| A6 old records readable, mixed tape refuses | `NativePlaneRecordTests.actResultWithoutALaneStillDecodes`, `.stabilityReportWithoutALaneStillDecodes`, `.recordsRoundTrip`; `NativePlaneLaneTests.preBackendTapeReplays`, `.sameLaneTapeReplays`, `.otherLaneTapeRefuses`, `.mixedTapeRefusesOnALaterStep`, `.unactuatedStepsDoNotTriggerTheGuard` | pass |
| A6b a sweep's passes share one lane | `NativePlaneLaneTests.stabilityReportCarriesTheSessionLane` | pass |
| A7 the wire comment describes the wire | comment change in `Wire.swift`; verified by review, deliberately not by a test | pass |
| A8 the code states the settled decision | comment changes in `main.swift` and `CuaDriverTool.swift`; same | pass |

A7 and A8 have no test on purpose. Asserting a comment's text pins prose and breaks on any
rewording, which is worse than no test; the plan said so and this table repeats it rather
than inventing a check that proves nothing.

### Red-to-green, on the one behavioural change

`requireSameBackend` was reverted to its old first-only form and
`mixedTapeRefusesOnALaterStep` failed with *"an error was expected but none was thrown"*,
then passed with the guard restored. The rest of the branch is additive fields, which are
proved by asserting the encoded output rather than by breaking something first.

### What the decision cost, stated plainly

Two actuation paths stay in the tree. This item declines to call that "frozen": while
native is the default it keeps absorbing macOS behaviour changes and its defects are
fixed. What is capped is expansion, not maintenance. The cost is real and is the honest
price of the failure mode the decision chose.

### Child work found

Recorded in the spec's `Child work found` section: PRO-0034 was retired on a premise this
item rejects; `appleScript` and `shortcut` are unreachable on the Cua lane; `KeyCodes` has
no test at all.
