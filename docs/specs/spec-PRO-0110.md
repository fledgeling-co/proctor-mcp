# PRO-0110: The registers nothing reads

**ID:** PRO-0110
**Status:** Ready for Plan
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/102-standing-checks-for-the-unread-registers.md`

## Feature description

Running DEF-227's input-side probe across every instrument in `scripts/` revealed three registers
that standing instruments do not read:

- **DEF-228.** `LEDGER.md` is the ledger of record and no standing gate reads it. PRO-0092's row read
  `In Progress` while its branch was merged into `main`. Build the check: a row whose branch is merged
  claims `Merged`; a row with no spec is declared; a spec with no row is a finding. All three computable
  from git and the filesystem.
- **DEF-229.** `capture-lineage.py` has zero references to `cases.json`, so a case citing an unpublished,
  misnamed or absent image is invisible to the lineage gate. Teach `capture-lineage.py` to cross-check
  `cases.json` against `captures.json`.
- **DEF-243.** `evidence/shots/mock/` is excluded from every instrument that reads the shots directory.
  Four uncited files under that directory are unread by anything. Give them a disposition or include
  them in `shot_disposition.py`.

## Acceptance sketch

- A new instrument or gate check reads `docs/feature-specs/LEDGER.md` and verifies every row's status
  against git merged branches, every row against `docs/specs/`, and every spec against the ledger.
- `capture-lineage.py` flags any case in `cases.json` that cites a capture not in `captures.json` or
  declared with an `unpublishedReason``.
- `shot_disposition.py` accounts for the files under `evidence/shots/mock/`.

## Defects

DEF-228, DEF-229, DEF-243.
