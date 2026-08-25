---
sources: [REQ-070, REQ-071, REQ-072]
status: retired
---
# The cua path leaves Proctor's own plane, and nothing on screen says so

**Wave 12, brief 1 of 2.** Reported from real use 2026-08-21. Sequence it first: it is the only
open item where a person watching the screen is told something untrue about what is driving their
Mac.

## What was reported

> Some apps using Xcode accessibility with "Automation Running" overlays don't show the HUD or use
> the fake cua mouse at all, and instead take over the real mouse. And some that use cua, although
> not often, and it's often still showing the mouse operating on a window that's in the background
> somewhere.

## What the code says, measured 2026-08-21

**"Automation Running" is not Proctor's, and where it does come from is unconfirmed.**
`grep -rn "Automation Running" Sources/` returns nothing, so Proctor does not draw it. It is also
absent from `strings` on `cua-driver` and `obscura`, and from `XCTest` and `UIAutomation`. So the
honest statement is the negative one: **Proctor is not drawing that banner**, and identifying what
is drawing it is the first thing the reproduction should settle, because it names which automation
stack actually took the machine. Do not carry the assumption that it is macOS's own indicator into
the work; it was assumed once in drafting this brief and did not survive a check.

**The cua backend already knows it cannot arm the overlays, and says so in a comment.**
`Sources/ProctorAgent/Actuation/CuaActuationBackend.swift:302-306`:

> An escalation to the front that this batch did not ask for. The guards that make a takeover
> visible arm before a post, **from inside the process making it** — and this post was made by
> another process, so nothing could have armed them. Saying so is the only honest thing left.

**Nothing on the cua path reaches the pointer overlay.** A grep for `PointerOverlay`,
`pointerMarker` or `drawnPointer` across `Sources/ProctorAgent/Actuation/` and `SessionAct.swift`
returns **zero** matches. `CursorOverlay.swift` carries the covered-target rule wave 9 built — the
`.hidden` case at line 273, *"over a target fully covered by another app"* — and the cua path never
consults it, because there is no Proctor-drawn pointer on that path to hide.

So the three symptoms are one mechanism seen three ways:

| What a person sees | Why |
|---|---|
| No HUD, no takeover notice | Both arm in-process before a post. The post came from the cua-driver subprocess. |
| The real mouse moves | There is no drawn pointer on this path, so the real cursor is the only cursor. |
| The pointer working on a background window | The covered-target rule lives in `CursorOverlay`, which this path never reaches. |

The backend records the escalation as `unrequestedForeground: escalated` on the `Actuation` result,
so the *data* is honest. What is missing is that the honesty never reaches the screen, and the
screen is where the person is looking.

## What to build

**1 — A run on the cua path raises the same standing signal as a run on the native path.** The HUD
and the takeover notice exist to answer "is something driving my Mac right now, and what". That
question has the same answer whichever process posts the event, so the signal cannot be gated on
which process posts it. Arm the overlays around the *batch* rather than around the in-process post.

**2 — When Proctor cannot draw its own pointer, say that rather than drawing nothing.** A run with
no visible pointer and a moving real cursor is indistinguishable from a person's own mouse, which
is the confusion reported. The honest surface is a notice that this batch is driving the real
cursor through an external driver, not a fabricated pointer standing in for one Proctor is not
posting.

**3 — Carry the covered-target rule to this path, or state why it cannot come.** Wave 9 established
the rule and its reasoning, and neither is up for revisiting: *dimming marks uncertainty about a
position; it cannot mark a pointer that is in the wrong plane entirely,* so a covered target gives
`.hidden`. If the cua path cannot know whether its target is covered, that is a ceiling and gets
recorded as one.

**4 — `unrequestedForeground` should be visible, not only recorded.** A batch that did not ask to
come to the front and came to the front anyway is exactly the event the run panel exists to report.

## First step is a reproduction, not a fix

The mechanism above is read off the source; the *frequency* and the trigger are not. Before
changing behaviour, reproduce it: run a batch that routes to cua, record whether the HUD appears,
whether the takeover notice appears, whether the real cursor moves, and what `unrequestedForeground`
says. Capture the screen while it happens. The reporter says it happens "not often", so the trigger
matters as much as the mechanism — find what selects the cua backend on those runs.

## What this brief does not do

`sharingType = .none` on the HUD and takeover overlay is correct and is not a defect: evidence must
not change because somebody was watching. This brief does not make Proctor's overlays appear in
Proctor's own captures.

It also does not remove the cua backend or make it a second-class path. cua is how Proctor reaches
things its own planes cannot; the defect is that the surfaces reporting a run do not follow the run
when it goes there.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-070, REQ-071, REQ-072
- surface: SURF-003, SURF-004, SURF-005
- cases: CASE-0003, CASE-0004, CASE-0008, CASE-0009, CASE-0010, CASE-0014
- rungs reached: effect-witness, metamorphic, outcome
- provider: none
