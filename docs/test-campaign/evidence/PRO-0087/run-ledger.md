# PRO-0087 — full-suite runs, before and after

All runs on 2026-08-21, one machine, `./scripts/test.sh` with PRO-0083's `ExternalWitnessTests.swift`
and `ReflectorWitnessTests.swift` copied in untracked, because those are what put fifteen sessions on
the socket at once. `forgeNoAnswer` counts the run's occurrences of *the forging peer got no answer*,
which is REQ-035's security clause failing to be exercised at all.

The machine was shared with other worktrees building throughout, and its load average moved between
90 and 900 across the afternoon. That is a confound and it is stated here rather than smoothed over:
the two red sets below were taken at the high end and the green set at the low end. What is *not*
load-dependent is CASE-0115, which reproduces the wedge deterministically in a unit test, and the
two samples, which show what the threads were doing rather than how long they took.

## Set 1 — unmodified tree, load average ~857

| Run | Result | Time |
|---|---|---|
| 1 | passed, 1832 tests | 20.8 s |
| 2 | passed, 1832 tests | 23.4 s |
| 3 | **hung** | killed after ~6 min, no verdict line |

Run 3 was sampled twice, five minutes apart: `wedge-before.txt` and `wedge-before-2.txt`. Both show
15 of 22 threads inside `SecStaticCodeCheckValidity`, every one on
`com.apple.root.default-qos.cooperative`, blocked in `Security::Dispatch::Group::wait()` →
`_dispatch_group_wait_slow` → `__ulock_wait`, with identical sample counts for the whole 5 s window.

## Set 2 — unmodified tree, control taken later the same afternoon, load average ~600-900

| Run | Result | forgeNoAnswer |
|---|---|---|
| 1 | passed | 0 |
| 2 | failed, 5 issues | **1** |
| 3 | failed, 1 issue | 0 |
| 4 | failed, 1 issue | 0 |

Run 2 is the defect this item exists for: four of its five issues are REQ-035's witness, reporting
`ForgedCall(answered: false, ok: false)`. The single issue in runs 3 and 4, and the fifth in run 2, is
`ScreenRecordingProbeWiringTests.aParkedCallDoesNotHang` — recorded as DEF-051, present on the
unmodified tree, and not this item's to fix.

## Set 3 — first fix: shared store, single flight, waiters blocking on an NSCondition

Fourteen runs. Thirteen completed with the forging arm answering on all thirteen, so the wasted work
was gone. One hung anyway, and that is what sent this item back to the drawing board:
`wedge-after-blocking.txt` shows **all sixteen cooperative threads blocked** — fifteen in
`__psynch_cvwait` inside `SignatureVerdictCache.verdict(for:)` and one in
`Security::Dispatch::Group::wait()` — and **no non-cooperative `com.apple.root.default-qos` worker
thread in the process at all**. Fifteen threads waiting on one verification starve it exactly as
fifteen threads running one did.

## Set 4 — shipped fix: shared store, single flight, waiters suspending

| Run | Result | Time | forgeNoAnswer |
|---|---|---|---|
| 1 | passed, 1837 tests | 13.2 s | 0 |
| 2 | passed | 15.2 s | 0 |
| 3 | passed | 18.3 s | 0 |
| 4 | passed | 12.6 s | 0 |
| 5 | passed | 12.1 s | 0 |
| 6 | passed | 13.2 s | 0 |
| 7 | passed | 18.1 s | 0 |
| 8 | passed | 13.2 s | 0 |
| 9 | passed | 15.6 s | 0 |
| 10 | passed | 11.6 s | 0 |

**10 of 10 green.** No run hung. REQ-035's forging arm answered on all ten, against three of five
reported by PRO-0083 and one outright failure in four control runs here.

The run time is worth recording on its own: 11.6-18.3 s against 20.8-31.4 s on the unmodified tree.
The suite is not doing less; it has stopped serialising on a pool that one file's signature check was
holding.

## Set 5 — shipped fix, this branch's own tree, without PRO-0083's suites

The committed tree does not carry `ExternalWitnessTests.swift` or `ReflectorWitnessTests.swift`;
those belong to PRO-0083's branch and were borrowed for sets 1 to 4 only. Five runs on the tree as
committed: **5 of 5 green**, 1828 tests in 216 suites, 3.9 s to 7.8 s.

## What is still open

DEF-051, the `ScreenRecordingProbeWiringTests` bound, which fires on either tree under load and is
recorded rather than fixed here. It did not fire in set 4, and set 4 ran at a lower load average than
the sets it is being compared with, so a green run there is weaker evidence about DEF-051 than it
looks. It says nothing either way about the signature path.
