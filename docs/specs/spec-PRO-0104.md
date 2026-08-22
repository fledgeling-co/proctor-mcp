# PRO-0104: An input the check cannot classify

**ID:** PRO-0104
**Status:** Ready for Plan
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/97-an-input-the-check-cannot-classify.md`

## Feature description

Three instruments across two repositories each meet an input they have no rule for and guess rather
than say so. DEF-201 and DEF-203 are the same sentence twice — a scanner that reads a whole document
for a token, with no exclusion for fences, comments or struck-through text, cannot tell a citation
from a mention of one. DEF-202 is the same failure in a status vocabulary, and it is the one that
shows why the class matters: it fails in **both** directions and only one is visible.

## What and why

An unrecognised input is currently resolved by a default. Over-reporting announces itself — an
inflated backlog makes somebody look. Under-reporting does not: a gate selecting its population by a
single status string drops rows meaning *still broken* out of the obligation entirely and prints a
clean count over a quietly smaller population. **A clean green is a worse failure than an inflated
backlog, because nothing about it asks to be checked.** Widening one such gate elsewhere surfaced
five real defects and took owing from 19 to 24.

## Acceptance sketch

- Every input the three instruments meet is classified explicitly as one thing or the other.
- An input that cannot be classified is a **finding naming the input and its count**, never a default
  in either direction and never a silent pass.
- The two scanners exclude fenced blocks, HTML comments and struck-through text before matching, with
  a fixture per kind rather than one in aggregate.
- `partially-fixed` stays in the owing set. It is not a member of the not-remaining-work words: a half
  still broken owes a reproduction for that half, and retiring it would make the tool under-report for
  the first time.

## Assumptions made writing this

- Assuming the repair is a predicate rather than a longer list or a longer floor, because both of those
  extend the set of inputs the instrument guesses correctly about and leave it guessing.
- Assuming DEF-201's "0 occurrences across 91 briefs" is a fact about this repository's idiom rather
  than about the risk, since a repository citing by convention has the opposite prior and one does.

## Defects

DEF-201, DEF-202, DEF-203.
