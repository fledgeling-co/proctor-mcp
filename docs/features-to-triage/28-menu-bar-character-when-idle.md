---
sources: [REQ-011]
status: retired
---
# The menu bar shows the character when idle, not a status symbol

## The problem

PRO-0021 put the character in the menu bar and made readiness outrank it: if the
agent is unreachable or a required grant is missing, you get a status symbol
instead, because a calm idle character over a Proctor that cannot work is a picture
telling you something untrue about your Mac.

That rule is right, and it is currently reaching further than intended. At rest, on
a healthy machine, the menu bar should be the pixel character in its idle state. The
reader reports seeing a symbol instead.

## What to establish first

This is a bug report about a rule that already exists, so the first job is finding
out which of these is true, and the answer changes the work entirely:

- **The ladder is being read wrong** — `MenuBarIcon.decide` returns `.character` for
  a reachable, ready agent, so the symbol means one of the guards is firing.
  `Automation` is reported as a grant and is `granted: false` until an Apple Event
  is first sent; if `ready` folds in a non-required grant, a perfectly healthy Mac
  reads as not ready forever.
- **The idle art is not being drawn** — `MenuBarLabel` falls back when
  `character.image` is nil, so a missing or unloadable idle frame shows as nothing
  and the symbol path wins. The asset tests cover the frame table, not what the
  running app resolves from its bundle.
- **The phase never reaches the UI at rest** — the phase arrives by poll, and an
  idle agent may simply never publish one, leaving the UI on its initial value.

`proctor_doctor` reports `ready`, the grants, and the hud block, so the three are
distinguishable from a single call. Establish which it is before changing anything.

## What it should do

At rest on a healthy machine, the menu bar carries the character in its idle state:
still, never animating, and never moving under Reduce Motion. The readiness ladder
stays exactly as it is — unreachable and missing-required-grant still outrank the
character, for the reason PRO-0021 gives.

## Worth knowing

- The idle state is deliberately still. An animating menu bar icon at rest is an
  irritation and a battery cost, and PRO-0021 decided that already.
- The art is full colour rather than a template image, so it does not adopt menu bar
  tinting: vermilion carries acting, blocked, finished and error, and grey belongs to
  paused alone. A template would throw all of that away.
- 22 points rather than 18, because 18 was rendered and rejected: the screen glyph
  collapses at that size and blocked and acting become the same solid block.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-011
- surface: SURF-010
- cases: CASE-0013, CASE-0037, CASE-0258, CASE-0259, CASE-0260, CASE-0266
- rungs reached: effect-witness, outcome, raster-visual
- provider: none
