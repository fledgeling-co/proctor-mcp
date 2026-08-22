# Instruments that do not prove their own step

**Wave 17, brief 3.** DEF-205, DEF-206, DEF-207, DEF-208. Four defects in three instruments, all of
the form *the tool performed a step and published the result without establishing the step happened*.

## The four

- **DEF-207.** `mutate_swift.py`'s `apply()` splices by byte offset and never re-reads, so it cannot
  report that the substitution happened. Its own sibling, `mutation_seam_arm.py`, asserts an
  occurrence count of 1 and then re-reads requiring `after` present and `before` gone — **the repair is
  porting a check the same repository already contains.**
- **DEF-208.** That sibling then scores `armed = code != 0`, so a process that dies in setup counts as
  red. CASE-0461's trapping mutant gave signal 5, **zero verdict lines**, and the suite's own
  `FAIL: no swift-testing verdict line`. The case is right only because its log proves the named test
  was running when it trapped, and the rule that scored it cannot tell that from a process that never
  ran one.
- **DEF-205.** `sweep()` computes a byte count and sha256 per file; `cmd_take` stores only the names
  and the count. The witness can say two files appeared and cannot say what was in them, and a file
  replaced between sweeps would be invisible. It also let a case claim four files with digests where
  the artifact held two names and none — and `campaign.py` counted that case witnessed **without
  opening the artifact.**
- **DEF-206.** `git()` strips its output, so ` M docs/…` arrives as `M docs/…` and a `[3:]` slice
  removes the first character of the path. A modified `docs/test-campaign/cases.json` is refused as
  `ocs/test-campaign/cases.json`, and with `--allow-dirty` that phantom is written permanently into
  `run.json.dirty_inputs`.

## Why DEF-207 is the worst of the four

An anchor-string mutator that aborts at least **reports** INERT, so something in the log disagrees
with the verdict. An unconditional splice by byte offset writes regardless, so there is nothing to
report and **a wrong-offset write is silent** — the harness grades pristine or wrongly-edited code and
nothing anywhere contradicts it.

This is not hypothetical. A mutator elsewhere the same night aborted because its anchor occurred in
the source *and* in the test asserting it, ran against pristine code, and published a live guard as
decorative. **A survivor has two readings: the guard is decorative, or the mutation never happened.**

PRO-0092's twenty survivors were each shown to land — by a verifier reconstructing all 24 mutants
against the tree the run used and confirming every recorded offset holds the recorded `before` text.
**That is a verifier's proof, not the instrument's, and the next sample does not get one.**

## The principle these four share with brief 97

An instrument owes the same standard it applies to the thing it measures. A mutation harness that
demands a test prove itself, while not proving its own edit, is holding its subject to a rule it does
not keep. So:

1. Prove the step before grading the outcome — read back the edit, open the artifact, check the
   verdict line exists.
2. Where the step cannot be proved, the result is `inconclusive` and names why, rather than a pass or
   a fail.
3. An instrument's own error message is part of its output and is worth a test.

## One more, small and separate

**DEF-200.** `CASE-0392` records `armed: false` on the grounds that arming it would mean breaking the
design of record. A verifier broke it on a scratch basis anyway and the check reds at line 397, so the
case is armable and the registry **understates its own strength**. The flag was not flipped, because
the probe left no evidence file and no artifact means no verdict. Arming it properly, with an
artifact, closes the row.

**DEF-215.** Four ledger rows carry no spec file, so two briefs have no artifact that could cite them.
Recorded open rather than fixed: writing retrospective specs for two retired items is a separate
decision and belongs to whoever takes it.
