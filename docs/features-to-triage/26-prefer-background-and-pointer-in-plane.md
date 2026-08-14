# Prefer the background, and draw the pointer where the work is happening

## The problem

Two halves of one complaint: Proctor takes the foreground more often than it needs
to, and when it works in the background the drawn pointer is in the wrong place
visually.

**It reaches for the front too readily.** The accessibility plane is the default and
it reaches occluded, background and other-Space windows without stealing focus. But
a step can end up on the synthetic-event plane for reasons that are not "the
accessibility plane genuinely cannot express this": a caller passing
`foreground: true` out of habit, a `type` whose element refused an attribute write
when a different route existed, or a batch raised once and then held in front for
its whole length. Every one of those is a run that could have left the machine
alone and did not.

**The pointer floats above everything.** `CursorOverlay` draws on a per-screen panel
at a very high window level, so while Proctor drives a background window the pointer
appears on top of whatever is actually in front. It reads as if Proctor is clicking
your foreground app. The truthful picture is a pointer that sits in the target
window's own plane, occluded by anything stacked above it, exactly as a real pointer
over that window would not be but a *drawn annotation of that window's activity*
should be.

## What it should do

- **Take the background route whenever one exists**, and treat the foreground as the
  exception it is already documented to be. Where a step falls back to synthetic
  events, prefer an attribute write that stays on the accessibility plane before
  accepting the fallback, and say which happened.
- **Draw the pointer in the target window's z-order**, so a window above the target
  covers it. A pointer drawn over the app somebody is using, while Proctor is
  driving something else entirely, is a picture that misrepresents what is
  happening.

## The hard parts, named

- **Window level is not the same as "behind that window".** macOS gives a panel a
  level, not a position in another application's stacking order. Sitting a panel
  immediately above the target window and below everything else means tracking the
  target's position in the window list and restacking when it changes, using
  `NSWindow.order(_:relativeTo:)` against a `CGWindowID` that belongs to another
  process. Whether that is reliable across Spaces, minimisation and full-screen is
  the question this item has to answer, and it should be answered by trying it and
  measuring, not by reasoning.
- **`CursorOverlay`'s header carries a measurement that must not be re-derived**: one
  panel per screen, never one spanning the union, because a ~26-megapixel panel is
  accepted by the window server, reported `onscreen=1, alpha=1`, and never presented.
- If restacking proves unreliable, the honest fallback is a pointer that is visibly
  *dimmed or marked* while the target is not frontmost, rather than one that lies
  about being on top. Say which was shipped.
- `PROCTOR_CURSOR=0` turns the pointer off entirely and must keep doing so.

## What already exists to build on

`ForegroundDemand` (PRO-0019) is the single answer to "does this batch take the
foreground", and it is also the scheduler's global-lane predicate. Anything that
changes which steps need the front changes that predicate, so it must go through
`ForegroundDemand` rather than around it.

## Not in scope

Making a step work that genuinely cannot travel through the accessibility plane. A
drag path, a canvas surface and a hover state have no accessibility expression; this
is about not paying the foreground cost when there was another route.
