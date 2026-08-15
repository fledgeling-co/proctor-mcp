# PRO-0041: `proctor_doctor` stops waiting forever, and says so

**ID:** PRO-0041
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0041.md`
**Brief:** `docs/features-to-triage/42-doctor-can-hang-on-the-screen-recording-probe.md`

## Wave 7 standing

The wave 7 direction hands actuation to Cua and keeps observation. This defect is in the
kept half: Proctor keeps its own ScreenCaptureKit path precisely because Cua's screenshots
carry no frame status, so an unbounded await in the capture-adjacent probe is a defect in
the part of the product wave 7 is betting on. Nothing here contradicts the direction file.

## What was measured

The brief carries the original measurement. Five things were measured again today, in the
worktree, and two of them change the implementation rather than merely confirming it.

**M1 — reproduced, now.** `swift test --filter ObscuraPresenceWiringTests` hangs, killed at
120s, `rc=142`, with zero test output. `replayd` was at **238.8% CPU with 4h41m elapsed**
at that moment.

**M2 — the control still holds, and it narrows the diagnosis.** The same
`SCShareableContent` call from a plain `swift` script answered `granted` (59 windows) in
**0.037s**, at the same moment, on the same machine, with `replayd` saturated. So replayd
saturation is an **aggravator, not a sufficient explanation** — a non-test process got a
definite answer in 37ms while the test host got none in 120s. The wedge is specific to the
swiftpm test host.

**M3 — the bundle is not the wedge.** Trivial suites in the *same* test bundle pass in one
second: `HorizontalAlignmentAssertionTests` (18 tests) and `BuildInfoTests` (25 tests).
Loading the bundle and its frameworks is not what hangs.

**M4 — decisive, and it rules out the obvious fix.** A structured `withTaskGroup` race does
**not** bound this call. Measured with unbuffered file markers: the timer fired at +2.07s
and the race resolved to `unknown`, but `withTaskGroup` **never returned**. A task group
awaits its children before returning, and `cancelAll()` cannot cancel a task parked inside
`SCShareableContent`'s non-cancellable continuation. The probe itself never answered in
120s. Anyone reaching for the idiomatic structured race here will reproduce the hang with
extra steps.

**M5 — the shape that works, verified green.** `withCheckedContinuation` plus two
`Task.detached` (the probe and a sleep timer) plus a resume-once lock returned `unknown` at
**2.030s**, the test passed, and the whole `swift test` process **exited in 4s with the
probe still parked**. So the bound must be unstructured, and an abandoned continuation does
not prevent process exit.

## The decision: unconfirmed, not denied

The brief names the fork. Proctor reports **unconfirmed** — a real third state — and not
denied.

The argument that settles it is already in this repo, written down for a different pair of
facts. `MenuBarBlock` exists because "the doctor's blockers are two different facts about a
Mac wearing one word": a missing grant is a Proctor that will not work until somebody
visits System Settings, and Secure Event Input is a Proctor that is fine and briefly locked
out of the keyboard. Showing the missing-permission triangle for the second was "a machine
reporting a fault it does not have". A probe that did not answer is a third such fact, and
collapsing it into `denied` is the same mistake the same codebase already refused once.

**A first draft of this decision was rejected out of family, and the rejection is taken.**
That draft kept `granted: false` and `ready: false` and put the honesty only in the
`blockers` string. Grok's verdict was that this is "(A) wearing a new field", and the
grounding pass confirms it precisely:

- `GrantRow` in the status window renders `grant.granted == false` as **"Required — not
  granted yet"**, an **Open Settings** button, and a **How** button showing `howToFix`.
- `MenuBarReadiness` maps `!requiredGrantsGranted` to the missing-permission triangle.
- **Neither reads `blockers`.** Honesty that lives only in the blocker string never reaches
  the two surfaces that actually send a person to System Settings.

So the third state has to reach the surfaces that render a remedy, or the fix is cosmetic.

### What the report says

- `DoctorReport.Grant` gains **`state`**: `granted` | `denied` | `unconfirmed`. This is the
  contract. It is optional on the wire so a report from an older agent still decodes.
- **`granted: Bool` stays, and stays fail-closed** — `false` for `unconfirmed` — but is
  **derived from `state`** and redefined in its documentation as *confirmed granted*. A
  legacy consumer that reads only the boolean is conservative and uninformed, which is
  where it already was; nothing over-claims.
- **`ready: false`** when a required grant is unconfirmed. `ready` means established-good,
  and an unanswered probe has established nothing.
- **`howToFix` for an unconfirmed grant is not the System Settings text.** It names the
  bound, says the probe did not answer, and points at re-running `proctor_doctor` or
  restarting the agent. Leaving the Settings text there would keep the **How** button
  telling a person to grant a permission they already granted, which is the whole defect.
- The **blocker** for an unconfirmed grant names it as unconfirmed rather than as a denial.

### The cost, stated plainly

Every consumer that renders a remedy gains a third branch, and `ready` still reads `false`
in a case where Proctor may well be able to capture. That is the price of not lying, and it
is paid in three files rather than across the codebase because the boolean stays.

## The bound, and exactly what is cached

**The bound is named in the report, not only in a comment.** The existing comment — "either
answers or throws, and the throw is the denial" — asserts a two-state model that M1 and M4
contradict, so it is corrected rather than left standing beside a timeout.

**Only definite answers are cached, for the life of the process.** PRO-0028 established
that macOS caches this answer per process for the process's life, which is why the
"Re-check now" row was deleted and `AgentRecovery` replaced it. A `granted` or `denied`
result is therefore a property of this process and cannot change without a relaunch, so
caching it is consistent with the platform rather than an optimisation layered over it.

**An unconfirmed answer is never cached.** A timeout is a property of the moment, not of
the process. Caching one would freeze a transient into a verdict and leave the agent
reporting the same non-answer for the rest of its life after a single slow probe — worse
than the hang, because the hang at least announces itself.

**A late answer may fill the cache for the next report, and never rewrites one already
sent.** If the parked probe eventually resumes with a definite answer, that answer is
recorded and the next `proctor_doctor` call is instant and correct. The report already
returned is history.

**Concurrent callers coalesce onto one probe, and a parked probe is retried on a backoff.**
The status window polls `doctor` every 2.0 seconds for the app's whole life. Without
coalescing, a permanently parked probe would leave a new parked task behind on every poll,
forever.

But *strict* single-flight — at most one probe ever — is worse, and the out-of-family gate
caught it. If the first probe parks forever it holds the slot forever, so every later call
is answered `unconfirmed` without a fresh attempt, and the agent reports the same
non-answer for the rest of its life. That is precisely the failure the brief forbids,
wearing `unconfirmed` instead of `denied`.

So the rule has two halves. Callers arriving **while a probe is within its bound** join it
rather than starting another. Once a probe has exceeded its bound it is **abandoned**, and
the next call may start a fresh one — but no sooner than a **retry interval that backs off
exponentially** (2s, 10s, 60s, then capped at 300s), reset the moment any definite answer
arrives. A call arriving inside the backoff window is answered `unconfirmed` immediately
without waiting. On a permanently wedged machine that is roughly 20 abandoned probes in an
hour rather than 1,800, and an abandoned probe is a suspended continuation rather than a
thread. On a machine that recovers, the agent recovers with it, without a restart.

**The state that makes this work lives outside the actor.** `Session` is a reentrant actor
whose isolation drops at every `await`, so the cache, the in-flight marker and the backoff
clock cannot be `Session` fields — a poll re-entering during the 2.0s wait would tear the
check-then-set. They live in a lock-guarded keeper of their own, every transition happens
in a single synchronous critical section with no `await` inside it, and the late-answer
write hops through that same lock rather than touching actor state from detached work.

**A waiter that times out re-reads the cache before answering.** If a definite answer
landed while it was waiting, it returns that answer rather than `unconfirmed` — the two are
one critical section, not two steps with a window between them.

## Acceptance clauses

1. **A1 — the probe is bounded.** A `doctor` call returns within the bound even when the
   platform never answers and never throws, and the bound is unstructured (M4: a structured
   task-group race does not return).
2. **A2 — the third state exists and is reported.** A grant whose probe did not answer
   reports `state: unconfirmed`, with `granted: false` derived from it, and `ready: false`.
3. **A3 — the remedy is not a lie.** An unconfirmed grant's `howToFix` names the bound and
   the non-answer and does not send the reader to System Settings; the blocker names it as
   unconfirmed rather than as a denial.
4. **A4 — the surfaces that render a remedy branch on `state`, not on the boolean.** The
   status window's grant row does not offer **Open Settings** for an unconfirmed grant, and
   the menu bar does not draw the missing-permission triangle for it, while still declining
   to show a healthy character.
5. **A5 — the recovery offer says what is actually wrong.** When the agent reports
   unconfirmed and this window's own read says granted, the restart is still offered — a
   restart is the right move for a wedged process — but its sentence says the probe did not
   answer rather than claiming the agent is holding an earlier answer.
6. **A6 — only definite answers are cached, for process life.** A definite answer is
   reused; an unconfirmed one is re-probed on a later call; a late definite answer is
   picked up by the next report.
7. **A7 — concurrent callers coalesce, and a wedged probe still recovers.** Calls arriving
   inside the bound share one probe rather than starting several. A probe past its bound is
   abandoned, retried on an exponential backoff, and never holds the slot permanently, so
   the agent cannot be stuck reporting `unconfirmed` for its whole life after one slow
   probe.
8. **A8 — a timed-out waiter returns a definite answer that landed while it waited**,
   rather than reporting `unconfirmed` beside a populated cache.
9. **A9 — the probe state is not actor state.** The cache, the in-flight marker and the
   backoff clock survive `Session`'s isolation dropping at every `await`, and every
   transition is one synchronous critical section.
10. **A10 — the full suite runs unskipped.** `swift test` passes with no `--skip`, and the
    count is read back. The bound itself is tested with the platform call driven as a
    closure (answers / throws / never answers), so injection does not leave it untested.

## Assumptions recorded in place of questions

- `[Experience]` The third state is called **unconfirmed** rather than `unknown`. *(It is
  the state of Proctor's knowledge, not of the permission. "Unknown" reads as a property of
  the grant.)*
- `[Operations]` **The bound is 1.5 seconds.** *(The control answers in 0.037s, so 1.5s is
  ~40x the measured healthy latency and will not fire on a merely slow machine. It is
  deliberately shorter than the status window's 2.0s poll interval: a bound equal to the
  poll leaves no idle gap between one probe's deadline and the next poll, which the
  out-of-family gate flagged. Only the first call of a cold probe pays it.)*
- `[Data & scope]` `granted: Bool` is kept rather than replaced. *(It is already consumed
  on the wire and by the shim; removing it is a protocol break for a cosmetic win, and
  keeping it fail-closed costs nothing.)*
- `[Data & scope]` The bound is named in prose — `howToFix` and the blocker — rather than
  as a new numeric field. *(A `probeTimeoutMs` on `Grant` would over-fit the shape to the
  one grant that has a probe with a timeout.)*
- `[Experience]` **The first-run walkthrough is deliberately not changed.** *(Its remedy is
  an in-process `CGRequestScreenCaptureAccess` prompt, which works whatever the agent's
  probe did, so fail-closed there costs a person one extra click rather than sending them
  somewhere useless. Its "Already allowed? Open System Settings" line is the one weak spot
  and is left alone as scope discipline; recorded here so the next reader knows it was
  considered rather than missed.)*
- `[Operations]` The probe becomes injectable into `Session`, the way `tools: ToolProbes`
  already is, defaulting to the real bounded probe. *(This is what restores the full suite:
  the six hanging tests inject an instant answer. The bound keeps its own tests so
  injection does not hide it.)*
- `[Data & scope]` Accessibility, Automation and the Shortcuts CLI are untouched.
  *(`AXIsProcessTrusted()` reads live and cannot park; Automation already reports a third
  thing — "not established" — through `required: false`, which is a precedent for the shape
  but not a substitute, because `required: false` keeps the Settings chrome off it and
  Screen Recording is `required: true`.)*

## The out-of-family gates

Both ran on grok (`grok-4.6`, effort `xhigh`, read-only), with the evidence inlined rather
than read from disk. Codex is off for this repo. Neither rubber-stamped.

**The decision gate** was given the brief's two options and the proposed design, and
**rejected the design** as option (A) wearing a new field, naming the two consumers that
make it so — the grant row's **Open Settings** button and the menu-bar rung, neither of
which reads `blockers`. That reversal is why clauses A4 and A5 exist, and it moved this
from a one-file change to a four-file one. It confirmed `ready: false` for unconfirmed and
confirmed the caching rule, adding that a late answer must not rewrite a report already
sent.

**The spec gate** attacked four named hazards and found three real ones.

| # | Finding | Disposition |
|---|---|---|
| a | Strict single-flight plus never-caching-unconfirmed starves the probe: a permanently parked probe holds the slot forever, so every later call is refused a fresh attempt and the agent reports `unconfirmed` for the rest of its life | **Accepted, design changed.** This recreated the exact failure the brief forbids. Coalescing now applies only within the bound; past it the probe is abandoned and retried on an exponential backoff. The largest change this review made. |
| b | A 2.0s bound under a 2.0s poll leaves no idle gap between one deadline and the next poll | **Accepted.** The bound is 1.5s. Cheap, and still ~40x the measured healthy latency. |
| c | Isolation drops at every `await`, so a check-then-set of the cache and in-flight marker on the reentrant actor is torn by a re-entering poll; the late fill is a cross-isolation write | **Accepted, and it is now a clause.** A9: the state lives in a lock-guarded keeper outside `Session`, every transition is one synchronous critical section, and the late answer hops through the same lock. |
| d, first half | A waiter can return `unconfirmed` after a definite answer has already landed in the cache, because the timeout path and the late fill are not one atomic step | **Accepted.** Clause A8: a timing-out waiter re-reads the cache inside the same critical section. |
| d, second half | Reusing a late answer treats the old probe's result as a current fact "without this call having probed" | **Rejected, with reason.** A definite answer is a per-process constant on this platform — the premise PRO-0028 rests on, and one the same reviewer affirmed in the decision gate. There is no freshness to lose: an answer arriving late from this process is exactly as valid as one arriving early. |

**The completeness critic**, run against the change as built, found three more real defects.

| # | Finding | Disposition |
|---|---|---|
| 1 | A slot claimed by a probe that never comes back is never freed, so every later call answers `unconfirmed` for the life of the process | **Accepted, fixed.** `claim` now reaps a past-bound probe in passing instead of trusting its starter to return. The permanent-wrong-answer failure had a third road to it and this closes it. Tested. |
| 2 | An abandoned probe is not cancelled, so its late answer could clear a *later* attempt's in-flight marker and let a third probe start beside the second | **Accepted, fixed.** Each attempt carries a generation token; only the current attempt's bookkeeping can be rearranged. The late *answer* is still kept whichever attempt produced it, because a definite answer is a per-process constant. Tested both ways. |
| 3 | A joining caller slept the whole remaining bound even after the answer landed, so a 20ms grant cost every concurrent caller the full 1.5s | **Accepted, fixed.** Joiners poll the cache in 20ms slices and return the moment an answer exists. |
| 4 | The starter's wait is `scheduling gap + bound` rather than exactly the bound, because the timer starts after `claim` stamps the slot | **Accepted as a caveat, not fixed.** The gap is task-scheduling latency between two adjacent statements. Naming a bound of 1.5s that is occasionally 1.51s is honest enough; making it exact would mean stamping the slot from inside the timer task, which reopens the double-start race that stamping in `claim` exists to close. |
| 5 | `SCShareableContent` raises the TCC consent dialog on an ungranted Mac and does not return until it is answered, which is longer than the bound, so a person sitting on the dialog trips the `unconfirmed` path | **Rejected as a defect, documented as behaviour.** It is the correct answer: while somebody is looking at the dialog, the grant genuinely is not established. When they answer, the parked probe returns, its answer is cached, and the window's own 2-second poll reports it. The behaviour this replaces was a health check that blocked until the dialog was dismissed. |

## Child work found

- The status window's **"Already allowed? Open System Settings"** line in the walkthrough
  has the same misdirection risk as the grant row's button, for the same reason. Left alone
  here deliberately (see Assumptions); worth its own item if the walkthrough is revisited.

## Progress — 2026-08-15

**Status: In Review.** Branch `ai/pro-0041`, worktree `.worktrees/PRO-0041`. `swift build`
clean with no new warnings.

**`swift test`: 935 tests in 105 suites pass, unskipped.** The baseline at `da4f48f` was 879
tests in 100 suites *with* `--skip ObscuraPresenceWiringTests --skip BrowserLaneWiringTests`,
and could not be run without them. Restoring the two suites adds 19 tests in 2 suites; this
item adds 37 tests in 3 suites.

Ten full unskipped runs were taken. Eight passed; two went red on a single pre-existing
cross-suite failure in `TakeoverWiringTests` that has nothing to do with this change and is
recorded under Child work with its attribution. Every one of this item's own tests passed in
all ten.

The headline clause was proved red before green rather than reasoned about. With the bound
temporarily removed from `ScreenRecordingProbe.state()`, the new regression test
`aParkedCallDoesNotHang` hung and was killed at 60s (`rc=142`); with the bound restored it
passes in 0.214s.

### Clause → test

| Clause | Proved by |
|---|---|
| A1 bounded | `ScreenRecordingProbeWiringTests.aParkedCallDoesNotHang` (red→green) |
| A2 third state | `unconfirmedIsItsOwnState`, `definiteStatesAreUnchanged`, `unconfirmedIsNotReady` |
| A3 remedy is not a lie | `theRemedyIsNotALie`, `theBlockerDoesNotClaimADenial`, `theSchemaExplainsTheThirdState` |
| A4 surfaces branch on state | `MenuBarUnconfirmedGrantTests` (5 tests). The grant row's dropped **Open Settings** button is read off the diff: there is no test target for `ProctorUI` and no window server under `swift test`. |
| A5 the offer says what is wrong | `unconfirmedIsStillOfferedTheRestart`, `unconfirmedDoesNotClaimStaleness`, `unconfirmedWithoutIndependentEvidenceOffersNothing` |
| A6 caching | `definiteAnswersAreCached`, `unconfirmedIsNeverCached`, `recordingUnconfirmedIsIgnored`, `definiteAnswersAreProbedOnce`, `unconfirmedIsNotRemembered` |
| A7 coalescing and recovery | `callersInsideTheBoundJoin`, `callersPastTheBoundDoNotStartASecondProbe`, `aWedgedProbeIsRetried`, `retriesBackOff`, `abandonIsIdempotentPerProbe`, `aStuckSlotIsReaped` |
| A8 late answers | `aLateAnswerFillsTheCache`, `aWaiterReadsWhatLandedUnderIt`, `aLateAnswerIsPickedUp` |
| A9 state outside the actor | `claimingIsAtomic` (200 concurrent claims, exactly one start), `aStragglerDoesNotDisturbALaterAttempt`, `aStraggerAbandonDoesNotCount` |
| A10 full suite | Ten unskipped runs, count read back each time; the two long-skipped suites are back |

Files: `Sources/ProctorCore/GrantProbe.swift` (new),
`Sources/ProctorAgent/Session/ScreenRecordingProbe.swift` (new),
`Sources/ProctorCore/Wire.swift`, `Sources/ProctorCore/RunHUDMenuBar.swift`,
`Sources/ProctorCore/AgentRecovery.swift`, `Sources/ProctorCore/ToolOutputSchemas.swift`,
`Sources/ProctorAgent/Session/SessionDoctor.swift`,
`Sources/ProctorAgent/Session/Session.swift`, `Sources/ProctorAgent/Contracts.swift`,
`Sources/ProctorUI/AgentModel.swift`, `Sources/ProctorUI/MainWindow.swift`,
`Tests/ProctorCoreTests/GrantProbeTests.swift` (new),
`Tests/ProctorAgentTests/ScreenRecordingProbeWiringTests.swift` (new),
`Tests/ProctorCoreTests/MenuBarReadinessTests.swift`,
`Tests/ProctorCoreTests/AgentRecoveryTests.swift`,
`Tests/ProctorAgentTests/Fakes.swift`,
`Tests/ProctorAgentTests/ObscuraPresenceWiringTests.swift`,
`Tests/ProctorAgentTests/BrowserLaneWiringTests.swift`, `CHANGELOG.md`.

### What a test cannot reach here

The real `SCShareableContent` behaviour: whether it parks on a given machine, and whether
the TCC dialog path behaves as described. Both were measured by hand and are recorded
above. The status window's grant row and the menu-bar glyph are code-complete and reasoned
about; there is no `ProctorUI` test target and no window server under `swift test`.

### Child work found

- **`TakeoverWiringTests.raisedAtTheRightStep` fails when it runs beside
  `StopReachabilityWiringTests`, and it is not this item's doing.** It asserts
  `h.takeover.shows.count == 1` and has been observed failing with both `0` and `2`.
  Attributed rather than assumed: on a clean detached checkout of `da4f48f`, with no part
  of this change present, `swift test --filter "TakeoverWiringTests|StopReachabilityWiringTests"`
  fails **8 runs out of 8** on exactly that test. The same filter on this branch fails 3 out
  of 3, identically. So it is a pre-existing cross-suite interaction rather than a flake and
  rather than anything to do with grants. In a whole-suite run it surfaces intermittently
  (roughly 2 in 10, load-dependent), which is why it reads as flaky from there.
  `StopReachabilityWiringTests`'s "the step's end closes the window even inside the quarter
  second" was seen failing once alongside it, so the interaction probably runs both ways.
  Worth its own item: a merge gate that goes red at random is a gate people learn to re-run,
  which is how a real failure gets waved through.
- **The walkthrough's "Already allowed? Open System Settings" line** carries the same
  misdirection risk the grant row's button did, and is deliberately untouched here (see
  Assumptions).
