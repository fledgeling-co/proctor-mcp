# PRO-0119: Retired Items Standalone Spec Closure

**ID:** PRO-0119
**Status:** Ready for AI
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/111-retired-items-spec-closure.md`
**Defects:** DEF-215

## Feature description

Author formal retrospective standalone spec files (`spec-PRO-0022.md`, `spec-PRO-0031.md`, `spec-PRO-0039.md`) for historical ledger rows to achieve complete 1-to-1 spec-to-ledger mapping and close DEF-215.

## Acceptance sketch

- `docs/specs/spec-PRO-0022.md`, `docs/specs/spec-PRO-0031.md`, and `docs/specs/spec-PRO-0039.md` exist and cite their historical briefs.
- Every ledger row in `docs/feature-specs/LEDGER.md` has a corresponding spec file on disk.
- DEF-215 transitions from open to fixed.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-215 | Four ledger rows have no spec file, so two briefs have no artifact that could cite them | Fixed |

## Assumptions made writing this

- Assuming retrospective specs accurately document the historical commits without modifying shipped behavior.
