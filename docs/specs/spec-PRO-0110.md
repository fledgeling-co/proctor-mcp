# PRO-0110: The registers nothing reads

**ID:** PRO-0110
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Defects:** DEF-228, DEF-229, DEF-243
**Brief:** `docs/features-to-triage/102-standing-checks-for-the-unread-registers.md`

## Feature description

Running DEF-227's input-side probe across every instrument in `scripts/` revealed three registers
that standing instruments do not read:

- **DEF-228.** `LEDGER.md` is the ledger of record and no standing gate reads it. PRO-0092's row read
  `In Progress` while its branch was merged into `main`. Build the check: a row whose branch is merged
  claims `Merged`; a row with no spec is declared; a spec with no row is a finding. All three computable
  from git and the filesystem.
- **DEF-229.** `capture-lineage.py` has zero references to `cases.json`, so a case citing an unpublished,
  misnamed or absent image is invisible to the lineage gate. Teach `capture-lineage.py` (and `shot_disposition.py`)
  to cross-check `cases.json` against `captures.json` and on-disk files.
- **DEF-243.** `evidence/shots/mock/` is excluded from every instrument that reads the shots directory.
  Four uncited files under that directory are unread by anything. Give them a disposition or include
  them in `shot_disposition.py`.

## What was built

1. **`scripts/campaign/ledger_gate.py` (DEF-228):**
   A standing gate that audits `docs/feature-specs/LEDGER.md` against git history and `docs/specs/`:
   - Cross-checks all merged features in git history (`merge PRO-XXXX`, `Merge branch ...`, etc.) against `LEDGER.md` status, asserting that merged work claims `Merged` (or `Retired`).
   - Asserts bidirectional spec accounting: every `spec-PRO-XXXX.md` on disk must have a ledger row.
   - Enforces that any row lacking a spec file is explicitly declared in `## Rows with no spec file` with a reason (minimum 20 characters), and refuses stale declarations where a spec file exists.
   - `docs/feature-specs/LEDGER.md` now carries the declared `## Rows with no spec file` table for `PRO-0022`, `PRO-0031`, and `PRO-0039`.
   - Hooked into `scripts/campaign/test_instruments.py` with 5 standing checks and 4 mutation cases (`test_ledger_gate_on_this_repository`, `test_ledger_gate_mutation_checks`).

2. **Cases and Captures Citation Cross-Check (DEF-229):**
   - `shot_disposition.py`'s `citations()` cross-checks every image cited in `docs/test-campaign/cases.json` against `docs/test-campaign/evidence/shots/captures.json`, disk existence, and publishing subjects.
   - Any case citing an absent, misnamed, or unpublished capture is refused unless explicitly accounted for in `KNOWN_CITATION_FAULTS` (DEF-224, DEF-225).
   - Hooked and regression-tested in `scripts/campaign/test_instruments.py`.

3. **Design Mock Disposition Lane (DEF-243):**
   - Added explicit dispositions for all files under `docs/test-campaign/evidence/shots/mock/` in `scripts/campaign/shot_disposition.py`: `mock/surf-008-status-window.png`, `mock/surf-009-walkthrough.png`, `mock/surf-010-menubar.png`, `mock/step-a3-walkthrough-primary-disabled.png`, and `mock/step-a3-walkthrough-primary-disabled.html`.
   - `shot_disposition.py`'s `audit()` now audits all 4 mock PNG files alongside the 43 capture shots (47 total PNG rasters), recording their exact dimensions, sha256 hashes, and byte counts in `docs/test-campaign/evidence/PRO-0107/shot-audit.json`.
   - `test_instruments.py` verifies the mock lane and proves that mutating a mock file's sha256 trips `verify()` with exit 1.

## Requirements

- **REQ-145:** Every merged branch/commit claims Merged in LEDGER.md, every spec on disk has a ledger row, and every row lacking a spec is declared with a reason.
- **REQ-146:** Cases citing unpublished, misnamed, or absent images fail standing lineage and disposition checks unless recorded as known faults.
- **REQ-147:** All design mock files under evidence/shots/mock/ carry explicit dispositions and byte audits.

## Defects

| Defect | State |
|---|---|
| DEF-228 | fixed |
| DEF-229 | fixed |
| DEF-243 | fixed |
