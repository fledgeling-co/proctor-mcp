---
sources: [REQ-145, REQ-146, REQ-147, DEF-228, DEF-229, DEF-243]
status: retired
validated-by: REQ-111, REQ-145, REQ-146, REQ-147 via CASE-0472, CASE-0479, CASE-0480, CASE-0590, CASE-0591, CASE-0592
validated-rungs: metamorphic, outcome
validated-provider: none
validated-through-defect: REQ-111 via DEF-227
---
# Standing checks for the registers nothing reads

**Wave 18, brief 2.** DEF-228, DEF-229, DEF-243. The standing checks for the three registers
found unread by DEF-227's probe across `scripts/`.

## What needs doing

1. **DEF-228 (`docs/feature-specs/LEDGER.md`):** Build a standing gate check verifying that every merged branch claims `Merged` in `docs/feature-specs/LEDGER.md`, every row with no spec file is declared, and every spec on disk has a ledger row.
2. **DEF-229 (`capture-lineage.py`):** Teach `capture-lineage.py` to cross-check `docs/test-campaign/cases.json` against `docs/test-campaign/evidence/shots/captures.json` so cases citing unpublished, misnamed, or absent images fail the lineage gate.
3. **DEF-243 (`evidence/shots/mock/`):** Account for the four uncited mock files in `scripts/campaign/shot_disposition.py`.
