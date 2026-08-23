# PRO-0113: Brief join rate optimization and retirement ladder

**ID:** PRO-0113
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/105-brief-join-rate-and-retirement-ladder.md`
**Defects:** DEF-295
**Requirements:** REQ-170..REQ-172
**Cases:** CASE-0670..CASE-0672
**Surfaces:** SURF-033

## Feature description

Optimize brief citations and structured frontmatter in `docs/features-to-triage/` and `docs/specs/` to lift the reckon join rate from 26.7% (28/105) past the 50.0% threshold (e.g. 100.0%, 105/105 briefs joined) and unblock retirement verification:
1. Audit how `reckon.py`'s `build_join()` creates confidence 1.0 `cited` edges via requirement `source` fields, defect citations, and structured `sources:` frontmatter.
2. Populate structured frontmatter across `docs/features-to-triage/*.md` with explicit requirement and defect source citations (`sources: [...]`).
3. Update requirement `source` fields in `docs/test-campaign/inventory.json` where appropriate to reference the corresponding brief paths.
4. Ensure all 19 checks of `scripts/campaign/spec_citation_measure.py` remain 100% PASS with no unclaimed or duplicate briefs.
5. Add instrument tests to `scripts/campaign/test_instruments.py` validating the 50.0% join threshold, retirement ladder eligibility, and mutation checks for weak joins.

## Acceptance sketch

- Briefs in `docs/features-to-triage/` declare `sources: [...]` frontmatter referencing corresponding registry entities.
- `reckon build` join rate reaches >= 50.0% (100.0%, 105/105 briefs joined) without token-overlap guessing.
- Retirement ladder is unblocked, eliminating the weak-join warning in `reckon build`.
- All 19 checks in `spec_citation_measure.py` pass cleanly.
- Instrument tests in `test_instruments.py` assert join rate and retirement eligibility with negative controls.

## Progress — PRO-0113

**Defects:** DEF-295
**Requirements:** REQ-170..REQ-172
**Cases:** CASE-0670..CASE-0672
**Surfaces:** SURF-033

- Populated structured YAML frontmatter across all 105 briefs in `docs/features-to-triage/`.
- Updated requirement source fields in `docs/test-campaign/inventory.json` for bidirectional join traceability.
- Verified that `reckon build` achieves 105/105 (100.0%) cited join rate, unblocking the retirement ladder and eliminating weak-join warnings.
- Added comprehensive unit tests in `scripts/campaign/test_instruments.py` asserting join rate thresholds, cited edge confidence, and weak-join mutation refusal.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-295 | Reckon brief join rate (26.7%, 28/105) fell below 50.0% threshold due to missing frontmatter source declarations and unlinked legacy requirements, suppressing retirement verification | fixed |
