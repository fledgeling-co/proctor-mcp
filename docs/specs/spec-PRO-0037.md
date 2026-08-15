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

Three readings of the built code, because the brief's framing turns on them.

**1. Two runs that can *yield* cannot overlap.** Arming requires
`demand.takesForeground` or a step whose measured plane was `.syntheticEvent`.
`takesForeground` is `mightPost || raises`, and the actuator refuses the
synthetic fallback outright when `foreground` is false — so a step can only
report `.syntheticEvent` from a batch that already had `takesForeground`. And
`LaneDemand.forBatch` takes the exclusive `.global` lane on exactly that
predicate. Therefore **armed implies the global lane**, and the global lane is
one at a time anywhere on the machine. PRO-0018's completeness critic asserted
this and it holds.

**2. A run that cannot yield is held anyway, silently.** `RunControl.shared` is
one latch for the whole process. When an armed run yields, `look()` reads
`paused` for **every** run in flight, including an accessibility-plane run on a
different app in a different session that samples nothing and can never yield.
That run parks at its next checkpoint, gets no `RunHUDEvent`, records no
`YieldRecord`, and reports nothing to its caller. PRO-0018's A1 is true of
*sampling* and was read as though it were true of *being held*. This is the
attribution gap in its sharpest form, and it is provable as agent logic with no
window.

**3. Nothing that reads a hold can name it.** `Session.yieldJSON` folds every
run's open reason into one highest-precedence string and drops the run.
`RunTicketInfo` — the scheduler's per-run value the panel and the health report
already read — carries identity, lanes, summary and arrival time, and no hold.
The two halves are one `Session` field apart and never meet.

## The decision the brief asks for: what each surface is responsible for

A menu bar item is one glyph and cannot carry a name, so nothing here tries to
make it. The responsibilities are split by what each surface can physically say:

| surface | carries | does not carry |
|---|---|---|
| **Menu bar icon** | precedence, as one glyph. `MenuBarIcon.decide`'s ladder is untouched and unreordered. | any name |
| **Menu bar / status-window text** (`proctor_recent_activity`'s `yield` block) | the reason, the session, the app and the display, in words | per-run detail for runs that are not the attributed one |
| **Panel live line** | the reason, in PRO-0018's settled vocabulary, unchanged | whose — one line at one size, and it is already full |
| **Panel queue bar** | whose: the attributed session and app on the bar, and a held mark on every row the hold reaches | the reason a second time |
| **`proctor_doctor`** | the whole join, per active run, machine-readable | — |
| **`ActResult.yields`** | what held this run afterwards, including a hold another session's reading caused | — |

The panel's live line is deliberately not touched. It is one line at one size in
a settled mock, it already says the thing a person reads first, and the surface
that has room for a name is the queue bar directly beneath it.

## The hold is one machine's, not one run's — and that is what gets attributed

One latch, one clock, one backstop. PRO-0018 took that decision deliberately
(A-ii: a second yield flag beside the first is a second way to strand a run), so
this spec does not reverse it. The consequence is that a hold reaches **every**
run in flight, and the honest attribution is therefore not "this run is held for
this reason" but:

> the machine is held, because *this* session's run read *this* contention about
> *this* app on *this* display — and every run in flight is waiting on it.

That is what `HoldAttribution` records and what every surface above says. It
turns finding 2 above from a silent stall into a stated one, which is the whole
of the feature's value: a person and a caller both learn why an unrelated run
stopped.

Making the automatic hold per-run is a real alternative and it is **child work,
not this spec** — it means a clock and a backstop per run, which is the second
mechanism PRO-0018 refused, and it is a change to when a run is held rather than
to what a hold says.

## Where the join lives, and the line it has to hold

`Session` is a **reentrant** actor: isolation drops at every settle and every
capture `await`, which is why PRO-0016 put the lanes in `RunScheduler`, an actor
of its own, outside the actor's turn-taking. Anything joining hold state to queue
state has to hold that same line.

So the join is published **into the keeper**, never read across from the actor at
draw time:

- `RunTicketInfo` gains `held: HoldAttribution?`. The scheduler is where a hold
  and a queue row meet, because the scheduler is the thing that already knows
  every run in flight and is already read by the panel, the menu bar mirror and
  the health report.
- `Session.contentionProbe` — the one place contention policy lives — calls
  `runScheduler.hold(_:)` when it yields and `runScheduler.unhold()` when it
  releases, the same two moments it already moves `RunControl`'s latch.
- No surface enters `Session` to learn about a hold. The panel reads the
  scheduler snapshot it already reads.

A run's ticket id reaches the probe by task-local — `RunScheduler.$currentRun`,
set in `Session.scheduled` beside the `holdingLanes` flag that is already there.
Task-locals travel with the task rather than with the actor, which is exactly why
`SessionIdentity.current` already works this way through the same reentrancy.

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

A run drives a window; a `WindowHandle` carries its `frame`. Which display that
is belongs to `RunHUDPlacement.screenIndex(for:in:)`, which already answers
"which screen holds most of this rect", already falls back to the nearest for a
window on a display that has been unplugged, and is already tested without a
display attached. Reusing it means there is no second table of what a display is.
Screens come from `CGDisplayBounds` over `CGGetActiveDisplayList`, which the
session already reads for its display resource and which is not main-actor bound.

The name is plain and derived: `the main display`, or `display 2`. No product
name is read, because none is available from CoreGraphics without a main-actor
hop and a display's marketing name is not what somebody needs in a one-line hold.

## `activate` takes the lanes it changes

`proctor_apps.activate` brings an application to the front and, when it is not
running, launches it. That is `raise` in every way that matters to the scheduler,
and PRO-0016 gives `raise` the global lane because raising changes where
everybody else's clicks land.

- **The global lane, always.** It changes what is in front.
- **The app lane, when the target is already attached** — keyed on the same
  `AppHandle.id` a batch would use, resolved from the running application the
  policy gate already resolves. When the app is not attached there is no handle
  and no key, and inventing one from the bundle id would be a *different key
  space*: a batch holding `app:app:3` and an activate holding `app:com.acme.x`
  would not contend at all, which is worse than not taking the lane. A batch can
  only drive an attached app, so the case that can contend is the case that gets
  the key.
- **After the policy gate, before the activation**, matching `Session.scheduled`
  at the other four entry points. A refused activation never takes a place in the
  line.

**What a caller sees, because this is a behaviour change.** `activate` never
waited before and now can. It waits the same way every other queued call waits —
held open until its turn, up to `PROCTOR_QUEUE_WAIT_LIMIT` (45s default) — and it
can now come back with `queueBusy` (the machine was busy, safe to send again,
nothing was activated) or `haltedByPerson` (a person dropped it from the queue).
Nothing is activated on either path, which is what makes the retry advice true.
The tool description says so, because a call whose timing changed silently is how
an existing driver starts looking for a fault in an app.

## Acceptance clauses

**A1 — a hold names its session, its app and its display, all derived.**
`HoldAttribution` carries the reason, the session label from
`RunSessionIdentity`, the app under test, and the display the driven window sits
on, chosen by `RunHUDPlacement.screenIndex`. Nothing in it is client-supplied.
*Test: attribution built from a window frame and a screen list picks the display
holding most of the window, falls back to the nearest for a window off every
screen, and names the main display as such.*

**A2 — the join is published into the keeper, never read out of the actor.**
`RunTicketInfo.held` is set by `RunScheduler.hold(_:)` and cleared by
`unhold()`; a hold reaches every active ticket, because one latch holds every run
in flight. `contentionProbe` publishes at the two moments it already moves the
latch. *Test: hold then snapshot — every active ticket carries the attribution;
unhold clears every one; a hold survives tickets being acquired and released
around it, and a released ticket carries none.*

**A3 — the queue bar says whose, in the settled row shape.**
`RunQueueModel` gains the machine's hold and each `Row` a `held` flag. The bar's
label becomes the hold sentence while a hold is on, the bar is visible while one
is (as it already stays visible for a held queue, and for the same reason: a
state with nothing on screen to explain it), and a held row is marked. One line
per row, no second line, no new colour — quiet, as PRO-0018 settled, because a
person using their own Mac is not a fault. *Test: model assertions for the label,
the visibility, and the per-row mark, including that Hold-the-queue and
held-by-contention are two different states that read differently.*

**A4 — the menu bar's glyph does not change; its words carry the name.**
`MenuBarIcon.decide` is untouched and unreordered. `proctor_recent_activity`'s
`foreground.yield` block gains `session`, `app` and `display`, and its `line`
names them. *Test: `decide` returns exactly what it returns at HEAD for a held
run; the wire block's shape and its wording; the block is unchanged in shape when
nothing is held.*

**A5 — a run held by another session's reading says so afterwards.**
`YieldRecord` gains `attributedTo`, nil when the hold was this run's own reading
and the other session's label when it was not. A run that samples nothing but is
parked by the shared latch now gets a record, so a caller whose accessibility run
stalled for forty seconds has a reason instead of a gap. *Test: an unarmed run
parked by another run's yield gets one record naming that session; an armed run's
own holds still record `nil`; encoding is byte-identical when nothing held.*

**A6 — `activate` takes the lanes it changes.** Global always; plus `.app(id)`
when the target resolves to an attached handle, keyed the same way a batch keys
it. Acquired after the policy gate and before the activation, once for the call.
*Test: the lane demand for an attached target, an unattached one, and a target
that is not running.*

**A7 — a queued `activate` tells its caller what happened.** It can now wait and
be refused with `queueBusy` or `haltedByPerson`, nothing is activated on either
path, and the tool description states the new waiting behaviour. *Test: the
refusal reaches the caller unchanged in shape; the catalogue text states it.*

**A8 — the health report joins the two.** `proctor_doctor`'s queue block gains
the machine's hold and marks each active run held, so a wedged-looking machine is
diagnosable as "somebody is using it" rather than as a stuck lane. *Test: the
JSON shape held and not held.*

## Assumptions recorded in place of questions

- **A-i. One latch, attributed — not a latch per run.** PRO-0018 settled one
  flag, one clock, one backstop; splitting the automatic cause per run splits the
  clock and the backstop with it, which is the second mechanism that spec
  refused. Recorded as child work rather than folded in.
- **A-ii. The hold is published to the scheduler rather than the scheduler
  reading the session.** The scheduler is outside the reentrant actor and is
  already the thing every surface reads; a draw-time read into `Session` would
  put a UI redraw behind the actor's turn-taking and behind every settle await.
- **A-iii. The panel's live line is not touched.** It is settled, one line at one
  size, and already carries the reason. The name goes on the surface directly
  beneath it that has room.
- **A-iv. The display is derived from the driven window, not from where the panel
  went.** They are the same screen by construction — the panel is placed by the
  same function — but the window is the fact and the panel is a consequence, and
  attributing to a consequence breaks the moment the panel is switched off.
- **A-v. `activate` takes the app lane only when a handle exists.** A key from a
  different key space would look like contention accounting and provide none.
- **A-vi. `activate` joins the queue rather than refusing when busy.** Every
  other entry point waits; a bootstrap call that failed fast while a batch waited
  would be the one inconsistent verb, and the ceiling already bounds the wait.
- **A-vii. A hold's attribution is one, because the latch is one.** Two armed
  runs cannot overlap (measured above), so there is never a second live reading
  to lose.

## Out of scope

- Making the automatic hold per-run. Child work; see A-i.
- Changing when a run yields, what it samples, or the vocabulary of the reasons —
  PRO-0018 owns all three and none changes.
- The HUD's design, which is settled and binding (`mocks/run-hud.html`,
  `docs/design/run-hud-queue.md`).
- Naming a display by its product name, or reading `NSScreen` from the session.
- The five open findings PRO-0018 recorded against itself (resume-and-walk-away,
  session-global secure input, helper processes, a dead target, the backstop's
  wording). This spec makes the first four *legible*; it does not fix them.

## What a `swift test` cannot witness here

- The queue bar drawing the hold, the mark on a row, and the menu bar's text.
  There is no window server in the suite and obscura is web-only. Code-complete
  against `mocks/run-hud.html`; needs a human glance.
- A real second MCP client contending, and a real person moving to another app.
- `CGGetActiveDisplayList` returning a second display. The screen arithmetic is
  tested by injection; the enumeration is CoreGraphics's.

## Child work found, not scheduled

*(filled in during the run)*
