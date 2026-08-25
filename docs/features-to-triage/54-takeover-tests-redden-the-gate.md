---
sources: [REQ-008, REQ-042]
status: retired
---
> **RESOLVED as PRO-0053, merged `477941f`. Both diagnoses in this brief were wrong, and
> the corrections are the interesting part.** It was not a flake: `TakeoverWiringTests` was
> exposing a live production concurrency defect in which a run that could not post cleared
> the *posting* run's declaration state, silently breaking PRO-0026's overlay and closing
> PRO-0033's in-flight window early so the event tap read the Stop rectangle while Proctor's
> own click was still travelling. And `swift test` does **not** exit 0 on failure; it exits 1,
> plainly and under `--parallel`. The zero came from `swift test | tail` without `pipefail`,
> which returns `tail`'s status — a defect in how this orchestrator and two runners invoked
> it, not in the toolchain. `scripts/test.sh` now owns the verdict.

# `TakeoverWiringTests` reddens the gate at random, and `swift test` exits 0 when it does

**Read `00-WAVE-7-DIRECTION.md` first.** This is a gate-reliability item, not a feature.
Sequence it early in whatever stage has room: every other item in the wave is gated by
the suite this defect makes untrustworthy.

## The measurement

`TakeoverWiringTests.swift:122`, in the test *"a batch that starts on the accessibility
plane raises it at the first synthetic step"*:

```
Expectation failed: (h.takeover.shows.count → 0) == 1
```

Three runners measured it independently, on three different trees, none of them carrying
a change that touches it:

| Measured by | Tree | Result |
|---|---|---|
| PRO-0043 | clean detached checkout of `da4f48f` | fired on the 5th of 5 runs |
| PRO-0041 | clean detached checkout of `da4f48f`, run beside `StopReachabilityWiringTests` | **8 failures in 8** |
| PRO-0040 | clean worktree at `0545219` | **3 failures in 6** |
| the orchestrator | `main` at `9756282`, full suite | 1 failure in 4 |

In isolation the suite is green. Under whole-suite load it surfaces in roughly two runs
in ten, and paired with `StopReachabilityWiringTests` it appears to fail every time. So
this is a cross-suite interaction, not a flake in the ordinary sense, and the pairing is
the strongest lead.

## The second half, which is worse than the first

**`swift test` exits 0 on this failure.** Measured by PRO-0040. Any check that reads the
exit code alone reports a red suite as green, which makes every exit-code-based gate in
this repo unsound rather than merely noisy. The only reliable signal today is parsing the
`Test run with N tests ... passed` / `... failed` line.

Both halves need an answer. A green exit code on a failed run is arguably the more
serious of the two, because it is silent.

## What it should do

Make the suite deterministic, and make a failed run fail the process.

## The hard parts, named

- **Find the shared state before changing the test.** `RunControl.shared` and
  `ContentionMonitor.shared` are singletons, and a harness that does not inject them
  drives production state and leaks it into other suites. `Tests/ProctorAgentTests/TrailIsolation.swift`
  (PRO-0047) already established the pattern for one such collision: a lock every suite
  touching the shared seam takes. Whether the same shape fits here is the question, not
  the assumption.
- **`.serialized` only orders tests within one suite.** PRO-0047 found two suites
  redirecting the same process-wide seam in parallel and stamping on each other. That is
  the class of defect to look for first, and `StopReachabilityWiringTests` is the named
  suspect.
- **Do not fix it by weakening the assertion.** `shows.count == 1` is the whole point of
  the test: a batch starting on the accessibility plane must raise the takeover overlay at
  the first synthetic step, which is PRO-0026's guarantee. An assertion relaxed to make a
  race pass deletes the coverage rather than the race.
- **The exit code is a separate investigation.** Establish whether this is swift-testing's
  behaviour, a SwiftPM behaviour, or something about how this package is configured, and
  say which. If it cannot be fixed, the gate needs a documented parse rule instead, and
  that rule belongs somewhere a CI job would find it rather than in a runner's memory.

## Not in scope

Changing what the takeover overlay does. PRO-0026 settled that, and this item is about
the test being able to tell the truth about it.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-008
- surface: SURF-005
- cases: CASE-0009, CASE-0010, CASE-0031, CASE-0052, CASE-0053, CASE-0054
- rungs reached: effect-witness, metamorphic, outcome
- provider: CGEventTap in Sources/ProctorAgent/Session/ContentionMonitor.swift and Sources/ProctorAgent/Overlay/TakeoverOverlay.swift; NSEvent.addGlobalMonitorForEvents
