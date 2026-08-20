# PRO-0074: `proctor tui`, the supervision surface

**ID:** PRO-0074 · **Status:** Merged · **Created:** 2026-08-20
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

## Verification

Status: **Merged** on `ai/wave-9`. Suite: 1,647 tests in 193 suites, green over five consecutive
runs. Campaign: 36 of 36, armed 36/36, ratchet raised 32 → 36.

### Settled here

- **A1** — every pane renders at 80×24 as well as 100×30, and both are asserted for all eleven
  states. A third test asserts nothing is clipped at the floor: `truncated`,
  `column-too-narrow`, `shelf-too-wide` and `keybar-overflow` are recorded findings rather than
  silent clips, so the floor is proven rather than hoped for.
- **A2** — the running program was captured through a pty at both sizes and compared against the
  renderer row by row: identical. The captures are committed under
  `design/surfaces/tui/captures/` and the comparison is a standing test rather than a one-off,
  with the live reason text read back out of the capture rather than pinned, so the test is of
  the layout and not of a string.
- **A3** — `tui_gates.py --strict` exits 0 on both captures with 0 high findings. Its output is
  campaign evidence.
- **A4** — `SupervisionControl.apply(_:to:)` defaults to `RunControl.shared`, which is the object
  `RunHUDPanel.togglePause()` and `RunHUDPanel.stop()` write and every run loop reads between
  steps. Six tests, driving an injected control rather than the process-wide one: PRO-0053
  recorded a suite writing a shared latch reaching whichever other suite was stepping
  concurrently, and the default argument carries the claim instead.
- **A5** — frames are pushed. `Server.serve` holds a `proctor.watch` connection open and writes a
  frame per change; `SupervisionBroadcast` fans the scheduler's single observer out to many, so a
  supervision client attaching cannot stop the HUD drawing. A new watcher is handed the current
  frame at subscribe, because a client that connected during a quiet minute would otherwise draw
  an empty screen and read as a broken agent.
- **A6** — three distinct absences, each with its own remedy: not answering, answering but too
  old, and answering but not lately. A frame past `staleAfter` drops its lanes rather than
  drawing a queue nobody has confirmed.
- **A7** — the surface reads the wire and holds nothing. `SupervisionFrame` carries no window
  handle, no pixels and no accessibility node, asserted over the encoded frame, so nothing on
  this path is gated by a TCC grant. `ProctorCLI` links only `ProctorCore`.

### Settled later, by the 0.8.0 campaign

- **A4 is settled.** A real keystroke into a TUI running under a pty halted a run an MCP client
  had started; the caller received `haltedByPerson` after five of ten steps. Two vacuous passes
  had to be caught on the way and are recorded on the case.
- **A5 is settled.** The run pane drew `Act ×8 · "TextEdit"` while that batch was in flight,
  from a pushed frame rather than a poll.
- **A6 gained a surface.** The readiness and switches panes had no data source at all — DEF-008
  — and now read a live health report. History stays empty: the trail is sealed and no client
  can read it, which is a security-surface decision rather than a defect.

### Needs a live agent

- **A4, end-to-end** — that pressing `s` in the TUI halts a run started from an MCP client. Every
  link is tested and the latch is the same object; the chain through a real socket into a real
  run is not. The agent installed on this machine predates the feature, which is what the
  captures record.
- **A5, end-to-end** — that a queue change reaches a watching client without a poll. The
  broadcaster and the connection are both tested; the round trip is not.

### Two things found by building rather than by reviewing

**The surface called an answering agent absent.** Capturing the running binary against the
installed agent — which predates this feature — produced `unknown tool "proctor.watch"` under a
headline reading "The background agent is not answering", with a remedy offering to start a
process that was already running. That is wrong advice of the kind that costs an hour, so an
agent that answers and does not know the request is now its own state, with `upgrade the agent`
in place of `start the agent`.

**The role ladder did not survive losing colour.** `tui_gates.py --strict` reported "no bold and
no dim anywhere in the frame — every glyph carries the same weight, so the screen has no
hierarchy that survives a monochrome terminal", because weight was applied only on the
`NO_COLOR` path. It now rides alongside colour on every role. This matters more here than the
finding's severity suggests: the 16-colour palette has no defined RGB mapping, so on a great many
terminals colour is the channel that cannot be relied on.

### The parked questions, unchanged

The HTTP transport stays out — putting Stop behind a bearer token on a network front door is a
separate decision with its own security surface. A screen-reader mode that drops stylised chrome
for linear text stays child work.
