# PRO-0016: Multi-session queue

**ID:** PRO-0016
**Brief:** `docs/features-to-triage/17-multi-session-queue.md` (brief 17)
**Status:** Merged
**Plan:** `docs/plans/plan-PRO-0016.md`
**Created:** 2026-08-14
**Last updated:** 2026-08-14

## Feature description

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

---

<!-- Triage, plan link, and progress sections are appended below. -->

## Triage — 2026-08-14

**Ready for Implementation Plan**

**Sentinel review:** S2 — Approve with assumptions. This decides which of several people's agents is allowed to drive a shared Mac, and it adds two more ways for a person to halt one. The risk it carries is a wait that looks like a hang, and a stop that a caller reads as a broken step and retries.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** the run panel that floats over the driven app *(customer-facing — existing surface that gains UI)*; the menu bar item *(customer-facing — existing surface that gains UI)*. The scheduler itself is *(behind the scenes — nothing visible changes)*, and so is what a waiting caller is told.
- **What users will see — per surface:**
  - Run panel: a `N sessions waiting` bar beneath the live line, expanding in place to a list — position, session name, what that run wants, how long it has waited, a drop control on each row, and Hold and Clear in the list's header.
  - Menu bar item: the same waiting count, beside the activity line already there.
- **Behaviour changes:** two sessions driving the same app now take turns instead of interleaving, and both finish. Two driving different apps run at the same time. A run that needs the machine's attention holds everything else until it is done. A caller that has to wait is told where it stands rather than hanging, and a run a person removes comes back saying so.
- **Design reference:** `mocks/run-hud.html` carries the waiting bar and its expanded list; `docs/design/run-hud-queue.md` is the model. Both are settled — do not re-open them.

**Assumptions**
- `[Data & scope]` Reads never join the line and never wait for a run to finish; they answer wherever a run pauses. *(they only observe, and the agent already lets other work in at those pauses.)*
- `[Data & scope]` A lane is held by a keeper separate from the agent's ordinary turn-taking, for the run's whole length. *(that turn-taking lets other work in every time a run pauses, so it cannot itself hold a lane.)*
- `[Data & scope]` A lane is taken once for a whole call; a repeated sweep's inner passes never rejoin the line. *(otherwise a sweep's own passes queue behind other sessions mid-sweep.)*
- `[Data & scope]` A run's lane is fixed before it starts, from its steps and whether it needs the app in front. *(the steps that need the whole machine are already named in one place, and every batch already names the window it drives.)*
- `[Data & scope]` A run takes every lane it needs at once, before it starts, and never acquires another after starting. *(taking them one at a time is how two runs wedge each other.)*
- `[Data & scope]` A run that brings an app to the front also holds that app's lane. *(raising changes where everyone else's clicks land.)*
- `[Data & scope]` Once a run needing the whole machine is at the head of the line, no new single-app run starts ahead of it. *(a trickle of single-app work would otherwise starve it indefinitely.)*
- `[Data & scope]` Every release re-examines the whole waiting list, not only the lane that just freed. *(a run waiting on several lanes would never be woken by one of them.)*
- `[Data & scope]` A lane is released however its run ends — finished, failed, stopped, or the caller lost — and reclaimed if its holder has gone. *(a leaked hold wedges the machine until Proctor restarts.)*
- `[Data & scope]` The whole batch holds its lane; a repeated sweep holds it across every pass. *(splitting a login is the failure this prevents.)*
- `[Data & scope]` Permission checks run before a run joins the line, so a refused run never takes a place. *(that check already runs first today, and it reads configured settings rather than touching any window.)*
- `[Data & scope]` A session is named for the connecting client's own process — its folder gives the project name, plus a short id. *(a client that could name itself could impersonate another, and the process behind a connection is readable without being told.)*
- `[Data & scope]` That name lasts as long as the client does, not as long as one call. *(each call opens its own line today, so per-call naming would rename a session constantly.)*
- `[Data & scope]` Callers reaching Proctor over the network through one front door share one session name and one waiting allowance. *(forced rather than chosen — one program serves them all and nothing on the connection tells them apart.)*
- `[Experience]` A waiting call is held open until its turn, rather than answered at once with a position the caller must re-send *(the materially different alternative)*. *(removing a run has to return that caller's call, so the call must still be open; and holding it open changes nothing for existing callers.)*
- `[Experience]` A call still waiting after forty-five seconds gives up, saying the machine was busy and where it stood. *(hosts commonly cut a tool call off around a minute, so the ceiling has to fire inside that or the caller gets the host's silent timeout instead of Proctor's reason.)* The ceiling is adjustable by the same kind of setting as Proctor's other switches.
- `[Experience]` A caller that has gone away keeps its place until its turn comes or the ceiling fires. *(a waiting connection cannot be seen to close from where the wait happens.)*
- `[Experience]` A reply that cannot be delivered is abandoned on a deadline rather than held indefinitely. *(a caller that has died must not tie up the way in.)*
- `[Experience]` A person's drop or clear returns that call saying a person removed it, not that a step failed. *(one is a signal to stop and ask, the other to retry.)*
- `[Experience]` One session may keep three runs waiting; a fourth is refused straight away. *(a session in a loop cannot starve the others.)*
- `[Experience]` Within a lane it is first come, first served. *(design.)*
- `[Experience]` A long sweep may hold its lanes for its whole length; only a person's Stop shortens it. *(running uninterleaved is the point, and the ninety seconds caps waiting, not running.)*
- `[Experience]` Hold stops any waiting run starting, the active session's next one included *(rather than only blocking other sessions, which is the leaning the design note records)*; the run in flight finishes. *(settles the first open question — the controls table's own "no waiting run starts" reads plainly as both, and a hold a session can jump by simply sending its next batch is not a control. Cheap to reverse if the leaning was meant to bind.)*
- `[Experience]` Removing a run takes effect at once, with no few-second undo. *(settles the second open question — the removed caller is being held open on that decision, so a delay is paid by the caller, and there is no undo drawn.)*
- `[Experience]` Clear removes every waiting run and leaves the active one alone. *(design.)*
- `[Experience]` Pause and Stop stay with the run, Hold and Clear with the list header, never side by side. *(design's verb-collision rule.)*
- `[Layout]` The expanded list shows every run that is not on the live line, each marked as running or as waiting with its position. *(settles the third open question without re-opening the mock — a run in another lane is not queued, and calling it queued is the understatement the design note flags.)*
- `[Layout]` The bar's count counts only the waiting ones. *(otherwise it overstates how blocked the machine is.)*
- `[Layout]` The live line shows the most recently started run, and Pause and Stop act on that one. *(one panel, one run in focus.)*
- `[Layout]` The bar is absent entirely when nothing is waiting. *(the queue costs nothing until there is contention.)*
- `[Operations]` A person's hold, clear or drop is recorded the same way a stop already is. *(these decide whether somebody's agent runs.)*
- `[Operations]` Proctor's own health report says how many runs are active and how many waiting, per lane. *(a wedged lane is otherwise invisible.)*
- `[Operations]` The scheduler runs whether or not the panel is on screen; only its display can be switched off. *(taking turns is correctness, not decoration.)*
- `[Operations]` The scheduling half is proved without a window, separately from the panel. *(brief; it is decision logic only.)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0016` before the planner picks this up.*

**Grounding note:** every kind of run — a batch, a replayed flow and a repeated sweep — already goes through one shared step loop, which is the single place a lane can be taken and given back. The set of steps that need the machine's attention is already named once in that same file, so classifying a run's lane needs no new judgement, and every batch already names the window it drives, so the app it contends for is known before it starts. Two facts run against the design as written and shaped the assumptions above. First, the agent's own turn-taking is not exclusion: it deliberately lets other work in every time a run pauses to wait for the screen to settle, which is exactly why the steps interleave today — so the lane has to be held by something separate, and "reads never wait" is true of the line, not of the agent's every instant. Second, a client opens a fresh way in for every single call and closes it again, so nothing about one connection identifies a session; the process on the other end does, and it is readable without being told, which is what makes the derived name possible at all. The remote front door has no such distinction available, which is why its callers share one name. This is Swift/macOS work; the gate is `swift build` + `swift test` (the web design and end-to-end stages do not apply), and the scheduling half is provable with no window on screen, matching how the existing pointer and policy logic is kept testable.

**Out-of-family spec review:** grok `grok-4.6` (xhigh, read-only) ran and returned 11 findings and a MATERIAL DEFECTS verdict — **8 accepted**, **2 accepted in part**, **1 rejected**. Accepted: that "reads never wait" overstated what the agent's turn-taking gives, so it now claims only that reads never join the line; that a lane needs a keeper independent of that turn-taking, held across the whole run; that a sweep must take its lane once for the whole call rather than per pass; that a lane must never be acquired after a run starts; that a release has to re-examine the whole waiting list or a run waiting on several lanes is never woken; that a lane must be given back however a run ends and reclaimed if its holder is gone; that a caller which has gone away cannot be detected from where the wait happens, so its place is held until its turn or the ceiling; and that an undeliverable reply needs a deadline. Accepted in part: its starvation finding (a run needing the whole machine now becomes a barrier once it reaches the head) while rejecting the half claiming the contended app is unknowable before a run starts — every batch is scoped to one named window, so it is known; and its point that a held-open call may outlive its host's own patience, which shortened the give-up from five minutes to ninety seconds and is recorded as an adjustable setting, while its reading of the shared remote identity as a human's decision was rejected as forced by the transport rather than chosen. Rejected: that the permission check could steal focus mid-run — it reads configured settings and a session token and shows nothing. Its observation that a long sweep can hold the machine for its whole length is now written down as an accepted decision rather than a discovery. Two earlier invocations hit the deadline mid-reasoning; the third, with the code facts quoted inline instead of read, completed in four minutes. Lane ran on grok as this repo requires, no downgrade, and Codex was not invoked.



**Assumptions review:** an independent in-family pass over the Assumptions block (would this default surprise the owner, reverse a locked decision, or hide an external question) failed two and passed the rest. Both were fixed rather than escalated. The give-up ceiling's own reasoning contradicted its number — ninety seconds sits past the host cutoff it cited, so the refusal it exists to deliver would have been lost anyway; it is now forty-five seconds, inside that cutoff. The Hold default was flagged as reversing the design note's recorded leaning, and it does: the note leans toward holding only other sessions while its own controls table reads as holding everything. Escalating it was rejected because the brief hands these three open questions to triage explicitly, and the choice is one cheap, reversible setting rather than an expensive external dependency — but the assumption now names the leaning it went against, so it can be vetoed knowingly.

---

## Progress — 2026-08-14

**In Review.** Branch `ai/pro-0016`, worktree `.worktrees/PRO-0016`. Plan:
`docs/plans/plan-PRO-0016.md`. Gate: `swift build` clean, `swift test`
**357 tests / 42 suites green** (315/35 at HEAD; +42 tests, +7 suites).

**The reentrancy fact, and why the keeper is separate.** `runSteps` is a method on
`Session`, which is a Swift actor, and actors are reentrant: isolation drops at
every settle and capture `await`, which is exactly why two clients' steps
interleaved. So the lane is held by `RunScheduler`, an actor of its own, for the
whole length of a call. `Session` owns one, because there is one `Session` and
every connection goes through it, so one session is one machine's worth of lanes.
This is proved rather than argued: with `Session.scheduled` short-circuited, the
recorded step order across two concurrent runs is `one, two, one, two, one, two,
two, one`; with it, one switch.

**Three lanes.** `.app(id)` always; `.global` when a step is synthetic, when the
batch asked for `foreground`, or when a step is a `raise`. Reads never reach
`runSteps` and so never reach the scheduler at all.

**One acquisition per call**, at the four entry points, after the permission gate
and re-checking it once the lane is ours. A sweep holds its lanes across every
repeat rather than rejoining the line between them.

**Identity from the peer process:** `LOCAL_PEERPID` at accept, `proc_pidinfo` for
the working directory and start time. Equality and the waiting cap key on the full
`pid:startTime`; the four-hex id is display only. Carried by a task-local set
inside the dispatching task, so it is never on the wire.

**Not machine-witnessable here:** the queue bar rendering, a click on Hold, Clear
or a row's drop, the expand, and the menu bar's mirrored count. `swift test` has
no window server and obscura is web-only. Code-complete against
`mocks/run-hud.html`; needs a human glance.

**One departure from the mock, deliberate.** The mock hides the bar whenever the
waiting count is zero. Natively that made Hold unreleasable: Hold lives inside the
bar, so holding the queue and then clearing it left the machine held with nothing
on screen to release it and every later run waiting out its ceiling. The bar now
stays while the queue is held and says which state it is in.

**Child work found, not done:** `proctor_apps.activate` brings an app to the front
and takes no lane, because the spec scopes queueing to a batch, a replay and a
sweep; there is no process-wide cap on held-open waiting calls, only the
per-session three and the ceiling.

**Out-of-family gates:** both ran on grok `grok-4.6` (xhigh, read-only), no
downgrade, Codex not invoked. Plan review: 10 findings, 3 accepted and folded in,
4 confirmed already held, 3 rejected with reasons. Completeness critic: 20
findings, 4 accepted and fixed (the unreleasable hold, `raise` taking the global
lane, the gate re-read after a wait, identity documented as not an authorisation
boundary), 13 rejected, 3 logged as child work. Both dispositions are written out
in full in the plan.
