---
sources: [REQ-016, DEF-215]
status: retired
validated-by: REQ-016, REQ-100 via CASE-0018, CASE-0430, CASE-0431, CASE-0432, CASE-0433, CASE-0434
validated-rungs: outcome
validated-provider: none
validated-through-defect: REQ-100 via DEF-215
---
> **RETIRED 2026-08-15 (PRO-0039), not built.** This is a policy rule refusing actuation into browser page content, written when Proctor performed that actuation and only recommended a browser tool. Cua binds a native window to its tab and drives it over CDP, so the shape of the question changed underneath the brief. A refusal rule may still be wanted over delegated calls; it should be re-derived from the new architecture in a later wave rather than ported.
>
> Kept for the reasoning, not as a plan. See `00-WAVE-7-DIRECTION.md`.

# Page-scoped refusal

## The problem

PRO-0020 taught Proctor to recognise browser content and recommend handing it to
Obscura. The recommendation is advisory: a caller that ignores it and actuates
into an `AXWebArea` gets exactly what it asked for, which is a flattened tree and
coordinates instead of the DOM, a console and a durable selector. PRO-0020 logged
a policy rule that would refuse actuation into page content while leaving the
browser's own native chrome drivable, and deliberately did not build it.

The gap this closes is not "the advice is ignorable". It is that an operator who
has decided their machine should never drive a page through the accessibility
plane has no way to enforce that decision.

## What it should do

A policy rule that refuses actuation into a web area inside a known browser,
while leaving native chrome, toolbars, tabs and application menus drivable.

## The hard parts, named

- **This is a second authority over a question that already has one**, which is
  why PRO-0020 said it deserves its own spec. `ForegroundDemand`-style single
  answers are the pattern this repo uses; two things deciding what may be driven
  is how they drift apart. Say which is authoritative and what the other becomes.
- **It touches three contended surfaces:** `PolicyStore`, the `proctor_policy`
  schema, and the tool catalogue. Read the current shape of all three before
  designing, because the gate is fail-closed and its schema is a wire contract.
- **Native chrome and page content are not cleanly separated in the tree.** A
  browser's toolbar is native and its rendered page is an `AXWebArea`, but the
  boundary has exceptions: extension popovers, PDF viewers, the new-tab page,
  devtools. A rule that refuses too much makes the browser undrivable and a rule
  that refuses too little is a rule an operator cannot rely on. Name the boundary
  precisely and say what happens at each exception.
- **A refusal must be legible.** A step that fails because a policy refused it
  has to say so in a way that distinguishes it from an element that was not
  found, or the first thing a model does is retry with a different selector.
- **Off by default.** This is an operator decision, exactly like
  `PROCTOR_SECOND_LANE`, and for the same reason: it changes what Proctor will do
  on somebody's behalf.
