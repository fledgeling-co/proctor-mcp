# Goal: close every open row in proctor-mcp's ledger and reconciliation

- **slug:** ship-remaining-work
- **armed:** 2026-08-26 20:15 local
- **project:** /Users/lukerhodes/Dev/proctor-mcp
- **bound:** 60 turns / 2026-08-28 20:00 local / stuck after 8 identical failures

## Objective

Take the three open ledger rows and the four broken reckon rows to a terminal
state, and keep every standing gate green while doing it. The finish line is not
a drained ledger — `ship-fleet` has seven recorded runs that reported a backlog
implemented and verified while the honest answer to "does every feature work" was
no in all seven. It is a reconciliation that a tool nobody in this run wrote
agrees with, re-anchored against the code as it is at that moment.

## Worklist

| ID | Item | Gate | Status |
|---|---|---|---|
| F-001 | PRO-0160 — Control Census Across Every Surface. | `control_census.py --gate` | **merged 2026-08-27.** 40 of 40 surfaces declare a list checked against the source that draws it; 17 of 82 controls actuated, up from 4 of 34 across 2 surfaces. |
| F-002 | PRO-0161 — Raise or Record Every Case Below the Effect Rung. `rung_routing.py` routes 36 of 43; 7 need a person to read them one at a time. Its declared figure `warrant.surface-conformance` 84.0 → 100 has not moved and `figure_ledger.py` enforces that. | `finish-line`, plus `python3 scripts/campaign/rung_routing.py docs/test-campaign --gate` | pending |
| F-003 | PRO-0162 — Cut or Record Every Durable Boundary. | `finish-line` | **44 of 50, and the finding is bigger than the count.** `boundariesCut` is asserted on the journey and no case names a boundary, so an asserted cut and a cut with a case behind it are indistinguishable. JRN-006's provider-effect was recorded uncut while CASE-0061 was already witnessing it. Six remain; the spec lists what each owes. |
| F-004 | DEF-221 — two byte-identical capture pairs still stand: `sweepK-theme-before.png` with `sweepL-wedged-t1.png` (670a93988315), and `sweepL-wedged-t7.png` with `-t14.png` (5c7d4535e70c). | `finish-line` | pending |
| F-005 | DEF-339 — the Maestro lane's second outbound connection, the one `MAESTRO_CLI_NO_ANALYTICS=1` does not stop. | `finish-line` | pending |
| F-006 | DEF-340 — 106 of 514 cases carry no lane; `cli` and `mcp-stdio` are declared and carry none. | `finish-line` | pending |
| F-007 | DEF-341 — the PTY latch check read a list shared across five scenarios and passed on another's work. | `finish-line` | **fixed 2026-08-26** — cause named, check scoped to its own scenario, three fixed sleeps replaced with bounded waits on observables |
| F-008 | DEF-344 — the PTY probe types before the TUI has taken raw mode. | `finish-line` | **cause measured 2026-08-27, fix owed.** The pty echoes `ps` back on a failing run, which a terminal in raw mode does not, and `requests_served` never rises — the keys went into a terminal with no reader. Same class as F-007, one layer earlier. The fix needs a readiness signal to wait on; the scenario now reports both observables so a failing run says which happened. |

Total: 8. One fixed.

## What closing each of the four defects may not mean

The reader chose **close all four** over declaring the last two as standing
limits, so these are work items rather than exemptions. Three of them have a
cheap wrong answer, and taking it would clear the gate while making the registry
less true:

- **DEF-340 may not be closed by inference.** Only 9 of the 106 name a lane
  readably in their own evidence; assigning the other 97 from what a case looks
  like is how a lane hides, which is the sentence already in the defect. The
  acceptable close is a mechanism that records a lane where one can be read, a
  back-fill limited to what the evidence actually says, and the remainder either
  measured or the defect re-scoped with a case standing behind the new scope.
- **DEF-341 may not be closed on a pass that was expected to fail and did not.**
  Its reproduction was re-run twice on a clean tree at `75a7a8c` and came back
  clean both times. That is evidence the recorded reproduction does not hold at
  this commit, not evidence the ordering dependency is gone. Closing it needs
  either the real cause named with something that fires on it, or the row
  re-scoped to what is true with a case behind that.
- **DEF-221 may not be closed by deleting a capture.** The byte-identical pairs
  are the evidence for the defect; removing a member removes the finding.
- **DEF-339's remaining half may be genuinely unfixable from here.** Proctor
  stops the connection it controls and discloses the one it cannot. If the
  second connection cannot be stopped without rewriting third-party config —
  which PRO-0023 rules out — say so with the measurement and re-scope the row.

**If a close is only reachable by one of those routes, park the item and record
why.** A run that ends on the stuck bound with a ledger naming the wall it hit is
a better outcome than one that ends green over a laundered row.

## Declared, and checked so the set cannot grow

`goal_reconciliation.py` reads registry ids **only** from the block below, not
from anywhere else in this file — the worklist above names the very defects the
run has to close, and a whole-file scan would declare them by accident and stop
requiring the work.

<!-- declared:begin -->
Two requirements are `unmeasured` and are expected to stay that way. Neither is
a gap in effort; each is a limit somebody established, and a gate demanding they
move could never pass.

- **REQ-025** — Tahoe guest window rendering. Deferred against an upstream Apple
  bug, FB21748086 / trycua #870. Nothing in this repository can move it.
- **REQ-072** — the two recorded ceilings on how far Proctor's plane disclosures
  reach, including wave 9's covered-target rule. Recorded on purpose; asking it
  to move is asking for the re-label the ratchet exists to refuse.
<!-- declared:end -->

Every other `broken` or `unmeasured` row is undeclared by construction, so the
`finish-line` gate names it until it closes. Adding an id here is a decision a
person makes and a reader can see, and it is the only way the exempt set grows.

## Gates

Run by the guard at the end of every turn, in order, judged on exit code alone.

| Name | Command | Passes when |
|---|---|---|
| build | `swift build` | the tree compiles |
| standing-gates | `./scripts/campaign/standing_gates.sh` | all 17 repo-side gates exit 0 (~26s) |
| finish-line | `python3 scripts/campaign/goal_reconciliation.py --brief docs/goals/goal-ship-remaining-work.md` | ledger outstanding 0, reckon undecided 0, every broken and unmeasured row declared above |
| tests | `./scripts/test.sh` | the Swift suite exits 0 — currently 2,179 tests in 276 suites, ~135s |

`finish-line` re-anchors the reconciliation on every run rather than reading the
last one, because a reckoning against a stale campaign is a reckoning about a
codebase that no longer exists. It resolves the installed reckon by version
rather than pinning one: the first draft sorted on the wrong path component, ran
reckon 1.0.0 against a 1.7.0 registry, and reported 136 undecided rows against
the 3 that are real. A gate reading an old tool is worse than a missing one,
because it answers.

`standing-gates` reads each gate's exit code from the gate, never through a pipe.
That is PRO-0166's finding applied to the thing that would suffer most from it.

## Blocked-item policy

- **Do not ask.** Record the question under **Open questions** below and take the
  reversible path, naming the assumption. Anything destructive, irreversible,
  outward-facing or costly stops and waits regardless.
- **Park rather than launder.** An item that can only be closed by weakening its
  own check is parked with the reason, and the row stays open.
- **A gate that cannot fail is a defect in the gate.** Arm every new check in
  both directions before relying on it, against the real tree where one exists
  rather than a fixture.
- **`main` is the integration branch and is AHEAD of `origin`. Merge means merge
  to local `main`; never push.**

## Resources

| Resource | Reserved for this run | Conflicts with |
|---|---|---|
| 5 booted iOS simulators | no | `EphemeralSimulatorTests` creates its own scratch device and deletes it; preflight warns but the suite passed with all five up |
| `proctor-guest` lume VM | no | the guest-glass lane; leave both VMs stopped and delete neither |
| `~/Library/Application Support/app.fledgeling.procter` | never delete anything under it | the installed agent's state |
| `anvil-mac-node` | belongs to another project | never delete, prune, rename or export it |

## Delivery

- **Driver:** `/ship-fleet:ship-fleet`, in-session.
- **Model / effort:** claude-opus-5 / high.
- **Concurrency cap:** 5 concurrent agents where any are used. ship-fleet 2.9.0
  records 92 agents dying silently in one window, 88 of them at exactly 180.0
  seconds, and treats a request to run wider as a request to lose work quietly.
- **Out-of-family review lane:** grok-4.6 at xhigh; when it returns
  `402 Payment Required`, substitute `agy --model gemini-3.7-flash-high` with
  `--new-project` from a neutral cwd, and name the substitution in the artifact.
  Codex stays off.
- **If an agent dies:** `workflow-resume` before relaunching anything.

## Stop conditions

- All four gates pass and the worklist has no pending item.
- 60 turns, or 2026-08-28 20:00 local, or 8 identical failing fingerprints.
- The stuck bound is the honest exit for F-006 and F-007 if their only close is a
  laundered one. A ledger naming the wall is the result in that case.

## Open questions

_None outstanding. Two things worth a reader knowing rather than deciding:_

**The stall watcher fires on a long turn, not only on a dead run.** It read the
ledger as stale after 25 minutes while turn 1 was still working. The ledger only
moves at a Stop event, so from outside, one long turn and a dead session look
identical — which is the gap the watcher exists to cover and also the reason it
cannot tell those two apart. Read a STALL line as "check", not "it died".

**DEF-344 is a new open row that this run created by fixing DEF-341**, and the
`finish-line` gate names it as undeclared. That is the gate working: a broken row
cannot be waved through by the run that found it.
