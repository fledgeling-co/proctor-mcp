# Plan — PRO-0053: The gate can tell the truth about the takeover

**Spec:** `docs/specs/spec-PRO-0053.md`
**Branch:** `ai/pro-0053` (worktree `.worktrees/PRO-0053`)
**Tier:** Small — four source files, two test files, one new script.

## The shape, in one paragraph

The defect has two halves that look alike and are not. In **production**, every run touches
`SyntheticPost.shared` at every step boundary, including runs that could never post; those
runs clear the posting run's state and break two guarantees. In **tests**, two `Session`
instances have two independent `RunScheduler`s, so the exclusive-global-lane invariant that
makes the singleton safe in production does not hold, and two posting suites collide. So:
fix production by having only a run that might post participate in the protocol, and fix
the tests by injecting the seam the way the harness already injects `takeover`,
`contentionMonitor` and `runControl`. Neither half touches the assertion, and neither
changes what a single run does.

## Phase 1 — Production: only a run that might post participates

`Sources/ProctorAgent/Session/SessionAct.swift`.

`ForegroundDemand.mightPost` is the exact predicate — *"could any step in this batch reach
the event stream?"* — and it is already the scheduler's own, via `takesForeground =
mightPost || raises`. `demand` is already in scope at line 179, two lines above the existing
`if demand.takesForeground` block, so this reuses a value rather than deriving a second one.

Because a batch that might post always takes the exclusive `.global` lane, and there is
exactly one `Session` in production (`main.swift:62`) and therefore one scheduler, gating on
`mightPost` means **at most one run at a time is inside the protocol**. That is what makes
the singleton's remaining process-wide scope correct rather than merely tolerated.

Gate all four touches:

- L211/L215 — install and clear the `onDeclare` handler only when the batch might post, so
  a non-posting run cannot take the single slot or nil another run's.
- L254 — `beginStep()`.
- L317 — `endStep()`, inside the step's `defer`.
- L389 — the `declaredThisStep` read that sets `takeoverShown`.

L254 and L317 are the two that caused the production defect: they clear `declared` (the
posting run then never raises the statement, PRO-0026) and `declaredAt` (the in-flight
window closes early and the tap resumes reading Stop mid-post, PRO-0033).

Write the invariant into the code as a comment, because it is load-bearing and not local.

## Phase 2 — The seam becomes injectable

`Sources/ProctorAgent/Session/Session.swift`, matching lines 182–188 exactly:

```swift
var syntheticPost = SyntheticPost.shared
func setSyntheticPost(_ post: SyntheticPost) { syntheticPost = post }
```

`SessionAct` then reads `syntheticPost` rather than `SyntheticPost.shared` at the four sites
above. **The default is `.shared`, so production wiring is unchanged**: the real actuator
declares on `.shared` from a static function and the event tap reads `.shared.inFlight`, and
both must keep meeting the session there.

## Phase 3 — The suites stop driving production state

`Tests/ProctorAgentTests/TakeoverWiringTests.swift` and `StopReachabilityWiringTests.swift`.

- Both harnesses construct a fresh `SyntheticPost()` and inject it. `StopReachability`'s
  harness returns it so its tests can drive it, and its `h.ax.onPerform` declares on that
  instance rather than on `.shared`.
- `StopReachability`'s four pure-unit tests of the type itself — `theKeeperClearsBoth`,
  `aLongGestureStaysStoppable`, `endStepClosesItEarly`, `eachStepStartsClean` — construct
  their own instance. Two of them redirect the `now` clock seam, which on `.shared` is a
  process-wide clock every concurrent suite reads.
- `TakeoverWiringTests` is otherwise untouched. Line 122 stays exactly as written.

No lock is added. `TrailIsolation` is the right shape for `AuditLog`, whose state is
genuinely process-wide; here the sharing is itself the bug, and serialising the suites
around it would leave the production defect in place while turning the gate green.

## Phase 4 — Tests for what Phase 1 fixes

New coverage in `TakeoverWiringTests`, driving two sessions concurrently against one shared
`SyntheticPost` — the production topology, with the lane invariant deliberately absent so
the interference is reachable:

- **A2/A3** — a non-posting batch stepping concurrently does not clear a posting batch's
  declaration or close its in-flight window.
- **A4** — a non-posting run beginning and ending does not remove the posting run's
  `onDeclare` handler.

These fail against Phase 1 reverted and pass with it, which is what makes them evidence
rather than decoration.

## Phase 5 — The gate script

New `scripts/test.sh`, because there is today no committed script that runs the suite and
the rule therefore lives only in runners' memory.

- `set -euo pipefail`, and the runner is **not** on the left of a pipe. Without `pipefail`,
  `swift test | tail` yields `tail`'s status — measured rc=0 on a failing run — which is the
  whole of the reported "exits 0" defect.
- Output is captured with `tee` to a file and the verdict parsed from the file afterwards,
  so nothing depends on the pipeline's status at all.
- The verdict comes from swift-testing's `Test run with N tests ... passed/failed` line. The
  header says why the XCTest `Executed 0 tests, with 0 failures` line must not be read as a
  verdict: it prints on every run, including a failing one.
- Exits non-zero if the runner failed, if the verdict line says failed, or if no verdict
  line was found at all — an absent verdict is a failure, not a pass.

## Phase 6 — Changelog

`## [Unreleased]`, prose through `/create-luke-content` (format `marketing`).

## Acceptance clauses

| Clause | Proven by |
|---|---|
| A1 — paired suites green, repeatedly | `scripts/test.sh` filtered to both suites, ≥20 runs |
| A2 — a poster still raises and reports under a concurrent run | new test, `TakeoverWiringTests` |
| A3 — a non-poster cannot close a poster's in-flight window | new test |
| A4 — a non-poster cannot remove a poster's handler | new test |
| A5 — `shows.count == 1` unchanged | diff of `TakeoverWiringTests.swift:122` |
| A6 — a failing suite fails the process, including when captured | `scripts/test.sh` against a deliberately failing filter |

## Risks

- **The `mightPost` gate could suppress a declaration for a batch that can in fact post.**
  Mitigated by using the scheduler's own predicate rather than a new one: if `mightPost`
  were wrong, the scheduler would already be handing out the wrong lanes.
- **Injection could drift production onto a non-shared instance.** Mitigated by the default
  being `.shared` and by no production code calling the setter.
