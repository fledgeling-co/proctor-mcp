# Spec PRO-0172 — A Defect's Status Word Means One Thing

**Brief:** `docs/features-to-triage/164-a-defect-status-word-means-one-thing.md`
**Status:** Ready for AI
**Created:** 2026-08-26
**Surfaces:** SURF-029
**Defects:** DEF-221

## Context & Purpose
The reckon skill decides the owing set from a defect's status word, so a wrong word removes a piece of
work from the only report that counts it. DEF-221 read `fixed` while its own note closed the
second of its two arms with "RECORDED rather than fixed", and the two captures that arm names
are still one image. The vocabulary is also open: four words are in use, nothing defines them,
nothing refuses a fifth, and `closed` is used once for what `fixed` means.

## Acceptance Criteria
1. The status words are enumerated in one place, each with what it means for the owing set.
2. A check refuses a status word outside that list, and prints the words it accepts.
3. A check refuses a `fixed` defect whose note declares an unfixed remainder, and the phrases it matches are quoted from rows somebody read.
4. That check prints its denominator: how many notes were examined and how many phrases matched.
5. DEF-033 either takes the word it means or `closed` is defined and kept.
6. Both checks are armed in each direction against a fixture, so a check that cannot fire is distinguishable from one that found nothing.

## What this deliberately does not do
It does not parse intent. A matcher tuned until it finds nothing is the failure this repository
refuses elsewhere, so the phrase list stays small, comes from read rows, and prints what it
examined.

**Moves:** none.
