# PRO-0033: A person's click reaches Stop

**ID:** PRO-0033
**Status:** Triage
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
check.

**And a click the tap swallows can be routed to Stop without being forwarded
anywhere.** PRO-0026 declined this because it couples the block to the panel's
layout and because a passed click would fall through the click-through panel to
the application. The second objection dissolves once the click is not passed at
all: the tap reads the panel's Stop rect, decides `stopRun`, and *swallows* the
event exactly as it swallows Escape. Nothing is forwarded, nothing reaches the
application, and the run ends on the first press. The first objection is real and
is paid for with a published rectangle rather than a layout dependency.

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
anything — and it is closed from the measured plane when `perform` returns,
however the step ended.

**A3 — The actuator declares before it posts.** The declaration is made at the
end of `requireEventPlaneAvailable()`, after its guard passes, so a declaration
means a post is imminent and a refused step declares nothing. It is a
lock-guarded hand-off, never an actor hop: the actuation path runs synchronously
off the main thread and nothing in it may wait.

**A4 — Declaration and outcome cannot disagree in the direction that matters.**
A declaration is made past every accessibility route, so a step cannot declare
synthetic and then succeed through accessibility. The disagreement that can
happen is the other one — the pre-step pessimistic open for a conditional step
that then resolves on accessibility — and the gate closes on the measured plane
when `perform` returns, so the panel is never left stepped aside.

**A5 — The declaration feeds what has been guessing.** Three consumers move from
after the step to before the post: the grace window (`noteSyntheticPost`), which
today does not open for a fallback post at all, so the application's echo of
Proctor's own wheel event can read as a person and yield the run; the takeover
statement, which today goes up only once the step has settled, claiming the
machine after it was taken; and the input block's arming.

**A6 — With the block armed, a person's click on Stop ends the run on the first
press.** The tap hit-tests the panel's published Stop rectangle and returns the
decision that swallows *and* stops, exactly as Escape already does. The event is
not forwarded to the panel, to the application, or anywhere else. A click
elsewhere in the panel is swallowed and yields, unchanged from PRO-0026.

**A7 — With the block unarmed, a person's click on Stop reaches Stop whenever
the gate is closed** — which after A1 is every step except one posting into the
panel's own footprint. At HEAD it was no synthetic step at all.

**A8 — Proctor's own click never presses Stop or Pause, and this is enforced
twice.** In the tap, `InputBlock.isOurs` is tested before the Stop rectangle, so
our own event passes as an ordinary event and is never read as a press; the
ordering is pinned by a test. At the panel, a mouse event whose source is
Proctor does not actuate a control. This is the invariant PRO-0015 established
and it survives every change here.

**A9 — Nothing is forwarded and no monitor is installed.** The panel's body
still swallows a click that is not on a control; no global mouse monitor is
created; the tap is still created only when an operator set
`PROCTOR_TAKEOVER_INPUT`, and with it unset no `CGEventTap` exists on any code
path.

**A10 — The published rectangle cannot outlive the panel.** It is cleared when
the panel is hidden, when it is taken down after a drawing fault, and when the
run ends. A stale rectangle would let a click on empty screen stop a run, which
is the one way this clause fails badly.

**A11 — Nothing new is refused.** `Session.refusal(for:foreground:)`, lane
demand, and every step's reported plane are byte-identical to HEAD.

## Design

Core holds the arithmetic and the decisions; the agent holds AppKit, the port
and the geometry it reads from a window server. The split is PRO-0026's, for the
same reason: the interesting half is then testable without one.

- **`ProctorCore`** gains the gate predicate (does a step's point or route
  intersect a rectangle), the AppKit-to-CoreGraphics rectangle conversion the
  tap needs (beside `RunHUDPlacement`, which already owns that transform), and
  the Stop-rect test inside `InputBlock.Gate.decide`, ordered after `isOurs`.
- **`RunHUDPanel`** publishes the Stop control's screen rectangle to a
  lock-guarded keeper the tap's thread reads, and clears it on hide, fault and
  run end. `RunHUDContentView` refuses to actuate a control on one of Proctor's
  own events.
- **`Actuator.requireEventPlaneAvailable()`** gains the declaration.
- **`Session`** computes the gate before each step from
  `cursorTarget(for:)` / `cursorRoute(for:)` — the screen points it already
  resolves for the drawn pointer — and reconciles it from the measured plane
  after `perform` returns.

## Assumptions recorded in place of questions

- **A-i. The tap routes Stop and nothing else.** Pause, the grip and the queue
  controls stay where they are. Stop is the kill switch; a tap that could work
  every control would be one performing arbitrary interface actions from an
  event callback, on a thread where nothing may wait.
- **A-ii. The gate's geometry is the panel's whole frame, not the Stop rect.**
  If Proctor is posting anywhere under the panel, the panel must be out of the
  way or it eats the step.
- **A-iii. A source check that cannot read a source treats the event as a
  person's.** The geometric gate is the primary enforcement of A8; a belt that
  failed the other way would leave the kill switch dead whenever AppKit
  synthesised an event carrying no `CGEvent`.
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
- **The panel's body still swallows a click that lands on no control.** PRO-0015
  decided that deliberately and this does not reopen it.
- **The unblocked takeover label says Pause and Stop are in the run panel.** In
  the footprint case above they momentarily are not. Not worth a second wording
  that flickers; PRO-0026 already established that a message which flickers is
  one people learn to ignore.

## What a `swift test` cannot witness here

The tap swallowing a real click and stopping the run, the panel receiving one,
`ignoresMouseEvents` taking effect in the window server, and the published
rectangle matching what is on screen. The gate predicate, the coordinate
transform, the decision ordering, the reconciliation and the model's values are
all values and are tested; the delivery of a click is a code reading and is named
as one.

## Out of scope

- True click-through on the panel body. Rejected in PRO-0015 for a reason that
  has not changed.
- Changing which steps are synthetic, what is refused, or the HUD's design,
  which is settled and binding (`mocks/run-hud.html`).
- A settings surface for the `PROCTOR_*` switches, which is somebody else's item.
