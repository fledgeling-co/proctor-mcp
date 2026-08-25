---
sources: [REQ-011, REQ-031]
status: retired
validated-by: REQ-011, REQ-031 via CASE-0013, CASE-0037, CASE-0713, CASE-0792, CASE-0795
validated-rungs: effect-witness, outcome, raster-visual
validated-provider: none
---
# A menu bar switch for the panel, and a menu bar icon that is the same character

## The problem

Two gaps, and they share a cause: the menu bar and the run HUD know nothing about
each other.

**The panel cannot be turned off without an environment variable.** `PROCTOR_HUD=0`
switches it off, which means editing a launchd plist and reloading the agent. That
is the wrong shape for a thing somebody wants gone for the next ten minutes, and
the wrong shape for a thing they want back afterwards.

**The menu bar icon says nothing.** Proctor already lives in the menu bar and is
already on every display, which makes it the one surface a person reliably sees. It
is currently static, while a character built for exactly this job sits in the
panel — a panel that may be on a display they are not looking at. The panel this
session landed at the bottom-right of an external display and was easy to miss
entirely.

## What it should do

- **Show and hide the panel from the menu bar.** A single item, taking effect at
  once and for the current run, not at the next relaunch. It is a preference about
  what is on screen, so it belongs where the other window controls already are.
- **Make the menu bar icon the same character, in the same state.** Idle, travelling,
  acting, paused, refused, failed and complete already exist as sprite states with
  their motion defined. The menu bar should show that character in that state, so
  a glance at the top of the screen answers "what is Proctor doing" without finding
  the panel.

The point of the second half is reach, not decoration. The character was built to
make state legible at 38px; the menu bar is 22px and always visible, which makes it
the better home for exactly that job.

## What already exists to build on

- `RunHUDCharacterView` drives the sprite from `RunHUDModel.phase`, with its loops
  and its Reduce Motion gate. A second consumer should read the same phase rather
  than deriving its own.
- The assets ship at @1x/@2x/@3x with real alpha, sliced to even footprints, in the
  app's own resource bundle. A menu bar rendition needs its own size; the design
  record says regenerate the grid rather than a cell, and `design/character/build-sprites.py`
  is the committed slicer.
- `Sources/ProctorUI/Motion.swift` carries the app's reduce-motion discipline.
- `OverlaySwitch` is the settled shape for a drawing off-switch and the menu bar
  item should agree with it rather than compete: a person who set `PROCTOR_HUD=0`
  and a person who chose Hide from the menu want the same thing.

## Worth deciding at triage

- **Whether the menu bar animates at all when nothing is running.** A permanently
  animating menu bar icon is an irritation and a battery cost. Idle probably means
  still.
- **Template rendering.** A menu bar icon normally adopts the menu bar's appearance
  as a template image, which would discard the character's own colouring. Whether
  the sprite ships as a template or as full colour is a real fork with a look
  attached, and it should be decided rather than defaulted.
- **Whether hiding the panel hides the stop button.** It does, and that matters:
  the panel is the kill switch. Hiding it should either keep a stop path in the
  menu bar or state plainly that there now is not one.

## Not in scope

Choosing a different character, or redesigning the panel. Both are settled.
