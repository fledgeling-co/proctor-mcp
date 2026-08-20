# PRO-0033: A person's click reaches Stop

**ID:** PRO-0033
**Status:** Merged
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/34-a-persons-click-reaches-stop.md`
**Builds on:** PRO-0015 (the panel, its controls, and the decision that its body
swallows rather than forwards), PRO-0019 (`syntheticInFlight`, the kind-driven
mouse gate, and the plane reported only on return), PRO-0018 (`PersonInput`,
the grace window), PRO-0026 (`InputBlocker`, `InputBlock.isOurs`, the tap)

## What it is

Stop is the kill switch, and three items have logged that a click aimed at it
can fail to arrive. They are one item because the fixes are coupled: routing a
click to the panel while the panel is click-through delivers it to the
application underneath, which is the corruption PRO-0015 refused.

Nothing here adds a capability. No monitor is installed, no new event is
observed, no step changes plane, and nothing new is refused. What changes is
which clicks the panel takes and when it steps out of the way.

## The three halves, and why each is where it is

**The mouse gate is a proxy for the wrong thing.** At HEAD the panel steps aside
for the whole of any step whose *kind* is synthetic — `panel.ignoresMouseEvents
= model.syntheticInFlight`. That is wrong twice. It misses a `scroll` that fell
back to a wheel event, whose kind is not synthetic; and it fires for every
synthetic step whether or not that step goes anywhere near the panel. The second
error is the expensive one, because while the gate is open a person's click on
Stop passes straight through the panel into the application under test — the
kill switch is dead and the run is corrupted by the same gesture.

**The gate's real question is narrower than its current rule.** The gate exists
for one reason, stated in `RunHUDPanel.render()`: a synthetic event is posted at
a screen point and *the window at that point wins*. So the panel only has to
step aside when a synthetic event is about to be posted **at a point the panel
occupies**. Everywhere else it can stay live, and Stop with it. That is one rule,
driven by the plane the step is actually travelling and by the geometry that
made the gate necessary in the first place.

**The plane is knowable before the post, at one choke point.** Every synthetic
route in `Actuator` — `type`'s fallback, `scroll`'s fallback, `key`, `click`,
`hover`, `dragPath` — passes through `requireEventPlaneAvailable()` immediately
before it posts, after `activate(pid)` and after every accessibility route has
been tried and refused. Declaring there means a declaration is the point of no
return: it cannot precede an accessibility success, because the accessibility
routes are already behind it. It is also the one place a future synthetic route
cannot forget, because forgetting it would also forget the Secure Event Input
check — the two travel together or neither does.

**And a click the tap swallows can be routed to Stop without being forwarded
anywhere.** PRO-0026 declined this because it couples the block to the panel's
layout and because a passed click would fall through the click-through panel to
the application. The second objection dissolves once the click is not passed at
all: the tap reads the panel's published Stop rectangle, decides that the run
ends, and *swallows* the event exactly as it swallows Escape. Nothing is
forwarded, nothing reaches the application, and the run ends on the first press.
The first objection is real and is paid for with a published rectangle rather
than a layout dependency.

## Acceptance clauses

**A1 — One gate rule, and it is the plane and the point together.** The panel
steps aside exactly when the step in flight is about to travel the event stream
**and** the point or route it will act on intersects the panel's own frame. The
kind of the step never decides it. `RunHUDModel` carries the gate as its own
value; the layout keeps reading `exception != nil`, which is genuinely about
whether a row is drawn.

**A2 — A fallback is covered and an accessibility success is not.** A `scroll`
or `type` that concedes to the event stream opens the gate on the same rule as a
`click`. One that resolves on the accessibility plane never opens it. For a
conditional kind the gate is opened before the step only when its target lies
under the panel — pessimism confined to the case where being wrong costs
anything.

**A3 — The gate closes when the step settles, not on `perform`'s return and not
at the next step.** Two failures, one on each side. `CGEventPost` returning is
not delivery — events it posted are still in the window server's queue, so
restoring hit-testing the instant `perform` returned would let Proctor's own
in-flight events land on a panel that has just become opaque. But holding it to
the next step's decision, which is what `syntheticInFlight` does at HEAD, leaves
Stop dead across the settle and the gap between steps — which is exactly when
somebody reaches for it, and it quietly contradicts PRO-0026's A6 route 1, which
claims the panel is clickable between steps. The settle is the signal that the
posted events landed and the application stopped moving, so the gate closes on
the first of the step settling, being refused, failing, the run yielding, or the
run ending. Every path through `runSteps` reaches one of those five.

**A4 — The actuator declares before it posts.** The declaration is made at the
end of `requireEventPlaneAvailable()`, after its guard passes, so a declaration
means a post is imminent and a refused step declares nothing. It is a
lock-guarded hand-off, never an actor hop and never a wait: the actuation path
runs synchronously off the main thread.

**A5 — Declaration and outcome cannot disagree in the direction that matters.**
A declaration is made past every accessibility route, so a step cannot declare
synthetic and then succeed through accessibility. The disagreement that can
happen is the other one — the pre-step pessimistic open for a conditional step
that then resolves on accessibility — and it costs one step of a dead Stop on a
step aimed under the panel, closed by A3's ordinary teardown.

**A6 — The declaration feeds what has been guessing.** Three consumers move from
after the step to before the post: the grace window (`noteSyntheticPost`), which
today does not open for a fallback post at all, so the application's echo of
Proctor's own wheel event can read as a person and yield the run; the takeover
statement, which today goes up only once the step has settled, claiming the
machine after it was taken; and the input block's arming.

**A7 — The block is armed for at least as long as the gate is open.** A gate
open wider than the armed window is the hole this feature exists to close, in
miniature: the panel is transparent, the tap is not yet holding, and the
person's click on Stop through-clicks into the application. So arming follows
the gate rather than the post — which is the shape PRO-0026 already has for a
certain synthetic step, extended to the pre-opened conditional one.

**A8 — With the block armed, a person's click on Stop ends the run on the first
press, and leaves no half of a gesture behind.** The decision is taken on the
mouse **up** inside the published Stop rectangle, matching how the panel's own
control actuates; the down is swallowed and remembered, so PRO-0026's pair rule
still holds and no orphaned up escapes into the application after the run ends
and the tap comes down. The event is forwarded nowhere. A click elsewhere in the
panel is swallowed and yields, unchanged from PRO-0026.

**A8b — The up's decision follows its own down, and nothing that happens in
between may change it.** A down inside the rectangle records a pending press for
that button; the up is decided from that record. Without this, a post beginning
between somebody's down and their up would make A9 suppress the rectangle at the
up, and the press would be swallowed and silently lost — the person pressed Stop,
saw the button go down, and the run carried on. An up outside the rectangle is a
cancel, as it is everywhere else on macOS, and is swallowed rather than
delivered.

**A9 — The Stop rectangle is tested only when no synthetic post is in flight,
and after `isOurs`.** Two enforcements, and the first is structural rather than
an identity check: Proctor's own click happens inside its own declared post, so
a rule that ignores the rectangle while a post is in flight cannot read
Proctor's click as a press even if both source fields were lost in transit.
`isOurs` is then tested before the rectangle as the second. This matters because
the tap route is a *new* way for a click to reach Stop, and a new way to press
the kill switch by accident would be worse than the problem it solves.

**A10 — With the block unarmed, a person's click on Stop reaches Stop whenever
the gate is closed** — which after A1 is every step except one posting into the
panel's own footprint. At HEAD it was no synthetic step at all.

**A11 — Proctor's own click never presses Stop or Pause at the panel either.** A
mouse event whose source is Proctor does not actuate a control. This is the belt
behind A1's geometry: if the gate is right, Proctor's event never reaches the
panel at all. This is the invariant PRO-0015 established and it survives every
change here.

**A12 — Nothing is forwarded and no monitor is installed.** The panel's body
still swallows a click that is not on a control; no global mouse monitor is
created; the tap is still created only when an operator set
`PROCTOR_TAKEOVER_INPUT`, and with it unset no `CGEventTap` exists on any code
path.

**A13 — The published rectangle is correct across the whole arrangement and
cannot outlive the panel.** The AppKit-to-Quartz flip is taken against the main
display's height for the whole arrangement rather than per screen, so a display
above the menu bar or left of the origin does not invert or displace it. It is
republished whenever the panel is placed, dragged, or changes height, and
cleared when the panel is hidden, taken down after a drawing fault, or the run
ends. A stale rectangle would let a click on empty screen stop a run, which is
the one way this clause fails badly.

**A14 — The keeper is a value the tap thread copies under a lock, and the
callback waits on nothing.** No dispatch to main, no work held under the lock,
no shared lock with anything that hops to main. A callback that blocked would
freeze the deadline timer and the release chord, which live on the same run loop
— PRO-0026's one way for both its invariants to fail without the process dying.

**A15 — Nothing new is refused.** `Session.refusal(for:foreground:)`, lane
demand, and every step's reported plane are byte-identical to HEAD.

## Design

Core holds the arithmetic and the decisions; the agent holds AppKit, the port
and the geometry it reads from a window server. The split is PRO-0026's, for the
same reason: the interesting half is then testable without one.

- **`ProctorCore`** gains the gate predicate (does a step's point or route
  intersect a rectangle), the AppKit-to-Quartz rectangle conversion the tap
  needs (beside `RunHUDPlacement`, which already owns that transform), and the
  Stop-rectangle test inside `InputBlock.Gate.decide`, ordered after `isOurs`
  and gated on no post being in flight.
- **`RunHUDPanel`** publishes the Stop control's screen rectangle to a
  lock-guarded keeper the tap's thread reads, and clears it on hide, fault and
  run end. `RunHUDContentView` refuses to actuate a control on one of Proctor's
  own events.
- **`Actuator.requireEventPlaneAvailable()`** gains the declaration.
- **`Session`** computes the gate before each step from `cursorTarget(for:)` /
  `cursorRoute(for:)` — the screen points it already resolves for the drawn
  pointer — arms the block alongside it, and tears both down on the next step's
  decision or at the run's end.

## Assumptions recorded in place of questions

- **A-i. The tap routes Stop and nothing else.** Pause, the grip and the queue
  controls stay where they are. Stop is the kill switch; a tap that could work
  every control would be one performing arbitrary interface actions from an
  event callback, on a thread where nothing may wait.
- **A-ii. The gate's geometry is the panel's whole frame, not the Stop rect.**
  If Proctor is posting anywhere under the panel, the panel must be out of the
  way or it eats the step.
- **A-iii. A source check that cannot read a source treats the event as a
  person's.** A9's in-flight rule is the structural enforcement, so the belt may
  fail toward the person; failing it the other way would leave the kill switch
  dead whenever AppKit synthesised an event carrying no `CGEvent`.
- **A-iv. A `dragPath` is tested along its whole route**, not at its start. A
  gesture that begins clear of the panel and crosses it still needs the panel
  out of the way.
- **A-v. No new switch.** This removes a failure rather than adding a capability,
  so there is nothing for an operator to opt into.
- **A-vi. The macOS floor stays 14** and nothing here uses a newer API.

## Known limits, stated rather than hidden

- **With the block unarmed and a step posting into the panel's own footprint, a
  person's click still falls through to the application.** That is HEAD's
  behaviour for every synthetic step and is now confined to this case. Three
  routes still cover Stop there: the gap between steps, Proctor's own menu bar,
  and the tap when an operator armed it. Closing it completely would need the
  panel to swallow Proctor's own click, which makes the step silently do nothing
  — a step reporting success having actuated nothing, which is the failure this
  repository refuses everywhere else.
- **A panel dragged onto the target during the step invalidates the geometry.**
  The points are resolved before the step. The consequence is bounded and is the
  safe direction: Proctor's click meets an opaque panel, A11 refuses to actuate
  it, and the step does nothing rather than pressing anything.
- **The keyboard route to stopping an armed run is Escape, not the Stop
  control.** While the block is armed every key is swallowed, so tabbing to Stop
  and pressing Space reaches nothing. That is PRO-0026's design and its overlay
  announces the chord; the mouse route added here joins the same latch rather
  than replacing it.
- **A stop still ends the run rather than the step in flight.** PRO-0015 settled
  that: killing a step mid-flight leaves the application in a state nobody can
  describe. The remaining events of a burst already posted still land, exactly as
  they do for an Escape today.
- **The panel's body still swallows a click that lands on no control.** PRO-0015
  decided that deliberately and this does not reopen it.

## What a `swift test` cannot witness here

The tap swallowing a real click and stopping the run, the panel receiving one,
`ignoresMouseEvents` taking effect in the window server, and the published
rectangle matching what is on screen. The gate predicate, the coordinate
transform, the decision ordering, the in-flight rule, the pair handling and the
model's values are all values and are tested; the delivery of a click is a code
reading and is named as one.

## Out of scope

- True click-through on the panel body. Rejected in PRO-0015 for a reason that
  has not changed.
- Changing which steps are synthetic, what is refused, or the HUD's design,
  which is settled and binding (`mocks/run-hud.html`).
- A settings surface for the `PROCTOR_*` switches, which is somebody else's item.

## Triage review

Out-of-family gate: **grok-4.6, `xhigh`, read-only**, 2026-08-15, evidence
inlined (Codex is off for this repo). The first invocation spent its deadline
reading the repository and returned narration with no findings; the retry, with
file reading explicitly suppressed and the design inlined at 30 lines, returned
nine findings. **Five changed the design, and three of those were defects that
would have shipped.**

| # | Finding | Disposition |
|---|---|---|
| 3 | Stopping on the mouse-down tears down the rect, the panel and the tap while the button is still held, so the person's mouse-up lands live in the application under test | **Accepted; the worst one.** A forwarded click into the driven application is the thing this feature is not allowed to do, and the first draft produced one on its own success path. A8: the decision is taken on the up, the down is swallowed and remembered, and PRO-0026's pair rule holds. |
| 1 | A tagged post that loses `userData` — or whose `sourcePid` reads 0 — is a mouse-down inside the Stop rect, and the belt fails open to "person", so Proctor's own click kills the run | **Accepted; the design changed.** Its premise about the two fields contradicts PRO-0026's T2, which measured both present on this machine, so the finding is not right about the mechanism — but it is right that an identity check is the wrong thing to rest a kill switch on. A9 makes it structural: the rectangle is not tested at all while a post is in flight, so the case cannot arise however the fields read. |
| 4 | `CGEventPost` returning is not delivery, so closing the gate on `perform`'s return restores hit-testing while Proctor's own events are still queued | **Accepted.** A3: the gate closes at the next step's decision or at the run's end, which is the window HEAD already used. The first draft's "close it from the measured plane on return" was a race dressed as precision. |
| 2 | The gate opens for the whole step while the tap arms only immediately before the post, so a Stop click in the gap still through-clicks | **Accepted.** A7: arming follows the gate, not the post. |
| 6 | The Quartz flip is arrangement-wide, not per screen; the rect goes stale on drag and height change | **Accepted for the transform and the republishing** (A13). **Rejected for the drawing-fault half** — a fault takes the panel down (`takeDownAfterDrawingFault` orders it out), so there is no visible button to click and clearing the rect is correct. |
| 5 | The tap callback must not share a lock with anything that hops to main, or it stalls input and macOS disables the tap | **Accepted as a constraint on the build** (A14), and it was already PRO-0026's rule for that callback; stated here because this change is the first to give the callback something new to read. |
| 9b | A VoiceOver user or somebody tabbing to Stop gets nothing while the block is armed, because only a mouse-down in a rectangle is recognised | **Accepted as answered by the existing design, and written down so it is not re-found.** Escape is the release chord, it stops an armed run, and PRO-0026's overlay announces it. |
| 7 | The choke point is not closed — a helper that posts directly never declares — and the takeover overlay is itself a window at the posted point | **Half accepted.** The first half is a property to state and hold rather than a defect: every synthetic route reaches the post through that guard, and a route that skipped it would also skip the Secure Event Input check. The second half is **rejected on the code**: every takeover panel sets `ignoresMouseEvents = true` unconditionally and sits below the run panel's level. |
| 8 | Pre-step geometry misses a panel dragged onto the target mid-step | **Accepted as a stated limit**, with its consequence named: the safe direction, a step that does nothing rather than a control that is pressed. |
| 9a | A stop from the tap does not kill the step in flight; the rest of a burst still posts | **Rejected, with PRO-0015's reason.** Killing a step mid-flight leaves the application in a state nobody can describe. Identical to what an Escape does today. |

## Child work found

- **The run panel has no surface for "Stop is momentarily unreachable".** In the
  footprint case the unblocked takeover label's "Pause and Stop are in Proctor's
  run panel" is briefly untrue. A second wording that flickers is worse than the
  gap, so this is a question about what the panel says rather than a defect here.

## Plan — 2026-08-15

Implementation plan: `docs/plans/plan-PRO-0033.md` (Plan size: Standard).
Its review gate accepted two findings that changed this spec: A3 was rewritten
(the gate closes on the settle, not at the next step) and A8b was added (the
mouse-up follows a record made at the down).

## Completeness critic

Out-of-family gate: **grok-4.6, `xhigh`, read-only**, 2026-08-15, the built
design inlined at 25 lines with file reading suppressed. Six findings. **Two
changed the code, and one was a defect that would have shipped.**

| # | Finding | Disposition |
|---|---|---|
| 1 | Holding the in-flight window for a whole step leaves Stop unreadable by mouse for the length of a `dragPath`, which the actuator clamps at thirty seconds | **Accepted; the worst one, and it was a real defect.** While the window is open the tap declines to read the Stop rectangle, so a person clicking Stop through a long gesture would have been swallowed for half a minute — and a long gesture is precisely the step PRO-0026 says must stay stoppable throughout. The window is now bounded in time rather than to the step, at the same quarter second `PersonInput` already uses to cover our own event's delivery. Pinned by `aLongGestureStaysStoppable`. |
| 3 | `stepsAside` is cleared only by five events, and a run killed between its last step and its end reaches none of them, leaving the panel click-through | **Accepted as a belt.** The five do cover every path through `runSteps`, so the finding's examples are wrong, but a hard task cancellation is not a path through `runSteps` at all. The panel now also clears the gate in `hide()`, which is the one place AppKit knows the run is over. |
| 4 | One physical press can be split across two hit-test modes: the down lands while the panel is click-through and the up on a live Stop that never saw it | **Accepted as an already-stated limit.** The panel actuates only when the down and the up agree, so the split press does nothing rather than firing — the safe direction. The down reaching the application is the footprint limit already recorded. |
| 2 | A real first press can be discarded as the agent's, if the source test is "has a source" or a poster's pid | **Rejected on the code and on measurement.** `InputBlock.isOurs` matches only our own tag or our own pid, and PRO-0026's T2 measured hardware arriving with both fields zero. The finding is right that the *shape* of the test matters, which is why it reuses that predicate rather than inventing one. |
| 5 | The block can double-arm and leak: the OR is two reasons, the declaration a third, and one `defer` releases once | **Rejected on the code.** The declaration handler deliberately does not arm — arming follows the gate, evaluated once per step — so there is one `arm` and one `release`. `takeoverEnd` calls `stopAll`, which zeroes the count at the run's end regardless. |
| 6 | `type` and `scroll` decide the gate before they know where they will post, so the geometry term is stale or missing | **Rejected on the code.** `gatePoints(for:)` resolves the same element the actuator will aim at, at that moment, through the resolution the drawn pointer already uses. The plane is what is taken as possible, never the position. |

## Progress

**Branch** `ai/pro-0033` · **worktree** `.worktrees/PRO-0033`. Ready to merge;
not merged, not rebased, not pushed.

**Gate.** `swift build` clean, no new warnings. `swift test`: **729 tests / 88
suites**, from 692 / 84 at the branch point.

| Clause | Proved by |
|---|---|
| A1 the plane and the point together | `gateNeedsBothThePlaneAndThePoint`, `edgesAreInside`, `nothingToStandInTheWay`, `theGateFollowsTheEvent` |
| A2 a fallback is covered, an accessibility success is not | `aFallbackOpensItAndAnAccessibilitySuccessDoesNot`, `awayFromThePanelNothingArms` |
| A3 the gate closes on the settle | `theGateClosesOnTheSettle`, `everyEndingClosesTheGate`, `aPausedRunIsClickable` |
| A4 a refused step declares nothing | code reading: the declaration is the last statement of `requireEventPlaneAvailable()`, after its throw |
| A5 a declaration cannot precede an accessibility success | code reading: the same guard sits past every accessibility route |
| A6 what the declaration feeds | `theDeclarationFeedsBothConsumers`, `theHandlerDoesNotOutliveTheRun`, `aDeclaringStepSaysSo` |
| A7 arming is never narrower than the gate | `armingFollowsTheGate`, `aSyntheticStepIsUnchanged`, `aThrownStepStillLetsGo` |
| A8 decided on the up, no half gesture left behind | `stopIsDecidedOnTheUp`, `theStoppingUpIsAlsoSwallowed`, `anUpOutsideTheRectDoesNotStop`, `aClickElsewhereIsUnchanged` |
| A8b the up follows its own down | `aPostBeginningMidClickDoesNotLoseThePress`, `aLateRectangleInventsNothing` |
| A9 the rectangle is not read while a post is in flight | `aPostInFlightIgnoresTheStopRect`, `oursIsTestedBeforeTheRect`, `eitherFieldIsEnoughAtTheRect`, `aLongGestureStaysStoppable`, `endStepClosesItEarly`, `theInFlightWindowClosesOnEveryPath` |
| A10 with the gate closed the click reaches Stop | `awayFromThePanelNothingArms`, `noPanelNothingArms`; the delivery itself is a code reading |
| A11 our own click never actuates a control | code reading: `RunHUDContentView.mouseDown`/`mouseUp`/`mouseDragged` return on `isOurs`; the predicate is tested in `oursIsTestedBeforeTheRect` |
| A12 nothing forwarded, no monitor installed | the existing PRO-0026 suites, unchanged and green |
| A13 the rectangle is right and cannot outlive the panel | `theQuartzFlipRoundTrips`, `aDisplayAboveTheMenuBarIsNotInverted`, `theKeeperClearsBoth`, `noRectangleNoStop` |
| A14 the callback waits on nothing | code reading; the keeper is lock-and-return and shares no lock with the main actor |
| A15 nothing new is refused | the full suite, including `the refusal table is unchanged` |

**Code-complete and not machine-witnessable here.** `swift test` has no window
server and no event tap, so none of these is proved by the suite: the tap
swallowing a real click and stopping a run, the panel receiving one,
`ignoresMouseEvents` taking effect in the window server, and the published
rectangle matching what is on screen. Named in the spec rather than implied.

**Child work found.**

- **The run panel has no surface for "Stop is momentarily unreachable."** In the
  footprint case the unblocked takeover label's claim that Pause and Stop are in
  the run panel is briefly untrue. A wording that flickers is worse than the gap.
- **PRO-0026's A6 route 1 is now true where it was not.** It claimed the panel is
  clickable between steps; at HEAD the gate was held to the next step, so it was
  not. Recorded here because that spec's wording still says it without the
  qualification, and it belongs to whoever edits that spec next.
