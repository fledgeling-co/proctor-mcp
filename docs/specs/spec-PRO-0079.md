# PRO-0079: seventy-eight tests that change state and never look at it

**ID:** PRO-0079 · **Status:** Ready to verify · **Created:** 2026-08-21
**Wave:** 11, brief 3 of 4 · **Brief:** `docs/features-to-triage/72-tests-that-mutate-and-never-read-back.md`
**Branch:** `ai/pro-0079` off `ai/wave-9` · **Depends on:** nothing · **Blocks:** PRO-0080
**Instrument:** `vacuity-check.py` blind pass, test-campaign 0.9.2

## The problem

The campaign's blind pass reports 78 tests that call a mutating verb and never read the state
back. Nobody knows what that number means. Seventy-eight genuine gaps would be the largest test
defect this repo has recorded; seventy-eight false positives would mean the pass is an instrument
that cannot be gated on. PRO-0080 has to decide which, and cannot until somebody has read the
tests.

The tool warns about exactly this failure mode in its own source: *a wrong vocabulary produces
more findings, so it reads as a thorough pass rather than a misconfigured one.* The number is
therefore evidence of nothing until it carries a measured error rate.

## Scope

Measure the false-positive rate on a declared sample, fix whatever the sample proves genuine, and
leave the instrument reporting what it reports. Do not tune the vocabulary until the count falls.

**Out of scope.** Raising the campaign's score — adding a read to a test that lacked one makes the
suite know more and changes no count. Deleting a test. Removing a mutator to reduce the count.
Re-litigating the three false-positive shapes the brief already identified.

## The sampling frame

78 findings across 30 files, bucketed by the trailing mutating verb.

| Stratum | Verbs | Findings | Read | Basis |
|---|---|---|---|---|
| Large | `act` 13, `unlock` 12, `release` 9, `set` 6, `claim` 6 | 46 | 25 | 5 per verb, `random.Random(20260821).sample` over each bucket sorted by (file, name) |
| Tail | 13 verbs at 1–4 each | 32 | 32 | census — every one read |
| **Total** | | **78** | **57** | 73.1% of the population |

The tail is censused rather than sampled because it is where an unusual shape would hide, and 32
bodies is cheap. The large strata are sampled because their contents are near-identical within a
bucket.

## A1 · The rate, with its denominator

Every sampled finding is read and classed. The verdict is recorded per finding with the evidence
that decided it, and the rate is stated with the denominator and a confidence bound on the
unsampled remainder. A rate quoted without the 21 findings nobody read is a rate that hides its
own gap.

**Acceptance.** `docs/test-campaign/evidence/PRO-0079/classification.tsv` carries 57 rows, each
with a shape and the read (or the reason there is none). `rate.txt` carries the arithmetic
including the bound. `REPORT.md` carries the rate and the denominator.

## A2 · The shapes, named and counted

The brief names three false-positive shapes. The sample is classed against those and against
whatever else it turns out to contain, because a shape nobody predicted is the more useful half of
the measurement. Each shape carries a count, so the report says which cause dominates rather than
that the findings are "mostly false positives".

**Acceptance.** Every one of the 57 rows carries one of a named, closed set of shapes; the counts
sum to 57; each shape is defined in `REPORT.md` by what in the check produces it.

## A3 · Genuine findings get their read added

A finding classed genuine is a test that arms a latch and never checks it — a test that would pass
if the latch never armed. It is fixed by adding the read the test is named after, never by
deleting the test and never by weakening an assertion. The suite is re-run after.

**Acceptance.** Every genuine finding names the read added and the file. Where the sample yields
none, that is stated with its denominator rather than left implicit, and no test is edited.

## A4 · The vocabulary moves only on evidence

`blindVocabulary` gains a reader only where a sampled finding proves a missing idiom, and an idiom
is a form used across the tree rather than one property on one fake. Each candidate is measured
two ways before it is added: how many files use it, and what it does to the count. The `why` field
records what was added, what was refused, and the measurement behind both, so nobody re-opens the
question from memory.

`#expect`/`#require` and bare `is` stay out. The mutator list is not touched: removing a mutator
reduces the count by blinding the pass, which is the failure this item exists to prevent.

**Acceptance.** `campaign.json.blindVocabulary.why` names every addition, its evidence and its
measured effect; the refusals are recorded with the numbers that refused them; the blind count
after the change is stated and is not zero.

## A5 · The instrument is proved able to fire

A rate of zero genuine findings is worth nothing from a pass that could not report one. Before the
rate is believed, the pass is armed: a read is removed from a test that currently has one, on a
copy of the tree, and the count must rise and name that test.

**Acceptance.** `evidence/PRO-0079/arming-control.txt` shows the before count, the edit, and the
after count with the newly-named test. The worktree's own `Tests/` is not the copy that was cut.

## What this does not change

No production source. No test is deleted or weakened. The campaign score does not move. The
remaining findings stay in the tool's output: a blind pass that reports zero because its
vocabulary was tuned until it did is worth nothing, and the count after this item is still a
count somebody has to read the report to interpret.
