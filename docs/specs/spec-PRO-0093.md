# PRO-0093 — A dead peer holds the queue, and a swallowed event says nothing

**Brief:** `docs/features-to-triage/86-a-dead-peer-holds-the-queue.md` (Wave 13, brief 6 of 6)
**Status:** ready to verify
**Branch:** `ai/pro-0093` off `ai/wave-9` · **Lane:** headless `./scripts/test.sh`
**Registry ranges:** CASE-0290..0309 · REQ-079..081
**Defects:** DEF-026, DEF-027, DEF-150, DEF-152 · **Found and left open:** DEF-151
**Allocated:** DEF-150..159. This item does not write `docs/feature-specs/LEDGER.md`.

Two defects a person meets as "Proctor has stopped working". The brief asked for DEF-027 to be
settled as a defect or as an instrument limit before anything changed. It is a defect, and the
evidence that settles it is the same evidence that recorded it.

## DEF-027 is a defect, and the ceiling the brief named does not apply

The brief's second reading was that `PersonInput.isAPerson` requires `sourcePid == 0`, so a helper
process could not forge a hardware event and the yield could not have fired. Read against source,
that ceiling governs a different path. `isAPerson` is applied in `ContentionMonitor.considerInput`
(`ContentionMonitor.swift:193-202`), which is the passive `NSEvent` monitor. The block's swallow
path does not go through it: `TakeoverOverlay.swift:451` calls `onPersonInput`, which
`SessionTakeover.swift:137` binds to `ContentionMonitor.noteUserInput`, and that method
(`ContentionMonitor.swift:226-229`) writes `lastUserInputAt` with no filter at all, under a comment
saying so — "the caller has already applied a stricter one". A helper's swallowed events were
therefore admissible as a person, and REQ-007's `inconclusive` ceiling is untouched by this item.

What was missing is when the field is read. `contentionProbe` runs only from
`RunControl.checkpoint`, and `SessionAct.swift:375` calls that **before** each step and nowhere
else. Two consequences follow, and both are visible in the recorded runs:

| Evidence | Steps | Step durations | Swallowed | Why no yield |
|---|---|---|---|---|
| `docs/test-campaign/evidence/witness/a45b-act.json` | 1 | 74,673 ms | 6 | the only checkpoint ran before the step; nothing sampled after it |
| `docs/test-campaign/evidence/witness/a4-act.json` | 3 | 18,602 / 20,157 / 17,716 ms | 24 | `ContentionWatch.inputWindow` is 10 s and every step outlives it, so a swallow was stale at the next boundary |

`a45b` is the decisive one. A single-step batch has exactly one checkpoint and it runs before the
step, so no event swallowed during that batch can reach a probe — the outcome does not depend on
timing, load, or what the helper posted. Neither result carries a `yields` key.

The fix has two halves, because the two failures are different. A batch needs a reading after its
last step, and a swallow needs to survive until something reads it.

## What changes

**REQ-081 — input the takeover block swallows is reported as a yield record and a held reason.**

`ContentionSample` gains `userInputSince`: a person's input arrived since the previous sample.
`ContentionWatch.conditions` treats it as `.userInput` holding, alongside the existing decay
window. `ContentionMonitor.sample()` sets it by comparing `lastUserInputAt` against the moment of
the previous sample, so the signal is an edge that survives until it is read rather than a
timestamp that expires unread. The decay window is unchanged and is still what ends the hold: a
swallow from 60 seconds ago opens a hold, and the next sample releases it after `releaseDelay`,
so a stale reading produces a record without parking the run on it.

`SessionAct` runs `contentionProbe` once after the last step, before `disarmContention`. That is
the boundary `a45b` never had.

`disarmContention` now calls `runControl.release(run:)` for the ending run. Without it a run that
ends while yielded leaves its entry in `RunControl.yields` forever: `paused` stays true, `pausedAt`
is never cleared, and `heldBy` goes on naming a run that has finished. That path is reachable today
and becomes common with the probe above, so it is closed here rather than left. Recorded as
**DEF-150**.

**REQ-079 — a lane held by a process that no longer exists is released.**
**REQ-080 — a peer that is alive but not talking keeps its lane.**

`RunSessionIdentity.key` is already `"<pid>:<start-time>"`, minted in `SessionIdentity.fromPeer`
from `LOCAL_PEERPID` and `proc_pidinfo`. `PeerLiveness` (new, in `ProctorCore`) parses that key and
crosses it with a probe of the pid, returning `alive`, `gone` or `unknown`. `RunScheduler.acquire`
sweeps the active runs through it before deciding anything, so a stranded slot is reclaimed by the
very call that would otherwise be refused as `queueBusy`.

Three rules, and each exists because reclaiming a live run's lane would cut the run off:

- The probe reports `noSuchProcess` only on `kill(pid, 0)` failing with `ESRCH`. A process that
  exists but cannot be described — a permission failure, a `proc_pidinfo` that returns short — is
  `unreadable`, and `unreadable` never reclaims.
- A pid that exists with a **different** start time is `gone`, because pids are reused and the
  peer that took the lane is not the process wearing its number now.
- A key that does not parse is `unknown` and never reclaims. `RunSessionIdentity.unattributed`
  carries the key `"unattributed"`, and every test in the suite that acquires a lane without a real
  peer takes that path, so the conservative default is also the one the suite exercises.

Slowness, a breakpoint and a blocked syscall all leave the process in the table with its original
start time, so all three read `alive`. That is the distinction the brief asked for and it is tested
against a real process rather than a fake.

## What this does not do

**Waiting runs are not swept, and the reason is that they are already bounded.**
`RunQueuePlan.defaultWaitLimit` is 45 seconds and `deadlineTask` fires on it whatever the caller is
doing, so a waiter whose peer died leaves on its own. An active run has no such bound, which is why
it is the one that strands. Sweeping waiters would add a second refusal path for a caller that has
already gone.

**No heartbeat and no new wire field**, as the brief requires. Liveness is derived from the key the
identity already carries.

**REQ-007's `inconclusive` ceiling is not revisited.** Nothing here can post at pid 0, so whether
the passive monitor's `considerInput` path fires for a real hand on a real keyboard is still
unproved by any instrument in this repo. Recorded on **DEF-151** with what would settle it: a
physical keypress, or a driver that posts at the HID layer rather than through `CGEvent`.

**The staleness half of DEF-027 is fixed by the edge flag, not by the window.** `inputWindow`
stays at 10 seconds. Lengthening it would hold runs on old evidence, which is the failure the
window exists to prevent.

## What the gates said

`./scripts/test.sh` exits 0 at **2,003 tests in 244 suites**, against **1,977 in 242** measured on this
branch before any change. `defect_gate.py claims` and `defect_gate.py dropped` both exit 0.
`campaign.py check` exits 1 on four inconclusive cases and three `observed` requirements with no
effect-witness; it exits 1 on the same four and the same three against the registries at HEAD, so
this item adds no finding — it moves the census from `examined=27 witnessed=23` to
`examined=29 witnessed=25` with `unwitnessed=0` either way. Full output:
`docs/test-campaign/evidence/PRO-0093/gates.txt`. The seven sabotages and what each reddened:
`docs/test-campaign/evidence/PRO-0093/sabotages.txt`.

## Defects

| Id | State | What it is |
|---|---|---|
| DEF-026 | fixed | A run whose MCP peer dies keeps the agent queue. Closed by the reclaim in `RunScheduler.acquire`; armed by S1, which reproduces the original refusal verbatim. |
| DEF-027 | fixed | Events swallowed by the takeover block produced no yield and no held reason. Closed by the arrival flag and the reading after the last step; armed by S4, S5 and S7. |
| DEF-150 | fixed | A run that ended while yielded left its entry in `RunControl.yields`, so `heldBy` went on naming a finished run and `pausedAt` never cleared. Armed by S6. |
| DEF-151 | open (recorded) | Whether the `userInput` yield fires for a real hand on a real keyboard is still unproved: nothing in this repo can post at pid 0, which is what `PersonInput.isAPerson` requires on the passive monitor path. This item did not change that path and does not close it. |
| DEF-152 | fixed | `FakeContention.noteUserInput` counted the call and stopped, so no test of a swallowed event could reach anything downstream of the counter — which is why `swallowedInputYields` asserted a counter and was named for a yield. The double now carries the signal the real monitor carries. |
