# Multi-session runs — the queue and what the HUD shows

Proctor is one agent process behind one socket, and any number of MCP clients
can connect to it. Today nothing arbitrates between them: two Claude sessions
driving the same Mac interleave their steps, and the second one's synthetic
click lands in whatever window the first one just raised. This is the model that
fixes that, and the surface that makes it visible.

## What actually contends

Not everything needs a queue, and queueing everything would make Proctor feel
broken for the common case.

- **Reads never contend.** `proctor_snapshot`, `proctor_find`, `proctor_capture`,
  `proctor_menu`, `proctor_zoom` and `proctor_assert` observe without mutating.
  They run immediately, always, whatever else is in flight.
- **Process-directed actuation contends per app.** An accessibility press or an
  Apple Event is IPC to one target process. Two sessions driving *different*
  apps genuinely do not interfere, so they run in parallel. Two sessions driving
  the *same* app serialise.
- **Synthetic events contend globally.** `click`, `hover`, `dragPath`, `key` and
  foreground `type` enter the single system event stream and require the target
  frontmost. Only one of these runs anywhere on the machine at a time, and it
  also blocks process-directed work on the app it raises.

So the queue is really three lanes: a free lane for reads, one lane per attached
app for the accessibility plane, and one global lane for synthetic events. A
run's lane is known from its steps before it starts, which is what makes this
schedulable rather than guesswork.

## What a run is

The unit that queues is a whole `proctor_act` batch, a `proctor_flow` replay, or
a `proctor_stability` sweep — never a single step. Splitting a six-step login
across two sessions' interleaved turns is exactly the failure the queue exists
to prevent, so a batch holds its lane from the first step to the last.

## Session identity

Every connection gets a label a person recognises. The MCP client's working
directory gives the project name (`diolog-web`, `armada`, `proctor-mcp`), and a
four-character connection id disambiguates two sessions in the same repo. That
pair — `proctor-mcp a3f1` — is what the HUD prints, on the active run and on
every queued one. A pid is not an answer to "which session is this".

The label is derived, never supplied by the client: a connection that could name
itself could impersonate another one in the very UI a person uses to decide
whether to stop it.

## Controls, and the verb collision to avoid

There are two different things a person might want to stop, and calling both of
them "pause" is how someone stops the wrong one.

| Control | Acts on | Effect |
|---|---|---|
| **Pause** | the active run | Holds before the next step. Nothing in flight is killed; the current step finishes settling. |
| **Stop** | the active run | Ends it. The owning session's call returns a refusal naming that a person stopped it. |
| **Hold** | the queue | No waiting run starts. The active run continues to completion. |
| **Clear** | the queue | Every waiting run is dropped. The active run is untouched. |
| **Drop** (per row) | one waiting run | That session's call returns; everything else keeps its position. |

Pause/Stop live with the run. Hold/Clear live with the queue header. They are
never adjacent, and they never share a word.

## What a queued session is told

A queued call must not silently hang — an agent that gets no answer retries, and
a retry behind a queue is how a queue becomes a stampede. A run that cannot
start immediately reports its position, and the client sees a queued result
rather than a stall. When a person clears or drops it, the call returns an
explicit refusal that names the reason: *dropped from the queue by a person, not
a failure of the step*. That distinction matters, because the first is a signal
to stop and ask, and the second is a signal to retry.

Fairness is FIFO within a lane, with a cap on how many runs one session may hold
waiting at once, so a session in a loop cannot starve the others.

## What the HUD shows

`mocks/run-hud.html` carries all three directions with the queue in place.

- **A · Sentinel** — one line, and a `5 sessions waiting` bar beneath it that
  expands in place to the full list with Hold and Clear. Smallest resting
  footprint; the queue costs nothing until someone opens it.
- **B · Ledger** — the same waiting bar, sitting between the step trail and the
  run controls, expanding to position, session, what it wants, how long it has
  waited, and a per-row drop. This is the one to build if multi-session is the
  common case rather than the exception.
- **C · Rail** — no queue at all. The rail is 32pt of chrome docked to the
  driven window's edge and a queue does not fit in it; a person who needs the
  queue opens the menu bar item.

The menu bar item mirrors the same count, so the queue is answerable without the
HUD being on screen.

## Open questions

- Whether a *held* queue should also block the active run from starting its next
  batch, or only block new sessions. Currently specified as the latter.
- Whether dropping a run should be undoable for a few seconds, or immediate. The
  mock is immediate.
- Whether the per-app lanes should be visible in the HUD, or whether showing
  three parallel active runs is more than a glance can carry. The mock shows one
  active run and treats the rest as queued, which understates what the scheduler
  can actually do.
