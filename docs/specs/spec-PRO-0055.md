# PRO-0055: The suite wedges in `haltCheckpoint` on a shared RunControl

**ID:** PRO-0055
**Status:** Merged `e53176b`
**Created:** 2026-08-16
**Last updated:** 2026-08-16
**Branch:** `ai/pro-0055` (worktree `.worktrees/PRO-0055`)

Source brief: `docs/features-to-triage/56-the-suite-wedges-in-haltcheckpoint.md`.

## The problem

`./scripts/test.sh` on unmodified `main` never printed a verdict line. Between 24 and 59
tests never reported, on a quiet machine, after a `replayd` restart. Ruled out by
measurement rather than by argument: not load (reproduces at load average 6 with zero stuck
helpers), not `replayd` (survives a restart), not `BrowserLaneWiringTests` (skipping it
changes nothing), and not any one suite in isolation.

A sample of the wedged process gave six threads on one identical stack:

```
Session.scheduled            SessionQueue.swift:96
  → Session.runSteps          SessionAct.swift:360
    → Session.haltCheckpoint  SessionHUD.swift:210
      → RunControl.checkpoint RunControl.swift:252
```

`checkpoint` is an unbounded poll returning only on a halt or on becoming un-parked, so a
run parked with neither spins forever holding its lane, and `Session.scheduled` above it
holds the queue.

## The cause, measured rather than inferred

A temporary probe on `RunControl` reporting every mutation of the process-wide instance,
with a backtrace, caught it on the first run:

```
=== SHARED RunControl yield(run: 1) ===
  RunControl.yield(run:hold:)
  Session.contentionProbe(run:step:)     ← inside the poll
  RunControl.checkpoint(run:probe:)
  Session.haltCheckpoint(probe:)
```

So it is not one suite leaving state behind for the next, which is what the brief expected.
It is a live re-decision. `Session` defaulted two seams to process-wide production state:

```swift
var runControl = RunControl.shared
var contentionMonitor: any ContentionSampling = ContentionMonitor.shared
```

`ContentionMonitor.shared` reads the actual Mac. A test process can never satisfy "the
application under test is frontmost", because there is no such application and the front
belongs to whatever the developer last clicked. Sampled from inside the checkpoint poll,
that reading yields the run, and yields it again on the next poll, and again, until the
900-second backstop gives up.

Five suites construct a `Session`, run a foreground batch and name neither seam:
`BackgroundRouteTests`, `BrowserRoutingTests`, `CuaBackendTests`,
`DelegatedSupervisionWiringTests`, `ForegroundWiringTests`. The four suites that actually
test yielding all inject a latch and a fake monitor explicitly, which is why they were
never implicated.

## What was built

The defaults are inverted. The safe values are what a `Session` takes when nobody says
otherwise, and the two process-wide seams are named at the single construction that wants
them, in `main.swift`. Both are constructor parameters, following PRO-0046, which converted
a process-wide `static var` seam for this same reason.

- `Session.runControl` defaults to a fresh `RunControl`.
- `Session.contentionMonitor` defaults to a new `NullContentionMonitor`, which samples a
  machine nobody is using. `expectedPid` nil is the load-bearing field: the frontmost
  reading cannot fire while Proctor has not demonstrably put anything in front.
- `main.swift` passes `runControl: .shared` and `contentionMonitor: ContentionMonitor.shared`,
  which it must, because the panel's Pause and Stop write the process-wide latch directly.

A park that happens anyway now says so. After 20 seconds the checkpoint writes one line to
stderr naming the run and its cause. The backstop is not shortened: how long a person's
pause may hold a run is a product decision, and cutting it would turn a hang into a wrong
answer.

## Why this shape rather than the alternatives

Referred out of family. The grok lane failed (exit 142, garbled output); the Google lane
answered and argued for making both seams parameters with no default at all, updating every
call site, and flagged that detecting a test process via `NSClassFromString("XCTestCase")`
is unreliable under swift-testing.

That reading is right about the direction and wrong about the cost. No-default means 47 test
sites and 1 production site, and its own named failure mode is that call-site fatigue drives
people to a shared helper that reintroduces the singleton. Inverting the default gets the
same explicitness for one edit, and makes the recurrence structurally impossible rather than
a matter of discipline: a new test that names nothing is now safe by construction.

What the losing option is better at: it makes the production dependency visible at every
site rather than at one, so a second production `Session` that forgot the arguments would be
caught by the compiler. That failure mode is real and is not covered by the compiler here,
so `SessionIsolationWiringTests.productionOptsIn` asserts the `main.swift` call site
directly instead.

## Evidence

`ForegroundWiringTests`, one of the five, is the cleanest single measurement:

| Tree | Result |
|---|---|
| `main` at `24c9b7d` | killed at 10 minutes, no verdict |
| `ai/pro-0055` | 8 tests, 1.189 seconds, verdict printed |

Whole suite, `./scripts/test.sh`:

| Tree | Result |
|---|---|
| `main` | no verdict line; 24 to 59 tests never report |
| `ai/pro-0055` | `Test run with 1426 tests in 158 suites failed after 126.582 seconds with 37 issues` |

## What the fixed gate reveals, and what it does not

The gate is now runnable and red. All 37 issues are pre-existing and none are caused by this
change, established by running each failing suite on unmodified `main` and comparing issue
counts:

| Suite | Issues here | Issues on `main` |
|---|---|---|
| `TakeoverWiringTests` | 13 | 13 |
| `HoldAttributionWiringTests` | 14 | 14 |
| `YieldWiringTests` | 4 | 4 |
| `StopReachabilityWiringTests` | 2 | 2 |
| `ToolchainDoctorTests` | 2 | 2 |
| `ForegroundWiringTests` | 2 | cannot be run: it hangs |

35 of 37 are byte-identical on `main`. The other 2 are in the suite that could not be
executed there at all, which is the defect this item closes.

`docs/features-to-triage/55-three-tests-still-redden-the-gate.md` says three tests redden
the gate. The measured figure is 37 issues across 14 tests in 6 suites. That understatement
was itself a consequence of the wedge, since nobody had seen a complete run.

`HoldAttributionWiringTests` takes 123 seconds alone, which is most of the whole suite's
wall clock and is a second defect this item does not fix.

## Not in scope

Changing what pause, yield or the backstop mean; PRO-0018, PRO-0033 and PRO-0037 settled
those. Fixing the 37 revealed issues, which is PRO-0056.
