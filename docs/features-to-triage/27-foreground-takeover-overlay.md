---
sources: [REQ-008, REQ-042]
status: retired
validated-by: REQ-008, REQ-042 via CASE-0010, CASE-0031, CASE-0052, CASE-0058, CASE-0068
validated-rungs: effect-witness, metamorphic, outcome
validated-provider: CGEventTap in Sources/ProctorAgent/Session/ContentionMonitor.swift and Sources/ProctorAgent/Overlay/TakeoverOverlay.swift; NSEvent.addGlobalMonitorForEvents
---
# When Proctor must take the front, take it visibly and hold it

## The problem

Some steps cannot avoid the foreground: a drag path, a hover state, a canvas
surface, a keystroke tested as a keystroke. While one runs, Proctor and the person
are both driving one machine through one event stream. Today the person gets a
352pt panel in a corner of one display and nothing else. Their clicks land in
whatever Proctor just raised, their keystrokes interleave with posted ones, and the
run they were watching quietly becomes a run they corrupted.

PRO-0019 made this legible. PRO-0018 made Proctor yield when it notices. Neither
stops the input arriving in the first place.

## What it should do

For the length of a foreground step, put a full-screen semi-transparent overlay on
**every** display, carrying a label saying Proctor is driving and what to press to
stop it, and swallow user input while it is up.

Three properties, and each of them is where this gets interesting:

- **Every display.** One panel per screen, never one spanning the union: a panel
  sized to the union of this machine's displays is a ~26-megapixel backing store
  that the window server accepts, reports `onscreen=1, alpha=1`, and never presents.
  That measurement is in `CursorOverlay.swift`'s header and cost most of a session
  to find. Do not re-derive it.
- **It must not contaminate the evidence.** Proctor's captures are window-scoped
  through ScreenCaptureKit to the app under test, so a separate overlay window is
  already excluded — but that is a property worth *proving* with a test rather than
  assuming, because a full-screen tint over every capture would silently poison
  every visual assertion the tool exists to make. `sharingType = .none` is the
  belt; a capture taken with the overlay up, compared against one without, is the
  proof.
- **Swallowing input is the heavy part.** See below.

## The part that decides whether this ships

Blocking a person's input means a `CGEventTap` at the session level, which is an
event *interception* capability: the same API a keylogger uses, requiring the same
Accessibility grant Proctor already holds. That is a genuine escalation of what
this process does, and it deserves a decision rather than a default.

Three readings, and the spec must choose and defend one:

1. **Swallow nothing.** The overlay is purely a visual claim on the screen; input
   still reaches the app underneath. Honest, useless against the actual problem.
2. **Swallow while the step is in flight**, releasing between steps and on Stop. A
   tap that is armed only during the moments Proctor is genuinely posting events,
   and demonstrably released otherwise.
3. **A modal window that takes key focus.** Cheaper and safer than a tap, but it
   takes focus from the app under test, which is the one thing a foreground step
   cannot tolerate.

Whichever is chosen, two invariants: **Stop must always work** — an input blocker
that can swallow the click releasing it is a trap, not a safety feature — and the
block must not survive the process. A tap that outlives a crashed agent leaves
somebody with a Mac that ignores them.

## Interactions to respect

- The run HUD's panel already ignores mouse events while a synthetic step is in
  flight, so a posted click cannot land on Stop and halt the run that posted it.
  A new overlay has the same problem and needs the same answer.
- PRO-0018's yield watches for a person taking the machine back. If input is being
  swallowed, `userInput` can no longer fire the way it did, and `frontmostChanged`
  becomes the live signal. Say what the interaction is rather than letting the two
  features quietly cancel each other.
- Reduce Motion and Reduce Transparency both apply to anything drawn here.

## Not in scope

Blocking input outside a foreground step, or any always-on interception. The
overlay exists for the seconds Proctor genuinely holds the machine.
