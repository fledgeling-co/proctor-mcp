# PRO-0106: Instruments that do not prove their own step

**ID:** PRO-0106
**Status:** Ready for Plan
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/99-instruments-that-do-not-prove-their-own-step.md`

## Feature description

Four defects in three instruments, all of the form *the tool performed a step and published the result
without establishing the step happened*. `mutate_swift.py` splices by byte offset and never reads back
(DEF-207); `mutation_seam_arm.py` scores `armed = code != 0`, so a process dying in setup counts as red
(DEF-208); `cmd_take` stores filenames while `sweep()` computed digests, so the witness cannot say what
was in the files (DEF-205); and `resolve_tree` prints a path missing its first character in its own
refusal, writing that phantom permanently into `run.json.dirty_inputs` under `--allow-dirty` (DEF-206).

## What and why

DEF-207 is the worst of the four and the reason is worth stating precisely. An anchor-string mutator
that aborts at least **reports** INERT, so something in the log disagrees with the verdict. An
unconditional splice by byte offset writes regardless, so there is nothing to report and **a
wrong-offset write is silent** — the harness grades pristine or wrongly-edited code and nothing
anywhere contradicts it. **A survivor has two readings: the guard is decorative, or the mutation never
happened.** PRO-0092's twenty survivors were each shown to land by a verifier reconstructing all 24
mutants against the tree the run used; that is a verifier's proof, not the instrument's, and the next
sample does not get one.

The repair for DEF-207 is porting a check this same repository already contains: its sibling arm
asserts an occurrence count of 1 and re-reads, requiring `after` present and `before` gone.

## Acceptance sketch

- Every instrument proves its own step before grading the outcome: the edit is read back, the artifact
  is opened, the verdict line is confirmed to exist.
- Where a step cannot be proved, the result is `inconclusive` naming why, rather than a pass or a fail.
- An arming with no verdict line is `inconclusive`, not armed — a process that died in setup is not a
  test that failed.
- The witness stores what `sweep()` already computes.
- An instrument's own refusal message is part of its output and carries a test.

## Assumptions made writing this

- Assuming an instrument owes the same standard it applies to its subject: a mutation harness demanding
  a test prove itself, while not proving its own edit, is holding its subject to a rule it does not keep.
- Assuming DEF-200 and DEF-215 ride along as smaller separate rows rather than justifying their own
  item: arming CASE-0392 with an artifact closes one, and the other is a decision about two retired
  items rather than a repair.

## Defects

DEF-205, DEF-206, DEF-207, DEF-208, DEF-200, DEF-215.
