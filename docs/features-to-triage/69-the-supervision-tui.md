---
sources: [REQ-029, REQ-030, REQ-033]
status: retired
---
# `proctor tui`, the supervision surface

**Wave 9, brief 11 of 11.** Reads `58`, `59`, `68`. Specified in `docs/PRD.md` §16.
Frames compiled at `design/surfaces/tui/` — 22 of them, at 100×30 and 80×24, all passing
both gate suites.

## The problem

**Status: not built.** Supervision today is a floating panel and a SwiftUI window, and both
need a GUI session on the machine being driven.

The remote HTTP transport and the SSH `StreamLocal` guest reach created the case neither
covers: an operator driving a Mac over SSH sees no run line, no queue, no history, and has
**no Stop button**. The kill switch exists and is unreachable — which is the same failure
PRO-0015 fixed locally when it moved the agent to `NSApplication.run()` so a click could
reach a button.

## What it should do

Five panes over one socket, drawn to the compiled frames.

| Pane | Source |
|---|---|
| Run | the derived step description, plane, route, target, elapsed |
| Queue | three lanes, who holds each, waiting count, hold attribution |
| Readiness | `proctor_doctor`: grants, five lanes, tools, secure input, build, machine |
| History | the folded run projection |
| Switches | the eight switches, their values and where each came from — read-only |

**A client, never a privileged process.** It speaks the same socket the shim does, holds no
TCC grants, and needs neither Accessibility nor Screen Recording itself. It must run over SSH
on a machine with no window server.

**Stop and Pause write the same latch.** `RunControl.shared` is what the panel's buttons
write and what the run loop reads. A terminal Stop is the same kill switch, not a second one.

## The conversion contract

The 22 frames are the reference, and they were compiled rather than drawn — the cell
arithmetic is the compiler's, using the same width function a capture is measured with. So
the acceptance path is the one `tui-craft` documents: build it, capture the running program,
and compare the capture against the compiled frame. A difference between the two is a
difference in the build rather than in the arithmetic, which is the whole reason the frames
were compiled.

## Acceptance

1. Every pane renders at **80×24** as well as at 100×30. The frames compile at both and a
   column narrower than its content is a compile error, so the floor is proven rather than
   hoped for.
2. A capture of the running program at each size matches its compiled frame; a difference is
   a finding with its row and column.
3. `tui_gates.py --strict` passes on every capture — border integrity, width arithmetic,
   overflow, truncation markers, glyph risk.
4. Stop from the TUI halts a run started from an MCP client, proving one latch rather than
   two.
5. Updates are **pushed, not polled**. `RunScheduler.observe` already exists; a supervision
   surface that polls shows stale state exactly when a run is moving fastest.
6. An unreachable agent shows the same reason and remedy `proctor status` prints, and the
   pane says the data is stale rather than showing the last good frame as current.

## The hard parts, named

**Colour is negotiated, never assumed.** `NO_COLOR` set to any non-empty value means no
colour and is checked first. The 16-colour palette has no defined RGB mapping, so an app
naming `red` cannot know its own contrast ratio — which is why the compiled frames carry
explicit hex role overrides and why selection is **reverse video** rather than a coloured
fill. Reverse survives `NO_COLOR`, a pipe, and an unhelpful theme.

**Wrap each frame in DEC mode 2026** so a partially-painted frame is never visible over a
slow link. This surface exists to be used over SSH.

**A screen reader linearises a 2D grid.** The shipped answer elsewhere is a dedicated mode
that drops stylised chrome for linear text and never encodes state in colour alone. Worth
deciding at triage rather than discovering later.

## Open decisions, for triage

- **Whether the TUI may attach over the remote HTTP transport as well as the local socket.**
  It would make supervision available wherever the tools are, and it would put **Stop behind
  a bearer token on a network front door** — a stronger gate than the local socket has, and
  one that needs deciding rather than inheriting.
- **Whether a read-only mode is worth having**, for watching a run without the ability to
  halt it.

## Out of scope

It does not issue tool calls, author flows, or edit policy. It watches and it halts.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-030, REQ-033
- surface: SURF-017, SURF-036
- cases: CASE-0033, CASE-0034, CASE-0035, CASE-0036, CASE-0040, CASE-0041
- rungs reached: effect-witness, metamorphic, outcome
- provider: Terminal.paint in Sources/ProctorCLI/TUI/Terminal.swift; scripts/campaign/supervision_tui_pty_probe.py
