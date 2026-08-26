---
sources: [REQ-001]
status: retired
validated-by: REQ-001 via CASE-0001, CASE-0002
validated-rungs: outcome
validated-provider: none
---
> **RETIRED 2026-08-15 (PRO-0034), not built.** Scroll is Cua's now. This brief asks Proctor to fix the unit mapping and rung order of an actuation path that brief 45 hands to `cua-driver`. Fixing units in code that is being replaced is spend on both sides of a decision. If Cua's scroll has the same problem, that is a bug report to file upstream, which is a better use of the finding.
>
> Kept for the reasoning, not as a plan. See `docs/features-to-triage/00-WAVE-7-DIRECTION.md`.

# Scroll moves by what was asked

## The problem

PRO-0025 shipped an accessibility route for `scroll` and recorded two known
limitations rather than smuggling in fixes that would change what existing
scrolls do.

- **The delta is a fraction of the document, not lines.** The shipped mapping is
  `current + delta/100` written to a scroll bar's value, so a delta of 3 barely
  moves and a delta of 200 jumps to the end. A caller asking to scroll by three
  has no way to express that.
- **The page action outranks the precise bar write.** An element offering
  `AXScrollDownByPage` gets a page, whatever delta was asked for.

Both were left because fixing them changes behaviour every existing scroll
depends on, which is the right call inside another feature and the wrong place to
leave them permanently.

## What it should do

Make a scroll delta mean something a caller can predict, and make the rung order
serve the delta that was asked for rather than the first action that exists.

## The hard parts, named

- **There is no cross-process line height on macOS.** A scroll bar's value is a
  fraction of the document and carries no unit. Turning a delta into a distance
  means either deciding what a unit is and documenting it, or reading geometry
  from the target's own frames. Say which, and say what happens when the geometry
  is unavailable, because a scroll that silently means something different on one
  app than another is the defect this item exists to remove.
- **This changes existing behaviour by design**, which is why it needs its own
  item and its own tests. Every currently-passing scroll is a case to consider.
  A migration note in the changelog is part of the deliverable.
- **The wheel fallback is a different plane with different units.** A synthetic
  wheel event has its own notion of a scroll unit and needs the foreground. When
  the accessibility rung and the wheel rung disagree about what a delta means, a
  caller sees one API behaving two ways. Reconcile or disclose.
- **Ordering the rungs by fitness rather than by availability** means the page
  action becomes a fallback for a delta close to a page. Define the rule
  numerically rather than by adjective.
