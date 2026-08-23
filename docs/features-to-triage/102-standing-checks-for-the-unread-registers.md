---
sources: [REQ-145, REQ-146, REQ-147, DEF-228, DEF-229, DEF-243]
---
# Standing checks for the registers nothing reads

**Wave 18, brief 2.** DEF-228, DEF-229, DEF-243. The standing checks for the three registers
found unread by DEF-227's probe across `scripts/`.

## What needs doing

1. **DEF-228 (`LEDGER.md`):** Build a standing gate check verifying that every merged branch claims `Merged` in `LEDGER.md`, every row with no spec file is declared, and every spec on disk has a ledger row.
2. **DEF-229 (`capture-lineage.py`):** Teach `capture-lineage.py` to cross-check `cases.json` against `captures.json` so cases citing unpublished, misnamed, or absent images fail the lineage gate.
3. **DEF-243 (`evidence/shots/mock/`):** Account for the four uncited mock files in `shot_disposition.py`.
