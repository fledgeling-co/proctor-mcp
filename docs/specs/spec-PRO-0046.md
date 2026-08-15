# PRO-0046: Supervision survives delegation

**ID:** PRO-0046
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/47-supervision-survives-delegation.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` — wins over any earlier spec
**Evidence:** `docs/research/2026-08-15-dossier-proctor-vs-cua.md`
**Builds on:** PRO-0044 (the actuation seam, `.routedEvent`, `unrequestedForeground`,
the no-op verdict), PRO-0053 (a run joins the declaration protocol only when it can
post), PRO-0033 (the mouse gate, the declaration choke point, the Stop rectangle),
PRO-0018 (`PersonInput`, `ContentionWatch`, the yield latch), PRO-0019 (`ForegroundDemand`,
the panel's one exception row), PRO-0025 (the in-plane pointer, `PROCTOR_CURSOR`),
PRO-0026 (`InputBlock`, the tap, the takeover statement), PRO-0014 (a step description
is derived, never supplied)
**Depended on by:** PRO-0051 (which decides the native planes' fate, and inherits the
capability regressions recorded here as evidence)

## Feature description

<!-- Verbatim from docs/features-to-triage/47-supervision-survives-delegation.md -->

# Supervision survives delegation

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

The reader's instruction was explicit: the overlay, the character, the menu bar app and
the run surface should keep working, with Cua underneath. None of that is automatic.
Four features were built on the assumption that Proctor posts the events.

- **Stop.** PRO-0033 gets a person's click to Stop on the first press, and the event
  tap passes only what Proctor itself posted. A delegated step is posted by another
  process, so that rule no longer identifies the same events, and the exception that
  keeps Stop clickable may now be letting Cua's synthetic clicks through, or swallowing
  the person's.
- **Yield.** PRO-0018 holds a run when a person takes the machine back, and its whole
  correctness rests on telling Proctor's own events from a person's. Same problem,
  same root.
- **The foreground disclosure.** PRO-0019 computes whether a batch needs the front, and
  PRO-0025 prefers the background route. Cua makes that decision itself now, and
  reports its own delivery mode.
- **The pointer overlay.** PRO-0025 draws the pointer in the target window's plane.
  Cua draws its own agent cursor. Two cursors on one screen is worse than either.

## What it should do

Make one supervised run surface that tells the truth about a run it did not actuate.

## The hard parts, named

- **Two cursors is the visible half and the easy half.** Decide which one draws, and if
  it is Cua's, say what happens to `PROCTOR_CURSOR` and to the character.
- **Event discrimination is the hard half.** Whatever replaces "only what Proctor
  posted" has to be at least as safe, and the failure directions are asymmetric: a
  swallowed click costs a repeated gesture, a wrongly-forwarded one corrupts the run
  somebody reached over to supervise. When in doubt, swallow.
- **The HUD's step text is derived, never supplied.** PRO-0014 settled that a step
  description comes from the step kind plus the accessibility label, and that a
  caller-supplied label is untrusted, sanitised and fenced. A description that now
  passes through Cua does not get a free pass on that.
- **Reduce Motion and Reduce Transparency still apply**, and the panel is still one per
  screen, never one spanning the union of the displays.

---

## What it is

The supervision surface, made true about a run Proctor did not actuate. Nothing here
adds a capability and nothing here changes what a step does. What changes is which
events the guards recognise, which of two pointers draws, and what the panel says about
a lane where Proctor is no longer the thing posting.

The native lane is untouched. Every rule below is either unchanged or gains one term
that reads `native` today, so an existing run behaves byte-identically and the whole
existing suite passes with no edit — the same proof shape PRO-0044 used, for the same
reason.

## Four defects found in the code, before any of this was designed

Each is reachable today on a branch where PRO-0044 has merged. Three are not what the
brief predicted and one is worse than the brief predicted.

**1. A delegated click can press Stop.** `InputBlock.Gate.decide` tests the run panel's
Stop rectangle for any event that fails `isOurs`, suppressed only while Proctor has a
post in flight. `isOurs` is Proctor's own tag or Proctor's own pid, so a driver's event
fails it; and nothing declares on a delegated step, so the suppression never engages. The
mouse-up therefore returns `.stopRun`. Reachable whenever a step's target lies under the
panel: `stepsAside` holds there — every Cua kind reports `BackgroundCapability.maybe`, so
`mayPost` is true for all of them — which raises the takeover statement, which is the
guard `takeoverArm` waits on.

**2. An armed block eats the driver's events, and the two runs genuinely overlap.**
`RunQueuePlan.grantable` grants an entry whose own lanes are disjoint from what is busy,
and `.global` is a lane rather than a barrier against app lanes. A native
`foreground: true` run holds `{.app(X), .global}`; a delegated `foreground: false` run
holds `{.app(Y)}`; disjoint, so both start. `InputBlocker.shared` is process-wide, so the
native run's armed tap sees the delegated run's driver events, fails `isOurs` on them, and
swallows them — and hands each one to `onPersonInput`, which is what makes the yield fire
on a run's own actuation. The delegated step does nothing and the run reports somebody
using a machine nobody touched.

**3. The grace window never opens for a delegated step.** `noteSyntheticPost()` is called
from `runSteps` only when `synthetic || stepsAside`, and `synthetic` is
`capability == .never`, which no Cua kind is. §2 explains why the obvious fix for this is
withdrawn and what replaces it.

**4. Both pointers draw.** `showCursor(for:window:)` runs on every step whatever the
backend, and the driver draws its own agent cursor.

A fifth is not a defect but looks like one: a delegated `foreground: true` batch currently
satisfies `participates` — `demand.mightPost && foreground`, and every Cua kind counts as
conditional — so it installs the declaration handler and drives `beginStep()`/`endStep()`
while never declaring, because `SyntheticPost.declare()` is reached only from
`Actuator.requireEventPlaneAvailable()`. It is harmless rather than wrong: such a batch
holds the exclusive `.global` lane, so there is no concurrent poster whose state it could
clear, which is exactly the invariant PRO-0053 established. It is meaningless, and §2 (d)
makes it say so.

## The four hard parts, answered

### 1. Two cursors: Proctor's draws, and the fallback is the one Proctor can enforce

**Decision: Proctor's pointer draws, and the driver's own cursor is requested off on every
delegated call. If the installed driver has no such control, Proctor's pointer stands down
for the delegated lane and the run says so.**

That shape rather than a flat pick, because Proctor can only *certainly* control one of
the two. "Never two cursors" is not achievable by choosing the driver's — Proctor would be
relying on a request to another process to suppress its own drawing, and an unhonoured
request leaves two on screen. It is achievable by being willing to switch Proctor's own
off, which Proctor can do with certainty. So the preference and the guarantee are separate
things: the preference is Proctor's pointer, the guarantee is that exactly one draws.

Proctor's is preferred on three grounds that are properties of the code rather than taste.
It is drawn in the target window's own z-order, so a window stacked above the target
occludes it (PRO-0025's M1–M3). It is excluded from evidence — the invariant in
`CursorOverlay`'s header — where another process's window is not something Proctor can
exclude from anything. And it is the one `PROCTOR_CURSOR=0` switches off.

Its one weakness, stated rather than hidden: Proctor's pointer draws **intent**. The point
comes from Proctor's own tree through `cursorTarget(for:)`, and the driver may strike its
own element's centre. PRO-0044's agreement check bounds the disagreement — both observers
must describe the same element with frames overlapping by more than half — so the drawn
point is within half a frame of the struck one rather than free. A bound, not an equality,
and the run record carries the backend so a reader knows which they are looking at.

**`PROCTOR_CURSOR` keeps exactly its current meaning and gains no new reach.**
`PROCTOR_CURSOR=0` still means Proctor draws no pointer anywhere and costs nothing —
PRO-0025's A10, including every window-list read. It does **not** silence the driver's
cursor, because it never could, and `proctor_doctor` says so in as many words rather than
letting an operator infer that setting it left nothing on screen.

**The character is untouched, and this is worth writing down so nobody wires the two
together.** It is a seven-state sprite in the panel's 38pt bay carrying tone and never
information the text does not also carry (`docs/design/run-hud-character.md`). Its
`Travelling` state is about the run's phase — Proctor is getting ready to act — not about
a pointer being on screen. So it means the same thing whether Proctor's pointer draws,
stands down, or is switched off, and it needs no new state. Any future state must still be
readable from its screen glyph alone at 38px, which is that document's standing rule and
is not reopened here.

### 2. Event discrimination: one identity, corroborated, counted, and fail-open

The existing code asks three different questions of an event and they fail safe in
different directions. Collapsing them is what PRO-0026's gate caught the first draft of
*that* spec doing, and delegation is not a reason to repeat it.

**The failure directions, restated for this lane.** A swallowed click costs a repeated
gesture. A wrongly-forwarded one corrupts the run somebody reached over to supervise. And
a third, which the brief does not name because it is Proctor's own worst case rather than
the person's: an event of Proctor's own making read as a person's holds the run to its
backstop, which PRO-0018 measured at 902 seconds across four suites. So: when in doubt
about *delivering*, swallow; when in doubt about *holding the run*, do not hold.

**(a) `PersonInput.isAPerson` is unchanged, and that is the answer rather than an
omission.** Its positive case is already "came from the hardware" — `sourcePid == 0` — so
a driver's event, carrying that driver's pid, is not a person. The rule that had to be
replaced turns out to be a rule about *passing*, and the *holding* rule was written the
safe way round in the first place. A test pins it, because the property is now load-bearing
for a second reason and an inversion would be silent.

**(b) The obvious fix for defect 3 is withdrawn, and the reason is the sharper half of
this section.** The first draft opened the 250ms grace window around every delegated step,
as insurance in case the driver's events arrive looking like hardware. The out-of-family
gate killed it on two counts and both hold:

- **It does not insure against the threat it names.** If the driver posted with `pid 0`,
  the grace window stops the *yield* firing — but the pass rule still swallows those
  events, because passing `pid 0` would pass all hardware. The step becomes a silent no-op
  with the one signal that would have explained it switched off. The insurance makes the
  failure quieter, not rarer.
- **The stamp is process-global.** `ContentionMonitor` is a singleton and
  `lastSyntheticPostAt` is one field, so a delegated batch of fast steps would hold the
  window open continuously and blind a *concurrent native run's* input signal. That is a
  cross-run clobber of exactly the class PRO-0053 fixed, reintroduced in a different
  costume.

What actually covers defect 3 is (c): the driver's events must be recognised at the tap,
and a swallow of a delegated actuation must never be reported as person input. Time is not
an identity, and this spec stops treating it as one.

**(c) `InputBlock.isOurs` admits one further identity: the driver's own pid, corroborated,
honoured only while a delegated actuation is outstanding, and reference-counted.** This is
the one widening, and defect 2 is why it is not optional.

*One pid, not a class.* PRO-0026's gate rejected `sourcePid != 0` as a pass rule because a
Mac running Karabiner delivers the person's own keystrokes carrying Karabiner's pid. That
hole stays closed: a remapper's pid is not the driver's pid, and `sourcePid != 0` is never
a pass.

*Corroborated, not taken on trust.* The gate asked for the pid to come from an XPC peer
audit token rather than from a value the driver reports. There is no such token here — the
transport is a long-lived endpoint client or a CLI spawn, not XPC, and PRO-0044 §3 records
that the process which actually posts may be the driver's app bundle rather than the
endpoint Proctor spoke to. What *is* available is corroboration: the pid is the driver's
own claim, and Proctor checks that the process bearing it is the same signed identity the
lane already verified at preflight (PRO-0044 A7). A pid that does not corroborate is
treated as unknown. That is weaker than an audit token and stronger than a number, and it
is named as which.

*Bounded by a window that closes on a trailing grace, not on the call's return.* The gate's
second D1 finding is real: a driver's `mouseDown` can land while the call is open and its
`mouseUp` arrive after the call returns, so a window ending at the RPC boundary strips the
end off a gesture and leaves the application holding a button nobody is pressing — the
state PRO-0026's A5c pair rule exists to prevent, which "outlives the block, the run and
the process". So the window closes one `PersonInput.graceSeconds` after the call returns.

*Counted, because two delegated runs overlap.* Both hold only an app lane, so the
scheduler runs them together. The keeper is a count of outstanding delegated calls and the
set of driver pids they are delegating to, not a boolean and not one pid.

**(d) With the driver unrecognised, the lane serialises and holds nothing.** The first draft
had the block *release* while an unrecognised delegated actuation was outstanding, on the
grounds that arming is a process-wide count and a delegated run which merely declined to
arm changes nothing when a native run armed the tap first. That premise is right and the
remedy was wrong: releasing a process-wide hold because *this* run cannot identify *its*
driver lifts the hold a **concurrent native run** put in place, so the person's input
reaches the application that run is driving. It is PRO-0053's cross-run clear wearing a
different costume, which is precisely what the plan gate caught.

So the overlap is made impossible instead of arbitrated. **A delegated batch whose driver
Proctor cannot recognise takes the exclusive `.global` lane**, exactly as a posting native
batch does. A run holding that lane cannot overlap a native posting run — the only kind
that arms the block — so there is no hold to lift, and the batch simply does not arm one
of its own. Nothing suspends anything, and the counter that would have tracked it does not
exist.

The cost is real and is the honest one: an operator whose driver cannot be identified gets
a lane that serialises against every run needing the front, and `proctor_doctor` says so
with the reason. A slower lane that holds nothing is a better trade than a hold that
either eats the driver's own events or drops a neighbour's.

It also disposes of the Stop rectangle in that branch without a second mechanism: an
unarmed block means the gate does not run, so the rectangle is never consulted and an
unidentified driver event cannot press Stop. The person keeps Escape, the menu bar, and
the gaps between steps.

**(e) The widened identity is read by both readers, not just the tap.** The gate's D3
finding, and it would have shipped: `RunHUDContentView.mouseDown`/`mouseUp`/`mouseDragged`
refuse to actuate a control by testing `InputBlock.isOurs` — PRO-0033's A11. Widen only
the tap and a *passed* driver click reaches the Stop `NSButton` and presses it in AppKit,
which is defect 1 arriving by a different road. Both readers take the same predicate. A
driver click that lands on the panel then actuates nothing, which is PRO-0033's stated safe
direction: a step that does nothing rather than a control that is pressed.

**(f) A delegated run does not join the declaration protocol at all.** `participates` gains
one term — the run joins only when **Proctor itself** may post, which is the native
backend. That is PRO-0053's rule at its actual width: the predicate was `demand.mightPost
&& foreground` because those were the runs that could post, and a delegated run cannot. The
per-run half (`declared`, `declaredThisStep`, the handler) and the machine-wide half
(`declaredAt`, `inFlight`) are both left alone, so nothing a delegated run does can clear a
concurrent native poster's state. PRO-0053's four tests stay green unmodified.

The gate proposed the opposite — declare on the delegated lane too, with a reference count,
so the Stop rectangle is suppressed structurally rather than by identity. It is a coherent
design and it is **not taken**, for a reason the gate could not see: `inFlight` is bounded
to 250ms *from the declaration*, and a delegated post happens at an unknown moment inside
an RPC, so the window cannot be placed where the post is. A window covering the whole call
instead would leave the Stop rectangle unreadable for the length of every delegated step —
the defect PRO-0033's completeness gate found and bounded for the native lane. An identity,
corroborated, is placeable where a time window is not.

### 3. The HUD's step text: derived already, and kept that way on purpose

The panel's live line is `StepDescription.line(for:node:outcome:)` in every case and its
object comes from Proctor's own resolved node, so nothing a driver returns reaches it
today. The work is to make that a clause with a test behind it rather than a property
nobody is watching, and to close the one place a driver's prose does reach a person.

**Where it reaches.** `CuaActuationBackend.perform` puts `reply.message` — the driver's own
writing — into `AgentError.message`, which becomes `StepResult.error` in the tool result
and the `reason` on the audit row. PRO-0044 dropped every driver string from `laneHealth`
for exactly this reason and did not apply the same rule one function away.

**What is done about it.** Any driver-supplied string reaching a surface a person reads is
fenced: collapsed to a single line, stripped of control characters and markup, attributed
to the driver rather than presented as Proctor's own words, and capped. Not through
`StepDescription.sanitised`'s 48-character cut, which exists for a line designed never to
ellipse and would destroy a diagnostic; the cap here is a diagnostic length. The audit
row's half belongs to PRO-0045 and is recorded as child work rather than reached into from
here.

**What does not change.** The verb still comes from the step kind and the object from
Proctor's own tree. A driver can supply neither, and a step performed on the delegated lane
produces the same line it would have produced on the native one.

### 4. Reduce Motion, Reduce Transparency, and one panel per screen

Unchanged, restated so a change here cannot pass unnoticed, and pinned by tests that
already exist. `Takeover.surface(reduceTransparency:reduceMotion:hudLevel:)` decides the
tint's alpha, whether the label sits on an opaque plate, and whether appearing and
disappearing are animated; none of that has anything to do with which process posted, and
none of it moves. Panels are built per `NSScreen` and no panel's frame is ever the union of
two screens. The measurement behind that rule — a union-sized backing store the window
server accepts, reports `onscreen=1, alpha=1`, and never presents — is in `CursorOverlay`'s
header and is not re-derived.

## The foreground disclosure, and the one thing that genuinely regresses

PRO-0044 already made the *finished* run honest: `ForegroundReport.unrequestedForeground`
counts escalations, `unproven` counts unknown planes, and `note` leads with the escalation
sentence. What is missing is the live surfaces, and one of them cannot be fixed.

**The panel says which lane it is, on the row it already has.** PRO-0019's A-iii is
explicit that the exception is one row with one wording function and several phrasings, and
that is not reopened: the delegated fact becomes a phrasing, not a second row, not a chip,
and not a new colour. A delegated batch reads as one that *may* need the front — every kind
on that lane is conditional — and the lane is named in the same sentence.

**The menu bar states it too**, in the `foreground` block `proctor_recent_activity` already
returns, so the fact does not depend on which display the panel landed on.

**What regresses, and it is a real regression rather than a corner case.** Proctor's
foreground guards arm *before* a post, from inside the process making it. A delegated post
is made by another process, so on a step that escalates to the front without being asked,
the statement goes up **after** the machine was taken rather than before it. The late path
already works — a measured `.syntheticEvent` raises the statement, notes the front and arms
the contention watch — so the run is supervised from the step after the first one. Nothing
available from outside another process closes that gap, so it is stated on the panel, in
the run's note, and here, and PRO-0051 inherits it beside the off-Space regression PRO-0044
recorded.

**The block follows the statement on that lane.** Once an escalation has been seen, the
block arms for the remaining steps of the batch rather than for the ones predicted to post,
because a delegated batch predicts nothing. That holds input across steps that turn out to
resolve on the accessibility plane, which is more of somebody's machine held than the
native lane takes — bounded by `Takeover.armSeconds` per arming, released per step, and
stated rather than smoothed.

## Acceptance clauses

**A1 — The native lane is untouched and provably so.** With the native backend selected,
every rule here evaluates exactly as it does at the branch point: the declaration protocol,
the pass rule, the Stop rectangle, the grace window, the pointer, the panel's wording and
the block's arming. The whole existing agent and core suite passes with **no edit to any
test**, PRO-0053's four tests and PRO-0033's clause tests included.

**A2 — A delegated run does not touch the declaration keeper.** `participates` is false for
a delegated backend whatever the batch's kinds and flag, so such a run never installs the
handler, never calls `beginStep()`/`endStep()`, and never sets `takeoverShown` from
`declaredThisStep`. A concurrent native poster's `declared` and `declaredAt` survive a whole
delegated batch running beside it.

**A3 — A driver's event never presses Stop, by either road.** With the driver recognised,
its event is passed before the tap consults the Stop rectangle **and** the panel itself
refuses to actuate a control on it, so a passed click cannot press the button in AppKit.
With the driver unrecognised, no block is armed on that lane, the gate does not run, and
the rectangle is never consulted.

**A4 — A person's click still reaches Stop, and a person's input is still heard.** With the
block armed on a delegated lane, a hardware click on the published Stop rectangle ends the
run on the first press, decided on the up from a record made at the down, forwarded
nowhere — PRO-0033's A8 and A8b, unchanged. A hardware event is still handed to the
contention monitor. Escape still stops an armed run from inside the tap, and the panic
chords still pass whoever sent them.

**A5 — The driver's own events never hold the run.** An event carrying a driver's pid is
not a person, and a delegated batch of ten steps against an application Proctor raised
yields zero times. A swallow of an event belonging to an outstanding delegated actuation is
never reported to the contention monitor as person input.

**A6 — The widening is one pid, corroborated, counted, and bounded on both sides.** The
pass rule admits the pid the delegating driver reported for itself **only** when the
process bearing it corroborates as the signed identity the lane verified at preflight;
never `0` and never Proctor's own, either of which would turn the rule into "everything is
ours"; only while a delegated actuation is outstanding; and for one
`PersonInput.graceSeconds` after the call returns, so a gesture's trailing event is not
stripped. Two concurrent delegated runs sharing one driver are retained per pid rather than
racing one lapse. A different process's pid, the same pid outside the window, and an event
with no source are all held exactly as today.

**A7 — With the driver unrecognised, the lane serialises and arms nothing.** Such a batch
takes the exclusive `.global` lane, so it cannot overlap the only kind of run that arms the
block, and it arms none itself. No hold belonging to another run is ever lifted on its
behalf. `proctor_doctor` states that the block does not operate on that lane, that the lane
serialises, and why; the takeover label uses the unblocked wording rather than claiming a
hold.

**A7b — Nothing a delegated run does releases a hold another run is keeping.** The
process-wide arm count is only ever decremented by the run that incremented it. A delegated
batch running beside a native one leaves the native run's hold, its declaration state and
its disclosure exactly as it found them.

**A8 — Exactly one pointer draws, decided once per run.** The owner is computed at
`runBegan` from that run's own backend, so a native run and a delegated run in flight
together do not flip a single machine-wide decision between them. On a delegated lane the
driver's cursor is requested off on **every** call rather than assumed from one earlier
answer; when the installed build cannot be asked, Proctor's pointer does not draw for that
run. The result records what Proctor decided — that it drew, or that it stood down for the
driver — rather than claiming knowledge of what the driver then did.
`PROCTOR_CURSOR=0` still draws nothing anywhere and still costs nothing, and
`proctor_doctor` states plainly that it does not reach the driver's cursor.

**A9 — The character is unchanged.** Seven states, driven by the run's phase, carrying no
position and no knowledge of which backend is acting. A delegated run drives the same
states a native one does.

**A10 — No driver string reaches the panel.** The live line, the trail rows and the
takeover label are derived from the step kind and Proctor's own resolved node in every
case, including a step the driver refused. A driver message carrying newlines, markup or
four hundred characters cannot change any of the three.

**A11 — A driver string that does reach a person is fenced.** Single-lined, stripped of
control characters and markup, attributed to the driver, and capped — never presented as
Proctor's own words.

**A12 — The panel and the menu bar say the lane, on the surfaces that already exist.** One
row with a delegated phrasing — no second row, no new colour — and the same fact in the
menu bar's foreground block.

**A13 — An unrequested escalation is stated live, and its lateness is admitted.** The
statement, the front note and the contention arming all fire from the first measured
foreground path; the run's note says the machine was taken with no warning shown; and
nothing claims the statement preceded it. What *was* knowable before the run — that this
lane's steps may take the front — is on the panel from `runBegan` under A12, so the late
statement is the surprise being announced late rather than the whole disclosure arriving
late.

**A14 — Reduce Motion and Reduce Transparency still apply, and there is one panel per
screen.** Both settings decide the surface exactly as they do today, on both lanes, and no
panel's frame is ever the union of two screens.

**A15 — The whole delegated lane is exercised without the binary.** A fake transport and a
fake takeover driver drive: the pass rule with a corroborated pid, an uncorroborated one
and an absent one; the release path with a tap a *native* run armed first; the trailing
grace keeping a gesture whole; the panel refusing to actuate on a driver event; the
declaration keeper surviving a concurrent delegated run; both pointer outcomes; the fencing
of a hostile driver string; the delegated phrasing; and a late escalation raising the
statement.

## Not in scope

- **The audit trail's shape, and what a row attests to** — PRO-0045. This ships what a
  person sees and can interrupt. The fencing rule stops at the surfaces this item owns.
- **Deleting or disabling the native planes** — PRO-0051, which inherits the regressions
  recorded here.
- **`proctor_doctor`'s toolchain reporting** — PRO-0050. This names two facts it should
  carry and does not restructure the report.
- **Changing which steps are synthetic, what is refused, or a step's plane.** Nothing here
  refuses anything new and no step changes plane.
- **Moving Stop off the panel.** The out-of-family gate proposed a status-item or a key
  equivalent so a driven click and a human abort are never the same rectangle. The HUD's
  design is settled and binding (`mocks/run-hud.html`), Stop is in the panel by PRO-0015's
  decision, and the menu bar is already the second route. Recorded, not adopted.
- **A settings surface for the `PROCTOR_*` switches.** Still somebody else's item, and now
  carrying one more switch's worth of reason to exist.

## Known limits, stated rather than hidden

- **A swallowed driver post is not always loud.** PRO-0044's A13 fails a step when the
  driver reports `suspected_noop` *and* Proctor's own post-state hash is unchanged. A
  driver whose event was swallowed but which reports `confirmed` or `unverifiable` produces
  a step that reads as a success with an unchanged hash, and PRO-0044's asymmetry
  deliberately does not fail that. The pass rule is what keeps it from happening; there is
  no second detector behind it.
- **The block holds a person's input machine-wide while any run has it armed**, including
  input aimed at an application no run is driving. That is PRO-0026's design rather than
  something delegation introduced — it is equally true of a native posting run beside a
  native background one — and delegation makes it reachable more often, because a delegated
  run takes only an app lane and so overlaps far more.
- **A person using a remapper is held rather than heard.** Their keystrokes carry the
  remapper's pid, so they are neither ours nor hardware: swallowed by the block, and not a
  reason to yield. Escape and the panic chords still pass whoever sent them, so the run is
  still stoppable. Pre-existing (PRO-0026's A-iii and PRO-0018's own limit), unchanged here,
  and written down so it is not re-found as new.
- **Corroboration is not attestation, and the pass rule is not a security boundary.**
  Checking that the process bearing the reported pid is the signed identity the lane
  verified is a check on a process, not a proof that an event came from it. The source pid
  is system-set on the ordinary posting path — measured in PRO-0018 and again as PRO-0026's
  T2, where Proctor's own posts carried Proctor's pid and hardware carried 0 — but a
  process that builds its own event can write that field, and a pid reused between the check
  and the event would also pass. Neither matters to the threat this feature addresses: a
  program able to forge the field is already a program able to post events into the
  application directly, and PRO-0026's A-iii already states that the block is partial and
  cannot lock anybody out of their Mac. The hold protects a run from a person, and is not
  presented as protecting the machine from a program.

## Child work found

- **The driver's prose reaches the audit row's `reason` field.** The fencing above covers
  the surfaces a person reads; the trail is PRO-0045's and should apply the same rule rather
  than inherit an unfenced string. Named here because the two halves were found together.
- **A hold still cannot be attributed to a run in the queue.** PRO-0018 recorded this;
  delegation sharpens it, because a native run and a delegated run in flight together are
  now the common case and the menu bar shows the highest-precedence hold across both
  without saying whose.
- **`stepsAside` raises the full-screen statement pessimistically on the delegated lane.**
  Every delegated kind is conditional, so a batch whose first target happens to sit under
  the panel raises the tint before anything has taken the front. The label is not false — it
  says Proctor is driving the application, and the unblocked line says clicks still reach it
  — but it is earlier and more frequent than on the native lane. A question about what the
  panel should say, not a defect here.
- **PRO-0018's prose contradicts its own code about a remapper.** That spec's Known limits
  say "Universal Control, a remapper, another automation tool: none carry Proctor's tag and
  some carry no pid, so they hold the run." `PersonInput.isAPerson` requires
  `sourcePid == 0`, so an injector carrying a pid does **not** hold the run. The code is the
  safe direction and the prose is wrong. Found by this item's assumptions gate, which read
  the prose and concluded the rule had been reversed; recorded so the next reader does not
  reach the same conclusion, and left to whoever edits that spec next.
- **Standing down can mean no pointer at all.** A driver that reports no cursor control and
  then draws nothing leaves the step unannotated. That is the cheaper of the two failures
  and it is the same call PRO-0025 already made when it chose to hide rather than dim an
  off-screen target: *"Hiding loses nothing: the HUD still says what is happening."* The
  result records that Proctor stood down, which is what Proctor knows, rather than claiming
  the driver drew.
- **One pointer serves two concurrent runs.** `CursorOverlay` draws one pointer and two runs
  on different applications genuinely overlap, so a second run's step moves the pointer the
  first run's step placed. That is PRO-0025's, unchanged and untouched here; delegation
  makes it reachable more often without making it worse.
- **The block's scope is the process where the run's scope is an app.** Narrowing it would
  let a person keep using an application no run is touching while another is held. It is a
  change to PRO-0026's design and to what "Proctor is holding the machine" means, so it
  belongs with that feature rather than here.

## Triage — 2026-08-15 — Ready for Implementation Plan

**Sentinel verdict:** S3. Governance-adjacent in the sharpest way available in this repo:
it changes the rule a kill switch uses to recognise an event, it widens a pass rule on an
event tap, and it decides what a person is told about a run another process is performing.
Every gap was resolvable from the direction file, the specs it builds on, a shipped
decision in this repo, or the out-of-family review, and each is recorded as an assumption
rather than asked.

### UI & logic preview

**Where it shows up:** the small panel that appears while a run is happening, the
full-screen statement that appears when a run takes the machine, the drawn pointer, and
Proctor's own menu.

**What people will see:** a run performed by the separate driver says so on the panel, in
the same one-line place a run already says it may need an application in front. Exactly one
pointer is drawn rather than two. When the driver takes an application to the front without
being asked, the statement appears — a moment later than it would have, and the run says
afterwards that it was late. When the optional hold on the keyboard and mouse cannot be
made safe on that lane, Proctor lets go of it and says so, rather than appearing to hold
something it is not holding.

**Behaviour changes:**
- Stop cannot be pressed by the driver's own clicks, on either lane and by either route.
- The driver's own clicks are no longer eaten by a hold another run put in place.
- A run performed by the driver can no longer hold itself because it mistook its own
  actions for somebody using the machine.
- The optional hold on keyboard and mouse lets go while Proctor cannot recognise the
  driver, and says which it is.
- Nothing the driver writes can change the words on the panel.

### Assumptions

- `[Experience]` **Proctor's own pointer is the one drawn**, and the driver's is asked to
  stand down (*Proctor can only switch its own off with certainty, so that is where the
  guarantee has to live*).
- `[Experience]` A driver that cannot be asked to stop drawing means Proctor stops instead
  (*two pointers is worse than either, and only one of the two is Proctor's to end*).
- `[Experience]` Which pointer draws is decided **once per run**, from that run's own lane,
  not once for the machine (*two runs on different applications genuinely happen at the same
  time, and a decision held for the machine would flip back and forth between them*).
- `[Experience]` A driver that can be asked to stand down but does not is not detectable, so
  the request rides every action rather than being assumed from one earlier answer (*asking
  once and trusting it is how two pointers appear on the tenth step*).
- `[Experience]` The pointer switch keeps its exact current meaning and gains no reach over
  the driver (*a switch that appears to do more than it does is worse than one that says
  what it does*).
- `[Experience]` The character is untouched and gains no state (*it carries tone about the
  run, never where anything is on screen*).
- `[Compliance]` The rule for whether an event should **hold the run** is unchanged: only
  something that came from the hardware counts, which the driver's own actions do not
  (*this is deliberately the opposite of the rule for whether an event reaches the
  application, and the two must not be collapsed — each fails toward safety and safety is
  in opposite directions*).
- `[Compliance]` The rule for whether an event reaches the application admits **one**
  further identity, the driver's own (*a broader rule would pass a keyboard remapper's
  events, which is precisely what it exists to hold*).
- `[Compliance]` That identity is checked against the signed program Proctor already
  verified, rather than believed because the driver said so (*a number a program reports
  about itself is a claim*).
- `[Compliance]` The check recognises the driver; it does not prove an event came from it,
  and it is not presented as a security boundary (*any program on the machine that could
  forge the marking could already act on the machine directly; the hold protects a run from
  a person, and never claimed to protect the machine from a program*).
- `[Compliance]` It is honoured only while Proctor has asked the driver to act, and for a
  fraction of a second afterwards (*ending it the instant the request returns would strip
  the end off a drag and leave an application holding a button nobody is pressing*).
- `[Compliance]` A reported identity of zero, or Proctor's own, is refused outright (*either
  would turn "recognise the driver" into "everything is ours", which is the opposite of the
  rule*).
- `[Operations]` When Proctor cannot recognise the driver, that run **waits for the whole
  machine** and holds nothing, rather than switching off a hold another run is keeping
  (*two runs share one hold; letting one run switch it off on the other's behalf is exactly
  the cross-run interference this wave has already had to fix once*).
- `[Operations]` The cost of that is a slower lane, said plainly (*a lane that serialises
  and holds nothing is a better trade than a hold that either eats the driver's own actions
  or drops a neighbour's*).
- `[Compliance]` A time window is not used as a substitute for recognising the driver (*it
  would quieten the failure rather than prevent it, and it would blind a second run
  happening at the same time*).
- `[Operations]` A run performed by the driver takes no part in the arrangement that tracks
  Proctor's own actions (*it has nothing of its own to record there, and joining would clear
  state belonging to a run that does*).
- `[Operations]` Everything shared between runs is counted rather than flagged (*two runs
  driven by the driver can happen at once, and so can one of each kind*).
- `[Experience]` **What Proctor knows before a delegated run starts is said before it
  starts**, on the panel: that the lane is the driver's and that a step on it may take the
  front. Only the full-screen statement waits (*the panel can say what the batch is; the
  statement claims something is happening now, and on this lane nothing outside the
  driver's process knows that until it has*).
- `[Experience]` The full-screen statement appears **after** the first unrequested taking
  of the machine rather than before it, **on the delegated lane only** (*on Proctor's own
  planes it still precedes the post, unchanged; on this one there are no steps knowable in
  advance to need the front, because every kind on it decides at the element*).
- `[Experience]` Once that has happened, the hold covers the rest of the batch rather than
  the steps predicted to need it (*nothing on that lane is predictable, and the safe
  direction is to hold*).
- `[Experience]` The disclosure stays one line in the place it already is (*a settled design
  that says the exception once, in words*).
- `[Data & scope]` Nothing the driver writes reaches the words on the panel, and anything of
  the driver's a person does read is marked as the driver's and cleaned up first (*text from
  another program does not belong unqualified on the surface somebody uses to stop a run*).
- `[Data & scope]` The trail's own handling of the driver's writing is left to the item that
  owns the trail (*two items editing one record is how a rule ends up applied twice and
  inconsistently*).

*If any of these are wrong, edit the answer inline (or correct an assumption) in this file
and re-run `/triage PRO-0046` before the planner picks this up.*

### Out-of-family review — grok-4.6, xhigh, read-only

Run on the three load-bearing decisions with the measured facts inlined at 42 lines. Codex
is off for this repo by instruction, so grok is the out-of-family lane. Nine findings;
**four changed the design, one of them a defect that would have shipped, and one of them
withdrew a decision entirely.**

Accepted and now in the spec:

1. **"Declining to arm does nothing — arming is process-wide."** The highest-severity
   finding. A delegated run that only declined to arm the block would still be swallowed by
   a tap a *native* run armed first, so the delegated step does nothing and the user has
   been told the tap is off. The block now **releases** while an unrecognised delegated
   actuation is outstanding. §2 (d), clause A7.
2. **"Identity in the tap cannot substitute for not delivering the click to our own
   chrome."** Right that the tap alone is not enough — `RunHUDContentView` tests `isOurs` to
   refuse actuating a control, so a *passed* driver click would press the Stop button in
   AppKit. Both readers now take the widened predicate. §2 (e), clause A3. Its stronger
   claim, that identity cannot work at all, is answered by taking both readers rather than
   one.
3. **"The grace window does not fix the threat it names, and the stamp is process-global."**
   Withdrew the decision. If the driver posted `pid 0` the pass rule still swallows, so the
   window only silences the signal that would have explained the failure; and
   `ContentionMonitor` is a singleton, so a delegated batch would blind a concurrent native
   run's input signal — the cross-run clobber class PRO-0053 fixed. §2 (b).
4. **"'Outstanding' is an RPC flag, not a HID-delivery flag."** A driver's `mouseUp`
   arriving after the call returns would be stripped, leaving an application holding a
   button nobody is pressing. The window now closes on a trailing grace. Clause A6.
5. **"Two delegated runs, one driver, one tap, one flag."** Everything shared is counted
   rather than flagged. Clause A6, and stated once in §2 (c) rather than per mechanism.

Narrowed rather than accepted whole:

- **"Take the pid from an XPC peer audit token, not from what the driver reports."** Correct
  in principle and unavailable in fact: the transport is not XPC, and PRO-0044 §3 records
  that the posting process may be the driver's app bundle rather than the endpoint Proctor
  spoke to. Answered with corroboration against the signed identity the lane already
  verified, named as weaker than an audit token and stronger than a number, with the
  residual pid-reuse window recorded under Known limits.
- **"Declare on the delegated lane with a reference count."** Coherent, and not taken:
  `inFlight` is bounded to 250ms from a declaration and a delegated post happens at an
  unknown moment inside an RPC, so the window cannot be placed where the post is; covering
  the whole call would leave the Stop rectangle unreadable for every delegated step, which
  is the defect PRO-0033's completeness gate bounded for native. Reason recorded in §2 (f).
- **"The block swallows the person's input aimed at an application no run is driving."**
  True, and pre-existing rather than introduced here — equally true of two native runs — so
  it is a stated limit plus child work against PRO-0026 rather than a change in this item.
- **"Move Stop off the overlay."** Out of scope: the HUD's design is settled and binding and
  the menu bar is already the second route. Recorded under Not in scope.

Rejected on the code:

- **"Keyboard Stop does not exist; under an armed tap the only abort is a mouse click."**
  Escape is read by the tap callback itself and calls `RunControl.stop()` —
  `InputBlock.releaseKeyCode = 53`, PRO-0026's A6 route 2 — and the overlay's label
  announces it. This is PRO-0033's finding 9b, already answered.
- **"The remapper user is locked out and the run continues."** Their input is held and does
  not yield, which is true and recorded; but Escape and the panic chords pass whoever sent
  them, so the run is stoppable throughout. Narrower than stated.
- **"A swallowed driver post still looks like a successful RPC, with no echo."** PRO-0044's
  A13 already crosses the driver's `suspected_noop` with Proctor's own unchanged state hash
  and fails the step. The residual — a swallow the driver reports as `confirmed` — is real
  and is recorded under Known limits.

No key material, gate code or audit-trail code was sent; the review was scoped to design
prose and the measured event-source facts.

### Assumptions review gate — fable-5, high effort, fresh reviewer

Run against the Assumptions block with this repo's locked decisions inlined (PRO-0023's
never-install rule, the no-silent-fallback rule, PRO-0026's off-by-default hold and its
fail-open rule, the ban on `sourcePid != 0` as a pass rule, the binding HUD design,
PRO-0014's derived descriptions, the observation-stays-home rule, PRO-0032's no-widening
rule). Three findings, none escalated to an Essential Question.

1. **"The unchanged hold rule reverses a locked decision."** **Rejected on the code**, and
   it is the best kind of wrong finding. It read `PersonInput.isAPerson` as the *pass* rule
   the lock forbids. They are two rules pointing deliberately opposite ways — PRO-0026's
   "Two predicates that point opposite ways, and must not be collapsed" — and this item
   changes the pass rule while leaving the hold rule alone. The assumption is reworded so it
   cannot be misread that way. **It also surfaced a real defect in a merged spec**: PRO-0018's
   Known-limits prose claims a remapper's events hold the run, and its own code says they do
   not. Recorded under Child work.
2. **"The late statement discards pre-run knowledge Proctor already surfaces."** **Accepted
   and narrowed.** Right about the principle — warn before where known, late only for the
   surprises — and the narrowing is that on the delegated lane there is no known-synthetic
   kind at all, because every kind there decides at the element. So the *full-screen
   statement* is genuinely late and the *panel row* is not: what Proctor knows up front is
   said from `runBegan`. Both assumptions and clause A13 now say which is which, and the
   native lane's pre-post warning is stated as unchanged.
3. **"The pid on an event is a poster-settable field; what actually attributes an event to
   the driver is an OS fact, not Proctor's choice."** **Accepted as a real limit, resolved
   rather than escalated.** The field is system-set on the ordinary posting path — measured
   twice in this repo — and writable by a process that builds its own event. That does not
   reach the threat this feature addresses: a program that could forge it could already post
   into the application directly, and PRO-0026 already states the block is partial. The
   claim is narrowed to recognition rather than attestation, and the spec says in as many
   words that the pass rule is not a security boundary.

</content>

## Plan — 2026-08-15

Implementation plan: `docs/plans/plan-PRO-0046.md` (Plan size: Standard).

The plan's out-of-family gate returned 21 findings and **six changed this spec rather than
only the plan**. The largest deleted a mechanism: the first draft had the input block
*release* while an unrecognised delegated actuation was outstanding, which lifts a hold a
concurrent native run is keeping — PRO-0053's cross-run clear in a different costume. Such a
batch now takes the exclusive `.global` lane instead, so the overlap is impossible rather
than arbitrated, and no suspend, counter or release reason exists at all (§2 (d), A7, A7b).
The others: a reported pid of `0` or Proctor's own is refused outright, the pointer owner is
decided once per run rather than once for the machine, and standing down is recorded as what
Proctor decided rather than as a claim about what the driver drew (A6, A8).

## Progress — 2026-08-15

**In Review.** Branch `ai/pro-0046`, worktree `.worktrees/PRO-0046`, commits `3fc5c8d`
(implementation) and `6b84edd` (critic fix + CHANGELOG). Not merged, not rebased, not
pushed; finalization is the orchestrator's.

**Gate:** `swift build` clean, no new warnings. `./scripts/test.sh` (never a bare
`swift test`, never piped): **1213 tests in 132 suites**, from **1162 in 128** at the
branch point. 51 tests added, 4 suites added.

### Reachability — every decision reaches a consumer

| Capability | Decision | Carried by | Consumer(s) | Wired |
|---|---|---|---|---|
| Recognise a delegated actuation | `InputBlock.isOurs(…delegated:)` `Takeover.swift:307` | `DelegatedPost.recognisedPids` `DelegatedPost.swift:104` | tap `TakeoverOverlay.swift:407`; panel `RunHUDContentView.swift:242` | ✅ |
| Open/close the recognition window | `DelegatedPost.begin/end` `:88,:101` | `StepRun` bracket | `SessionAct.swift:419` around `actuator.perform` | ✅ |
| Learn the driver's pid | `CuaPreflight` stage 6 `:174` | `CuaLaneReport.recognisedPid` `:70` | `CuaActuationBackend.actuatingPid` `:108` → `SessionAct`, `SessionQueue` | ✅ |
| Corroborate it | `CuaPreflight.liveCorroborate` `:216` | injected per backend | `CuaActuationBackend.init(corroborate:)` `:36` | ✅ |
| Serialise an unrecognised lane | `Session.delegatedLaneMustSerialise()` `SessionQueue.swift:67` | `LaneDemand.lanes` | `lanes(for:)` `:25` → `act`, flow ×2, CUA façade | ✅ |
| Suppress person-input on a delegated swallow | `DelegatedPost.outstandingCall` `:120` | — | tap `TakeoverOverlay.swift:429` | ✅ |
| Choose the pointer | `PointerOwnership.decide` `PointerOwner.swift:44` | `StepRun.pointerOwner` | `showCursor(for:window:owner:)` `SessionCursor.swift:43`; `ActResult.pointerDrawnBy` | ✅ |
| Ask the driver to stand down | `CuaRequest.suppressCursor` `CuaTransport.swift:52` | every `.act` | `CuaActuationBackend.perform` `:184` | ✅ |
| Fence the driver's prose | `StepDescription.fenced` `:238` | `AgentError.message` | `CuaActuationBackend.perform` `:193` | ✅ |
| Say the lane on the panel | `ForegroundDemand.notice(…delegated:)` `:145` | `RunHUDEvent.runBegan(delegated:)` | `RunHUDState.apply` `RunHUD.swift:322`; `hudRunBegan` | ✅ |
| Say the lane in the menu bar | — | `foregroundJSON["backend"]` `Session.swift:598` | `recentActivity()` | ✅ |
| Say it in the health report | — | `takeoverStatus()` `SessionTakeover.swift:127` | `proctor_doctor` `Dispatch.swift:395` | ✅ |

### Clause coverage

| Clause | Kind | Evidence | Status |
|---|---|---|---|
| A1 native untouched | behavioural | 1213 green; `git diff -U0 -- Tests/ \| grep -c "@Test"` = **0**; only two helper files touched | ✅ |
| A2 keeper untouched by a delegated run | behavioural | `aDelegatedRunNeverParticipates`, `aNativePostersStateSurvivesADelegatedBatch`; both red with the backend term reverted | ✅ |
| A3 driver never presses Stop | behavioural | `aRecognisedDriverPassesBeforeTheRect`, red when reverted; `withoutTheIdentityTheRunStops` pins the defect. Panel reader: **code reading** (one predicate, both call sites) | ✅ |
| A4 person still reaches Stop; chords | behavioural | `hardwareStillStopsOnTheUp`, `escapeAndChordsAreUnaffected` | ✅ |
| A5 driver's events never hold the run | behavioural | `aDriverPidIsNotAPerson`, `aDelegatedBatchYieldsZeroTimes`, `aSwallowDuringADelegatedCallIsNotPersonInput`, `theSuppressionIsNotConditionalOnRecognition` | ✅ |
| A6 one pid, corroborated, counted, bounded | behavioural | 11 tests: `twoCallsOnOnePidAreRetained`, `theWindowOutlivesTheCallByTheGrace`, `aHungCallExpiresAtTheCeiling`, `endIsIdempotent`, `zeroAndOurOwnPidAreNotRecognised`, `zeroIsNeverAdmitted`, `aRemapperPidIsStillHeld`, `onlyTheDriversPidPasses`, `aClaimedPidIsCorroboratedBeforeItIsTrusted`, `anUncorroboratedPidIsNotRecognised`, `noReportedPidIsNotARefusal` | ✅ |
| A7 unrecognised ⇒ serialise, arm nothing | behavioural | `anUnrecognisedDelegatedBatchTakesTheGlobalLane` (red when reverted), `aRecognisedDelegatedBatchDoesNotSerialise`, `theNativeLaneDemandIsUnchanged`; doctor's wording is static at `SessionTakeover.swift:145` | ✅ |
| A7b nothing releases another run's hold | static | no suspend mechanism exists; the arm count is only ever decremented by its own `defer`, `SessionAct.swift:424` | ✅ |
| A8 exactly one pointer, per run | behavioural | `pointerOwnerIsProctorWhenTheDriverCanStandDown`, `pointerOwnerDefersOtherwise`, `unknownSuppressibilityFailsClosed`, `nativeAlwaysDraws`, `absentSuppressibilityFailsClosed`, `suppressionRidesEveryAct`, `theResultSaysWhenProctorStoodDown`, `aProctorDrawnRunEncodesAsBefore` | ✅ |
| A9 character unchanged | static | `git diff` over `RunHUDCharacter.swift`, `RunHUDCharacterView.swift`, `MenuBarCharacter.swift`, `run-hud-character.md` is **empty** | ✅ |
| A10 no driver string on the panel | behavioural | `aHostileDriverMessageCannotChangeTheLine`; the three panel lines are `StepDescription.line(for:node:…)` at `RunHUD.swift:384,392` and take no driver input | ✅ |
| A11 driver prose fenced | behavioural | `driverProseIsFencedAndAttributed`, `markupAndControlCharactersDoNotSurvive`, `aDriverCannotEscapeItsQuotes`, `fencingIsCutAtADiagnosticLength`, `fencingIsGraphemeSafe`, `emptyProseFallsThrough`, `aRefusalFencesTheDriversProse` | ✅ |
| A12 lane on panel + menu bar | behavioural | `theDelegatedPhrasingIsOneRow`, `aQuietDelegatedBatchStillDiscloses`, `theNativeWordingIsUnchanged`, `theMenuBarCarriesTheBackend` | ✅ |
| A13 escalation stated live, lateness admitted | behavioural | `aLateEscalationRaisesTheStatement` (asserts the statement AND the note's "no warning shown"), `aQuietDelegatedBatchDrawsNoStatement` | ✅ |
| A14 Reduce Motion / Transparency / one panel per screen | static | `git diff -- Takeover.swift` over `surface(`, `reduceTransparency`, `reduceMotion`, `ordinaryAlpha`, `labelPlate`, `NSScreen` is **empty**; the existing `accessibilitySettingsApply` is green | ✅ |
| A15 whole lane without the binary | behavioural | every row above runs against `FakeCuaTransport`, `FakeActuationBackend` and `FakeTakeover` | ✅ |

### Regression discrimination

Four production gates were reverted one at a time and the named test confirmed red, then
restored:

| Gate reverted | Test that went red |
|---|---|
| `&& actuator.id == .native` on `participates` | `aDelegatedRunNeverParticipates`, `aNativePostersStateSurvivesADelegatedBatch` |
| the `.global` insert in `lanes(for:)` | `anUnrecognisedDelegatedBatchTakesTheGlobalLane` |
| the `delegated` membership in `isOurs` | `aRecognisedDriverPassesBeforeTheRect` |
| (the fourth is the same revert seen from the panel's side) | — |

### Implementation assumptions

- **Preflight now runs at lane selection** for a delegated backend, not at the first
  `perform`. The lane decision needs the driver's pid before the batch is queued, and
  PRO-0044 §3 says detection belongs at lane selection anyway — its implementation had
  drifted to doing it lazily. `try?`, so a driver that cannot preflight still refuses at
  the step with its own full message rather than as a scheduling error.
- **`lanes(for:)` became `async`.** Four call sites gained `await`; no behaviour changed
  for the native lane, which returns before the first suspension.
- **Corroboration asks about the running code**, via `SecCodeCopyGuestWithAttributes` with
  a pid attribute, rather than reading an executable path and checking the file. It is the
  API for that question and it answers for a plain helper as well as a bundled app.

### Two defects found by my own work, worth recording

- **A test that asserted the clock.** `aNativePostersStateSurvivesADelegatedBatch` first
  asserted `inFlight` after a multi-step batch. That window is bounded to 250ms from the
  declaration, so it was asserting that a three-step batch takes under a quarter second,
  not that nothing cleared it. Frozen clock; now it pins only the clobber.
- **A process-wide test seam, which is the defect this repo keeps meeting.** Corroboration
  was first an injectable `static var`. swift-testing parallelises across suites, so two
  tests wanting opposite answers stomped each other and the failure read as a logic error
  in whichever lost. It is now a constructor parameter, following `verifySignature`'s
  existing shape, and there is no shared mutable state left on that path.

### Out-of-family completeness critic — grok-4.6, read-only

First attempt at `xhigh` on a 41-line prompt died at the deadline having written only a
narration stub (exit 142) — the measured failure mode. Retried at `high` on 23 lines and
returned in full. Its findings, dispositioned:

**Accepted, and it was a real defect:** *"the driver's own clicks classify as human, and
then the run pauses on them."* This was **an acceptance clause of this spec that the first
pass did not implement** — A5's "a swallow of a delegated actuation's events is never
reported as person input". Without it, a driver whose events reach the tap unrecognised is
swallowed *and* handed to the contention monitor, so the run yields on its own actuation
and holds to the backstop. Fixed at `6b84edd`, pinned by two tests.

**Rejected on the code**, recorded so they are not re-found:

- *"Stop does not stop while a step is in flight; the kill switch is a drawing."* The tap
  is how a person's Stop press works: `Gate.decide` reads the published rectangle and
  returns `.stopRun` on the up, swallowing rather than forwarding. That is PRO-0033's
  design and `hardwareStillStopsOnTheUp` covers it with the delegated set populated.
- *"Stop can be queued behind the exclusive lane."* Stop is `RunControl.stop()`, a latch
  reached from the tap, the panel and the menu bar. The scheduler queues runs, not Stop.
- *"A driver could name another app's pid and make that app's input ours."* That is what
  corroboration checks: the process *bearing* the pid must be the signed driver, so naming
  another app fails and the lane serialises.
- *"Tap-ours and watch-ours were never shown to be the same predicate."* They are
  deliberately different and must not be collapsed (PRO-0026). `isAPerson` is unchanged and
  requires `sourcePid == 0`; `aDriverPidIsNotAPerson` pins it.
- *"A mixed run: the agent still posts natively during a delegated run."* The backend is
  fixed per run (PRO-0044 A2) and a delegated run never reaches `Actuator`.

**Accepted as stated limits**, now in the spec: the 250ms membership window is a real
window in which a reused pid would pass; `reply.message` is the only prose field on the
driver's wire, so prose arriving in a field this build does not read would not be fenced.

### What a `swift test` cannot witness here

Named rather than implied. `swift test` has no window server and no event tap, so none of
these is proved by the suite: a real driver event arriving at a real tap and being passed,
the panel receiving one, either pointer drawing or not drawing, and the driver honouring or
ignoring the stand-down request. The decisions, the keeper's arithmetic, the counting, the
grace, the ceiling, the ordering and the wording are all values and are tested.

And the driver is not installed — PRO-0023 forbids installing it as a side effect — so the
two new wire fields (`actuatingPid`, `cursorSuppressible`) are a documentary reading. Both
fail closed: an absent pid serialises the lane and arms nothing, an absent suppressibility
flag stands Proctor's pointer down. Being wrong costs a stated capability loss rather than
a guard that silently is not there.

### Dropped or changed vs spec/plan

- **The block's suspend/resume mechanism was designed and then deleted**, before it was
  built, by the plan gate. The spec and plan both record why: suspending a process-wide
  hold on one run's behalf lifts a guard a concurrent run is keeping. Replaced by the
  exclusive lane. Nothing else in the spec or plan was dropped or narrowed.

### Child work found

Recorded in the spec's `Child work found` section: the driver's prose still reaches the
audit row's `reason` unfenced (PRO-0045's to apply the same rule); PRO-0018's Known-limits
prose contradicts its own code about a remapper; `stepsAside` raises the full-screen
statement pessimistically on this lane; and the block's scope is the process where a run's
scope is an app.
