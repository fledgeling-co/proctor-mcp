---
sources: [REQ-038]
status: retired
---
# Multi-session scheduling — session identity, lanes, and the queue

**Status:** untriaged · **Value:** high · **Effort:** high · **Source:** design session 2026-08-14 · **Spec:** `docs/design/run-hud-queue.md`

## What it is
Proctor is one agent behind one socket and any number of MCP clients can connect. Today nothing arbitrates between them: two Claude sessions driving the same Mac interleave their steps, and the second one's synthetic click lands in whatever window the first just raised. This adds the scheduler that prevents it, and the surface that makes it visible.

`docs/design/run-hud-queue.md` is the full model. The load-bearing parts:

## Three lanes, not one queue
Queueing everything would make Proctor feel broken for the common case, because most calls do not contend at all.

- **Reads never contend** — `snapshot`, `find`, `capture`, `menu`, `zoom`, `assert` run immediately, always.
- **Process-directed actuation contends per app.** An accessibility press is IPC to one process; two sessions driving *different* apps genuinely run in parallel. Same app serialises.
- **Synthetic events contend globally** — one system event stream, target must be frontmost. One at a time anywhere on the machine, and it also blocks process-directed work on the app it raises.

A run's lane is knowable from its steps before it starts, which is what makes this schedulable rather than guesswork.

## What queues
A whole `proctor_act` batch, a `proctor_flow` replay or a `proctor_stability` sweep — never a single step. Splitting a six-step login across two sessions' interleaved turns is the exact failure this exists to prevent, so a batch holds its lane from first step to last.

## Session identity
Derived, never client-supplied: the MCP client's working directory gives the project name, plus a four-character connection id — `proctor-mcp a3f1`. A connection that could name itself could impersonate another in the very UI a person uses to decide whether to stop it. A pid is not an answer to "which session is this".

## Controls, and the verb collision to avoid
Two different things can be stopped, and calling both "pause" is how someone stops the wrong one:

| Control | Acts on | Effect |
|---|---|---|
| Pause | active run | Holds before the next step; the step in flight finishes settling |
| Stop | active run | Ends it; the owning call returns a refusal naming that a person stopped it |
| Hold | the queue | No waiting run starts; the active run continues |
| Clear | the queue | Every waiting run is dropped; the active run is untouched |
| Drop (per row) | one waiting run | That call returns; everything else keeps its position |

Pause/Stop sit with the run, Hold/Clear with the queue. Never adjacent, never sharing a word.

## What a queued session is told
A queued call must not silently hang — an agent that gets no answer retries, and a retry behind a queue is how a queue becomes a stampede. A run that cannot start reports its position. When a person clears or drops it, the call returns a refusal that names the reason: dropped by a person, not a failed step. The first is a signal to stop and ask; the second is a signal to retry. Fairness is FIFO within a lane, with a cap on how many runs one session may hold waiting, so a looping session cannot starve the others.

## UI
In the HUD: a `N sessions waiting` bar that expands in place to the list — position, session, what it wants, how long it has waited, per-row drop, with Hold and Clear in the section header. Rendered in `mocks/run-hud.html`. The menu bar item mirrors the count so the queue is answerable without the HUD on screen.

## Success looks like
Two MCP clients driving the same app serialise and both complete. Two driving different apps run concurrently. A synthetic-event run blocks everything until it finishes. Hold prevents the next start without touching the active run. Clear returns every waiting call with a person-initiated refusal.

## Dependencies / notes
- The scheduler half is independently testable — it is agent logic with no window involved.
- The queue UI depends on the run HUD panel.
- Open questions are listed at the end of `docs/design/run-hud-queue.md`; triage should settle them rather than leave them to the implementer.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-038
- surface: SURF-020, SURF-038
- cases: CASE-0048, CASE-0049, CASE-0055, CASE-0086, CASE-0750, CASE-0751
- rungs reached: effect-witness, outcome
- provider: none
