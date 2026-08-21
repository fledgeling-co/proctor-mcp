# spec-PRO-0098 — The four nobody owns

**Status:** In Progress
**Brief:** `docs/features-to-triage/90-the-four-nobody-owns.md`
**Defects closed:** DEF-136, DEF-132, DEF-110, DEF-111
**Ids allocated:** CASE-0270..0289, DEF-140..149, REQ-076..078
**Branch:** `ai/pro-0098` off `ai/wave-9`

Four open defects that no wave-13 or wave-14 item names. They share nothing but their
orphanhood, so this spec keeps them as four independent clauses rather than pretending a
mechanism unites them. DEF-136 is first because it is the only one that can hide the other
three: a force-unwrap in a test aborts the runner, and an aborted runner prints no verdict
line at all, so every other result on the machine becomes unreadable.

## Baseline

`./scripts/test.sh` on `ai/pro-0098` at `4fc77da`: **1,977 tests in 242 suites, exit 0**
(`docs/test-campaign/evidence/PRO-0098/gate-before.txt`).

## A1 — every force-unwrap in the suite is classed, and the live ones cannot abort the runner

`grep -rn ')!' Tests` is the brief's denominator. It returns **29 lines**, of which one
(`CommandSurfaceTests.swift:47`) is prose in a comment recording PRO-0090's fix, leaving **28
real sites** — one more than the 27 the brief counted, because `ProctorCoreTests.swift` has
gained a site since the brief was written. The drift is recorded rather than smoothed over.

Every one of the 28 is classed into exactly one of two groups, and the classification is
published in `docs/test-campaign/evidence/PRO-0098/unwrap-census.md` with the reason per site:

- **unfailable by construction** — the initializer is total for the literal it is given, so no
  input reachable from this suite makes it return nil. Left as it is, with the reason recorded so
  a later sweep does not re-litigate it.
- **live** — the unwrap is a lookup, a parse or a crypto call against production code or
  production data, which is DEF-135's shape exactly: the regression the test exists to catch is
  the input that kills the runner instead. Converted to `try #require(...)`, or restructured to
  an expression that carries no unwrap.

**Acceptance:** the census names all 28 with a class and a reason; every site classed live no
longer force-unwraps; every site classed unfailable states which input space makes it total.

## A2 — the conversion is proved to buy something, not assumed to

One converted site is broken at what it unwraps and the suite is run. The recorded evidence
shows, for the same sabotage:

- **before** the conversion — signal 5, `0 tests`, `0 suites`, and `FAIL: no swift-testing
  verdict line`;
- **after** — a verdict line, a named failing test, and the honest failures elsewhere in the run
  still reported.

**Acceptance:** `docs/test-campaign/evidence/PRO-0098/def136-arming.txt` holds both runs with
their exit codes, and the two differ in whether a verdict line exists.

## A3 — `isApplying` is cleared by the restart, not by a stopwatch

`AgentModel.reprobeAfterGrant()` currently clears `isApplying` from
`DispatchQueue.main.asyncAfter(deadline: .now() + 1.2)`. The flag is instead cleared by the
event that ends the restart — the first probe after the restart that finds the agent reachable.

The 1.2 is **not raised**. It keeps the one job it was always doing correctly: it is the beat
before the *first* probe, because polling immediately races launchd. What changes is what
clears the flag afterwards.

The lifecycle is a pure value type in `ProctorCore` (`RestartWatch`), for the same reason
`AgentRecovery.decide` is: `ProctorUI` is an executable target with no test target, so a
decision that lives only inside `AgentModel` is a decision no test can reach.

A restart that never completes must still end, or the window claims "applying" forever. The
give-up is a **count of probes that came back unreachable**, not a wall-clock deadline, and when
it fires the window says the agent is down — which by then is the true statement.

**Acceptance:** a probe sequence that stays unreachable well past 1.2 s and then becomes
reachable leaves `isApplying` true throughout and clears it on the reachable probe; the
agent-down state is not drawn at any point before the give-up; the literal `1.2` is unchanged in
`AgentModel.swift`.

## A4 — REQ-055 witnessed as the negative it is

REQ-055 claims the suite writes nothing belonging to the operator. It declares
`filesystem-write`, records `observed`, names no provider, and its five cases CASE-0130..0134
all sit at `outcome` (DEF-110).

A witness for "nothing happened" is worth nothing without a control arm proving the same
instrument reports something when something happens. PRO-0089's `FileWitness` in
`PolicyStoreSeamTests.swift` already arms exactly that way, and is reused rather than duplicated:
it is lifted to a shared test helper so a second requirement can stand on the same recorder.

The witness sweeps the operator's own paths — the policy directory, the switch store and the
audit trail under the agent's real application-support root — reading existence, byte count,
mtime and sha256 either side of a suite-representative write, and reports **zero** changed. The
same recorder, in the same case, reports a **non-zero** count of changes on an injected path the
same call does write. That non-zero count is what the case records as its witness count, and the
note says plainly that the count is the control arm's and the claim is the zero.

**Acceptance:** REQ-055 carries a provider and at least one `pass` case at `effect-witness` with
a recorder, effect class `filesystem-write` and count ≥ 1; `campaign.py check` no longer names
REQ-055 under unwitnessed external effects; the control arm is watched failing.

## A5 — REQ-063 witnessed at the effect rather than the outcome

REQ-063's cases stat the resulting file, which is the outcome of the write. The effect is the
write itself. The witness records the directory across the write through a recorder that is not
`PolicyStore`: every path created, and the mode of each taken off disk through a fresh
`attributesOfItem` after the call returned, including the temporary that `Darwin.open` creates
and the replace consumes.

**Acceptance:** REQ-063 carries at least one `pass` case at `effect-witness` with a recorder,
effect class `filesystem-write` and count ≥ 1, armed by putting the pre-fix write back and
watching it red.

## A6 — the gates

`./scripts/test.sh` exit 0 with the suite count reported before and after.
`scripts/campaign/defect_gate.py` clean: no spec claims a defect still reading `open`, and no
registry value dropped by a merge.
`campaign.py check` re-run with its blocker list read as findings rather than as cases.

## What this spec does not do

DEF-033 (a survival-rate measurement), DEF-099, and every ratchet are out of scope, as the brief
states. `docs/feature-specs/LEDGER.md` is not touched. No gate, bound or threshold is edited to
make anything green.
