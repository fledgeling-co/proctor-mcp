# Plan — PRO-0093

**Spec:** `docs/specs/spec-PRO-0093.md` · **Tier:** Standard · **Lane:** headless `./scripts/test.sh`
**Registry ranges:** CASE-0290..0309 · DEF-150..159 · REQ-079..081

Baseline before any change: `./scripts/test.sh` exit 0, verdict line recorded in step 0 below. Every
step names the assertion that fails without it.

## 0 — Record the baseline

Run `./scripts/test.sh` on the branch as it stands and keep the verdict line. The suite count before
and after is part of the brief's contract, and a count taken after the work has started cannot
answer it.

## 1 — Peer liveness as a value (`Sources/ProctorCore/PeerLiveness.swift`, new)

`PeerLiveness.peer(fromKey:)` parses `"<pid>:<start-time>"` into a pid and a start time, returning
nil for anything else. `PeerLiveness.verdict(key:probe:)` crosses that with a probe result and
returns `.alive`, `.gone` or `.unknown`.

Probe results are `.running(startedAt:)`, `.noSuchProcess`, `.unreadable`. The mapping: no parse is
`.unknown`; `.noSuchProcess` is `.gone`; `.running` with a different start time is `.gone`;
`.running` with the same start time is `.alive`; `.unreadable` is `.unknown`.

Pure, so the pid-reuse case is provable without reusing a pid. Tests: `PeerLivenessTests`, one per
row of that mapping plus the malformed keys (`"unattributed"`, `"12"`, `"a:b"`, `"-1:0"`).

## 2 — The real probe (`Sources/ProctorAgent/SessionIdentity.swift`)

`SessionIdentity.probe(pid:)` returns the three-case result. Existence comes from `kill(pid, 0)`:
0 is running, `ESRCH` is `.noSuchProcess`, any other errno is `.unreadable`. The start time comes
from the existing `startTime(of:)`, and a zero reading is `.unreadable` rather than a start time of
zero, because `proc_pidinfo` returns 0 for both a failure and an impossible value.

`kill(pid, 0)` succeeds for a zombie, so an unreaped child reads `.alive`. That is the conservative
direction and it is stated on the function.

## 3 — Reclaim in the scheduler (`Sources/ProctorAgent/Session/RunScheduler.swift`)

`RunScheduler` gains `peerProbe: @Sendable (String) -> PeerLiveness.Verdict`, defaulting to the real
one, and `reclaimDeadPeers()` which force-releases every active run whose identity key reads `.gone`.
`acquire` calls it once, before the fast path, so the reclaim happens on the call that would
otherwise be refused. `forceRelease` already publishes and promotes, so a waiter behind the dead run
is woken by the existing path.

The hook `onReclaim: (@Sendable (Int) -> Void)?` is called per reclaimed ticket; the agent sets it
to `RunControl.shared.release(run:)` in `main.swift`, so a dead run's automatic hold does not outlive
its slot.

Acceptance (CASE-0290, CASE-0291): a test spawns a real child process, builds its identity key from
`SessionIdentity.startTime(of:)`, acquires a lane as that identity, kills the child and waits for it
to leave the process table, then acquires the same lane from a second identity and reads
`scheduler.snapshot()` back. The recorder is the snapshot, not a value the test wrote. The live-peer
twin keeps the child running and asserts the second acquire is refused and the first run is still in
`snapshot().active`.

## 4 — The swallowed event survives until it is read (`Sources/ProctorCore/Contention.swift`)

`ContentionSample` gains `userInputSince: Bool = false`. `ContentionWatch.conditions` inserts
`.userInput` when it is true, in addition to the existing window test. Default false, so every
existing construction of `ContentionSample` is unchanged.

`ContentionMonitor.sample()` sets it by comparing `lastUserInputAt` with the timestamp of the
previous sample, and records the new sample time under the same lock.

Acceptance (CASE-0292, CASE-0293): a sample carrying `userInputSince` with `lastUserInputAt` set 60
seconds in the past yields `.userInput`, and the following sample without the flag releases it after
`releaseDelay`. The sabotage is deleting the new clause in `conditions`, which must redden both.

## 5 — A reading after the last step (`Sources/ProctorAgent/Session/SessionAct.swift`)

Call `contentionProbe(run: foregroundRun, step: steps.count)` after the step loop and before
`disarmContention`. `disarmContention` gains `runControl.release(run: RunScheduler.currentRun)` so
the ending run's automatic hold leaves the latch with it (DEF-150).

Acceptance (CASE-0294..0296): a single-step batch whose block swallows an event reports a
`YieldRecord` with reason `userInput` in the act result, and the scheduler publishes a held
attribution while it holds. Sabotage: unbind `onPersonInput` in `takeoverBind`, and the record must
disappear.

## 6 — Make the fake carry what the real monitor carries (`Tests/ProctorAgentTests/YieldWiringTests.swift`)

`FakeContention.noteUserInput` counts and returns; its `sample()` serves a script that no swallow
can reach. That is why the existing test `swallowedInputYields` asserts the counter and stops there:
the instrument cannot carry the signal end to end, so nothing downstream of the counter was ever
checked. Give the fake the real monitor's behaviour — a swallow stamps `lastUserInputAt` and raises
`userInputSince` on the next sample — and extend the existing test to assert the yield record it
claims in its own name. Recorded as **DEF-152**.

## 7 — Registries and gates

Append CASE-0290..0299 to `docs/test-campaign/cases.json` at the rung each stands on; every case
naming a sabotage records what was cut and what reddened. Flip DEF-026 and DEF-027 to `fixed` with
the test that closes each, and add DEF-150, DEF-151, DEF-152. Add REQ-079..081 to
`inventory.json`. Then run `scripts/campaign/defect_gate.py` and `campaign.py check`, and report
both verbatim.

## Open decisions

**The staleness half is closed by an edge flag rather than by sampling inside a step.** Sampling
during a step would notice a person while the step is still running, which is closer to what the
yield is for; it needs a poller inside the actuation path and a decision about whether a step can be
interrupted mid-flight, which is larger than this item. The edge flag guarantees the record and the
held reason the brief asks for, and defers the parking question. If a run should get out of a
person's way *during* a 74-second drag rather than at the end of it, that is a separate item and
step 4 is where it would attach.

**A reclaim races a run that is about to finish.** A dead peer's run could be reclaimed at the same
moment its own task unwinds and calls `release`. `LaneTicket.claimRelease` already makes the second
one a no-op and `forceRelease` guards on `active.removeValue` returning non-nil, so the race is
absorbed rather than prevented. No new lock.

**Not measured:** whether a shim that exits leaves a zombie long enough for the probe to read it as
alive. The tests spawn and reap their own child, which is the controlled case; the production case
depends on whoever parented the shim.
