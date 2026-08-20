# PRO-0077 — effect witnesses off glass

Four `effect-witness` cases, CASE-0059..CASE-0062, closing REQ-017, REQ-020, REQ-015 and REQ-009.
Everything here was produced by `Tests/ProctorAgentTests/EffectWitnessTests.swift` on branch
`ai/pro-0077`.

| File | What it is |
|---|---|
| `witness-run.txt` | The passing run of the four witnesses, verbatim. Each test contains its own sabotage half, so a pass here is the live effect and its zero-count sabotage in one measurement. |
| `arming-run.txt` | The arming run. Two changes per witness: the non-zero count assertions were inverted so the run prints the number each recorder actually saw, and each sabotage's broken target was replaced with the working one so the zero-check is watched failing. 12 issues across 4 witnesses. |
| `gate.txt` | `./scripts/test.sh` over the whole package, with its verdict line. `scripts/test.sh` owns the verdict: a bare `swift test` exits 1 while reporting every test passing, because the pipe eats the exit code. |

## The counts, and where each came from

| Case | Req | Effect | Recorder | Count | Read out of |
|---|---|---|---|---|---|
| CASE-0059 | REQ-017 | `subprocess` | sentinel files written by each `/bin/sh` child with its own `$$` | 2 | `(livePIDs.count → 2) < 0` |
| CASE-0060 | REQ-020 | `subprocess` | same, at the simctl call site | 2 | `(pids.count → 2) < 0` |
| CASE-0061 | REQ-015 | `filesystem-write` | the trail file's bytes, read with a fresh `FileHandle` and opened with `AuditSeal` | 3 | `(lines.count → 3) == -1` |
| CASE-0062 | REQ-009 | `ipc` | client connections the server answered, plus the peer identity the server read off each accepted descriptor | 3 | `(answered → 3) == -1`, `(identities.count → 3) == -1` |

## The lane's ceiling, stated rather than left silent

This is the **portable floor**, not the kernel bar. `dtrace` and `eslogger` need privilege this
suite does not have and SIP does not grant, so there is no `execve` census, no eBPF and no
syscall trace behind any of these four. What is here instead cannot pass when nothing runs: a
real spawned process writing a sentinel the test reads back off the filesystem, a real file read
with a fresh descriptor rather than through the writer's own API, and a real `AF_UNIX` listener
answering real connections.

## What the four do not claim

A witness proves the effect, not its correctness — a recorded spawn says a process ran, not that
the argv was right. A count is not a distribution: one non-zero count on one run is one draw.
And none of the four touches production source; all four drive seams that were already in the
tree.

## What the census reads before and after

Measured with `campaign.py check --json` against the same inventory, with only
`cases.json` swapped:

| | before | after |
|---|---|---|
| oracle mix, `effect-witness` | 0 | 4 |
| external claims witnessed | 0 of 22 | 4 of 22 |
| requirements claiming an effect with no witness | 16 | 12 |

`campaign.py check` still refuses, and that is the gate working: the twelve that remain are
outside this item, which the brief puts out of scope in its own words. No requirement's effect
class was changed to `none` to clear it.

## Two things found by measuring, neither of them fixed here

**The brief's count of the gate's list is short by four.** It reads "twelve requirements are
named by the gate", and the gate's *printed* list is capped at twelve. The real count was
sixteen. PRO-0078's brief names REQ-002, 003, 004, 006, 007, 008, 012 and 014 — eight of the
twelve that remain. That leaves **REQ-023, REQ-024, REQ-027 and REQ-028** named by no Wave 11
item at all: three `ipc`, one `subprocess`, one `device`. Flagged for the orchestrator, not
taken on here.

**`Session.runBounded` can return exit 0 with empty stdout under load.** Its output drain is
bounded at `group.wait(timeout: .now() + 5)` after the child exits, on `DispatchQueue.global()`.
On a machine running several test suites at once the drain can be starved, and the caller sees a
successful child that produced nothing — which `LumeInventory.parse` reads as an empty inventory
rather than as a failed read. Observed on 2026-08-21 during this item's first full gate run:
`proctor_guest` action `list` answered `count=0` against a script that prints one guest. The same
class is already recorded in the tree, in the comment on `IOSDeviceList.parse`, dated 2026-08-20.
Pre-existing, out of this item's scope, and the reason both subprocess witnesses stand on the
child's filesystem effect rather than on its stdout.
