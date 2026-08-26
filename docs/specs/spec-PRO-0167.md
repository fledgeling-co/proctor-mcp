# Spec PRO-0167 — Path Citations That Resolve From the Root

**Brief:** `docs/features-to-triage/159-repository-relative-path-citation-resolver.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-024
**Defects:** none

## Context & Purpose
An external audit reported a cited path as existing nowhere, over a file that exists — the citation was a bare filename. A citation an outside reader cannot resolve is a citation that fails silently.

## Acceptance Criteria
1. A path citation in a durable artifact resolves from the repository root.
2. A bare filename that resolves to exactly one file is reported with the repository-relative path that would fix it.
3. A bare filename matching several files is reported as ambiguous rather than resolved to the first.
4. The check prints how many citations it examined.

## Verify
- `python3 scripts/campaign/path_citation_check.py --gate` — exit 0, ratchet 473 held, 1,428 of 1,901 resolve.
- `python3 scripts/campaign/test_instruments.py` — the arm writes a two-citation fixture and asserts the bare one is reported with its fix while the qualified one beside it is not.
- `docs/test-campaign/evidence/PRO-0167/path-citations.txt` — the run, with all four classes.

## What criterion 1 does and does not cover, measured
`--fix` rewrote 742 citations on its first run and took `scripts/campaign/spec_citation_measure.py` from 19/19 to
16/19. `docs/feature-specs/UNCLAIMED-BRIEFS.md` keys its shared-parent table on bare brief names,
so expanding them orphaned every row; and `docs/specs/spec-PRO-0053.md` carried a prose instruction to read wave 7's direction
brief first, which expanded into a second path citation in a spec that already had one, raising
that brief's count from 13 to 16 and leaving brief 54 claimed only by an incidental mention. The
brief is named here by its number rather than its path for the same reason: a brief path written
into a spec's prose is a citation that tool counts.

`docs/feature-specs/UNCLAIMED-BRIEFS.md` had already recorded the same result from an out-of-family review that
proposed normalising all 24 prose citations to the header form: *"Measured against this tree that
would break the invariant it was meant to strengthen."* The document said so and the fixer did it
anyway, which is the finding worth keeping.

So criterion 1 holds for the artifacts where nothing else reads the citation form, and
`docs/specs/` and `docs/feature-specs/` are excluded by name in `FIXED_FORM`. That leaves 347
citations that are resolvable and deliberately unexpanded, counted apart from the 78 ambiguous
and 48 absent so the residue is not one undifferentiated number.

**Moves:** none.

