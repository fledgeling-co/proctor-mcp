# PRO-0108: Two findings reckon 1.2.0 still leaves open

**ID:** PRO-0108
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/96-what-1-1-0-still-groups-and-still-grades.md`
**Defects:** DEF-280..DEF-281
**Requirements:** REQ-155..REQ-157
**Cases:** CASE-0620..CASE-0626
**Surfaces:** SURF-031

## Feature description

Two findings a peer session measured against `reckon` 1.1.0 and which 1.2.0 still leaves open:

1. **The denominator correction, now settled:** the brief's finding 1 ("one BLOCK-0001 at 16.7%")
   was measured on a 24-case ledger where four cases **is** 16.7%. On this 400-case repository there
   are four blockers at one case each (+0.3 points) and 16.7% was the *briefs joined* line. Both
   readings were right and the disagreement was a missing denominator. The requirement this leaves:
   **print the denominator beside every percentage**, so two right numbers from two registries cannot
   look like a contradiction.
2. **`source` is read to JOIN and is still allowed to GRADE:** a `source` inside the brief queue is both
   the citation that ties a brief and the circular case that must not promote a requirement to `observed`.
   A requirement whose only evidence is the document that states it has been restated, not measured.
   The repair is one predicate with two exits: read `source` to join, refuse to let it grade.

## What and why

`unjoined` did not absorb the 19 self-sourced requirements — they stay `unmeasured` under both
versions, which is the measurement that makes 1.1.0 safe. But `source` is still doing two jobs at once,
and the two findings compose rather than compete.

## Acceptance sketch

- Every percentage the tool emits carries its denominator beside it.
- A requirement whose only evidence is its own `source` declaration is classed `unmeasured` by a rule
  that names circular evidence, not by a fallback.
- A brief that joins *only* through `source` joins at confidence 1.0, proved by a fixture.
- The two exits are tested separately.

## Assumptions made writing this

- Assuming the repair lands in `fledgeling-plugins/plugins/reckon`, committed by explicit path.
- Assuming the denominator requirement applies to all four reports (`build`, `check`, `take`, `compare`).

---

## Implementation plan — 2026-08-23

Implementation plan: `docs/plans/plan-PRO-0108.md` (tier: Small). Work lands in
`~/Dev/fledgeling-plugins/plugins/reckon` (`reckon.py`, `selftest.py`), committed by explicit file paths,
with test-campaign tracking in `proctor-mcp`.

## Progress — PRO-0108

**Defects:** DEF-280..DEF-281
**Requirements:** REQ-155..REQ-157
**Cases:** CASE-0620..CASE-0626
**Surfaces:** SURF-031

Built in `~/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/` (`reckon.py`, `selftest.py`).
- Every percentage emitted across report modes carries its denominator beside it (`X/Y (Z%)`).
- `source` is read to join briefs to registry entities at confidence 1.0 cited edges, but circular source evidence is refused for grading requirements and kept as `unmeasured` naming circular evidence.
- Self-test suite expanded to prove denominator outputs and both source exits separately.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-280 | Reckon emitted percentages without denominators across reports | fixed |
| DEF-281 | Reckon allowed circular source evidence to grade requirements to observed | fixed |
