# PRO-0037: A hold names whose run it is

**ID:** PRO-0037
**Status:** Triaged
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/38-a-hold-names-whose-run-it-is.md`
**Builds on:** PRO-0016 (the three lanes, `RunScheduler`, derived session identity), PRO-0018 (the yield, `ContentionWatch`, `RunControl`'s attributed latch), PRO-0015 (the panel and its queue bar)

## Feature description

PRO-0018 taught Proctor to hold a run when a person takes the machine back, and
logged what it could not say. With two runs in flight against different
applications, the menu bar shows the highest-precedence hold across all of them
and does not say whose it is. The queue bar has the rows; nothing joins the two.

A person seeing a hold indicator therefore knows something is held and not what,
which on a machine running one session is enough and on a machine running three
is the wrong half of the information.

A second gap sits next to it, from PRO-0016: `proctor_apps.activate` brings an
app to the front and takes no lane, because that spec scoped queueing to a batch,
a replay and a sweep. So a call that genuinely takes the foreground is invisible
to the thing that accounts for who has the foreground.

**What it should do.** Attribute a hold to the session and the display it belongs
to, and account for `activate` in the lane model that already exists for every
other way of taking the front.

## What is actually true at HEAD, measured before designing

Four readings of the built code. The first three are why the design below is not
the design the brief implies; the fourth is the one the out-of-family gate found.

**1. Two runs that can *yield* cannot overlap.** Arming requires
`demand.takesForeground` or a step whose measured plane was `.syntheticEvent`.
`takesForeground` is `mightPost || raises`, and the actuator refuses the
synthetic fallback outright when `foreground` is false — so a step can only
report `.syntheticEvent` from a batch that already had `takesForeground`. And
`LaneDemand.forBatch` takes the exclusive `.global` lane on exactly that
predicate. **Armed implies the global lane**, and the global lane is one at a
time anywhere on the machine. So there is never a second live reading.

**2. A run that cannot yield is parked anyway, silently.** `RunControl.shared` is
one latch for the whole process, and `look()` reads `paused` for **every** run in
flight — including an accessibility-plane run on a different app in a different
session that samples nothing and can never yield. That run parks at its next
checkpoint, gets no `RunHUDEvent`, records no `YieldRecord`, and tells its caller
nothing. It just stops for up to the fifteen-minute backstop. PRO-0018's A1
("an accessibility-plane run … can never yield") is true of *sampling* and was
read as though it were true of *being parked*.

**3. Nothing that reads a hold can name it.** `Session.yieldJSON` folds every
run's open reason into one highest-precedence string and drops the run.
`RunTicketInfo` — the scheduler's per-run value the panel and the health report
already read — carries identity, lanes, summary and arrival time, and no hold.

**4. Any run starting wipes the latch.** `hudRunControlBegin()` calls
`RunControl.begin()` at each of the four entry points, and `begin()` clears
`yieldReason`, `pausedByPerson`, `stopped`, `pausedAt` and `yieldHeldTotal`
unconditionally. `RunScheduler.acquire` never consults the latch, so a run
against a free app lane starts *while another run is yielded* and clears its
hold. The yielded run's next `look()` sees nothing and posts into the person it
had just got out of the way of. A person's own Pause and Stop go the same way.
Found by the spec-review gate; see Gates.

Together 2 and 4 are the reason this cannot ship as pure naming. Attribution that
a third run silently erases is not attribution.

## The decision the brief asks for: what each surface is responsible for

A menu bar item is one glyph and cannot carry a name, so nothing here tries to
make it. The responsibilities split by what each surface can physically say:

| surface | carries | does not carry |
|---|---|---|
| **Menu bar icon** | precedence, as one glyph. `MenuBarIcon.decide`'s ladder is untouched and unreordered. | any name |
| **Menu bar / status-window text** (`proctor_recent_activity`'s `yield` block) | the reason, the session, the app and the display, in words | anything about runs the hold does not reach |
| **Panel live line** | the reason, in PRO-0018's settled vocabulary, unchanged | whose — one line at one size, and it is already full |
| **Panel queue bar** | whose: the held run's session and app on the bar, and a mark on that run's row | the reason a second time |
| **`proctor_doctor`** | the whole join, per active run, machine-readable | — |
| **`ActResult.yields`** | what held *this* run, unchanged in shape | somebody else's hold — because it no longer reaches this run |

The panel's live line is deliberately not touched. It is one line at one size in a
settled mock, it already says the thing a person reads first, and the surface with
room for a name is the queue bar directly beneath it.

## One latch, one clock, one backstop — and the yield gains an owner

PRO-0018 settled one flag, one clock, one backstop (A-ii: a second yield flag
beside the first is a second way to strand a run). **That decision stands and is
not reversed.** What changes is not the latch's shape but *who reads its automatic
cause*:

- **`pausedByPerson` parks every run.** A person pressed Pause; that is a decision
  about the machine, and it is what the panel's one pair of buttons means.
- **`yieldReason` parks only the run that read it.** The reading is about one
  event stream and one expected pid — an accessibility press into Slack is not
  fighting somebody who cmd-tabbed away from Safari.
- **Still one clock and one backstop.** Finding 1 proves at most one run can be
  yielded at any instant, so `pausedAt`, `yieldHeldTotal` and the fifteen-minute
  bound stay exactly as they are. The only new field is *which run owns the
  yield*, which is a key, not a second mechanism.

An unarmed run therefore does not park, records nothing, and tells its caller
nothing — because nothing happened to it. That is a better outcome than the
record the brief's framing would have bought: a run parked for fifteen minutes
cannot deliver a record anyway, because the host cut the call off fourteen
minutes earlier.

### The three write-path defects the gate found, and what closes each

1. **`begin()` erases another run's hold** (finding 4). `begin(run:)` now clears
   the yield **only when this run owns it**. A new run beginning is a statement
   about itself. The person's own flags keep their settled behaviour — PRO-0015
   fixed Pause and Stop to the live line and a new run is a new live line — and
   that pre-existing sharpness is recorded as child work rather than widened here.
2. **The backstop stops every run and blames a person.** `look()` sets the global
   `stopped` when the bound expires, so a *sibling's* next look returns `.stopped`
   and its caller is told "a person stopped this run from Proctor's run HUD" — a
   halt nobody chose, attributed to somebody who was not there. An expired **yield**
   now expires the run that owned it, through a per-run expiry rather than the
   global stop flag. An expired **person's pause** still stops everything, because
   a person's pause held everything.
3. **Stop leaves the published hold behind.** The panel writes `RunControl.shared`
   directly and never hops to the scheduler, so a Stop during a yield would leave
   `RunTicketInfo.held` set on a ticket about to be released. The unhold is
   published from the run's own unwind — `disarmContention(run:)`, which already
   exists and already closes the open hold record — so every path that ends a
   hold (release, person's Resume, Stop, backstop, run end) publishes exactly
   once, within one 60ms poll of the decision.

## Where the join lives, and the line it has to hold

`Session` is a **reentrant** actor: isolation drops at every settle and every
capture `await`, which is why PRO-0016 put the lanes in `RunScheduler`, an actor
of its own, outside the actor's turn-taking. Anything joining hold state to queue
state has to hold that same line.

The join is therefore **published into the keeper** and never read across from the
actor at draw time:

- `RunTicketInfo` gains `held: HoldAttribution?`, set on the ticket of the run
  that is actually held.
- `Session.contentionProbe` — the one place contention policy lives — calls
  `runScheduler.hold(run:_:)` when it yields and `unhold(run:)` when it releases,
  the same two moments it already moves the latch; `disarmContention` publishes
  the unhold for the ending paths.
- No surface enters `Session` to learn about a hold. The panel, the menu bar
  mirror and the health report read the scheduler snapshot they already read.

**The scheduler's copy is a copy, and the latch remains the truth.** Pause and
Stop are synchronous main-thread writes onto `RunControl.shared` for a reason: a
`Task { await scheduler.hold(…) }` from a button is late by at least one poll. So
the scheduler is the read surface and the latch is the decision, and the invariant
that keeps them from diverging is that every path clearing the latch's yield also
publishes an unhold — which is what defect 3 above closes and what A2's tests pin.

A run's ticket id reaches the probe by task-local — `RunScheduler.$currentRun`,
set in `Session.scheduled` beside the `holdingLanes` flag already there.
Task-locals travel with the task rather than with the actor, which is exactly why
`SessionIdentity.current` already works through the same reentrancy. The ticket id
is the key rather than the session label, because one client can have an armed run
and an accessibility run in flight at the same time.

## Session identity, restated because it is load-bearing

Derived from the peer process, never client-supplied, and never per-connection.
`MCPServer.callAgent` opens a new socket per tool call, so a per-connection id
would rotate every call; identity keys on `pid:startTime` and the four-hex
`connection` is display only. A hold names a session using
`RunSessionIdentity.label` — the value the scheduler already holds — and nothing
in this feature accepts a name from a client. A connection that could name itself
could impersonate another one in the very UI a person uses to decide whether to
stop it.

## The display, derived rather than asked for

A run drives a window; a `WindowHandle` carries its `frame`. Which display that is
belongs to `RunHUDPlacement.screenIndex(for:in:)`, which already answers "which
screen holds most of this rect", already falls back to the nearest for a window on
a display that has been unplugged, and is already tested with no display attached.
Reusing it means there is no second table of what a display is. Screens come from
`CGDisplayBounds` over `CGGetActiveDisplayList`, which the session already reads
for its display resource and which is not main-actor bound.

The name is plain and derived: `the main display`, or `display 2`. No product name
is read — none is available from CoreGraphics without a main-actor hop, and a
display's marketing name is not what somebody needs in a one-line hold.

## `activate` takes the lanes it changes

`proctor_apps.activate` brings an application to the front and, when it is not
running, launches it. That is `raise` in every way that matters to the scheduler,
and PRO-0016 gives `raise` the global lane because raising changes where
everybody else's clicks land.

- **The global lane, always.** It changes what is in front.
- **The app lane, when the target already resolves to an attached handle** — keyed
  on the same `AppHandle.id` a batch uses, from the handle the policy gate already
  resolves. An unattached process is not keyless but *differently* keyed
  (`app:<pid>:0` from a listing versus `app:<pid>:<epoch>` from an attach), and a
  key from the wrong space would look like contention accounting while never
  contending. A batch can only drive an attached app, so the case that can contend
  is the case that gets the key.
- **After the policy gate, before the activation**, matching `Session.scheduled` at
  the other four entry points. A refused activation never takes a place in the line.

**A stated limit, accepted from the gate.** The lane set is fixed before the call
starts and never added to — PRO-0016's rule, because acquiring lanes one at a time
is how two runs wedge each other. So an attach that happens *while* an `activate`
waits is invisible to it, and that `activate` holds only the global lane. What is
left uncovered is narrow: a background accessibility batch against an app that
became attached during the wait. The global lane it does hold still excludes every
synthetic run on the machine, which is the half that moves the ground under other
people's clicks.

**What a caller sees, because this is a behaviour change.** `activate` never waited
before and now can. It waits the way every other queued call waits — held open
until its turn, up to `PROCTOR_QUEUE_WAIT_LIMIT` (45s default) — and can now come
back with `queueBusy` (the machine was busy; nothing was activated; safe to send
again) or `haltedByPerson` (a person dropped it from the queue). Nothing is
activated on either path, which is what makes the retry advice true. The tool
description says so, because a call whose timing changed silently is how an
existing driver starts looking for a fault in an app.

## Acceptance clauses

**A1 — a hold names its session, its app and its display, all derived.**
`HoldAttribution` carries the reason, the session label from `RunSessionIdentity`,
the app under test, and the display the driven window sits on, chosen by
`RunHUDPlacement.screenIndex`. Nothing in it is client-supplied. *Test:
attribution built from a window frame and a screen list picks the display holding
most of the window, falls back to the nearest for a window off every screen, names
the main display as such, and survives an empty screen list.*

**A2 — the join is published into the keeper, and never diverges from the latch.**
`RunTicketInfo.held` is set by `RunScheduler.hold(run:_:)` on the owning ticket
and cleared by `unhold(run:)`; every path that clears the latch's yield —
release, a person's Resume, Stop, the backstop, the run ending — publishes exactly
one unhold. *Test: hold then snapshot; unhold clears it; a hold on one ticket
leaves other tickets alone; a released ticket carries none; and each of the five
ending paths leaves no ticket held.*

**A3 — a yield parks the run that read it, and only that one.**
`pausedByPerson` parks every run; `yieldReason` parks its owner. An
accessibility-plane run on another app in another session runs to completion while
another run is yielded, and reports nothing, because nothing happened to it.
*Test: two runs, one yielded — the other's checkpoint returns nil throughout; a
person's Pause parks both; the yielded run still parks.*

**A4 — a run beginning does not erase another run's hold.** `begin(run:)` clears
the yield only when this run owns it. *Test: run A yields, run B begins, A is
still held with its reason and its clock; B is not held.*

**A5 — the backstop expires the run it was holding, and blames the right thing.**
An expired yield gives up that run alone, through a per-run expiry rather than the
global stop flag, so a sibling is never told a person stopped it. An expired
person's pause still stops everything. *Test: a yield with a millisecond bound
expires its owner and leaves a sibling running; the sibling never sees `.stopped`;
a person's expired pause still reaches every run.*

**A6 — the queue bar says whose, in the settled row shape.** `RunQueueModel` gains
the hold and each `Row` a `held` flag. The bar's label becomes the hold sentence
while a hold is on, the bar is visible while one is (as it already stays visible
for a held queue, and for the same reason: a state with nothing on screen to
explain it), and the held run's row is marked. One line per row, no second line, no
new colour — quiet, as PRO-0018 settled, because a person using their own Mac is
not a fault. *Test: the label, the visibility, the per-row mark, and that
Hold-the-queue and held-by-contention read as two different states.*

**A7 — the menu bar's glyph does not change; its words carry the name.**
`MenuBarIcon.decide` is untouched and unreordered. `proctor_recent_activity`'s
`foreground.yield` block gains `session`, `app` and `display`, and its `line` names
them. *Test: `decide` returns for a held run exactly what it returns at HEAD; the
wire block's shape and wording; the block unchanged in shape when nothing is held.*

**A8 — `activate` takes the lanes it changes, and says what a waiting caller
gets.** Global always; plus `.app(id)` when the target resolves to an attached
handle, keyed as a batch keys it. Acquired after the policy gate, once for the
call. It can now be refused with `queueBusy` or `haltedByPerson`, nothing is
activated on either path, and the tool description states the waiting behaviour.
*Test: the lane demand for an attached target, an unattached one and a target that
is not running; the refusal's shape; the catalogue text.*

**A9 — the health report joins the two.** `proctor_doctor`'s queue block marks each
active run held with its attribution, so a machine that looks wedged is diagnosable
as "somebody is using it" rather than as a stuck lane. *Test: the JSON shape held
and not held.*

## Assumptions recorded in place of questions

- **A-i. One latch, one clock, one backstop — with an owner on the automatic
  cause.** PRO-0018's decision is kept rather than reversed: there is still one
  flag set, one `pausedAt` and one bound, because at most one run can be yielded at
  a time (measured). What is added is a key saying which run the yield is about.
- **A-ii. An unarmed run is not parked and gets no record.** The alternative —
  parking it and naming who did it — documents the stall rather than removing it,
  and the record cannot reach a caller whose host gave up thirteen minutes earlier.
- **A-iii. The hold is published to the scheduler rather than the scheduler reading
  the session.** The scheduler is outside the reentrant actor and is already what
  every surface reads; a draw-time read into `Session` would put a redraw behind the
  actor's turn-taking and behind every settle await.
- **A-iv. The scheduler's copy is a read surface, not the decision.** The latch stays
  the truth because the buttons write it synchronously from the main thread.
- **A-v. The panel's live line is not touched.** Settled, one line at one size, and
  already carrying the reason.
- **A-vi. The display is derived from the driven window, not from where the panel
  went.** They are the same screen by construction, but the window is the fact and
  the panel is a consequence; attributing to a consequence breaks the moment the
  panel is switched off.
- **A-vii. A hold is keyed by run, and does not rely on there being only one.**
  Two armed runs cannot overlap (measured above), so at most one hold is open at
  a time. The latch keys holds by run anyway, because that invariant is enforced
  two files away and a single owner would be silently retargeted by a second
  yield — unparking the first run into the very person it had got out of the way
  of. Keying costs a dictionary and removes the dependency rather than
  documenting it. Found by the completeness gate; see Gates.
- **A-viii. `activate` takes the app lane only when a handle exists**, and its
  lane set is fixed before it waits, like everything else's.
- **A-ix. `activate` joins the queue rather than failing fast when busy.** Every
  other entry point waits; a bootstrap call that refused while a batch waited
  would be the one inconsistent verb, and the ceiling already bounds the wait.

## Out of scope

- Changing when a run *yields*, what it samples, or the vocabulary of the reasons —
  PRO-0018 owns all three and none changes.
- A person's Pause or Stop being cleared by the next run beginning. Real, settled by
  PRO-0015's "the live line is the most recently started run", and recorded as child
  work rather than widened here.
- The HUD's design, which is settled and binding (`mocks/run-hud.html`,
  `docs/design/run-hud-queue.md`).
- Naming a display by its product name, or reading `NSScreen` from the session.
- The five open findings PRO-0018 recorded against itself (resume-and-walk-away,
  session-global secure input, helper processes in front, a dead target, the
  backstop's wording). A5 fixes the *misattribution* half of the last one for a
  yield; the rest stand.

## What a `swift test` cannot witness here

- The queue bar drawing the hold, the mark on a row, and the menu bar's text. There
  is no window server in the suite and obscura is web-only. Code-complete against
  `mocks/run-hud.html`; needs a human glance.
- A real second MCP client contending, and a real person moving to another app.
- `CGGetActiveDisplayList` returning a second display. The screen arithmetic is
  tested by injection; the enumeration is CoreGraphics's.

## Gates

- **Spec review, out of family, `grok-4.6 --effort xhigh --sandbox read-only`,
  2026-08-15.** Ran on grok as this repo requires; no downgrade, Codex not invoked.
  It read the built code rather than only the prompt, and returned four findings.
  **Three accepted and folded in before any code was written**, and they changed the
  design rather than decorating it:
  1. *Attribution documents the stall rather than fixing it.* Accepted. The claim in
     the draft — that splitting the automatic cause means a clock and a backstop per
     run — was wrong, and it was the load-bearing reason for the naming-only design.
     Parking is now per-run while the clock, the flag set and the bound stay single.
     This is A3.
  2. *`begin()` is an implicit Resume of every other run.* Accepted, and it is the
     finding the build would not have caught: `RunScheduler.acquire` never consults
     the latch, so any run starting on a free lane wipes a live yield, a person's
     Pause and a Stop. This is A4, and finding 4 above.
  3. *Stop and the backstop lie about who died.* Accepted. An expired yield sets the
     global `stopped`, so a sibling's caller is told a person stopped it. This is A5.
  **One accepted in part:** that the app-lane key is resolved before `activate`
  waits, so an attach during the wait is invisible. True, and it is PRO-0016's own
  fixed-lane rule rather than a defect introduced here; recorded as a stated limit
  above with what it leaves uncovered, rather than fixed by acquiring a lane
  mid-call, which is the thing that wedges two runs.
  Its endorsement of the read rule — publish into the scheduler, never hop into the
  session at draw time — is kept, with its caveat (the copy diverges at every
  `await`) turned into A2's five-ending-path test.
  The response was cut off mid-sentence at the end of finding C by grok's own
  deadline; the substance of that finding is complete and is dispositioned above.

- **Completeness critic, out of family, `grok-4.6 --effort xhigh --sandbox
  read-only`, 2026-08-15.** Ran on grok; no downgrade, Codex not invoked. The
  first invocation died mid-reasoning with no findings after spending its budget
  reading the repository, which is a lane failure rather than a pass; it was
  re-run with the built code inlined and reading forbidden, and returned in full.
  **One accepted and fixed:**
  - *A second yield silently unparks the first.* The draft kept one
    `yieldOwner: Int?`, so a second yield would retarget it and the first run's
    park would evaporate — it would resume posting into the person it had just
    got out of the way of, with nothing anywhere saying so. The measured
    invariant (armed implies the exclusive global lane, so only one run can be
    yielded) makes this unreachable today, but it is enforced two files away and
    the failure would be silent and severe. Holds are now keyed by run in a
    dictionary, so two holds park two runs and each releases its own. Pinned by
    `aSecondHoldNeverUnparksTheFirst` and `releasingAnUnheldRunIsANoOp`. The
    invariant is now a fact about the system rather than a load-bearing
    assumption of this file.

  **Three accepted as real and recorded rather than fixed**, each with the reason:
  - *`begin(run:)` still clears `pausedByPerson` and `stopped` for every run*, so
    an unrelated run starting lifts a person's Pause and their Stop. True, and
    the same shape as the defect A4 fixes. It is PRO-0015's settled rule that a
    new run is a new live line, and unpicking it is a decision about what Pause
    means rather than about what a hold says. Child work, below, now carrying
    the gate's exact sequence.
  - *One `pausedAt` shared by both causes gives an approximate elapsed time when
    a person's pause and a yield overlap.* Inherited unchanged from PRO-0018 and
    not made worse here — in fact improved, because a run parked only by a
    person's pause no longer inherits another run's banked yield time. Every
    inaccuracy biases toward giving up **earlier**, never toward holding longer,
    which is the safe direction for a bound whose whole job is to stop a run
    being held forever.
  - *A person's pause expiring reports `.stopped` to a separately-yielded run*,
    whose wording names a person stopping it from the run HUD. A person's pause
    did hold every run, so stopping every run is right; only the wording is
    approximate. Adding a third refusal shape late, untested against every
    caller that switches on `Halt`, is the riskier move. A5 scopes the yield
    case, which is the one that reported a halt nobody chose.

  **One rejected:** that a run can be parked forever with `pausedAt` unset. Both
  setters arm the clock under the same lock, and `look` returns nil rather than
  parking when it is absent, so the path does not exist. Its remark that there is
  no Resume in the API was answered by `resume()`, which the excerpt it was given
  did not include.

## Child work found, not scheduled

- **A person's Pause or Stop is cleared by the next run beginning.** `begin(run:)`
  resets `pausedByPerson` and `stopped` unconditionally, so a person who paused a
  run watches it resume when an unrelated session starts one. The completeness
  gate gave the sequence: run A is in flight, a person presses Pause, run B
  starts on a free lane, `begin(B)` clears the flags, and A's next checkpoint
  finds nothing holding it. Settled behaviour under PRO-0015's live-line rule and
  out of scope here, but it is the same shape as the defect A4 fixes and the half
  that is still broken is the more important one, because it is a decision
  somebody actually made.
- **The backstop's wording does not separate its causes.** A person's pause
  running out reports `.stopped` — "a person stopped this run from Proctor's run
  HUD" — to every other run in flight, including one held for its own reason.
  PRO-0018 recorded the same complaint as its finding 5. A third `Halt` case
  would fix it and would need every caller that switches on `Halt` re-checked.
