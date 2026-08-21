# PRO-0080: two gates nobody has watched fail, and one record that drifted

**ID:** PRO-0080 · **Status:** Ready to verify · **Created:** 2026-08-21
**Brief:** `docs/features-to-triage/73-gates-nobody-has-watched-fail.md` (Wave 11, brief 4 of 4)
**Branch:** `ai/pro-0080` off `ai/wave-9` · **Lane:** headless, `./scripts/test.sh` + a long mutation run
**Depends on:** PRO-0077 (merged, built REQ-017's witness), PRO-0079 (merged, measured the blind pass)
**Ledger id:** already allocated by the orchestrator. This item does not write `docs/feature-specs/LEDGER.md`.

## The problem

Three items, one defect wearing three sets of clothes: **a check whose passing state has never been
proved to mean anything.** The campaign's own rule is that an assertion nobody has watched fail is
not known to bite, and it binds the campaign's instruments exactly as it binds the product's tests.

The precedent is measured, not hypothetical. The census's `blind` pass shipped with a default
vocabulary that read `examined=1857 mutating=1 blind=1` — a dead predicate wearing a clean run's
clothes. Wave 11a then found `capture_with_manifest.py` writing `file` plus a dict target while
`capture-lineage.py` read `path` plus a string, so **every row that writer ever produced was
invisible to the gate checking it**: the gate was not lenient, it was reading an empty population
and exiting 0. Three instruments in three waves, each reporting zero for a structural reason.

## Scope

Three items, delivered at the scope the brief intends and no wider.

1. Run `vacuity-check.py --seed-strengthen` in both directions and paste both outputs **verbatim**
   into `REPORT.md`, then close the hole that running it exposes.
2. Mutation-sample `ProctorAgent` — a partial sample, honestly reported with its denominator, its
   seed and its unrun count. Every survivor gets a killing test or a recorded reason.
3. Verify the defect-registry reconciliation wave 11a already performed, and correct the brief,
   which is stale on it.

**Out of scope, stated so it stays out.** `.warrant/warrant.toml` — that charter needs a
defect-class taxonomy and a risk limit, both the reader's call rather than a derivable default;
inventing them would put a number on the run's own risk tolerance that nobody chose. Copying the
mutation figure into `.warrant/suite-health.json`, where `mutation_measured: false` is correct and
means warrant's own assay has not run. Chasing equivalent mutants — `RunHUDGate.onSegment`'s `<=`
boundary is already recorded as one, and a suite contorted to kill an unkillable mutant is worse
than the survivor. A full ProctorAgent sweep, which the machine's contention makes unreliable.

## Item 1 — the census control, and the half of the census it does not reach

### What the control does

`vacuity-check.py --seed-strengthen <REQ-ID>` is the skill's own arming rule turned on its own
gate: it takes a requirement that currently clears the census, replaces its declared effect class
with one no case witnesses, drops its `provider`, re-runs, and requires a red. A strengthened
constraint that still clears proves the gate reads nothing. It restores the registry either way.

The control is only meaningful if the census is **clear before** it runs. `_census_clear` is
`not (unclassed or uncensused)`; if the census were already red, `after` would be red for a reason
the mutation did not cause and the tool would still print *the gate bites*. Measured before the
run: `unclassed examined=45 findings=0`, `uncensused examined=22 findings=0`, gate exit 0. The
`before=clear` in both outputs below is therefore load-bearing and was checked, not assumed.

### Both directions, run

Run against **REQ-017** (`subprocess`, the requirement whose witness PRO-0077 built and merged) and
against **REQ-001** (classed `none`). Both go red. The registry's SHA-256 is identical before and
after both runs, so *restored byte-for-byte* is a measurement rather than a claim. Verbatim output
in `REPORT.md` §*The census gate, watched failing*.

### What running it exposed — DEF-030

The census has **two** exact passes at requirement level. `--seed-strengthen` sets
`effect: "packet-filter"` and pops `provider`, which is precisely the `uncensused` predicate. It
therefore fires `uncensused` and **only** `uncensused` — in both directions, for every requirement,
whatever its starting class. Measured per pass:

| seeded mutation | `unclassed` findings | `uncensused` findings |
|---|---|---|
| REQ-017 → `packet-filter`, provider dropped | 0 | 1 |
| REQ-001 → `packet-filter`, provider dropped | 0 | 1 |

So after the shipped control runs green, `unclassed` is still a pass reporting `examined=45
findings=0` that nobody has watched go red — the exact position the control exists to get a gate
out of, surviving the control. This is recorded as **DEF-030** against the campaign's instrument,
not against Proctor.

### The second control — CASE-0074

`scripts/campaign/seed_unclass.py` is the missing half, built to the same contract as the shipped
one: strengthen the *specification* rather than the census record by removing a requirement's
`effect` field, require `unclassed` to go red, and restore the registry byte-for-byte whatever
happens. Removing `effect` from REQ-017 — whose text names `virtualized` machines and `lume`
adapters, so the vocabulary must hit it — takes `unclassed` from 0 findings to 1.

It is a separate script rather than a patch to the vendored skill, because the skill lives in a
plugin cache this repo does not own and a fix there would be reverted by the next plugin update
with nothing saying so.

## Item 2 — `ProctorAgent` has never been mutation-sampled

### Why this package

The existing figure is **11 of 188 sites in `ProctorCore` under one seed**, with 29 selected
mutants unrun because another build on the machine made their kills unreadable. Every mutation site
ever scored in this repo is in `ProctorCore`. `ProctorAgent` holds the session, the queue, the
overlay, the actuation backend and every guest adapter — the largest untested claim about the
suite's strength — and the wave's own record argues for sampling it: **DEF-018 was *half of
ProctorCore's sampled mutants survived*, found only because somebody sampled.**

Measured pool: **3,189 mutation sites across 84 files.** That is 17× `ProctorCore`'s 188, so any
sample this lane can afford is a small fraction and the denominator is stated on every number.

### The three operating facts, honoured

- **Nothing edits the tree while `mutate_swift.py` runs.** It compiles the whole package per mutant
  from the working directory, and it refuses to start on a dirty tree. The spec and plan are
  committed before the run starts, and no edit lands until it finishes.
- **A timeout under CPU contention is scored as a kill.** `run_suite` returns `(False, "timeout")`
  and the caller scores anything not-passed and not-build-failed as killed. **Survivors are
  trustworthy in both directions; a kill under load is not.** Load average is recorded at the start
  of the run and every mutant's wall-clock seconds are kept, so a reader can see which kills came
  from a slow machine.
- **The number does not go into `.warrant/suite-health.json`.** `mutation_measured: false` there is
  correct and is not stale.

### What the sample owes

A denominator (`sites`), a seed, a count run, an unrun count, and a per-operator breakdown — all of
which `mutate_swift.py` already writes. Survivors are handled one of two ways and the distinction
is kept sharp:

- **killed by a new test** — the behaviour was unwatched and now is;
- **recorded, with its reason** — and the reason is one of *equivalent* (the mutant cannot change
  observable behaviour) or *uncovered-by-lane* (the site needs a window server or TCC grant this
  headless lane does not have). Those are different claims and conflating them would report a
  coverage hole as a mathematical impossibility.

Results in `REPORT.md` §*ProctorAgent, sampled* and `docs/test-campaign/evidence/mutation-agent.json`.

## Item 3 — the defect registry, verified rather than redone

**The brief is stale.** It describes flipping DEF-019 and auditing 18 other records. Wave 11a's
merge already did more than that: it backfilled wave 10's four defects into the inventory,
renumbered PRO-0078's five from DEF-020..024 to DEF-025..029, and flipped DEF-019 to `fixed`. The
brief's item 3 is corrected in place to say so.

**Verified, not assumed.** `inventory.json` holds **28** defect records: DEF-001..023 and
DEF-025..029. DEF-024 is a deliberate gap left by the renumber — PRO-0078's fifth defect moved from
DEF-024 to DEF-029 while the backfilled four took DEF-020..023 — and nothing recorded that, so a
reader counting sequentially would report a missing record. A `note` in the inventory now says why.

**What the verification found, and the brief did not anticipate — DEF-031.** The 18 ids present in
both registries agree on status exactly, zero disagreements, so wave 11a's reconciliation is sound
in the direction it ran. But `REPORT.md`'s defect table holds **18 of the 28**: DEF-001..005 and
DEF-025..029 appear nowhere in it. The drift the brief named has reversed direction — the inventory
is now ahead of the report by ten records, five of them `open`, and **a reader of the report sees no
open defect at all.** The table is completed to 28 with the statuses the inventory carries.

## Acceptance

| # | Clause | How it is judged |
|---|---|---|
| A1 | `--seed-strengthen` run against REQ-017 and against one requirement classed `none`, both `before=clear after=red`, exit 0 | Verbatim output in `REPORT.md`; `before=clear` corroborated by the pre-run gate reading `findings=0` on both passes |
| A2 | The registry is restored byte-for-byte by both runs | SHA-256 of `inventory.json` identical before and after; `git diff` empty |
| A3 | The `unclassed` pass is shown able to go red | `seed_unclass.py` takes it 0 → 1 finding and exits 0; a control run against a requirement the vocabulary cannot hit is refused rather than scored |
| A4 | `ProctorAgent` mutation sample reports sites, seed, run, unrun, killed, survived, unbuildable | `evidence/mutation-agent.json` summary block; denominator 3,189 named in the report |
| A5 | Every survivor is killed by a new test or recorded with a reason typed *equivalent* or *uncovered-by-lane* | One row per survivor in `REPORT.md`; each killing test named and each reason argued |
| A6 | A new killing test is shown to fail on the mutant and pass without it | Per-test arming record: the mutant re-applied, the suite run, the named test red, the mutant reverted |
| A7 | `inventory.json` and `REPORT.md` agree on all 28 defect records | Reconciliation script prints `in inventory not report: []`, `in report not inventory: []`, `status disagreements: []` |
| A8 | The four campaign gates re-run green afterwards, `evidence.html` regenerated, `export-warrant` run | `check`, `strict-check`, `capture-lineage --gate`, `vacuity-check --gate` with exit codes recorded; `campaign.py check` is expected to exit 1 on PRO-0083's ten unwitnessed requirements and that is the gate working |
| A9 | `./scripts/test.sh` green, and the verdict read from its exit code | Exit code printed; no XCTest summary line read as a verdict |

**A8's expected non-zero is stated up front so it cannot be quietly re-read as a failure.**
`campaign.py check` exited 1 at the close of wave 11a — 11 of 22 external effects witnessed, ten
still unwitnessed, and those ten are exactly PRO-0083's set. This item witnesses no requirement, so
that exit stays 1 and is the gate working, not a regression this item caused.

## Registry ids

Allocated by the orchestrator and disjoint from the other wave 11b runners. Discovering ids by
reading the registry is what produced three collisions in wave 11a — three runners each read a
registry and each correctly took the next free id.

- Cases: **CASE-0072..0079**
- Defects: **DEF-030..034**
- Requirements: **REQ-046..047**
