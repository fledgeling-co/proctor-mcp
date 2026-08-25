---
sources: [REQ-022]
status: retired
---
> **A FOURTH CASE, added 2026-08-16 after this brief was written, and it is the worst of the
> set because it is not intermittent.** `ToolchainDoctorTests.swift:203` — *"a machine with
> none of these tools is still ready"* — fails **4 runs out of 4** on unmodified `main` at
> `330338d`, asserting `report.ready == true` and getting `false` with the blocker
> *"Accessibility is not granted"*.
>
> The cause is visible in the test's own helper and does not need measuring: `session(...)`
> in that file injects `screenRecordingProbe: .fake()` but injects **nothing for
> Accessibility**, so `doctor()` reads the live `AXIsProcessTrusted()` of the test host. The
> suite therefore passes or fails on whether the terminal that launched `swift test` happens
> to hold the Accessibility grant, which is ambient machine state the test does not control
> and does not declare. It passed throughout the wave and fails now with no change to the
> tree between.
>
> This is the same defect class as the other three — a test measuring something it does not
> own — and PRO-0041 already built the seam that fixes it, since the grant model has an
> injectable probe. Fix it the way `screenRecordingProbe` is already handled here. It is
> **not** a product regression: `ready` correctly reports a real ungranted Accessibility, and
> that is the fail-closed behaviour PRO-0041 chose deliberately.

# Three tests still redden the gate at random, and PRO-0053 only fixed one of them

**Read `00-WAVE-7-DIRECTION.md` first.** This is a gate-reliability item, the second of its
kind, and it exists because the first one worked: PRO-0053 went looking for a flaky test and
found a live production concurrency defect that was silently breaking PRO-0026's overlay and
PRO-0033's Stop tap. **Treat these three the same way: assume the test is right until
measurement says otherwise.**

## The measurements

All taken on unmodified `main` at or after PRO-0053's merge (`477941f`), by three different
runners plus the orchestrator, none carrying a change to the file in question.

| Test | Measured | By |
|---|---|---|
| `TakeoverWiringTests.swift:317` | **2 failures in 30** on unmodified main, 2 in 15 on a branch | PRO-0029 |
| `ForegroundWiringTests.swift:108` — *"the menu bar can answer whether a run is taking the machine, with the panel off"*, `sample → nil` | **2 in 30 in isolation**, and reproduced once at merge under fleet load | PRO-0053, then the orchestrator |
| `ScreenRecordingProbeWiringTests.swift:116` — *"a late answer is picked up by the next call"*, `await probe.state() == .granted` | 1 in 7 under fleet load; 1 more in 6 on a later branch | the orchestrator, PRO-0049 |

Together they redden a full-suite run roughly one time in ten. That is high enough that a real
finding will eventually be waved away as "that flake again", which is the actual cost.

## What PRO-0053 established, and what it did not

It fixed **line 122** of `TakeoverWiringTests`: every run called `beginStep()` at each step
boundary and cleared state belonging to whichever run was actually posting. Line 317 is a
different assertion in the same file and **survived that fix**, so it is either a second
instance of cross-run clearing that the `mightPost && foreground` predicate does not cover, or
something else entirely. Do not assume it is the same bug wearing a different line number.

`ForegroundWiringTests:108` is explicitly *not* cross-suite: PRO-0053 measured it failing **in
isolation**, which makes it a race inside that test's own 800ms polling budget. That is a
different diagnosis and probably a different fix.

`ScreenRecordingProbeWiringTests:116` tests PRO-0041's late-answer path, which is deliberately
timing-dependent: a probe that misses its 1.5s bound, answers afterwards, and fills the cache
for the next call. A test of a deadline that is itself sensitive to load is the hardest of the
three to make honest without weakening what it proves.

## The hard parts, named

- **Do not fix any of these by weakening an assertion or widening a timeout until you have
  said what the test is for.** PRO-0053's whole value came from asking why the assertion was
  there before making it pass. A timeout widened to absorb a real race deletes the coverage
  rather than the race.
- **`ScreenRecordingProbeWiringTests` needs a decision, not a nudge.** Either the test drives
  the clock rather than the wall, or it accepts that it is measuring a deadline and is marked
  as such. PRO-0041's own design notes say a non-answer is a property of the moment, and a
  test asserting on the moment inherits that.
- **The three may want three different answers**, and a single mechanism applied to all of
  them is a smell. Say per test what it was, what it is now, and how many runs under what load
  you took as evidence.
- **Prior art is on `main` and worth reading first:** `Tests/ProctorAgentTests/TrailIsolation.swift`
  (PRO-0047's lock for a shared process-wide seam), and PRO-0046's note that it converted a
  process-wide `static var` test seam into a constructor parameter for exactly this reason.

## Evidence bar

A race that passes once proves nothing, and this brief exists because that mistake has already
been made. PRO-0053 took **80 post-fix runs at load averages 18 to 97** with another runner
active. Match that order of magnitude, say the load, and check each fix red first by reverting
it.

## Not in scope

Changing what the takeover overlay, the foreground disclosure or the Screen Recording probe
do. PRO-0026, PRO-0019 and PRO-0041 settled those; this is about the tests being able to tell
the truth about them.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-022
- surface: SURF-008, SURF-016
- cases: CASE-0011, CASE-0024, CASE-0027, CASE-0028, CASE-0029, CASE-0039
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: none
