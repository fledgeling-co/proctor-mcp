# PRO-0054: Three tests still redden the gate at random

**ID:** PRO-0054
**Status:** Merged `a4483ec`
**Created:** 2026-08-15
**Last updated:** 2026-08-16
**Branch:** `ai/pro-0054` (worktree `.worktrees/PRO-0054`)

Source brief: `docs/features-to-triage/55-three-tests-still-redden-the-gate.md`, which names
three intermittent failures and, in a later addendum, a fourth that fails every run.

## What this turned out to be

The brief's instruction was *"assume the test is right until measurement says otherwise"*, and
that was the right instruction. All four named cases, plus thirty more that only became
visible once PRO-0055 unwedged the suite, are **one defect with one cause**: production code
reading ambient machine state that the test neither controls nor declares.

`SessionAct.refusal` decided whether a synthetic step could be delivered by calling
`Grants.secureEventInputActive()` directly. Secure Event Input is on whenever anything
anywhere on the Mac holds a password field or a terminal is in secure keyboard entry mode. A
refused step raises no takeover statement, arms no input block, declares no synthetic post and
yields nothing, so every assertion about synthetic behaviour failed at once, in whichever
suites happened to make one.

That is why the set looked random and looked like several separate bugs. It was neither: it
was a single ambient read, and whether the suite was red depended on what the person at the
keyboard was doing.

## The measurement

Whole suite, `./scripts/test.sh`, on this machine with secure input active:

| Tree | Result |
|---|---|
| `main` before PRO-0055 | no verdict line; the run never completed |
| `main` after PRO-0055 | `1426 tests in 158 suites failed after 126.582s with 37 issues` |
| this branch | `1426 tests in 158 suites passed after 6.516s` |

Seven consecutive runs green: 6.14, 5.79, 5.23, 6.07, 6.81, 3.76 seconds after the first.
Repeated deliberately, because these were the tests the project had been calling flaky, and a
single green run of a timing-sensitive suite proves nothing.

Per suite, before and after:

| Suite | Issues before | After |
|---|---|---|
| `TakeoverWiringTests` | 13 | 16 tests pass |
| `HoldAttributionWiringTests` | 14 | 20 tests pass |
| `YieldWiringTests` | 4 | 19 tests pass |
| `StopReachabilityWiringTests` | 2 | 13 tests pass |
| `ToolchainDoctorTests` | 2 | 21 tests pass |
| `ForegroundWiringTests` | 2 | 8 tests pass |

The wall clock is the other half of the finding. `HoldAttributionWiringTests` alone took **123
seconds** and now takes **1.5**, and the whole suite went from 126 seconds to about 6, because
a refused step still waited out its settle budget. Most of the suite's runtime was spent
waiting for actions that had already been refused.

## What was built

Three changes, all the same shape: state the run does not own becomes an injected seam.

- `Session.accessibilityProbe`, defaulting to `Grants.accessibility()`. The doctor read the
  live `AXIsProcessTrusted()` of the test host, so `ToolchainDoctorTests:203` passed or failed
  on whether the terminal that launched `swift test` held the grant.
- `Session.secureInputProbe`, defaulting to `Grants.secureEventInputActive()`. Added because
  fixing only the Accessibility half left the same test failing on the other ambient read in
  the same assertion, with the blocker text naming secure input outright.
- `SessionAct.refusal` takes `secureInput` as a parameter rather than reading it. This is the
  one that mattered: it is in the hot path of every step, and it is what made 33 of the 37
  issues.

Six test harnesses declare `secureInputProbe: { false }`, and the two direct calls to
`Session.refusal` pass it explicitly.

## Product behaviour is unchanged

`main.swift` constructs the only production `Session` and names neither probe, so both default
to the live grants. Refusing a synthetic step under secure input is correct and deliberate,
it is what the skill documents, and it is untouched. What changed is that a test can now say
which machine it is testing against.

## The limit, named

Both probes default to reading the real machine, which is the right default for a grant: a
`Session` built without arguments must not claim a permission it has not checked. The cost is
that a *new* suite asserting on synthetic steps and not declaring `secureInputProbe` will fail
whenever secure input happens to be on. That is a visible test failure rather than a hang, and
it is the opposite trade from PRO-0055's, where the dangerous value was the one that had to be
named because the failure there was silent.

## What the brief expected, and what was true

The brief predicted three unrelated diagnoses: a second instance of cross-run clearing at
`TakeoverWiringTests:317`, a race inside `ForegroundWiringTests`'s own 800ms polling budget,
and a deadline test in `ScreenRecordingProbeWiringTests` that would be hard to make honest
without weakening it. None of those was the cause. `ScreenRecordingProbeWiringTests` needed no
change at all, and `ForegroundWiringTests`, which an earlier attempt deliberately left alone
as the hardest of the four, went green with the rest.
