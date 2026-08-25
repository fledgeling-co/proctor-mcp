---
sources: [REQ-006, DEF-215]
status: retired
---
# A drawing fault must not kill the agent

## What happened

On 2026-08-14, the first run after installing the HUD build, the agent aborted:

```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
reason: '*** -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]:
attempt to insert nil object from objects[2]'
```

Thrown from `TAttributes::ApplyFont` while CoreText copied an attributes
dictionary, inside `RunHUDContentView.drawLiveLine`, reached through
`NSViewBackingLayer display`. `launchd` restarted the agent; the run died with it,
and the next tool call came back `agentUnavailable`.

The palette has since been moved from the calibrated colour space to sRGB, on the
reasoning that every font in that dictionary is a system font and cannot be nil and
the paragraph style is built inline, which leaves the colour, and a calibrated
`NSColor` has to be converted before CoreText can use it. That is hardening a
plausible cause. It is **not** a confirmed diagnosis: the crash did not reproduce
across four attempts, including with the same binary, the same batch and the panel
confirmed on screen.

## Why the specific nil is the smaller problem

The HUD is a kill switch and a supervision surface. It is the thing a person reads
to decide whether to stop a run. An exception while drawing it currently takes down
the agent, the run in flight, and the MCP server that every connected session is
using.

PRO-0015's spec already states the property this violates: panel absent, run still
proceeds, `proctor_doctor` says why. `RunHUDAvailability` exists precisely so that
a panel that could not be drawn is reported rather than silently missing. That
promise holds for a panel that fails to *build*. It does not hold on the *drawing*
path, where any AppKit exception is fatal.

An annotation must never be able to kill the thing it annotates.

## What it should do

Catch a drawing fault, disable the panel, record the reason through the existing
`RunHUDAvailability`, and let the run carry on. `proctor_doctor` already has the
field to report it and the note to explain it.

Log enough at the point of failure to identify the next occurrence: which draw call,
which text, and the values of the three attributes. A crash that leaves nothing
behind but a stack is why the specific nil above is still unknown.

## The awkward part, which triage should decide

Swift cannot catch an `NSException`. The options are a small Objective-C target
holding a `@try/@catch` barrier, or validating every attribute before it reaches
AppKit, or both. A new target in `Package.swift` for one function is a real cost
and deserves a decision rather than a default.

Whichever is chosen, the barrier belongs around the whole `draw(_:)` pass rather
than around one call, because the next fault will be in a different one.

## Worth knowing

- Reproduce with the panel confirmed on screen, not merely built. `hud.onScreen`
  reports `RunHUDAvailability.built`, which is set when the panel is constructed and
  ordered in. It is a belief, not a measurement, and a run that never draws will
  report it as true. This project has already been caught once by a window-server
  report that looked healthy while nothing was presented.
- The window list is the instrument that did work: during a run the panel appears
  as a 352x200 layer-25 window with its alpha animating down through the fade.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-006
- surface: SURF-004
- cases: CASE-0004, CASE-0008, CASE-0021, CASE-0030, CASE-0032, CASE-0065
- rungs reached: effect-witness, outcome
- provider: NSPanel over the window server in Sources/ProctorAgent/Overlay/RunHUDPanel.swift, readable back through CGWindowListCopyWindowInfo
