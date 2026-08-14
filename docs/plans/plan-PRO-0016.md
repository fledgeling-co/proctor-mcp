# Plan — PRO-0016: Multi-session queue

**Spec:** `docs/specs/spec-PRO-0016.md` · **Design:** `docs/design/run-hud-queue.md`,
`mocks/run-hud.html` (binding) · **Tier:** Large · **Branch:** `ai/pro-0016`

## The shape

Three new pieces and four seams into code that exists.

| Piece | Where | Why there |
|---|---|---|
| Lane classification + the waiting list | `Sources/ProctorCore/RunQueue.swift` | Pure arithmetic over steps. Provable with no window and no actor. |
| The keeper | `Sources/ProctorAgent/Session/RunScheduler.swift` | An actor **separate from `Session`**. `Session` is reentrant — isolation drops at every settle and capture `await`, which is why two runs interleave today — so the lane cannot be held by the session's own turn-taking. |
| Session identity | `Sources/ProctorAgent/SessionIdentity.swift` | Needs `LOCAL_PEERPID` on the accepted fd; agent-side by necessity. |
| Queue model + layout | `Sources/ProctorCore/RunQueue.swift`, `RunHUD.swift` | Same rule the panel already follows: decisions in Core, drawing in the agent. |

## 1 · Lanes (Core)

```
RunLane = .app(String)   // the driven window's app handle id
        | .global        // the single system event stream
```

A run's demand is fixed **before it starts** and never grows:

- always `.app(<driven app>)`
- plus `.global` when any step is in `Session.syntheticKinds` (`dragPath, hover, click, key`),
  or the batch asked for `foreground: true`, or any step is a `raise` (added at the
  completeness critic: raising moves the ground under everybody else's synthetic events).

`foreground` is this codebase's own name for "the target must be in front", and a run that
brings an app forward changes where every other session's clicks land — so it takes the
global lane and the app lane together, atomically. Reads never reach `runSteps`, so they
never touch the scheduler at all: that is the whole of "reads never join the line".

## 2 · The keeper (agent)

`actor RunScheduler`, owned by the one `Session` rather than reached for as a global:
one session is one machine's worth of lanes, and every connection goes through it.

- `acquire(lanes:identity:summary:) async throws -> LaneTicket` — grants immediately when
  every lane is free; otherwise appends to one arrival-ordered waiting list and suspends on
  a continuation.
- `release(id:)` — idempotent, frees the lanes, then re-examines **the whole waiting list**,
  not only the lane that just freed (a run waiting on two lanes is otherwise never woken).
- Scan rule, in arrival order: grant an entry whose lanes are all free; on the first entry
  that cannot be granted, stop if it needs `.global` (the barrier that stops a trickle of
  single-app work starving it), otherwise reserve its lanes and carry on so two apps run
  in parallel while FIFO holds within each lane.
- `hold(_:)` / `clear()` / `drop(id:)` / `snapshot()`.
- Caps: **3** waiting runs per session (a fourth is refused at once), **45 s** give-up
  ceiling (`PROCTOR_QUEUE_WAIT_LIMIT`, same shape as `PROCTOR_HUD_PAUSE_LIMIT`).

`LaneTicket` is a class whose `deinit` posts an idempotent release, so a lane comes back
however its run ends — returned, thrown, or its holder gone.

**New refusals.** `AgentError.Code.queueBusy` for the ceiling and the per-session cap;
`haltedByPerson` (already exists, already says "stopped or held") for a drop or a clear,
because a person removed it and that is a signal to ask, not to retry.

## 3 · Identity, derived from the peer process

At `accept()` in `Server.swift`: `getsockopt(LOCAL_PEERPID)` for the pid,
`proc_pidinfo(PROC_PIDVNODEPATHINFO)` for its working directory, `PROC_PIDTBSDINFO` for its
start time. Project name = the cwd's last component; the four-character id is a stable hash
of pid + start time, so it survives the shim's new-socket-per-call
(`MCPServer.callAgent` does `let client = SocketClient(); defer { client.disconnect() }`)
and lasts as long as the client process rather than as long as one call. Never read from
the request: a connection that could name itself could impersonate another in the very UI a
person uses to decide whether to stop it.

Carried to the run through a **task-local** set inside `Server.dispatchBlocking`'s detached
task, not a new parameter on six call sites and never on the wire.

## 4 · Seams

- `act`, `flowReplay`, `stability`, `computerUse` — acquire **after** the policy gate (a
  refused run never takes a place) and **once for the whole call**, so a sweep's inner
  passes never rejoin the line. Via one `Session.scheduled(lanes:summary:_:)` helper.
- `RunHUDModel` gains `queue: RunQueueModel`; `RunHUDState` folds a scheduler snapshot in.
- `RunHUDLayout` gains the bar (33pt) and the expanded body (35pt header + 2 + 28·n + 10),
  slotted between the trail and the footer where PRO-0015 left the gap.
- `RunHUDContentView` draws the bar and the body and hit-tests `queueBar`, `hold`, `clear`,
  `drop(i)`. Hold/Clear sit in the list header, never beside Pause/Stop, never sharing a word.
- `proctor_doctor` gains a `queue` block (active and waiting per lane).
- `proctor_recent_activity` gains the waiting count so the menu bar mirrors it.
- Audit: a hold, a clear and a drop are recorded the way a stop already is.

## 5 · Acceptance clauses → tests

Swift package; the gate is `swift build` + `swift test`. 315/35 green at HEAD must stay green.

| Clause | Test |
|---|---|
| Two sessions on the same app serialise, both complete | `RunQueueTests` + agent wiring test |
| Two sessions on different apps run concurrently | scheduler grants both |
| A synthetic run blocks everything | global lane exclusion |
| Reads never join the line | no scheduler call on snapshot/find/capture |
| Whole batch holds its lane; a sweep holds across passes | one acquire per call |
| Hold stops the next start, active run untouched | `hold()` |
| Clear returns every waiting call as person-initiated | `haltedByPerson` |
| Drop returns one; the rest keep position | position renumbering |
| Ceiling fires at 45 s naming the position | injected clock |
| Fourth waiting run refused at once | cap |
| Lane released however the run ends | throw + deinit |
| Release re-examines the whole list | two-lane waiter woken |
| Global barrier stops starvation | ordered scan |
| Identity derived, never supplied | request field ignored |
| Bar absent when nothing waits; count counts waiting only | `RunQueueModel` |

Not machine-witnessable here: the bar rendering, a click on Hold/Clear/drop, the expand
animation. No window server in `swift test`; obscura is web-only.

---

## Out-of-family plan review — 2026-08-14

grok `grok-4.6` (xhigh, read-only) ran on a compacted inline prompt and returned
10 findings. Lane ran; no downgrade; Codex not invoked, as this repo requires.

**Accepted and folded in (3).** A lost wakeup if a run joins a non-empty list but
contends with nobody: the slow path now runs the same whole-list scan on enqueue,
so a run against an idle app starts at once instead of sitting until some
unrelated release woke it. The give-up timer is cancelled the moment a waiter
leaves the list, rather than sleeping out the ceiling behind a granted run. And
identity is now judged on the full `pid:startTime`, with the four-hex id demoted
to display only, so a short-id collision cannot merge two clients' waiting
allowances.

**Confirmed already held (4), and the invariants are now written down rather than
implied.** Grant-or-enqueue happens in one await-free stretch inside the actor;
every path removes a waiter before resuming it, so a continuation cannot be
resumed twice; the scan's lane reservation is a local of one decision and never
scheduler state; and the explicit release on both exits is the real path with
`deinit` as the backstop, which is what it recommended.

**Rejected with reasons (3).** That a `.global` run should exclude every app lane:
the design's own model is that an accessibility press is IPC to one process, so a
run on a different app is unaffected by what is in front, and queueing it would
make Proctor feel broken for the common case. That the global set misses
`type`: a foreground `type` is covered by the `foreground` clause. That a
disconnected waiting caller should be dropped: triage already settled it — the
close cannot be seen from where the wait happens, so it keeps its place until its
turn or the ceiling.

## Completeness critic — 2026-08-14

grok `grok-4.6` (xhigh, read-only), same lane, on the built feature. First
invocation hit a 120s wall; the retry at 300s completed. 20 findings.

**Accepted and fixed (4).**

1. **A held queue with an empty list could not be released.** Hold lives inside
   the bar and the bar was hidden whenever nothing was waiting, so holding the
   queue and then clearing it left the machine held with nothing on screen to let
   it go: every later run would have waited out its ceiling and nothing would
   have said why. The bar now stays while the queue is held and says so.
2. **A `raise` step now takes the global lane.** It brings a window forward,
   which moves the ground under every synthetic event anybody else is posting.
3. **The permission gate is read again once the lane is ours.** A run can wait
   the whole ceiling, and a TTL-bounded approval that admitted it may have lapsed
   in that time; the authority that matters is the one held when the app is
   touched, which is the rule a repeated sweep already follows between repeats.
4. **Identity is documented as not an authorisation boundary.** The 0600 socket
   is; identity decides a label and an allowance, which is why an unreadable peer
   gets a plain name rather than a refusal.

**Rejected (13)** as misreadings of what was built (the CUA plan is translated up
front so its lanes are known; the cap and equality already key on one field; the
ticket has exactly one holder) or as decisions triage settled (a dead waiter
keeps its place; a long sweep holds its lanes; reads interleave at the actor by
design).

**Logged, not acted on (3), and carried to the report as child work.** There is no
process-wide bound on waiting calls, only a per-session one and the ceiling.
`proctor_apps.activate` brings an app to the front and is not scheduled, because
the spec scopes queueing to a batch, a replay and a sweep. And `queueBusy` covers
both the ceiling and the cap under one code, with the two remedies carrying the
difference.
