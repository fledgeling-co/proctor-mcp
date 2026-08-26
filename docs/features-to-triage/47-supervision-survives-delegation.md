---
sources: [REQ-029]
status: retired
validated-by: REQ-029 via CASE-0035, CASE-0036, CASE-0040, CASE-0082
validated-rungs: effect-witness, outcome
validated-provider: Darwin.bind/listen/accept in Sources/ProctorAgent/Server.swift; Darwin.connect in Sources/ProctorCore/Transport.swift
---
# Supervision survives delegation

**Read `docs/features-to-triage/00-WAVE-7-DIRECTION.md` first.**

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
