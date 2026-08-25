---
sources: [REQ-076, REQ-077, DEF-099, DEF-110, DEF-111, DEF-132, DEF-135, DEF-136]
status: retired
validated-by: REQ-028, REQ-047, REQ-055, REQ-063, REQ-076, REQ-077 via CASE-0032, CASE-0074, CASE-0075, CASE-0076, CASE-0077, CASE-0078
validated-rungs: effect-witness, metamorphic, outcome
validated-provider: StreamCapture in ProctorAgent/Capture/StreamCapture.swift
validated-through-defect: REQ-047 via DEF-033; REQ-028 via DEF-099
---
# Twenty-seven unwrapped tests, a fixed timer, and two witnesses the rung wants

**Wave 14, brief 2.** DEF-136, DEF-132, DEF-110, DEF-111. Four open defects no item covers. Do
DEF-136 first: it is the only one that can hide every other result on the machine.

## DEF-136 — a force-unwrap in a test can take the whole runner down

PRO-0090 measured what this class costs. Under one mutation, a `command(id)!` on a literal id gave
`Fatal error: Unexpectedly found nil`, signal 5, and **0 tests, 0 suites and no verdict line at
all** — `scripts/test.sh` exiting 1 on "no swift-testing verdict line" while masking four honest
failures the kill-switch test had already recorded. The same mutation with `try #require` reported
1,963 tests, 12 issues, and every guard naming what it found.

`grep -rn ')!' Tests` outside the file PRO-0090 fixed finds **27 sites across nine files**:
AuditChainTests 11, AuditChainWiringTests 4, ProctorCoreTests 3, TUIHistoryPaneTests 2,
ToolchainTests 2, SwitchSettingsTests 2, MenuBarReadinessTests 1, GuestInventoryTests 1,
RunHUDCharacterAssetTests 1.

**They are not equally live, and the brief will not pretend otherwise.** `TimeZone(identifier: "UTC")!`
cannot fail. A lookup into a catalogue by a literal id can, and that is the shape that bit. Class
each of the 27: unfailable by construction, or convertible to `try #require`. Convert the second
group; record the first with the reason it cannot fail, so a later reader does not re-litigate it.

There is a live reason to do this now beyond the principle. A full run on the merged tree died on
SIGTRAP in `CommandSurfaceTests.presenceIsUnconditional` with no verdict line, then passed alone and
reported on two subsequent full runs. That function carries no force-unwrap of its own, so the
transient crash is unexplained — and a suite with 27 unswept traps in it is a suite where "the run
died" cannot be distinguished from "the run found something".

**Prove the conversion is worth something rather than assuming it.** Pick one converted site, break
what it unwraps, and show the suite now reports a verdict and a named failure where it previously
reported nothing.

## DEF-132 — a restart cleared by a stopwatch rather than by the restart

`AgentModel.swift:460-471`. `reprobeAfterGrant()` sets `isApplying`, restarts the agent, and clears
the flag from a `DispatchQueue.main.asyncAfter(deadline: .now() + 1.2)` — a fixed delay rather than
the restart's own lifecycle. A restart that outlives 1.2 s leaves the window with `isApplying` false
and the agent still down, drawing the red "the background agent is not answering" at a person who
did exactly what the window asked.

This repo has already replaced two oracles of this shape — `ScreenRecordingProbe`'s bound timer and
`CuaLineReader`'s monotonic clock — and the pattern holds here: clear the flag on the event that
ends the restart, not on a clock. A machine under load is precisely when a restart takes longer than
1.2 s, and precisely when a person is least able to tell a slow restart from a broken one.

Do not raise 1.2 to a larger number. That makes the window wrong less often on this machine and says
nothing about what it is waiting for.

## DEF-110 and DEF-111 — two requirements whose cases sit one rung below their claim

Both declare `filesystem-write` and both rest entirely on `outcome` cases.

**REQ-055** — *"running the test suite does not read or write any state belonging to the operator of
the machine it runs on"* — records `observed` with **no provider at all**, and its five cases
CASE-0130..0134 are `outcome`.

**REQ-063** — *"the policy file is created with mode 0600 by the write that creates it"* — names
`PolicyStore.write` as provider, which opens with `Darwin.open(O_WRONLY|O_CREAT|O_EXCL|O_TRUNC, 0o600)`
and replaces. Its cases stat the result, which is the outcome rather than the effect.

The rung wants a recorder that is not the code under test, an effect class, and a non-zero count.
For REQ-063 the recorder is the filesystem read back through a fresh descriptor with the mode taken
off disk; for REQ-055 it is the operator's own paths observed unchanged while the suite runs, which
PRO-0089 already did once by fingerprinting size, mtime and sha256 either side.

**Read REQ-055's claim carefully before witnessing it**, because it is a negative: the effect it
names is one that must *not* happen. A witness for "nothing was written" needs a control arm
proving the same instrument reports a write when one occurs, or its zero is structural. PRO-0089's
`FileWitness` arms itself exactly that way and is the thing to reuse.

If either genuinely cannot reach the rung, `vacuous` or a recorded ceiling is the honest answer —
not a reclassification to `none` to clear the gate.

## The conversion contract

- All 27 sites classed, the convertible ones converted, the unfailable ones recorded with the reason.
- One converted site broken to show the suite now reports where it previously did not.
- `isApplying` cleared by the restart's own completion, with a test that a restart longer than 1.2 s
  no longer draws the agent-down state, and the 1.2 not raised.
- REQ-055 and REQ-063 each witnessed with a recorder, an effect class, a non-zero count and a
  control arm, or recorded at a ceiling with the instrument named.
- `./scripts/test.sh` green with the suite count before and after.

## What this brief does not do

It does not touch DEF-033, which is a survival-rate measurement and closes when the number moves.
It does not close DEF-099. It does not raise any ratchet.
