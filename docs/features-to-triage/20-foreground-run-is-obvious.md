---
sources: [REQ-008]
status: retired
---
# Make a foreground-only run obvious before it takes the machine

## The problem

Proctor's default is the accessibility plane, which reaches background, occluded
and other-Space windows without stealing focus. That is the whole reason it can
run while somebody is using the Mac. But some steps cannot travel that way —
`click`, `hover`, `dragPath`, `key`, and typing into a field the accessibility
plane cannot write — and those need the window in front. When one runs, the person
loses the foreground with no warning.

Right now the only statement about this is one line on the HUD, during the step,
on a panel that may be on another display. By the time it is readable the machine
has already been taken.

## What it should do

Make "this run is going to interrupt you" legible **before** it happens and
unmissable **while** it does.

- **Before.** A batch's steps are known when the call arrives, so Proctor can say
  up front that this batch contains foreground-only work and how much. A person
  glancing at the HUD should be able to tell a run that will leave them alone from
  a run that will not, without reading step by step.
- **During.** While a synthetic step is in flight the panel should be
  unambiguous about it, and unambiguous somewhere a person actually looks. The
  menu bar is the obvious candidate: it is on every display's menu bar, it is
  already Proctor's, and it does not depend on which screen the panel landed on.
- **Afterwards.** The run's result should say how much of it needed the foreground,
  because "this suite cannot run unattended" is a fact worth knowing about a suite
  rather than something you discover by watching it.

## Why the existing surfaces are not enough

`proctor_act` already reports `plane` per step, and the skill already tells a model
to prefer `foreground: false`. Both are after the fact or advisory. Neither reaches
the person whose machine it is.

The HUD states the synthetic exception in words, once, deliberately — accessibility
is the rule and is never announced. That design decision is settled and this brief
does not reopen it. What it adds is reach: the same fact, in a place that does not
depend on the panel being on the display somebody is looking at.

## Worth deciding at triage

- Whether a batch containing any synthetic step should say so at the start, or
  only when the first one is reached. Saying it early is more useful and slightly
  less honest, since a batch can end before it gets there.
- Whether this should be able to refuse rather than only warn: a run that needs
  the foreground while somebody is typing may be better held than announced. That
  overlaps the yield brief and the two should be triaged together.

## Not in scope

Changing which steps are synthetic, or adding an accessibility route for a step
that genuinely has none. This is about disclosure, not about the planes.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-008
- surface: SURF-005
- cases: CASE-0009, CASE-0010, CASE-0031, CASE-0052, CASE-0053, CASE-0054
- rungs reached: effect-witness, metamorphic, outcome
- provider: CGEventTap in Sources/ProctorAgent/Session/ContentionMonitor.swift and Sources/ProctorAgent/Overlay/TakeoverOverlay.swift; NSEvent.addGlobalMonitorForEvents
