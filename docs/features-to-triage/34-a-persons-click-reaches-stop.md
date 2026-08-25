---
sources: [REQ-007]
status: retired
validated-by: REQ-007 via CASE-0009
validated-rungs: outcome
validated-provider: CGEventTap in Sources/ProctorAgent/Session/ContentionMonitor.swift and Sources/ProctorAgent/Overlay/TakeoverOverlay.swift; NSEvent.addGlobalMonitorForEvents
---
# A person's click reaches Stop

## The problem

Stop is the kill switch, and three separate items have logged that a click aimed
at it can fail to arrive.

- **The run panel's mouse gate is driven by the step's kind, not its measured
  plane.** Carried unchanged from PRO-0019 through PRO-0018. A step that falls
  back to a synthetic `scroll` posts a wheel event the panel does not step aside
  for. Narrow today, and the wrong rule.
- **The actuator reports its plane only when `perform` returns**, so nothing
  before that moment knows the step went to the event stream. PRO-0019 logged
  this as child work because fixing it means the actuator declaring its plane
  before it posts, which is a change to the actuation path rather than to
  disclosure. That declaration is exactly what the mouse gate needs.
- **While the takeover block is armed, a person's click on Stop is swallowed.**
  PRO-0026 states what happens: the first click yields, which ends the hold and
  makes the panel clickable, so Stop lands on the second. The fix is to
  hit-test the run panel's frame inside the tap callback and route that click
  through. PRO-0026 declined to do it because it couples the block to the panel's
  layout, and because the panel is deliberately click-through for as long as a
  synthetic step is in flight, so a passed click would fall through to the
  application anyway. Both halves have to move together.

## What it should do

Make one rule for when the panel steps aside, driven by the plane the step is
actually travelling, and make a click aimed at Stop reach Stop on the first press
whether or not the takeover block is armed.

## The hard parts, named

- **The two halves genuinely are coupled**, and that is the reason this is one
  item rather than three. Routing a click to the panel while the panel is
  click-through delivers it to the application underneath, which is the corruption
  PRO-0015 refused. The gate has to know that Stop specifically is live even while
  the body is not.
- **Declaring the plane before the post** changes the actuation path. Say what
  declares it, when, and what happens when the declaration and the outcome
  disagree, because a step that declares synthetic and then succeeds through
  accessibility must not leave the panel stepped aside.
- **Proctor's own synthetic clicks must never press Stop.** PRO-0015 established
  this and it is the invariant that survives every change here. The takeover tap
  already distinguishes Proctor's posted events from a person's; that
  discrimination is the tool for it.
- **A swallowed click costs one repeated gesture. A wrongly-forwarded one
  corrupts a run.** When the two trade off, the safe direction is to swallow.

## Not in scope

True click-through on the panel body, which was rejected in PRO-0015 for a
reason that has not changed: it needs an always-on global mouse monitor inside a
process holding Accessibility.
