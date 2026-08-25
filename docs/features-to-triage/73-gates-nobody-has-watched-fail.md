---
sources: [REQ-001, REQ-017, REQ-046, DEF-018, DEF-020, DEF-024]
status: retired
---
# Two gates nobody has watched fail, and one record that drifted

**Wave 11, brief 4 of 4.** Sequence it after `72`, which measures whether the blind pass is
trustworthy, and after `70`, which gives the seed-strengthen control something real to check.

## Why this is one brief and not three

All three items are the same defect wearing different clothes: a check whose passing state has
never been proved to mean anything. The campaign's own rule is that an assertion nobody has
watched fail is not known to bite, and it applies to the campaign's instruments as much as to the
product's tests.

## Item 1 — the census gate has never been shown to go red

`vacuity-check.py` ships `--seed-strengthen <REQ-ID>` precisely as this control: it strengthens a
requirement's claim and the gate should refuse it. It has never been run against this campaign.

Until it has, the census's three passes are in the position the campaign spent this wave getting
tests out of. `unclassed` and `uncensused` both currently report `examined=44 findings=0` and
`examined=22 findings=0`, and a pass reporting zero is indistinguishable from a predicate that
cannot fire — which is exactly how the default vocabulary read before it was replaced
(`examined=1857 mutating=1 blind=1`, a dead predicate that looked like a clean run).

Run it against `REQ-017` once `70` has built that requirement's witness, and against one
requirement classed `none`, so both directions are covered. Record the output verbatim.

## Item 2 — `ProctorAgent` has never been mutation-sampled

Mutation survival is measured and thin, and the report says so: **11 of 188 sites under one seed**,
with 29 selected mutants unrun because another build on the machine made their kills unreadable.
Every one of those sites is in `ProctorCore`. A later run took 24 mutants over `TUISurface`,
`CLISurface`, `StatusChecks` and `RunHUDMenuBar` from 14 killed / 10 survived to 24 killed / 0
survived, and both runs are kept as `mutation-survival-before.txt` and `-after.txt`.

`ProctorAgent` is the package that holds the session, the queue, the overlay, the actuation
backend and every guest adapter, and no mutant has ever been generated in it. That is the largest
untested claim about the suite's strength, and it is the one the wave's own defect record argues
for: DEF-018 was *half of ProctorCore's sampled mutants survived*, found only because somebody
sampled.

Three operating facts, each measured the hard way:

- **Nothing may edit the tree while `mutate_swift.py` runs.** It compiles the whole package per
  mutant and picks up whatever is in the working directory.
- **A 900-second timeout under CPU contention produces false kills.** The runner scores a timeout
  as killed. Survivors are trustworthy in both directions; a kill under contention is not.
- **Do not copy the resulting number into `.warrant/suite-health.json`.** `mutation_measured: false`
  there is correct and is not stale — it means warrant's own assay has not run, and a value copied
  into a generated file is a second source that drifts.

Chasing equivalent mutants is out of scope. `RunHUDGate.onSegment`'s `<=` boundary is already
recorded as one, and a suite contorted to kill an unkillable mutant is worse than the survivor.

## Item 3 — the defect registry (STALE: done at wave 11a's merge, verify instead)

**Corrected 2026-08-21 by PRO-0080.** This item was written before wave 11a merged and it describes
a job that has since been done, larger than as described. What follows is what is actually true.

Wave 11a's merge reconciled the registry: it backfilled wave 10's four defects into
`inventory.json`, renumbered PRO-0078's five from DEF-020..024 to DEF-025..029, and flipped DEF-019
to `fixed`. So the one-line fix this item asked for is already made, and the "other 18" it asked to
audit is now 28. **DEF-024 does not exist and that is deliberate** — the backfilled four took
DEF-020..023 while PRO-0078's fifth moved to DEF-029, so 23 + 5 = 28 with a gap in the sequence and
nothing recording why.

Verified rather than redone: the inventory holds 28 records, and of the ids present in both
registries there are **zero status disagreements**. That work is sound.

**What the verification found instead.** The drift has reversed direction. `REPORT.md`'s defect
table held **18 of the 28** — DEF-001..005 and DEF-025..029 appeared nowhere in it, not in the table
and not in the prose. All five open defects were among the missing ten, so a reader of the report
saw **no open defect at all**, under a heading reading "Eighteen defects, all eighteen fixed". Same
failure mode as the one this item was written for, running the other way: a ledger nobody re-read
against the thing it describes. Recorded as DEF-031 and fixed by completing the table.

## The conversion contract

- `--seed-strengthen` run in both directions with the output pasted into `REPORT.md`, not
  summarised.
- A `ProctorAgent` mutation sample with its denominator, its seed, and its unrun count named. A
  partial sample honestly reported is the deliverable; a full sweep is not required and the machine
  contention makes one unreliable anyway.
- Every surviving mutant either gets a test that kills it or a recorded reason it is equivalent.
- `inventory.json` and `REPORT.md` agreeing on every defect record. ~~19~~ 32 after PRO-0080:
  28 inherited plus the four this item found. Zero status disagreements, neither registry ahead of
  the other.
- The four campaign gates re-run afterwards — `check`, `strict-check`, `capture-lineage --gate`,
  `vacuity-check --gate` — with `evidence.html` regenerated and `export-warrant` run.

## What this brief does not do

It does not author `.warrant/warrant.toml`. That charter needs a defect-class taxonomy and a risk
limit, both of which are the reader's call rather than a derivable default, and inventing them
would put a number on the run's own risk tolerance that nobody chose.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-001, REQ-017
- surface: SURF-001, SURF-002, SURF-013
- cases: CASE-0001, CASE-0002, CASE-0019, CASE-0020, CASE-0038, CASE-0059
- rungs reached: effect-witness, metamorphic, outcome
- provider: none
