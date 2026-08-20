# PRO-0018: Notice when a person is taking the machine back, and yield

**ID:** PRO-0018
**Status:** Merged
**Created:** 2026-08-14
**Last updated:** 2026-08-14
**Brief:** `docs/features-to-triage/19-yield-when-a-person-takes-the-machine.md`
**Plan:** `docs/plans/plan-PRO-0018.md`
**Builds on:** PRO-0019 (`ForegroundDemand`, `syntheticInFlight`), PRO-0015 (`RunControl`, the panel)

## What it is

A run that is taking the foreground stops taking it when the person whose Mac it
is starts using it, and says why. PRO-0019 computed whether a batch takes the
foreground and disclosed it; this acts on it.

Nothing about which steps are synthetic changes. Nothing new is refused. The only
new behaviour is that the run holds, on the latch a person's own Pause already
uses, when it can tell it is fighting somebody.

## The signal, and what it costs

The whole feature is signal quality, so this names which signals it takes,
which it declines by default, and what each one misses.

| signal | how it is read | default | what it misses |
|---|---|---|---|
| **The frontmost application changed under the run** | `NSWorkspace.didActivateApplicationNotification`, cached | **on** | a person acting *inside* the app under test |
| **Secure Event Input turned on** | `Grants.secureEventInputActive()`, already used by `proctor_doctor` and by the step refusal | **on** | anything that is not keyboard-secure |
| **A person's own input event** | run-scoped `NSEvent.addGlobalMonitorForEvents`, armed only while a contending run is in flight | **off**, opt-in via `PROCTOR_YIELD_INPUT` | nothing — it is the direct reading, and it is the one that can go wrong |

### The privacy decision, taken deliberately

PRO-0015 declined a global mouse monitor for click-through and the reasoning
holds: an agent that already holds Accessibility should not quietly acquire an
input-observation capability nobody asked for.

A **run-scoped, foreground-only** monitor genuinely is a different proposition
from an always-on one. It exists only while Proctor is already posting events
into the person's session — a moment the panel and the menu bar are both already
announcing — it is torn down when the run ends, and it records one timestamp and
one event class per event, never a keycode, a character, a modifier or a
location. Nothing it holds could reconstruct what anybody typed.

Different is not the same as free, so it ships **off**. What a default install
gets is the two signals that read *facts about the machine* rather than
observations of what a person did: which application is in front, and whether
the window server is in secure keyboard entry.

**Does the frontmost signal alone buy enough to skip the monitor?** For the
common case, yes: a person taking their machine back reaches for another
application — their editor, their browser, Slack — and that is exactly what it
sees. It misses one case, and the miss is real: a person clicking inside the
same app Proctor is driving. That case is what the opt-in buys, and it is the
case where a false positive is also most expensive, which is a second reason for
it not to be the default.

## Proctor's own events must never read as a person's

The named failure mode: a `click` step posts an event, that event is counted as a
person taking over, and every synthetic run halts itself on its first step. Three
independent filters, two of them fully testable without a window server.

1. **The frontmost signal separates by construction.** The contended fact is
   `frontmostPid != expectedPid`, and `expectedPid` is *the pid Proctor put in
   front*. A foreground change Proctor caused changes both sides of the
   comparison, so it can never register. `expectedPid` is set only once Proctor
   has demonstrably taken the front — a step whose reported plane was
   `.syntheticEvent`, or a settled `raise` — and is nil before that, when
   Proctor has not taken anything and there is nothing to take back. **And the
   reading is armed only once that pid has actually been observed in front**, so
   a raise that silently failed reads as a raise that failed rather than as
   somebody moving an app that never arrived. That last clause was added after
   the suite caught its absence; see Gates.
2. **Every event Proctor posts carries a tag.** The actuator's four
   `CGEventSource(stateID: .hidSystemState)` sites go through one factory that
   sets `source.userData` to a per-process magic, and each posted event carries
   `.eventSourceUserData`. The monitor discards any event whose user data
   matches. The predicate is pure and tested; the actuator's use of the factory
   is tested; what a real posted event carries through to a real `NSEvent` is
   not witnessable here and is stated as such.
3. **A grace window around every synthetic post.** An `NSEvent` global monitor
   delivers on the main run loop, asynchronously, so an event Proctor posted can
   arrive after `syntheticInFlight` has already gone false — the in-flight flag
   alone is a race. Input arriving within `graceMs` (250ms) of the last
   synthetic post is discarded regardless of its tag. Pure arithmetic over two
   timestamps, and fully tested.

Filter 3 costs the feature its best case — a person clicking while Proctor
clicks — and that is the trade the brief names. Losing that case is cheap
(a person using the machine generates input between steps too, which is where
the checkpoint reads); pausing every synthetic run on its own first click is not.

## The mechanism: one latch with an attributed cause

Not a second mechanism. `RunControl` keeps one `paused` flag, one `pausedAt`
clock and one backstop; what is new is that it records *who* paused:

```
paused == pausedByPerson || yieldReason != nil
```

- `pause()` sets `pausedByPerson`; `resume()` clears both; `stop()` clears
  everything. The three buttons behave exactly as they do at HEAD.
- `checkpoint(contention:)` evaluates a probe on every poll of the loop it
  already runs, so a yield can begin *and end* while the run is parked.
- The 15-minute backstop already bounds `paused`, so it bounds a yield. A
  yielded run cannot be held forever, and gives up saying so.

**Contention is a state, not an edge.** The yield holds while the condition holds
and releases when it clears: the app comes back to the front, or secure input
goes off. Nothing guesses a window length. (The input signal is genuinely an
edge, so it decays after `PROCTOR_YIELD_INPUT_WINDOW`, default 10s.)

`ContentionWatch` in `ProctorCore` is the whole of the logic — a pure value
taking samples and returning `yielded`/`released`/`none`. `ContentionMonitor` in
`ProctorAgent` is the AppKit half: it caches the frontmost pid from a workspace
notification, arms and disarms the optional `NSEvent` monitor, and holds no
policy at all.

## Acceptance clauses

**A1 — only a run that is actually contending can yield.** The watch is armed
when `demand.takesForeground` **or** when a step has actually reported
`plane == .syntheticEvent` — measured, not predicted, so a `type` batch that
fell back is covered and one that did not is never held. An accessibility-plane
run samples nothing and can never yield. *Test: an all-`press` batch with a
person's app in front runs to completion unpaused.*

**A2 — Proctor's own foreground changes never read as a person's.**
`ContentionWatch` returns `nil` for every sample where `frontmostPid ==
expectedPid` and for every sample where `expectedPid` is nil. A batch of ten
synthetic steps against an app Proctor raised yields zero times. *Test: drive the
watch through a whole synthetic batch's samples; assert no yield.*

**A3 — the two default signals fire and release.** Frontmost moving to another
pid yields `.frontmostChanged` and returns to running when it comes back;
`secureEventInputActive` turning on yields `.secureInput` and releases when it
turns off. Secure input outranks the frontmost reading when both hold, because it
is the one that names why injected keystrokes are least welcome. *Test: sample
sequences for both, each asserting the yield and the release.*

**A4 — one latch, one backstop.** A yield sets the same `paused` flag a person's
Pause sets, starts the same clock, and expires through the same
`pauseExpired` path with the same `haltedByPerson` refusal. A run yielded and
never released gives up rather than hanging. *Test: a yield with a millisecond
`pauseLimit` returns `.pauseExpired`.*

**A5 — a person's decision always wins, and Resume is not immediately
undone.** Resume — from the panel or from the menu bar's `proctor_hud` verb —
clears a yield and records the reason as overridden, so the still-true condition
that caused it does not re-yield on the next poll. It re-arms only once that
reason has cleared and recurred. A person's own Pause is never cleared by a
yield releasing. *Test: yield → resume → the same sample twice → still running;
then clear and re-assert the condition → yields again.*

**A6 — the panel says why, in the settled vocabulary.** `RunHUDEvent.yielded`
and `.unyielded` reduce to phase `.paused` (quiet grey — a person using their own
Mac is not a fault) with one line at one size:

| reason | line |
|---|---|
| `frontmostChanged` | `Paused — you moved to another app` |
| `secureInput` | `Paused — secure keyboard entry is on` |
| `userInput` | `Paused — you used the keyboard or mouse` |

The **ask** is the two controls already there: the line is the question,
`Resume` (`pauseLabel` is already "Resume" in `.paused`) and `Stop` are its two
answers. No third control, no dialog, no new colour. *Test: reducer assertions
for each reason's line, phase, tone and `pauseLabel`.*

**A7 — the menu bar states it, and the icon ladder is not reordered.**
`proctor_recent_activity`'s `foreground` block gains `yield` (`active`,
`reason`, `line`); `MenuBarContent`'s activity line states it. While yielded no
step is acting, so `foreground.active` is false and
`MenuBarIcon.decide(reachable:ready:phase:takingForeground:)` reaches
`.character(.paused)` through its existing order — reachability, grants,
foreground, phase — with no new case and no reordering. *Test: the wire block's
shape, and `decide` returning `.character(.paused)` for a yielded run.*

**A8 — a yielded run says so afterwards, so a slow suite has a reason.** Each
yield is audited as it happens (`run.yielded` / `run.resumed`, with the reason),
and `ActResult` gains `yields: [YieldRecord]?` — `reason`, `step`, `heldMs`,
`endedBy` (`released`, `person`, `stopped`, `backstop`, `runEnded`) — with a
one-sentence `note`. Nil when nothing yielded, so every existing result is
byte-identical. Flow replay reports the same block. *Test: encode/decode of the
records; a run with no yield encodes exactly as it does at HEAD.*

**A9 — the input monitor is off by default and armed only inside a contending
run.** With `PROCTOR_YIELD_INPUT` unset, no monitor is installed, on any code
path. With it set, one is installed when a contending run begins and removed
when it ends. `PROCTOR_YIELD=0` switches the whole feature off, the pointer
overlay's and the panel's switch shape exactly. *Test: the switch parsing for
both, defaulting opposite ways; the arm/disarm wiring against a fake.*

## Assumptions recorded in place of questions

- **A-i. The yield holds while the contention holds** rather than for a fixed
  window. The condition that caused it is observable and so is its end, so a
  timer would be a guess where a fact is available. The existing backstop is the
  only time bound, and it is a give-up, not a resume.
- **A-ii. It rides the existing latch with an attributed cause.** The brief says
  reuse `RunControl`'s pause with its backstop; a separate yield flag beside it
  would be a second mechanism with a second way to strand a run. One flag, two
  causes, one clock.
- **A-iii. An explicit Resume overrides the current episode.** Otherwise the
  button is dead while the person is still in another app — press Resume, get
  re-yielded on the next 60ms poll — which is the "pause nobody can undo" this
  spec exists to avoid.
- **A-iv. The ask is the panel's existing pair, not a dialog.** A modal from an
  accessory agent over somebody's work is worse than the thing it is asking
  about, and the settled design allows one line and the run's two controls.
- **A-v. Proctor does not get a vote on why the front changed.** A notification
  centre alert or an app finishing a launch reads as contention and yields. That
  is a false positive and it is deliberately cheap: the yield releases by itself
  the moment the app is back in front. Deciding whether the person meant it is
  explicitly out of scope.
- **A-vi. Arming is measured, not predicted.** `mayTakeForeground` is not used —
  PRO-0019 built it for disclosure only, and holding a `type` batch that never
  falls back would be exactly the noise the brief's scope rules out.
- **A-vii. A stability sweep yields like anything else.** All four run kinds go
  through `runSteps`; a sweep posting events is contending. The `yields` block is
  added to `act` and flow replay only, following PRO-0019's A-v.
- **A-viii. The grace window is 250ms and the input decay 10s.** Both are
  substitutable properties so tests run in milliseconds rather than in seconds.

## Out of scope

- Deciding whether the person's action was a mistake.
- Refusing a run, or changing which steps are synthetic, or what is disclosed —
  PRO-0019 owns disclosure and its behaviour is unchanged.
- A CGEventTap. The optional monitor is a passive `NSEvent` observer; a tap can
  swallow or rewrite the person's events and is not worth its risk here.
- The HUD's design, which is settled and binding (`mocks/run-hud.html`).

## What a `swift test` cannot witness here

- **That a real posted `CGEvent` carries our tag through to a real `NSEvent`.**
  The tag is set and read by tested code, and filter 3 covers the case where it
  does not survive, but the round trip needs a window server. Stated, not
  dressed up.
- The panel drawing the yielded line, the menu-bar item, and a real person's
  click arriving. Same category as PRO-0015's and PRO-0019's untestable set.
- `NSWorkspace`'s activation notification actually firing. The cache it feeds is
  tested by injection; the notification itself is AppKit's.

## Known limits, stated rather than hidden

Every one of these was found by an out-of-family gate rather than by the build,
and each is a real cost of the design rather than a defect left in.

- **A burst of synthetic steps closer together than the grace window hides a
  person's click.** The 250ms grace opens before every synthetic post and again
  after it, so a batch of fast steps keeps the filter closed almost continuously
  and the best case the brief names — a person clicking while Proctor clicks —
  is exactly the case that is lost. That is the trade filter 3 exists to make,
  and the alternative is worse: an echo the driven application emits in response
  to Proctor's own click would read as a person and hold every synthetic run on
  its first step. Between steps the filter is open, which is where the checkpoint
  reads anyway.
- **The watch is read between steps, never during one.** A hold declared while a
  `dragPath` is mid-gesture takes effect after that gesture settles, exactly as
  a person's Stop already does. Killing a gesture halfway leaves an application
  in a state nobody can describe.
- **The first synthetic step of a run is not covered by the frontmost signal.**
  `expectedPid` is set from a measured plane, so before the first posted event
  there is nothing Proctor has demonstrably put in front and nothing to take
  back. Secure input *is* sampled at the first checkpoint, so a password field
  focused before the run does hold it. Disclosing a run before it starts is
  PRO-0019's job, and it does it.
- **Secure Event Input stuck on turns a fast refusal into a hold.** At HEAD, a
  synthetic step under secure input is refused in a second with wording that
  names the cause. Now the watch usually gets there first and the run parks
  instead, which is the right answer when a person is typing a password and the
  wrong shape when secure input has been left on by an input method or a
  password manager with nobody there. It is bounded (below) and reported, and
  `PROCTOR_YIELD=0` opts out of it. The per-step refusal is unchanged and still
  fires when the watch did not get there first.
- **Anything else injecting events reads as a person.** The filter's positive
  case is "came from the hardware", i.e. a source pid of 0. Universal Control, a
  remapper, another automation tool: none carry Proctor's tag and some carry no
  pid, so they hold the run. The cost is a visible hold with a stated reason and
  a Resume button, which is the cheapest way to be wrong here.
- **The frontmost signal says what happened to the front, not who did it** — the
  restatement of A-v, and the reason the input signal exists at all.
- **A flapping condition is bounded on the run, not on the episode.** A
  condition that takes and loses the front repeatedly would otherwise start a
  fresh backstop on every re-latch and hold a run indefinitely in chunks each
  one of which is individually legal. Time already spent yielded is banked
  against the same `pauseLimit`, so the automatic hold is bounded across the
  whole run. A person's own pause is judged on its own episode, because a person
  deciding again is a person deciding.

## Gates

- **Measurement before design, 2026-08-14.** A throwaway probe on this machine,
  because reasoning about `CGEvent` semantics is how this feature fails.
  Load-bearing negative result: `CGEventSource.secondsSinceLastEventType(
  .hidSystemState, .mouseMoved)` read 3.108s, one `mouseMoved` was posted to
  `.cghidEventTap` exactly as `Actuator` does, and it then read 0.298s — **our
  own posts reset the hardware idle timer, so the cheap idle-timer route cannot
  separate agent from person and is not used.** Two positives: an event we
  posted carries our own pid in `.eventSourceUnixProcessID` where hardware
  carries 0, and a `userData` stamp set on the source survives to the event.
  One further negative: `.eventSourceStateID` reads 1 for a posted event exactly
  as for hardware, so source state must not be used. An idle machine produced no
  events at all through the discrete-down mask over six seconds.
- **Spec review, out of family, `grok-4.6 --effort xhigh`, 2026-08-14.** Put the
  two-signals-versus-three question with the measurements inlined. It argued for
  including the input signal and named three constraints: discrete downs rather
  than movement, teardown on run end and on `deinit`, and stating the hold on
  the HUD rather than pausing silently. All three are in the build. Its
  counter-argument — "this time the scope is tight is how the second tap gets
  in" — is answered by shipping the input observation **off by default** rather
  than dismissed, which is a stronger answer than the one it argued against, and
  by using a passive `NSEvent` monitor rather than the tap it assumed.
- **Plan review, out of family, `grok-4.6 --effort xhigh`, 2026-08-14.** Four
  real defects in the draft plan, all fixed before any code was written:
  1. **The classifier was inverted.** The plan read "ours if the pid is mine,
     else a person", which compiles, passes a test written against it, and in
     production reads the driven application's echoes, an input method and the
     window server as a person — none of which ever lets go. The measurement
     says hardware carries pid 0; the predicate now says so, and
     `aProcessIsNotAPerson` pins it.
  2. **Proctor's own windows could hold the run.** Somebody opening Proctor's
     menu to press Resume changes the frontmost application, which would hold
     the very run they were reaching to release. `proctorPids` is now part of
     the condition.
  3. **One reason at a time forgot the others.** A click plus an app switch left
     the state holding one reason, so clearing that one released a hold the
     other still justified. The watch keeps the set and releases on none.
  4. **The release had no damping**, so a single sample of the front flickering
     would release a real hold and immediately re-take it.
- **Completeness critic, out of family, `grok-4.6 --effort xhigh`, 2026-08-14.** that the build and the suite both passed: a
  condition that flaps re-latches and restarts the backstop, so a run could be
  held indefinitely in individually-legal chunks. Fixed by banking yielded time
  against the run rather than the episode; pinned by
  `aFlappingConditionIsStillBounded`. Five of its other points are true and are
  now in Known limits above. Four were false of the built code, and are recorded
  here so the next reader does not re-find them: a global `NSEvent` monitor
  **does** see typing in the app under test (it misses only Proctor's own
  events); `expectedPid` is set from the app under test's pid and so cannot
  retarget to the person's application; every latch field is reset in `begin()`
  and every monitor field on the last `disarm()`, pinned by
  `nothingCarriesIntoTheNextRun`; and an event carrying no `CGEvent` is treated
  as not-a-person rather than as pid 0, pinned by `noSourceIsNotEvidence`.

## Progress

**Branch:** `ai/pro-0018` · **Worktree:** `.worktrees/PRO-0018` · not merged, not pushed.

### Clause → the test that proves it

| clause | tests |
|---|---|
| A1 only a contending run can yield | `anAccessibilityRunArmsNothing`, `aContendingBatchArms`, `aMeasuredFallbackArms` |
| A2 Proctor's own foreground changes never read as a person's | `proctorsOwnForegroundIsNotContention`, `noExpectedPidMeansNoContention`, `proctorsOwnProcessIsNotAPerson` |
| A3 the signals fire and release | `frontmostYieldsAndReleases`, `secureInputYieldsAndReleases`, `secureInputOutranksFrontmost`, `userInputDecays`, `releaseIsDamped`, `everyReasonHasToClear` |
| A4 one latch, one backstop | `aYieldExpiresLikeAPause`, `oneClockForBothCauses`, `releaseAndResumeDifferent`, `aFlappingConditionIsStillBounded`, `aPersonsRepeatedPauseIsTheirOwnDecision` |
| A5 a person's decision wins and Resume is not undone | `resumeOverridesTheEpisode`, `overrideIsSpentWhenTheConditionGoes`, `theOverrideIsPerReason`, `resumeIsRecordedOnTheLatch`, `beginClearsEverything`, `nothingCarriesIntoTheNextRun` |
| A6 the panel says why, in the settled vocabulary | `everyReasonSaysWhy`, `theYieldedStateIsThePausedOne`, `unyieldingReturnsToTheStep` |
| A7 the menu bar states it, the ladder is not reordered | `theMenuBarStatesTheHold` |
| A8 a yielded run says so afterwards | `theRecordsSayWhatHappened`, `silenceWhenNothingHappened`, `noYieldsIsByteIdentical`, `aHeldRunSaysSo` |
| A9 the input monitor is off by default, armed only inside a contending run | `theInputMonitorIsOptIn`, `theWholeFeatureSwitchesOff`, `theOptInReachesTheMonitor`, `nothingNewIsRefused` |
| the three filters | `ourOwnEventsAreNeverAPerson` (exhaustive), `aProcessIsNotAPerson`, `noSourceIsNotEvidence`, `theGraceWindowCatchesTheEcho`, `everySourceIsStamped`, `theGraceOpensBeforeThePost` |

### Deferred

- **Nothing deferred from this spec.** Every clause is built.

### Child work found, not scheduled

- **The panel's mouse gate is still driven by the step's kind, not its measured
  plane.** Carried over from PRO-0019 unchanged; a fallback `scroll` posts a
  wheel event the panel does not step aside for. Narrow, not a regression, and
  not widened here.
- **A hold cannot be attributed to a particular display or session in the
  queue.** With two runs in flight on different applications, the menu bar shows
  the highest-precedence hold across all of them but does not say whose. The
  queue bar has the rows; joining the two is a change to the queue's model.

- **The suite found the defect the reviewers did not, 2026-08-14.** The first
  full `swift test` after the feature landed took **902 seconds** and failed 21
  expectations across four pre-existing suites, every one of them a run that
  performed exactly one step and then stopped. The runtime was the diagnosis:
  900 seconds is `RunControl`'s backstop. Those runs were being **yielded and
  held to expiry**.

  The cause is a real design fault, not a test artefact. `frontmostChanged` held
  whenever `frontmostPid != expectedPid`, which reads as "the front is not what
  Proctor asked for" rather than "somebody moved it". In the suite the driven
  application is a fake whose pid is never frontmost, so the condition was true
  from the first sample of every synthetic run. In production the same fault
  fires whenever a raise silently fails or an application is slow to come
  forward: Proctor would park the run and tell the reader they had moved to
  another app, when the app never arrived.

  **Fixed by requiring confirmation.** The watch records the expected pid it has
  actually seen in front, and the frontmost reading cannot fire until it has.
  Pinned by `anUnconfirmedFrontCannotFire`, which is the test that would have
  caught this before the suite did. The wording now matches what is observed:
  Proctor put an app in front, it was there, and it is not there now.

  Worth recording as a method note: the three out-of-family gates found a
  classifier inversion, a self-hold through Proctor's own menu, a lost reason, a
  missing damper and an unbounded flapping hold, and none of them found this
  one. A slow suite was the instrument.

## Completeness critic (grok-4.6 xhigh, run at merge by the orchestrator)

The runner died on a gateway 503 before reaching this gate, so it was run here.
Twelve findings; dispositions below. **None blocks the merge**, and the reason is
one comparison: without this feature a person taking the machine back gets no hold
at all. Every finding below describes either holding when it should not (bounded by
the backstop, and annoying) or ceasing to hold (which is exactly today's behaviour).
Nothing here is worse than the status quo it replaces.

**Accepted as real, and open:**

1. **Resume-and-walk-away.** The override lasts until the condition clears, so a run
   resumed while somebody else's app is still in front keeps posting into it,
   unattended, with no re-raise. The strongest finding. Today's behaviour is the
   same, and the person did choose Resume, but a supervision feature that resumes
   into the wrong app deserves better than parity with having no feature.
2. **`secureInput` is session-global** and does not ask whether the secure field
   belongs to the target. A run legitimately driving a password field holds itself,
   waits out the backstop and stops, reported as a person's decision.
3. **A helper process in front is not a person.** A Security Agent sheet, a TCC
   prompt, System Settings, or any helper the test itself opened all read as
   `frontmostChanged`.
4. **A target that quits or crashes mid-hold** reads as the front changing, so the
   run waits out the backstop and the stop is attributed to a person.
5. **The backstop attributes everything to a person's decision**, which hides a
   stuck detector, a dead target and a forgotten override behind one wording.

**Accepted as true and already bounded elsewhere:**

6. Concurrent foreground runs holding each other — PRO-0016's global lane is
   exclusive, so two foreground runs do not overlap in the first place.
7. Synthetic events landing on Proctor's own UI — PRO-0015's panel already ignores
   mouse events for exactly as long as a synthetic step is in flight.

**Accepted as a stated design choice, not a defect:**

8. If Proctor never observed the target in front, nothing arms and a person gets no
   hold. That is the deliberate conservative end of the `confirmedFront` rule: the
   alternative reads "the front is not what I asked for", which is true from the
   first sample whenever a raise silently failed, and reports a person moving an app
   that never arrived.
9. A ~250ms poll can miss a very short cmd-tab. Sampling is what this is; the panel
   is the instantaneous surface.
10. An armed run holds during its accessibility-plane stretches too. Arming is
    per-run rather than per-step because the run holds the foreground across them.

**Child work worth its own spec:** findings 1 and 2 are the two that change what a
person experiences rather than what the log says, and 5 is a wording fix that would
make 3 and 4 diagnosable instead of misattributed.
