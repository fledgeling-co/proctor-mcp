# PRO-0028: Re-check now says what it checks

**ID:** PRO-0028
**Status:** Merged
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0028.md`
**Brief:** `docs/features-to-triage/29-re-check-now-says-what-it-checks.md`

## The question, and the fact that answers it

The brief offers two options — relabel the menu's **Re-check now** to name its object,
or remove it and rely on the poll — and says the poll interval is the whole argument
for removal. It is not. Something else is.

**The poll interval is 2.0 seconds.** `AgentModel.startPolling` schedules
`refreshDoctor()` on a repeating 2-second timer, and a second timer polls activity
every 0.5s. Polling starts in the model's `init`, not on the window appearing, so it
runs for the app's whole life with the window closed. `refresh()` — what the button
calls — is those same two calls, run now. So the button advances a read by **at most
two seconds**.

**The button cannot do the one job the brief keeps it for.** The brief's case for
keeping it is the permission moment: a grant made in System Settings that macOS never
tells the app about. Take the two required grants separately.

| Grant | How it is probed | Does the 2s poll see a grant made in Settings? | Does Re-check? |
|---|---|---|---|
| Accessibility | `AXIsProcessTrusted()`, in the agent | Yes, within 2s | Yes — up to 2s sooner |
| Screen Recording | `SCShareableContent.excludingDesktopWindows(…)`, in the agent | **No** | **No** |

`SCShareableContent` answers from a TCC state macOS caches **per process, for the life
of that process**. The agent is long-lived. Once it has been told no, it keeps being
told no, and both the poll and the button ask that same process. This is not a new
claim — the app already relies on it: `AgentModel.requestScreenRecordingPrompt` grants
through its own dialog and then calls `reprobeAfterGrant()`, which
`launchctl kickstart -k`s the agent so it re-probes, holding an "Applying…" transient
across the socket drop. That path exists *because* a running agent cannot be told.

So the moment the brief names is real, it is the reason the button is defended, and
the button does not serve it. Relabelling to "Check permissions now" would make it
worse than a vague label: it would name the object it demonstrably cannot re-read.

## What this feature is

**The menu row goes, and its slot carries the controls that actually resolve the two
states where the menu had nothing to offer.**

1. **`Button("Re-check now")` is deleted from `MenuBarContent`.** Everything it could
   read is already read every two seconds.
2. **A conditional block appears in its place**, in the menu's existing
   statement-plus-action idiom (the same shape PRO-0027 used for the stale build): a
   sentence saying what is wrong, and one button that fixes it. Two conditions produce
   an offer, and nothing else does.

**The restart, for a Screen Recording grant the agent is holding a stale denial of.**
The gate is Screen Recording specifically, not "a required grant is missing". A missing
Accessibility grant does not need a restart — the poll picks it up — and offering a
`SIGKILL` for it would drop a run to fix nothing. This narrowing came from the
out-of-family review of the first draft.

It is offered **only when this window can see the grant for itself**, through
`CGPreflightScreenCaptureAccess()` — a live, non-prompting read of the same TCC record,
because `scripts/build-app.sh` signs every nested binary with `-i "$BUNDLE_ID"` for
exactly this reason. Verified on the installed bundle: `Proctor` and `proctor-agent` both
report `Identifier=app.fledgeling.procter`, one team, one Info.plist.

That gate is a reversal, and the completeness critic is why. The first draft offered the
restart whenever the agent reported Screen Recording ungranted, hedging the sentence with
"if you have just granted it in System Settings", and treated the window's own read as a
wording refinement rather than a condition — on the reasoning that a preflight which
turned out to cache would otherwise suppress the control. The critic named what that
actually ships: a permanent row, on every Mac that has not granted Screen Recording and
is not going to, whose button cannot create a grant. A restart cures a stale answer, never
an absent permission. The suppression risk is real and accepted knowingly, because it is
bounded — the same restart sits one row below through `Proctor Status…` — where a
permanent nag is not.

**The start, for an agent that is not answering.** Removing the row would otherwise have
left the menu with nothing to do about a wedged agent, which the critic caught. The old
row's `refresh()` was never the cure for that either; `Actions.ensureAgent()` is, and the
status window has had it all along. Now it is on the surface people actually reach for.

**Nothing is offered while a restart is in flight.** `isApplying` is checked first and
above everything, because during the 1.2s settle the agent is legitimately unreachable:
without it the menu would offer to start an agent that is already coming back, and a
second click would stack a second `SIGKILL` on a process mid-launch.

**The cost is named where it is real.** `launchctl kickstart -k` drops any run in flight,
and a run *can* be live with Screen Recording denied because the accessibility plane still
works. So when a run is in flight the sentence says the restart stops it. No confirmation
sheet: a menu is a poor confirmation surface, and the run at risk is one that cannot
capture anything anyway.

**Nothing else moves.** PRO-0027's stale-build block, the status line, the activity line,
the foreground notice, the run controls, the panel toggle and the bottom group are
untouched. The new block sits directly below the stale-build block, because both are
"something about this Proctor is wrong, here is the one action that fixes it" and the
stale build is deliberately first — a status read from a replaced build is a status about
the wrong Proctor.

**The status window's `Re-check` buttons are out of scope and stay.** The brief is about
the menu row. Those three sit beside a `Checked 14:32:01` timestamp, an "agent not
answering" paragraph, and an Obscura callout respectively — each has its object from
context, which is exactly what the menu row lacked.

## Acceptance clauses

1. **A1 — the row is gone.** `Re-check now` no longer appears anywhere in
   `MenuBarContent`, and no menu item calls `model.refresh()`.
2. **A2 — the restart is offered only for a stale Screen Recording grant.** Reachable,
   the agent denying it, and this window seeing it offers the restart. A healthy agent
   offers nothing, and no other grant is an input at all.
3. **A3 — a restart is offered only where a restart is the cure.** With the window's own
   read denied or unavailable, nothing is offered: a restart cannot create a permission,
   and the status window owns the grant flow. The sentence claims staleness only where it
   is independently confirmed.
4. **A4 — a run in flight is named as the cost**, and naming it changes nothing else
   about the offer.
5. **A5 — the decision is a pure function in Core**, decided from five inputs and
   testable without a window server, with button titles in the register of their
   neighbours. The actions are the existing `Actions.ensureAgent()` and the existing
   `reprobeAfterGrant()`; no new mechanism.
6. **A6 — the grant path is not contradicted.** `requestScreenRecordingPrompt` →
   `reprobeAfterGrant` → `Actions.restartAgent()` with its "Applying…" transient is
   unchanged, and now has a second caller reaching the same remedy by hand.
7. **A7 — a restart already in flight is not offered a second one.** While `isApplying`,
   nothing is offered, whatever the other inputs say.
8. **A8 — an unreachable agent is offered a start**, whatever it last said about grants,
   and never a restart.

## Assumptions recorded in place of questions

- `[Experience]` Removal plus a targeted replacement, rather than the brief's bare
  relabel-or-remove. *(Relabel names an object the control cannot read. Bare removal is
  defensible but strictly loses the one case the brief cared about, and takes the menu's
  only action away from a wedged agent as well. The out-of-family review picked the same
  third option unprompted and narrowed it from "any missing required grant" to "Screen
  Recording", which is taken.)*
- `[Experience]` The restart is gated on this window's own read of the grant, not merely
  worded by it. *(Reversed from the first draft on the completeness critic's first
  finding. Ungated, every Mac without Screen Recording carries a permanent row whose
  button cannot help. The cost is that a preflight which caches per process would
  suppress the offer on a window older than the grant; that is bounded by the same
  restart being one row below through `Proctor Status…`, and by relaunching the window,
  which PRO-0027 already surfaces.)*
- `[Experience]` No confirmation before the restart, and the cost is carried in the
  sentence above the button instead. *(A menu is a poor confirmation surface, and the run
  at risk is one already running without Screen Recording.)*
- `[Operations]` `CGPreflightScreenCaptureAccess()` in the UI process reads the same TCC
  record the agent answers from. *(Measured on the installed bundle rather than assumed:
  `codesign -dv` reports `Identifier=app.fledgeling.procter` for `Proctor` and for
  `proctor-agent`, one team identifier, one Info.plist, because `build-app.sh:112` signs
  every nested binary with `-i "$BUNDLE_ID"` and says why. Whether the call reads live in
  a long-running process is not verifiable under `swift test`.)*
- `[Operations]` The 2-second figure is the scheduled interval, not a guaranteed one.
  *(App Nap, timer coalescing and menu-tracking run-loop mode can all delay a tick, and
  the critic was right to say so. It does not change the decision: the button never solved
  the Screen Recording case at any cadence, and for everything else the two answers are
  the same answer.)*
- `[Experience]` The brief says the menu's items are sentence case. They are not —
  `Proctor Status…`, `Run Setup Again…`, `Show Run Panel`, `Pause Run`, `Stop Run`,
  `Quit Proctor` are title case, which is the macOS menu convention. The new buttons are
  `Start Agent` and `Restart Agent`, matching `Relaunch Proctor`. The explanatory line
  above them is a sentence, matching PRO-0027's `Proctor was updated. Relaunch to use the
  new version.`
- `[Data & scope]` No new tool, no new internal verb, no change to the readiness ladder,
  the character, the panel, or `DoctorReport`. The status window is untouched.

## The out-of-family gates

Both ran on grok (`grok-4.6`, effort `xhigh`, read-only), with the evidence inlined
rather than read from disk. Codex is off for this repo. Neither rubber-stamped.

**The decision gate** was given the measured facts and the brief's two options plus a
third, and chose the third — remove and replace with a restart — unprompted, then
narrowed it: gate on Screen Recording alone, "do not show it for Accessibility-only: that
grant does not need a restart, and showing it would SIGKILL for nothing." Taken. It also
argued for naming the run cost in the label rather than behind a confirmation, which is
what the sentence does.

**The completeness critic** returned nine findings against the built change. Four landed
and changed the code:

| # | Finding | Disposition |
|---|---|---|
| 1 | Offering the restart whenever the agent says "denied" ships a permanent, useless row on every Mac that has not granted Screen Recording; a restart cannot create a grant | **Accepted, design changed.** The window's own read became a gate rather than a wording refinement. This is the largest change the review made. |
| 4 | Removing the row left the menu mute about a wedged agent, which is the case where a restart is genuinely required | **Accepted, feature added.** An unreachable agent is offered `Start Agent`, wired to the existing `Actions.ensureAgent()`. |
| 6 | `isApplying` is not an input to the decision, so a double click stacks a second `SIGKILL` and the momentary unreachability reads as "start me" | **Accepted, guarded and tested.** `applying` is checked first, above reachability. |
| 9 | A long `Text` in a menu truncates and is read aloud as one string | **Accepted in part.** The sentences were shortened to the length PRO-0027's neighbour already carries, pinned by a test. Truncation and VoiceOver themselves are not witnessable here. |
| 2 | "Both binaries in one `.app`" does not mean one TCC client; a LaunchAgent usually has its own bundle identifier, so the preflight would be reading a different record | **Refuted by measurement.** `codesign -dv` on the installed bundle reports `Identifier=app.fledgeling.procter` for both binaries, and `build-app.sh:112` pins them there deliberately, with a comment naming TCC as the reason. |
| 3 | Only the agent is recycled, so a capture path in *this* process would still be stuck | **Rejected.** The UI process never captures; capture is the agent's job. The related risk — that this process's own preflight is frozen — is the accepted cost of finding 1's gate, recorded above. |
| 5 | The "2 seconds" rationale is weakened by App Nap, timer tolerance and menu-tracking mode, and Re-check was a user-timed invalidation | **Accepted as a caveat, not a reversal.** Recorded as an assumption. The button never reached the Screen Recording case at any cadence. |
| 7 | Any `SCShareableContent` failure is labelled a TCC cache, including "no display" or pre-unlock | **Narrowed rather than fixed.** With finding 1's gate, staleness is claimed only when the grant is independently confirmed present. A non-TCC failure with the grant in place still reads as stale, and a restart is a defensible response to it. |
| 8 | The insight was not carried to the status window's own Re-check buttons | **Rejected for this item, logged as child work.** Those sit beside a `Restart agent` button that already does the right thing, and the brief is about the menu row. |

## What a test cannot reach here

`swift test` has no window server and there is no test target for `ProctorUI`. Not
machine-witnessable in this repo: the menu drawing at all, the block appearing in a real
menu, either button receiving a click, whether a menu row truncates the sentence or how
VoiceOver reads it, the kickstart running, and whether
`CGPreflightScreenCaptureAccess` reads live in a long-running process. The decision
function and every sentence it produces are tested in Core; the wiring in
`MenuBarContent` is code-complete and reasoned about.

What was witnessed outside `swift test`: the TCC identity. `codesign -dv --verbose=2` was
run against `/Applications/Proctor.app` and against
`/Applications/Proctor.app/Contents/MacOS/proctor-agent`, and both report
`Identifier=app.fledgeling.procter`, `TeamIdentifier=H4HGFL52W7`. That is the premise the
whole gate rests on, and it is measured rather than assumed.

## Progress — 2026-08-15

**Status: In Review.** Branch `ai/PRO-0028`, worktree `.claude/worktrees/pro-0028`.
`swift build` clean, with exactly the three warnings that pre-exist in `ProctorUI`
(`ProctorUIApp.swift:69` twice, `Walkthrough.swift:303`) and none added. `swift test`:
**622 tests in 79 suites pass**, up from 610 in 78. The 12 new tests were run under a
filter reporting `12 tests in 1 suite`, so the count was read back rather than assumed,
and both new rules were confirmed red before green by breaking them and reading the
failures.

Files: `Sources/ProctorCore/AgentRecovery.swift` (new),
`Sources/ProctorUI/AgentModel.swift`, `Sources/ProctorUI/ProctorUIApp.swift`,
`Tests/ProctorCoreTests/AgentRecoveryTests.swift` (new), `CHANGELOG.md`.

### Child work found

- **The status window's three `Re-check` buttons carry the same limitation** the menu row
  did: none of them can clear a stale Screen Recording denial. The window has a working
  `Restart agent` beside them, so nothing is broken, but the buttons still promise a check
  that cannot reach that grant. Critic finding 8, out of scope here.
- **`AgentBuild.version` is a hardcoded `0.1.0`**, already logged by PRO-0027. It is why
  a version compare was useless for stale-build detection and why `proctor_doctor`'s
  `agentVersion` tells a reader nothing.
