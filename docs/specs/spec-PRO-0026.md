# PRO-0026: When Proctor takes the front, take it visibly and hold it

**ID:** PRO-0026
**Status:** Merged
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/27-foreground-takeover-overlay.md`
**Plan:** `docs/plans/plan-PRO-0026.md`
**Builds on:** PRO-0019 (`ForegroundDemand`, `syntheticInFlight`), PRO-0018
(`PersonInput`, the yield latch), PRO-0025 (`Sources/ProctorAgent/Overlay/`,
the one-panel-per-display rule)

## What it is

The third member of a family. PRO-0019 made a foreground run legible before it
starts; PRO-0018 made it let go when it notices somebody; this one puts the fact
on every display while it is happening, and — behind a switch that is off by
default — stops the person's input reaching the application underneath for the
moments Proctor is genuinely posting into it.

Nothing changes about which steps are synthetic, what is refused, or what a
background run does. A run that never posts an event never draws this.

## The decision the brief says decides whether this ships

**Reading 2 — swallow while the step is in flight — is what ships, and the
swallow ships OFF by default behind `PROCTOR_TAKEOVER_INPUT`.** The overlay
itself ships on.

Reading 1 (swallow nothing) is honest and does not touch the problem: the
person's click still lands in the application Proctor is driving, and the run
they were watching is still the run they corrupted. Reading 3 (a modal window
taking key focus) is disqualified by arithmetic rather than by taste — a
synthetic event goes to whatever is frontmost, so a window that takes key focus
takes the very thing the step needs, and every step after it fails. That leaves
reading 2.

**Why the swallow is off by default.** This repo has already decided the
adjacent question once, deliberately, and in writing. PRO-0018 declined to ship
even a *passive* `NSEvent` global monitor by default — "an agent that already
holds Accessibility should not quietly acquire an input-observation capability
nobody asked for" — and shipped it behind `PROCTOR_YIELD_INPUT`. A `CGEventTap`
is strictly more than that: it sits *in* the delivery path and can drop or
rewrite what it sees. Turning the stronger capability on by default while the
weaker one stays opt-in would reverse a decision this project made on the record,
in the direction of more power rather than less.

There is a second reason, and it is the sharper one: **the escalation is
invisible to the person it affects.** A tap needs the same Accessibility grant
Proctor already holds, so macOS shows no prompt, asks nothing, and records
nothing a person would see. An installed agent that can silently begin
intercepting keystrokes on its own judgement is a different product from one
that does it when an operator has said so. The operator who wants an unattended
suite to hold the machine sets one variable; everybody else gets a full-screen
statement that Proctor is driving, and their input keeps working.

So the default install gets the honest half of reading 1 with reading 2 available
in one variable, and the label never claims a block that is not armed.

## What was measured, because reasoning about `CGEventTap` is how this fails

Five probes on this machine, macOS 26.6, 2026-08-15. T1 to T3 touched only
`.mouseMoved` posted at the cursor's existing location, so nothing moved and
nothing was clicked; T5 posted one F13, which almost nothing binds.

| # | Question | Result |
|---|---|---|
| T1 | Does a session tap see events **Proctor itself** posts to `.cghidEventTap`, and does swallowing remove them? | **Yes to both.** A `.headInsertEventTap` `.defaultTap` returning nil ate our own posted event; a `.tailAppendEventTap` listener downstream saw **0**. Disabling the tap restored delivery (1), re-enabling swallowed it again. |
| T2 | Can Proctor's own event be told apart **at the tap**? | **Yes, by the two fields PRO-0018 already reads.** The event arrived carrying `eventSourceUnixProcessID = <our pid>` and `eventSourceUserData = 0x50524f43` (the probe's stand-in tag). Hardware events in the same run carried pid 0, user data 0. |
| T3 | Does a tap die with the process that created it? | **Yes, immediately, with no cleanup code.** A second process armed a swallowing tap and exited after 2s; a watcher posting one event every 350ms saw delivery, then **five consecutive zeroes** while the armer lived, then delivery resuming the instant it exited (plus the backlog of real cursor motion). |
| T4 | Does the overlay enter a capture? | **No, and it is genuinely on screen while it does not.** Against a real Ghostty window, mean per-channel levels (0-255) against a two-capture noise floor: display-scoped **0.000 → 5.979** with the panels at `.readOnly` and **0.116** at `.none`; window-scoped **0.002 → 0.010** and **0.004**. The A/B on one property is what makes it decisive — the tint presents (six levels on a display capture against a floor of nothing), `sharingType = .none` is what excludes it from one, and a **window-scoped capture of the application under test is unchanged either way**, at the level of a terminal's own cursor blink. |
| T5 | Do keyboard events reach a session tap in this process at all? | **Yes, carrying the same two fields.** A posted F13 arrived at a listen-only tap as `(key 105, our pid, our tag)`. T1 to T3 all used the mouse, so without this the keyboard half of the mask would be an assumption. What no probe here shows is a **hardware** key being swallowed — that needs a hand at the keyboard, and it is stated as unverified rather than implied. |

T1 is the measurement that changes the design: **an unconditional swallow-all
tap would eat Proctor's own synthetic events and break every foreground step it
was drawn for.** The pass-through discriminator is load-bearing, not a nicety,
and T2 says the two fields PRO-0018 already reads are the ones to read here
too. They are read the other way round, and that is the subject of the next
section.

T3 is the whole of the second invariant. The block cannot survive the process
because the tap is a Mach port this process owns; when the port dies the window
server drops the tap. That is a structural property, not a promise, and it is
now measured rather than assumed. What T3 does **not** cover is a block left
armed inside a process that is still alive — a task that threw between arming
and releasing — which is what A7's deadline exists for.

## The two invariants, and what enforces each

**Stop must always work.** Four routes, and they do not share a failure:

1. **Between steps.** The block is armed only while a step is genuinely in
   flight and released the moment it settles, and between steps the run panel is
   accepting clicks again (`ignoresMouseEvents` follows `syntheticInFlight`, and
   it always has). A batch of clicks has a gap between every pair of them.
2. **During a step, from inside the tap.** Escape is read by the tap callback
   itself and calls `RunControl.stop()`. The block is the thing that hears it,
   so a step long enough to matter — a `dragPath` may run 30 seconds — is
   stoppable throughout it, which it is not at HEAD. The overlay's label says so
   in words.
3. **The menu bar.** Pause, Resume and Stop are in Proctor's own menu bar and
   reach the same latch through `proctor_hud`. Proctor's own windows are already
   exempt from being read as contention (PRO-0018's `proctorPids`), and the
   overlay is click-through, so it never stands between a person and that menu.
4. **With the block off** — the default — nothing about Stop changes at all.

**The block must never survive the process.** T3 is the structure. Two more,
because a structure that only holds when the process dies says nothing about a
process that lives:

- **A deadline on the tap's own thread.** The tap runs its run loop on a
  dedicated thread, not on main, and that thread holds a disarm deadline
  independent of whoever armed it. A run that throws, hangs, or forgets releases
  the block on the deadline anyway. The deadline is the step's own bound (a
  `dragPath`'s `durationMs`, or the settle timeout) plus slack, under a hard
  ceiling.
- **Fail open, everywhere.** Every failure mode of this feature releases input:
  a tap that cannot be created, a tap macOS disables for being slow, a deadline
  reached, a run ending, a Stop, a yield. There is no path in which not knowing
  what is happening leaves input held.

## The interaction with PRO-0018, stated rather than left to cancel out

The brief is right that this breaks `userInput`. Measured at T1: a swallowing
tap at the head of the session removes the event, so anything downstream —
including `NSEvent.addGlobalMonitorForEvents`, which PRO-0018's optional monitor
uses — never sees it. While the block is armed, `userInput` cannot fire the way
it did.

**So the tap becomes the signal instead of destroying it.** A person's event
that the tap swallows is handed to `ContentionMonitor` as one timestamp, exactly
as the optional monitor would have handed it over, and PRO-0018 yields on the
next checkpoint with `.userInput` unchanged. The consequence is the behaviour
this feature ought to have: **the person's first keystroke is eaten so it cannot
corrupt the step, and it is also what makes Proctor let go** — the run yields,
the overlay comes down, the block releases, and their second keystroke lands.
The block is momentary by construction, not because somebody chose a duration.

Three specifics, so this does not quietly change PRO-0018's contract:

- **No `NSEvent` monitor is installed.** PRO-0018's A9 — "with
  `PROCTOR_YIELD_INPUT` unset, no monitor is installed, on any code path" — is
  untouched. The source here is the tap the operator turned on with a different
  variable, and it feeds the yield without `PROCTOR_YIELD_INPUT` because an
  operator who has enabled interception has already granted strictly more than
  observation, and silently discarding a person's attempt to take their machine
  back would be the worse of the two failures.
- **`PROCTOR_YIELD=0` still switches yielding off entirely**, block or no block.
  The block then swallows without yielding, which is the state that operator
  asked for.
- **What is read, and what is not.** The callback reads two source fields and,
  for a key event, one keycode compared against Escape. No character, no
  modifier, no location, no history: there is no field on the block that could
  reconstruct anything anybody typed, which is a property of the code, in the
  same terms PRO-0018 used.

## Two predicates that point opposite ways, and must not be collapsed

PRO-0018 asks "should this event **hold the run**?" and answers conservatively:
only an event that came from the hardware — `sourcePid == 0`, not our tag, not
inside the grace window — is a person. Its header explains at length why the
mirror image of that rule is a trap.

This asks a different question — "should this event **reach the application**?"
— and conservative points the other way. Pass only what Proctor demonstrably
posted; hold everything else. The two rules look like inversions of one another
and are not: each fails toward safety, and safety is in opposite directions
because the consequences are. Getting `isAPerson` backwards makes Proctor hold
itself forever; getting the block's rule backwards makes it hold nothing at all.

Two things fall out of that, and both were the out-of-family gate's findings
rather than this spec's first draft:

- **The 250ms grace window has no place in the block.** It exists so an
  application's echo of Proctor's own click cannot read as a person. Used as a
  *pass* rule it would open the gate to real hardware input for a quarter of a
  second after every post — which, on steps that are mostly shorter than that,
  is most of the time the block is meant to be closed. A block that is open
  whenever Proctor has just acted is not a block.
- **`sourcePid != 0` has no place in it either.** A Mac with Karabiner,
  BetterTouchTool or a vendor mouse driver delivers the person's own keystrokes
  carrying *that* process's pid, so a rule that passes anything with a pid on it
  passes exactly the input it was built to hold. The strict rule also treats an
  assistive input device the same as a hand: held while a step runs, and its
  Escape stops the run, rather than passed through into the application where it
  would corrupt the run and where Escape would do nothing.



**A1 — The overlay is up for exactly as long as the machine is being held.** It
goes up when the first step that travels the event stream is about to run, stays
up for the rest of the batch rather than strobing between steps, and comes down
when the run ends however it ended. A batch with no synthetic step never draws
it, and neither does one whose `foreground: true` was inert (PRO-0025's A1).

**A2 — One panel per display, never one spanning them.** The measurement in
`CursorOverlay.swift`'s header applies to this surface unchanged: panels are
built per `NSScreen`, and no panel's frame is ever the union of two screens.

**A3 — The overlay does not contaminate a capture.** Every panel sets
`sharingType = .none`, and captures are window-scoped to the application under
test. Proved by measurement, not by argument (T4): a window-scoped capture taken
with the overlay up is compared against one taken without, **and the same run
proves the overlay was genuinely on screen at the time**, by flipping the one
property under test — a comparison that passes because nothing was drawn proves
nothing, and the window list cannot tell those apart.

**A4 — The block is off unless an operator asked for it, and says so when it is
not there.** With `PROCTOR_TAKEOVER_INPUT` unset, no `CGEventTap` is created on
any code path. When it is set and the tap cannot be created — the grant that
gates a keyboard tap is not the one Proctor already holds — the run proceeds
unblocked, the label does not claim a hold, and `proctor_doctor` reports both
the switch and the live Input Monitoring state read through `IOHIDCheckAccess`,
which asks nobody for anything. `PROCTOR_TAKEOVER=0` switches the overlay off
too, in the shape `PROCTOR_CURSOR` and `PROCTOR_HUD` already have.

**A5 — Only Proctor's own events pass, and they always do.** The pass rule is
`userData == ProctorEventTag.value || sourcePid == our pid`, and nothing else:
everything the tap sees that Proctor did not post is held. This is the deliberate
**mirror** of PRO-0018's `isAPerson`, and the two must not be collapsed —
see "Two predicates that point opposite ways" below. Proctor's own posted Escape
passes as an ordinary keystroke and never stops the run.

**A5b — The panic chords always pass, and two of them also stop the run.**
Cmd-Tab, Cmd-Shift-Tab, Cmd-Opt-Esc, Ctrl-Cmd-Q and the screenshot chords are
never swallowed, whoever sent them, and `systemDefined` events — media,
brightness, power — are not in the mask at all. **Force Quit and lock-the-screen
also end the run**, because somebody pressing either means "make this stop", and
because locking the screen raises Secure Event Input, which releases the block:
an agent that carried on posting into a locked session with the hold gone is the
worst end state this feature has.

**A5c — A pair is swallowed as a pair.** An up is swallowed only when its own
down was, and a dragged only while its button's down was; `flagsChanged` is not
in the mask at all. Arming mid-chord or mid-drag therefore cannot leave the
application holding a modifier or a mouse button nobody is pressing — a state
that outlives the block, the run and the process, and is worse than the race it
was closing.

**A6 — Stop always works, and the block is one of its routes rather than a wall
in front of them.** Escape reaching an armed tap stops the run and is swallowed
rather than also reaching the application. A person's click that the block
swallows yields the run (A8), which ends the hold and makes the run panel
clickable again, so a click on Stop lands on the second press rather than the
first — stated in those words rather than as "Stop always works instantly",
because a `.defaultTap` sits ahead of window-server dispatch and the first click
genuinely does not reach the panel. The label claims a hold only while one is
actually armed.

**A7 — The block cannot outlive the step, the run, or the process.** Arming
carries a deadline; a run-loop timer on the tap's own thread disarms at the
deadline whatever happened to the run that armed it, and never on the arrival of
an event, because a block with no events arriving is exactly the block nobody is
releasing. The same timer re-reads Secure Event Input and releases if it turned
on mid-step. The run's end disarms it; a tap macOS disables is re-enabled once
and then released. Nested arming is balanced, and an unbalanced release still
lets go.

**A8 — A swallowed event is not a discarded one.** While the block is armed, a
person's event feeds `ContentionMonitor`, so the run yields with `.userInput` at
the next checkpoint and the block and the overlay come down with the hold.

**A9 — The overlay never takes a click, hides a control, or appears in a tree.**
Every panel is `ignoresMouseEvents`, non-activating, and never calls
`activate(_:)`; its level is derived from the run panel's, below it, so Pause and
Stop stay visible above the tint. It is not an accessibility element, so it
cannot answer a hit test. It is rebuilt when the displays change, so a screen
attached mid-run is covered and a detached one leaves nothing behind.

**A10 — Reduce Motion and Reduce Transparency both apply.** Reduce Motion drops
the appearance and disappearance fades; Reduce Transparency gives the label an
opaque plate rather than making the whole screen opaque, because a person
watching Proctor drive their Mac must still be able to see what it is doing.

**A11 — The run says afterwards that the machine was held.** `ActResult` gains a
`takeover` block — shown, blocked, `blockedMs`, `swallowed`, `releasedBy` — nil
when nothing was drawn, so every existing result is byte-identical, with one
sentence alongside it in the shape `yieldNote` and `foregroundNote` already
have. Flow replay reports the same block.

**A12 — A drawing fault does not kill the agent.** Every draw goes inside
`ProctorCatchNSException`, and a panel that cannot be built is reported the way
the run panel's absence is, not thrown.

## Design

**Core holds the decisions; the agent holds AppKit and the port.** The split is
PRO-0018's, for the same reason: the interesting half is then testable without a
window server.

`Sources/ProctorCore/Takeover.swift`:

```swift
enum TakeoverPolicy {
    static func shows(demand: ForegroundDemand, sawSynthetic: Bool) -> Bool
    static func label(app: String?, blocking: Bool) -> TakeoverLabel   // title + line
    static func tint(reduceTransparency: Bool) -> TakeoverTint         // alpha, plate
    static func deadline(stepDurationMs: Int?, settleTimeoutMs: Int, now: Double) -> Double
    static let ceilingSeconds: Double = 35     // above any single step's own bound
}
enum InputBlock {
    enum Decision { case pass, swallow, stopRun }
    static func decide(kind: EventKind, sourcePid: Int64?, userData: Int64?,
                       sinceSyntheticPost: Double?, keyCode: Int64?) -> Decision
}
struct TakeoverReport: Codable { ... }        // A11
```

`Sources/ProctorAgent/Overlay/TakeoverOverlay.swift` owns one `NSPanel` per
screen and the tap. The panels carry the run panel's own settings with two
differences: the level is `statusBar - 1`, stated as a relationship to
`RunHUDPanel`'s level rather than as a second magic number, and
`ignoresMouseEvents` is unconditionally true — the run panel toggles it, and this
surface has nothing to click.

The tap is created on a dedicated thread with its own run loop, for a reason
that is not stylistic: `options: .defaultTap` requires the callback to answer
promptly or macOS disables the tap, and the agent's main thread is where the
panels draw and where AppKit work already queues. A tap serviced behind a draw
pass would be disabled by timeout at exactly the moment it was holding somebody's
keyboard. The same thread carries the deadline.

The mask is what it needs and no more: `keyDown`, `keyUp`, the three mouse
buttons' down/up/dragged, and `scrollWheel`. Three deliberate absences:

- **`flagsChanged`.** Swallowing half a modifier pair leaves the application
  holding a Shift or a Command nobody is pressing, and that state outlives the
  block, the run and the process. A modifier on its own actuates nothing, so
  there is nothing to gain against it.
- **`mouseMoved`.** Proctor warps the cursor itself, a hand brushing a trackpad
  is not somebody taking the machine back, and a pointer that stops moving reads
  as a hung Mac rather than as a held one.
- **`systemDefined`.** Media, brightness and power keys are how somebody makes a
  machine stop doing something, and Proctor never stands between them and that.

Within the mask, an up is swallowed only when its own down was swallowed, and a
dragged only while its button's down was — `InputBlock` carries the set of
swallowed keycodes and buttons so that arming mid-gesture cannot strip the end
off a gesture that started before the block existed. And the panic chords pass
whoever sent them: Cmd-Tab, Cmd-Shift-Tab, Cmd-Opt-Esc, Ctrl-Cmd-Q and
Cmd-Shift-3/4/5, listed as data in Core so the list is testable rather than
buried in a callback.

Wiring, in `runSteps`, beside the calls already there: the overlay is raised
where `hud(.stepApproaching)` fires for the first synthetic step and lowered
beside `restCursor()`; the block is armed immediately before `noteSyntheticPost()`
and released in a `defer` around the `perform`, which is the same window
`syntheticInFlight` covers and which PRO-0019 already established opens before
the first post and stays open past a multi-event gesture.

**Nothing in the tap callback may wait on anything.** It writes lock-protected
counters and calls two closures that do the same — `RunControl.stop()` and the
contention monitor's timestamp — and never hops to the main actor, never joins
its own thread, and never exits the process. The deadline is a run-loop timer on
that thread rather than a check inside the callback, because a block nobody is
sending events into is exactly the block that needs releasing.

## Assumptions recorded in place of questions

- **A-i. The overlay is per batch and the block is per step.** A full-screen
  tint flashing on and off between ten clicks is strobing, and strobing is worse
  than the thing it is announcing; a block held across the gaps between steps is
  more of somebody's machine taken than the problem needs. So the statement is
  steady and the interception is minimal. The cost is stated rather than hidden:
  a click landing in the gap between two steps still reaches the application, and
  that case is PRO-0018's, not this one's.
- **A-ii. Escape is the release chord.** While the block is armed every key is
  being swallowed, so no chord costs the application anything, which leaves
  memorability as the only criterion. A run stopped by somebody's reflexive
  Escape is the cheap direction of being wrong.
- **A-iii. The block is partial, and that is also a safety property.** A session
  tap does not reach Secure Event Input's keyboard, and this one deliberately
  passes the panic chords and never masks `systemDefined` or multi-touch
  gestures — a three-finger swipe to another Space still works. Proctor
  therefore cannot lock anybody out of their Mac even if every other guard here
  fails, and the label says "held", never that the machine is locked.
- **A-iv. Secure Event Input arms nothing, and un-arms what is armed.** A
  synthetic step under secure input is already refused before it runs
  (`Session.refusal`), so the block does not arm there; and the tap thread
  re-reads it while armed, so secure input turning on mid-step releases the
  block rather than leaving a tap between somebody and a password field.
- **A-ix. The overlay cannot absorb the person's clicks, and that is arithmetic
  rather than a preference.** The obvious way to close the mouse half of the
  race without a tap is to let the tint take the click. It cannot: a synthetic
  click is delivered to whatever window is topmost at that point, so a
  full-screen panel that accepts mouse events eats **Proctor's own** clicks and
  every foreground step fails. PRO-0015 found the same shape from the other
  direction, which is why the run panel goes click-through for exactly as long
  as a synthetic step is in flight. So the default install gets a statement
  rather than a guard, and the label says which of the two it is.
- **A-x. An unmatched up may reach the application after the block lets go.**
  The pair rule stops a swallowed up from stranding an unswallowed down; the
  reverse — a down Proctor swallowed whose up arrives after the tap is disabled
  — leaves an application receiving an up for something it never saw pressed.
  Applications ignore that; the opposite would not be ignored, which is why the
  rule is this way round.
- **A-v. The label names the application under test.** It is the one thing on
  screen that says which of somebody's windows this is about, and PRO-0014's
  object fencing already governs how an application's own name is rendered.
- **A-vi. `takeover` is a new optional block, not a change to
  `ForegroundReport`.** `ForegroundReport.measured` counts planes and is what
  "this run took the foreground" means; adding a held-input field to it would
  change what an existing field measures.
- **A-vii. The pointer overlay is left alone.** PRO-0025's dimmed fallback draws
  at `.screenSaver`, above this tint. Harmless, and moving it would be a change
  to a feature that just landed for reasons that have nothing to do with this
  one.
- **A-viii. The macOS floor stays 14** and nothing here uses a newer API.

## Out of scope

- Blocking input outside a foreground step, or any always-on interception. The
  block exists for the seconds Proctor genuinely holds the machine.
- Changing which steps are synthetic, what is refused, or the HUD's design,
  which is settled and binding (`mocks/run-hud.html`).
- Making the block complete. See A-iii; a complete block is a lock-out, and this
  is not that.

## What a `swift test` cannot witness here

- **The tap swallowing anything**, and Escape arriving in it. Covered by T1 and
  T3 above and by unit tests of the decision, and named as a code reading beyond
  that.
- **Any panel presenting**, the tint, the label, the fades, and the level
  ordering as pixels. The values are tested; the drawing is not.
- **The capture comparison**, which is why A3 is a measurement rather than a
  test.

## Triage review

Out-of-family gate: **grok-4.6, `xhigh`, read-only**, 2026-08-15, evidence
inlined (Codex is off for this repo). Twelve findings; **six changed the
design**, and two of those were defects that would have shipped.

| # | Finding | Disposition |
|---|---|---|
| 2 | The pass rule does not mean "us, not the human": `pid != 0` passes Karabiner and every remapper — i.e. the person's own keystrokes — and the 250ms grace passes real hardware around every post | **Accepted; the design changed.** A5 and "Two predicates that point opposite ways". The first draft would have shipped a block that was open for most of the time it claimed to be closed. |
| 1 | Swallowing `flagsChanged`, or an up whose down was not swallowed, leaves a stuck modifier or a stuck drag that outlives the block, the run and the process | **Accepted; the design changed.** A5c: `flagsChanged` leaves the mask and a pair is swallowed as a pair. This is the one finding that made the feature actively worse than not having it. |
| 4 | The panic chords are in the swallow mask, so somebody can be 35 seconds without app switch, force quit or lock on a machine clicking by itself | **Accepted.** A5b, with the list held as data in Core. |
| 5 | A keyboard tap is gated on Input Monitoring, a third TCC grant, so `tapCreate` can return nil and the label would claim a hold that does not exist | **Accepted.** A4: the failure is reported rather than silent, `proctor_doctor` reads the live state through `IOHIDCheckAccess`, and the label never claims an unarmed block. Which service gates this tap on macOS 26 is **not verified here** and the report names it rather than asserting it. |
| 3 | In-step Stop is not Stop: a `.defaultTap` sits ahead of window-server dispatch, so a click on the panel never reaches it while armed | **Accepted as a correction to the wording.** A6 now says what actually happens — the first click yields, which ends the hold and makes the panel clickable, so Stop lands on the second. Its second half (Proctor's own posted Escape stopping the run) is answered by A5's ordering: ours passes before any chord test, and a test pins it. |
| 6 | Secure Event Input is only checked at arm | **Accepted as a cheap belt.** A7: the tap thread's existing timer re-reads it. Its premise may be false — secure input exists to stop taps seeing keystrokes — but the check costs one read every 250ms and is correct whichever way that goes. |
| 9 | The overlay is missing AX-hiding and display-change rebuilding | **Accepted.** A9. The others it lists (`orderFrontRegardless`, `canJoinAllSpaces`, `fullScreenAuxiliary`, `hidesOnDeactivate`) were already in the design. |
| 11 | A tap macOS disabled should fail the step, not carry on under a lying overlay | **Half accepted.** The lie is fixed — the label stops claiming and the release reason is recorded. The step is not failed: losing a guard returns the run to exactly what HEAD does, and failing a step because a safety extra died would be a regression dressed as caution. |
| 8, 12 | The default install is a placebo; ship a click-absorbing overlay instead, and an env var is the wrong knob | **Rejected on evidence, and it is the sharpest exchange here.** A click-absorbing full-screen panel eats Proctor's *own* synthetic clicks and breaks every foreground step (A-ix). The placebo objection is answered where it is true — the label now says plainly that input still reaches the application when nothing is held. The env var is every switch this repo has (`PROCTOR_CURSOR`, `PROCTOR_HUD`, `PROCTOR_YIELD`, `PROCTOR_YIELD_INPUT`); inventing a second configuration mechanism for one feature is child work, recorded below. |
| 7 | A tap-thread deadlock breaks both invariants without the process dying; the deadline must be a run-loop timer, not an on-event check | **Accepted as a constraint on the build**, and it was already the design: the timer is a run-loop timer, and the callback now carries an explicit rule that nothing in it may wait on anything. |
| 10 | The mask is keyboard and mouse buttons, not "human control": gestures, tablet, `systemDefined` are open | **Accepted as a stated limit** (A-iii), and part of it is deliberate: never masking `systemDefined` is what keeps the power and brightness keys out of Proctor's reach. |

## Child work found

- **A settings surface for the five `PROCTOR_*` switches.** The gate's point that
  an environment variable leaks to children and vanishes from a launchd plist is
  true of all five, not of this one, and belongs to whichever change gives them a
  home.
- **The tap could route a person's click on Stop directly**, rather than the
  two-press path A6 describes, by hit-testing the run panel's frame inside the
  callback. Real, and it couples the block to the panel's layout, which is a
  design decision rather than an oversight.

## Completeness critic

**Lane failure, logged.** grok-4.6 was called twice at `xhigh`, read-only, with
the built design inlined at 45 lines and again compacted to 30, and returned
**empty both times** (the process exited having written nothing). Per the repo's
rule that an empty response is a lane failure rather than a pass, the gate ran
**in family on `claude-fable-5`**, from an empty directory so the CLAUDE.md chain
did not load ahead of the prompt. That is Claude reviewing Claude and is carried
here as a known weakness in the evidence; the triage gate before it **did** run
out of family and is the stronger of the two.

Fifteen findings. **Five changed the code**, all at `ebd6e39`.

| # | Finding | Disposition |
|---|---|---|
| 3 | The panic chords pass but do not stop the run. Ctrl-Cmd-Q locks the screen, secure input comes up, the block releases, and the agent goes on posting into a locked session with the hold gone | **Accepted; the worst one.** Force Quit and lock now return `passAndStop`: delivered *and* the run ends. Pinned by `forceQuitAndLockAlsoStop`. |
| 7 | A deadline or secure-input release happens on the tap's thread and the label does not follow, so the overlay claims a hold that ended | **Accepted.** `onReleased` moves the label from that thread. This was a real defect: the two releases that happen without the caller knowing were the two that left the claim standing. |
| 14 | The label strobes: the block arms and releases per posting moment, so a line that says "held" only while armed flickers several times a second, and a message that flickers is one people learn to ignore | **Accepted.** The line is now worded for the batch — "held while it acts" — which is true either way and never changes mid-run. |
| 11 | A VoiceOver user gets nothing: the overlay is deliberately not an accessibility element and says everything visually, so with the block on they meet a dead keyboard with no account of why or how to escape | **Accepted.** The raise posts an `announcementRequested` carrying both lines. |
| 5 | The keyboard half is unverified: T1 to T3 all used the mouse | **Accepted as a gap in the evidence, and closed as far as it can be.** T5 shows keyboard events reaching a session tap in this process carrying our pid and tag. A hardware key being swallowed still needs a hand at the keyboard and is stated as unverified rather than implied. |
| 1 | Exact-modifier matching will swallow the panic chords, because `CGEventFlags` carries device-dependent left/right bits, non-coalesced and Caps/Fn | **Rejected on the code, and it is a good finding against a plausible build.** The agent reduces the flags to four semantic bits (`maskCommand`, `maskAlternate`, `maskControl`, `maskShift`) before any comparison, so Caps Lock, Fn and a keyboard's own device bits cannot reach the match. The reason is now written where the mapping is, because a chord that failed on somebody else's keyboard would be the safety mechanism failing silently, per-machine, after passing every test here. |
| 12 | A throwing post between arm and release strands the block | **Rejected on evidence.** The release is a `defer` inside the `do` block, and `aThrownStepStillLetsGo` fails if it is moved. |
| 15 | The health report should also carry Accessibility trust and live secure input | **Rejected: both are already on `proctor_doctor`**, in the grants list and in `secureEventInputActive`. |
| 6 | A mid-batch display change can drop the overlay while the tap stays armed | **Rejected on the code.** The screen-parameter handler re-asserts the raise, so a hotplugged display is covered rather than leaving input held with no banner. |
| 2 | A person's click on Stop is swallowed while the block is armed | **Accepted as already stated, and its fix is harder than the finding suggests.** A6 says what happens: the first click yields, which ends the hold and makes the panel clickable, so Stop lands on the second. Hit-testing the panel's frame in the callback would not be enough on its own, because the run panel is deliberately click-through for exactly as long as a synthetic step is in flight (PRO-0015), so the passed click would fall through to the application anyway. Both halves would have to move together. Child work. |
| 4, 13 | Multi-touch gestures and `mouseMoved` are not held, so a three-finger swipe changes Space mid-step and the cursor moves under the person's hand | **Accepted as stated limits** (A-iii). Not masking `mouseMoved` is deliberate: Proctor warps the cursor itself, and a pointer that stops moving reads as a hung Mac rather than a held one. |
| 8 | Keyboard holding is structurally impossible under Secure Event Input, and the 250ms poll leaves up to a quarter second of believing otherwise | **Accepted as a stated limit.** The block never arms under secure input in the first place (the step is refused), and the poll covers it turning on mid-step. The quarter second is real and is recorded rather than smoothed. |
| 9 | Passing `flagsChanged` means a resting Command can turn agent typing into destructive shortcuts in an application that reads global modifier state | **Accepted as a stated limit, and it is not a regression** — it is equally true at HEAD with no block at all. The alternative is stuck modifiers, which outlive the process. |
| 10 | The overlay signals mechanism rather than consequence: an all-accessibility run can delete a file through `AXPress` in silence | **Out of scope by the brief**, which scopes this to the seconds Proctor genuinely holds the machine. A real question about what the run panel should say, and recorded as child work rather than answered here. |
| — | A tap disabled mid-drag leaves a dangling down once the up passes | **Accepted as a stated limit.** The pair rule cannot help once the tap is gone. |

## Progress

**Branch** `ai/pro-0026` · **worktree** `.worktrees/PRO-0026` · commits `5dfe3f9`
(implementation) and `ebd6e39` (critic fixes). Ready to merge; not merged, not
rebased, not pushed.

**Gate.** `swift build` clean, no new warnings. `swift test`: **653 tests / 81
suites**, from 610 / 78 at HEAD. Runtime smoke on a scratch socket
(`PROCTOR_SOCKET=/tmp/pro26run/agent.sock`, the reader's installed agent
untouched): the agent starts under the new code, listens, and `proctor_doctor`
answers `ready: true` with both grants and the new block —
`overlay: true, inputBlockRequested: true, inputBlockAvailable: true,
inputMonitoring: "granted"` with `PROCTOR_TAKEOVER_INPUT=1`, and
`inputBlockRequested: false` with it unset.

| Clause | Proved by |
|---|---|
| A1 up for exactly as long as the machine is held | `certainAnnounces`, `conditionalWaitsForTheMeasurement`, `accessibilityDrawsNothing`, `inertRequestDrawsNothing`, `raisedOncePerBatch`, `raisedAtTheRightStep`, `accessibilityRunIsUntouched` |
| A2 one panel per display | the surfaces are built from `NSScreen.screens` individually; not machine-witnessable, see below |
| A3 no contamination | **T4**, a measurement rather than a test |
| A4 off unless asked for, and says so | `switchesDefaultOppositeWays`, `doctorSeparatesTheTwo` |
| A5 only ours passes | `ourOwnEventsAlwaysPass` (exhaustive over every kind), `ourEscapeIsJustAKeystroke`, `eitherFieldIsEnough`, `aProcessIsNotAPass`, `hardwareIsHeld`, `theTwoPredicatesAreMirrors` |
| A5b the panic chords | `panicChordsPass`, `chordsAreExact`, `forceQuitAndLockAlsoStop` |
| A5c a pair is swallowed as a pair | `armingMidGestureDoesNotStrandADown`, `aWholeGestureIsHeld`, `trackingIsPerKeyAndPerButton`, `modifiersPass`, `resetIsComplete` |
| A6 Stop always works | `escapeStopsAndIsSwallowed`, `deliveryAndStoppingAreSeparate`, `boundToThisRun`, `labelNeverOverclaims` |
| A7 cannot outlive the step, run or process | `armingIsBalanced`, `aThrownStepStillLetsGo`, `armingCarriesTheDeadline`, `armingIsBounded`, `aStoppedRunLetsGo`; **T3** for the process |
| A8 a swallowed event is not a discarded one | `swallowedInputYields`, `boundToThisRun` |
| A9 never takes a click or hides a control | `belowTheRunPanel`, `neverTakesAClickOrAFrame` |
| A10 Reduce Motion and Reduce Transparency | `accessibilitySettingsApply` |
| A11 the run says so afterwards | `theRunSaysSo`, `silenceWhenNothingWasTaken`, `silenceWhenNothingHappened`, `shownButNotHeld`, `heldSaysSo`, `reportEncodes` |
| A12 a drawing fault does not kill the agent | the draw is inside `ProctorCatchNSException`; the barrier itself is PRO-0022's and is tested there |

**Code-complete and not machine-witnessable here.** `swift test` has no window
server and no event tap, so none of these is proved by the suite: any panel
presenting, the tint, the label, the fades, the accessibility announcement, the
level ordering as pixels, the tap swallowing a hardware event, Escape arriving in
one, and the deadline firing on a real run loop. T1 to T5 cover the tap's
mechanics and T4 covers the capture clause; the rest is a code reading and is
named as one.

**Child work found.**

- **A settings surface for the five `PROCTOR_*` switches.** The gate's point that
  an environment variable leaks to children and vanishes from a launchd plist is
  true of all of them, not of this one.
- **A person's click on Stop landing on the first press rather than the second.**
  It needs the tap to hit-test the run panel's frame *and* PRO-0015's
  click-through rule to change together; either alone does nothing.
- **The overlay says mechanism, not consequence.** An accessibility-plane run can
  be just as destructive and draws nothing. That is the brief's scope, and it is
  a real question about what the run panel should say.
- **`scroll` and `type` limitations inherited from PRO-0025** are unchanged and
  untouched here.
