# PRO-0112: Warrant charter and release integrity

**ID:** PRO-0112
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/104-warrant-charter-and-release-integrity.md`
**Defects:** DEF-290
**Requirements:** REQ-165..REQ-167
**Cases:** CASE-0650..CASE-0653
**Surfaces:** SURF-032

## Feature description

Formalize `.warrant/warrant.toml` charter and release gate integration:
1. Audit and validate `.warrant/warrant.toml` against `campaign.py export-warrant` and `charter_validate.py` so the charter passes cleanly without charter-absent blocks.
2. Formalize all seven defect classes (`evidence-integrity`, `surface-conformance`, `capture-trust`, `operator-state`, `run-lifecycle`, `registry-drift`, `release-integrity`) with complete surface globs matching 100% of campaign surfaces and enforce 100% census sampling on designated census classes (`evidence-integrity`, `operator-state`, `inconclusive`).
3. Add comprehensive instrument tests in `scripts/campaign/test_instruments.py` asserting charter integrity, census class coverage, and release gate verification.

## Acceptance sketch

- `.warrant/warrant.toml` validates against `charter_validate.py` and `campaign.py export-warrant`.
- All seven defect classes match repository evidence rules, cover all enumerated surfaces, and roll up cleanly.
- Census classes (`evidence-integrity`, `operator-state`, `inconclusive`) are capped at tier 0 and enforced at 100% sampling under warrant rules.
- Test instruments in `test_instruments.py` assert charter schema, surface matching, and release gate integrity with negative controls.

## Progress — PRO-0112

**Defects:** DEF-290
**Requirements:** REQ-165..REQ-167
**Cases:** CASE-0650..CASE-0653
**Surfaces:** SURF-032

- Defined full charter in `.warrant/warrant.toml` with 7 defect classes, surface globs, deterministic thresholds, and lot census rules.
- Verified that `campaign.py export-warrant` and `rollup_classes.py` roll up all 31 surfaces cleanly across the 7 classes.
- Added charter integrity, census coverage, and release gate tests to `scripts/campaign/test_instruments.py`.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-290 | Warrant charter .warrant/warrant.toml lacked surface mappings and census class integration causing rollup and tier export to report 0 matched surfaces | fixed |
