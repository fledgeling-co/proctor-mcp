# PRO-0053: The gate can tell the truth about the takeover

**ID:** PRO-0053
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0053.md`
**Branch:** `ai/pro-0053` (worktree `.worktrees/PRO-0053`)

## Feature description

# `TakeoverWiringTests` reddens the gate at random, and `swift test` exits 0 when it does

**Read `00-WAVE-7-DIRECTION.md` first.** This is a gate-reliability item, not a feature.
Every other item in wave 7 is gated by the suite this defect makes untrustworthy.

Source brief: `docs/features-to-triage/54-takeover-tests-redden-the-gate.md`, carrying four
independent measurements on three different trees.

## The problem

`TakeoverWiringTests.swift:122`, in *"a batch that starts on the accessibility plane raises
it at the first synthetic step"*:

```
Expectation failed: (h.takeover.shows.count → 0) == 1
```

Green in isolation, roughly two runs in ten under whole-suite load, and near-certain when
paired with `StopReachabilityWiringTests`. Alongside it, `swift test` was measured exiting
0 on a failed run, which makes every exit-code-based gate in the repo unsound rather than
merely noisy.

## What it should do

Make the suite deterministic, and make a failed run fail the process.

## Not in scope

Changing what the takeover overlay does. PRO-0026 settled that. This item is about the
test being able to tell the truth about it, and about the state underneath being scoped
the way both PRO-0026 and PRO-0033 already assume it is.

## Triage — 2026-08-15

**Ready for Implementation Plan**

**Sentinel review:** S2 — Approve with assumptions. The item arrived described as a test
flake and a build-tool defect. Grounding found neither description survives contact with
the code: the flake is a **production** concurrency defect that the test harness merely
exposes, and the exit code is correct in `swift test` itself. Both restatements are
carried below with the measurement behind them, because acting on the original framing
would have produced a test-only lock that hides a live defect, plus a workaround for a
bug that does not exist.

### Reproduction on current `main`

Confirmed before any change, worktree `.worktrees/PRO-0053` at `8d2fde6`:

| Configuration | Runs | Failures |
|---|---|---|
| `--filter TakeoverWiringTests --filter StopReachabilityWiringTests` | 8 | **7** |
| whole suite, 1043 tests in 113 suites | 3 | 1 |

The pairing is the reproduction; the whole suite is the incidental exposure.

### The cause, and the asymmetry that identifies it

Only `shows.count == 1` fails. `arms.count == 1`, four lines below in the same test, holds
every time. That asymmetry names the mechanism exactly, because the two guards read the
same flag in opposite directions:

```swift
func takeoverShow(app: String?) { guard !takeoverShown else { return }; takeoverShown = true; takeover.show(app: app) }
func takeoverArm(for step: ActionStep) { guard takeoverShown else { return }; takeover.arm(...) }
```

A show that is skipped while an arm still fires means `takeoverShown` was **already true**
when the batch reached its first synthetic step. `SessionAct.swift:389` is what sets it:

```swift
if SyntheticPost.shared.declaredThisStep { takeoverShown = true }
```

`SyntheticPost.shared` is one process-wide object. `StopReachabilityWiringTests` installs
`h.ax.onPerform = { _ in SyntheticPost.shared.declare() }` in three of its tests. Running
concurrently — swift-testing parallelises across suites, and `.serialized` orders tests
only *within* one suite — that declaration sets the process-wide `declared` flag that
`TakeoverWiringTests` then reads after its own non-posting `press` step. The overlay is
marked as already raised, so the `click` that follows raises nothing and the batch reports
zero shows and one arm.

This is the same class of defect PRO-0047 found and the same class the brief predicted.
It is not the same *fix*, for the reason below.

### It is a production defect, not a test artifact

`Sources/ProctorCore/RunQueue.swift` states the concurrency plainly: *"two sessions driving
different apps genuinely do not interfere and run in parallel."* An accessibility-only
batch takes only its app's lane; only a batch that can post takes the exclusive `.global`
lane. So two runs genuinely do overlap inside one process, and every one of them calls
`SyntheticPost.shared.beginStep()` at every step boundary:

```swift
func beginStep() { lock.lock(); defer { lock.unlock() }; declaredAt = nil; declared = false }
```

That clears **two** pieces of state belonging to whichever run is currently posting:

- `declared` — so the posting run reads `declaredThisStep == false` at `SessionAct:389`,
  never raises the statement for a `type` or `scroll` that fell back to the event stream,
  and under-reports `takeover.report(shown:)`. A person is not told the machine was taken.
  That is PRO-0026's guarantee failing silently.
- `declaredAt` — so the in-flight window closes early and the event tap resumes reading the
  Stop rectangle *while Proctor's own click is still travelling*. That is PRO-0033's
  guarantee failing, and it is the more serious of the two.

The single `handler` slot has the same shape: `onDeclare` is installed per run and `defer
{ onDeclare(nil) }` clears it, so the last run to start wins the slot and the first to
finish removes it for everyone.

The out-of-family review found the `declaredAt` half, which this triage had not drawn out
(see **Gates** below).

### The fix: split the type by what each field's scope actually is

Three options were weighed.

**A. A test-only mutex**, in `TrailIsolation`'s shape. Rejected: it makes the suite green
while leaving both production failures in place, which is the outcome the brief warned
against in a different costume. `TrailIsolation` is the right precedent for `AuditLog`,
whose state is *genuinely* process-wide; it is the wrong precedent here, where the sharing
is itself the bug.

**B. A run token threaded through `SyntheticPost`.** Rejected: it turns a singleton into a
run table without encoding why, and leaves easy leftovers — a `beginStep(run:)` that still
zeroes the one `declaredAt`, or an `inFlight` keyed per run that the tap then reads for the
wrong run.

**C. Split the type by scope.** Taken. The object holds two different kinds of fact:

- `declaredAt` / `inFlight` is a **machine-wide** physical fact. The event tap must decline
  to read Stop while *any* post is open, so this scope is already correct and stays on the
  shared instance.
- `declared` / `declaredThisStep` and the `handler` are **per-run** facts — did *this* step
  post, and who should be told.

The split is enforced by **who is allowed to touch the object at all**, which turned out to
be simpler than the run token option C first sketched and strictly stronger. A run joins the
protocol only when it can actually post, and a run that can actually post holds the
exclusive `.global` lane, so the one participant has the shared instance to itself. No owner
field is needed: there is only ever one owner.

The predicate is `demand.mightPost && foreground`, both halves load-bearing. `mightPost` is
the scheduler's own, so it cannot disagree with the lane that backs it. `foreground` is
required because `refusal(for:foreground:)` turns away every synthetic step when the batch
did not ask for the front, and the stability sweep's `resetBetween` is a real path where the
two come apart (see **Gates**).

Behaviour for a single run is unchanged, which is what keeps PRO-0026 out of scope. What
changes is that the guarantee now also holds when two runs overlap, which is the case the
scheduler explicitly permits.

The assertion is not touched. `shows.count == 1` stays exactly as written.

### The exit code is a shell defect, not a toolchain one

Measured on current `main`:

| Invocation | Failed run |
|---|---|
| `swift test` | **rc=1** |
| `swift test --parallel` | **rc=1** |
| `swift test 2>&1 \| tail -3` | **rc=0** |
| `swift test 2>&1 \| grep -c Expectation` | **rc=0** |

`swift test` reports failure correctly. The zero exit is a pipeline artifact: without
`set -o pipefail`, `$?` is the *last* command in the pipeline, so any runner reading the
status of `swift test ... | tail` reads `tail`'s success. Every measurement in the brief
was taken through such a pipe.

A second trap sits beside it. The XCTest half of the run prints, on every run including a
failing one:

```
Executed 0 tests, with 0 failures (0 unexpected)
```

A gate grepping that line reads green on a red suite. The swift-testing line — `Test run
with 1043 tests in 113 suites passed/failed` — is the one that carries the verdict.

There is today **no committed script that runs the suite**: the gate exists only in
runners' memory, which is precisely where the brief said the rule must not live. So the
answer is a checked-in gate script that a CI job would find, carrying `set -euo pipefail`,
no pipe around the runner, and the parse rule documented beside the code that applies it.

### Assumptions

1. **Behaviour under a single run is unchanged**, so no PRO-0026 or PRO-0033 acceptance
   clause is renegotiated. The change is a scope correction, verified by the existing
   suites for both features staying green unmodified.
2. **The event tap's in-flight window keeps machine-wide scope.** Narrowing it to a run
   would let one run's post be readable as a person's Stop press during another's.
3. **The gate script does not replace `swift test` in anyone's fingers** — it is the thing
   CI and a runner *should* call, and it says why in its own header rather than relying on
   this spec being read.

## Gates

**Out-of-family design review — grok-4.6, effort xhigh.** Given the three candidate fixes
with the concurrency evidence inlined. Returned **C**, and independently surfaced the
`declaredAt` half of `beginStep()` that this triage had identified only for `declared`:
*"beginStep() today also nils declaredAt, so a non-posting run does not just steal the
overlay flag; it closes the tap's window."* Verified against
`Sources/ProctorAgent/Overlay/RunHUDGeometry.swift` and adopted — it is the reason the
in-flight window gains an owner rather than being left alone. Its rejection reasons for A
and B are carried into the option table above.

**Out-of-family completeness critic — grok-4.6, effort xhigh.** Given the finished gate and
asked what it misses, with the other entry points to the run loop named. It found a real
hole that the first draft of the fix left open, on the stability sweep's reset path:

> *"The hole is `resetBetween`. Lanes and `foreground` come from the flow. A click/key reset
> of an AX-only flow has `mightPost == true` and no `.global` … it still steals the handler
> and `beginStep`s, which is the original clobber against a concurrent poster."*

Verified against `SessionFlow.swift:270-306`: the sweep computes its lane demand from the
**flow's** steps and then runs `resetBetween` through the same loop as a batch of its own,
so `mightPost ⇒ holds the exclusive lane` does not hold there. Closed by widening the gate
to `demand.mightPost && foreground`, which is sound because
`SessionAct.refusal(for:foreground:)` turns away every synthetic step when `foreground` is
false — such a batch is refused before it can post and has nothing to declare, so nothing
legitimate is lost. Covered by A7.

Its other two observations were checked and needed no change: no current step kind reaches
the actuator's declaration with `participates` false, and a refused step that skips its
`endStep` leaves nothing open, because `beginStep` has already cleared `declaredAt` and
`endStep` only clears it again.

## Child work found

**A second, unrelated flake in `ForegroundWiringTests`.** Surfaced by the verification runs
for this item, not by the original brief, and it is a different defect with a different
cause.

`ForegroundWiringTests.swift:108`, *"the menu bar can answer whether a run is taking the
machine, with the panel off"*: `Expectation failed: sample → nil`. The test starts a
four-step run in a `Task` and polls `recentActivity()` up to 400 times at 2ms for
`foreground.active == true`, so it has an 800ms budget to catch a state that exists only
while the batch is in flight. Under load the run either completes before the poller
observes it or the poller's own sleeps are starved, and the `#require` fails.

Measured on this branch, after PRO-0053's fix, with machine load average 18 to 38 because
another runner was active:

| Configuration | Runs | Failures |
|---|---|---|
| whole suite | 20 | 1 |
| `ForegroundWiringTests` **alone** | 30 | 2 |

It fails in isolation, which rules out the cross-suite state collision this item fixed. It
is a timing race inside one test, and fixing it properly means deciding how a test observes
mid-run state deterministically — a barrier or a signal rather than a poll — which is a
design question of its own. Recorded and reported rather than specced, per the runner
contract.

The `RunHUDGeometry.shared` panel rectangle is the other process-wide seam the two suites
in this item share. It is published and cleared under `defer` by the only suite that writes
it, and no measured failure traces to it, so it is left alone rather than pre-emptively
locked.

## Acceptance

- **A1** — Paired, `TakeoverWiringTests` + `StopReachabilityWiringTests` run together
  repeatedly, the takeover suite is green every time. Measured over enough runs to beat the
  7-in-8 pre-fix failure rate by a wide margin.
- **A2** — A run that posts still raises the statement exactly once per batch and still
  reports having taken the machine, when a second run is stepping concurrently.
- **A3** — A concurrent non-posting run cannot close the in-flight window that a posting
  run opened.
- **A4** — The declaration handler installed by one run is not removed by another run
  finishing.
- **A5** — `shows.count == 1` at `TakeoverWiringTests.swift:122` is unchanged.
- **A6** — A committed gate script exits non-zero on a failing suite, including when its
  output is being captured, and refuses to read the XCTest `Executed 0 tests` line as a
  verdict.
- **A7** — A batch that cannot post because it did not ask for the front does not touch the
  declaration keeper, which is the stability sweep's `resetBetween` path.

## Progress — 2026-08-15

**In Review.**

### Verification

A race that passes once proves nothing, so the numbers and the load both matter. Another
runner was active on this machine throughout, which is the load the defect needs.

| Configuration | Before | After | Load average |
|---|---|---|---|
| paired suites | 7 failures in 8 | **0 in 25** | 53 |
| paired suites (first pass) | as above | **0 in 20** | 18 |
| whole suite, 1046 tests | 1 in 3 | **0 in 15** | 97 |
| whole suite (first pass) | as above | 1 in 20, unrelated suite | 18 |

**Zero takeover failures in 80 post-fix runs.** The single failure across all of them was
`ForegroundWiringTests`, a separate defect that reproduces in isolation and is recorded
under **Child work found**.

Every acceptance clause that asserts a behaviour was checked red first, by reverting the
production gate and confirming the test fails:

| Clause | Test | Red without |
|---|---|---|
| A2 | `aNonPostingRunLeavesTheDeclarationAlone` | `participates` gate |
| A3 | `aNonPostingRunLeavesTheWindowOpen` | `participates` gate |
| A4 | `aNonPostingRunLeavesTheHandlerInstalled` | `participates` gate |
| A7 | `aRefusedSyntheticBatchLeavesTheKeeperAlone` | the `&& foreground` half |

A6 was checked against a genuinely failing suite, direct and under command substitution
(rc=1 both), against a zero-test filter (rc=1), and against a build failure (rc=1, reported
as an absent verdict rather than a pass). The zero-test case was found by testing the
script rather than by reasoning about it: the first draft read `Test run with 0 tests in 0
suites passed` as green.

`swift test` counts: 1043 before, 1046 after.
