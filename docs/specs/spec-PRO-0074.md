# PRO-0074: `proctor tui`, the supervision surface

**ID:** PRO-0074 · **Status:** Ready for Plan · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/69-the-supervision-tui.md` · **PRD:** §16
**Branch:** `ai/pro-0074` off `ai/wave-9` · **Depends on:** PRO-0073
**Frames:** `design/surfaces/tui/` — 22 compiled, 100×30 and 80×24, both gate suites clean

## The problem

Not built. Supervision is a floating panel and a SwiftUI window, and both need a GUI session on
the machine being driven. The remote HTTP transport and the SSH `StreamLocal` guest reach
created the case neither covers: an operator over SSH sees no run line, no queue, no history,
and **has no Stop button**. The kill switch exists and is unreachable — the same failure
PRO-0015 fixed locally when it moved the agent to `NSApplication.run()` so a click could reach
a button.

## Acceptance criteria

1. **A1** — every pane renders at 80×24 as well as 100×30. The frames compile at both and a
   column narrower than its content is a compile error, so the floor is proven not hoped for.
2. **A2** — a capture of the running program at each size matches its compiled frame; a
   difference is reported with its row and column. Both sides were measured by the same width
   function, so a difference is a difference in the build rather than in the arithmetic.
3. **A3** — `tui_gates.py --strict` passes on every capture.
4. **A4** — Stop from the TUI halts a run started from an MCP client, proving one latch rather
   than two. `RunControl.shared` is what the panel writes and the run loop reads.
5. **A5** — updates are pushed via `RunScheduler.observe`, never polled. A supervision surface
   that polls shows stale state exactly when a run is moving fastest.
6. **A6** — an unreachable agent shows the reason and remedy `proctor status` prints, and the
   pane says the data is stale rather than showing the last good frame as current.
7. **A7** — it holds no TCC grants and runs on a machine with no window server.

## Decisions taken at triage

- **Selection is reverse video, not a coloured fill.** The 16-colour palette has no defined RGB
  mapping, so an app naming `red` cannot know its own contrast ratio; reverse survives
  `NO_COLOR`, a pipe and an unhelpful theme. The compiled frames already carry explicit hex
  role overrides for the same reason.
- **Each frame is wrapped in DEC mode 2026** so a partially-painted frame is never visible over
  a slow link. This surface exists to be used over SSH.

## Parked for the reader — appended to the goal brief's Open questions

- **Whether the TUI may attach over the remote HTTP transport.** It would make supervision
  available wherever the tools are, and it would put **Stop behind a bearer token on a network
  front door** — a stronger gate than the local socket has. **Assumption taken:** local socket
  only for this item; the HTTP path is a separate decision with a security surface.
- **A screen-reader mode** that drops stylised chrome for linear text and never encodes state
  in colour alone. **Assumption taken:** not in this item; recorded as child work.

## Out of scope

It does not issue tool calls, author flows, or edit policy. It watches and it halts.
