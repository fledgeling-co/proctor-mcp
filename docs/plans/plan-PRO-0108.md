# PRO-0108 — implementation plan

**Spec:** `docs/specs/spec-PRO-0108.md` · **Brief:** `docs/features-to-triage/96-what-1-1-0-still-groups-and-still-grades.md`
**Tier:** Small — shared Python module `reckon.py`, self-tests in `selftest.py`, and campaign registry rows.
**Lands in:** `~/Dev/fledgeling-plugins/plugins/reckon` and `proctor-mcp` campaign registry.
**Design stage:** skipped (CLI / report tooling).

## What gets built

### 1 — Denominator printing across all report modes (DEF-280 / REQ-155)
Every percentage emitted across reckon report modes carries its denominator beside it (`X/Y (Z%)`):
- `cmd_build` headline: `speaks for %d/%d (%.0f%%) of the campaign's designed cases and %d/%d (%.0f%%) of its stated requirements`
- `gate()` weak-join warning: `only %d/%d (%.1f%%) of briefs could be joined to the registry at all`
- `render()` blocker table: `Coverage returned` column prints `+%d/%d (+%.1f pts)` (e.g. `+4/24 (+16.7 pts)`)
- `render()` "What it can speak for" table: carries `Measured` and `Of` columns directly beside `%`

### 2 — Circular `source` evidence gating: Read to JOIN, refuse to GRADE (DEF-281 / REQ-156, REQ-157)
- **Exit 1: Read `source` to JOIN (REQ-157):** In `build_join()`, read frontmatter `reckon-sources`, `sources`, `source` in briefs, and `source` field across registry items (`requirements`, `defects`, `cases`). Establish confidence 1.0 cited edges for briefs citing or cited via `source`.
- **Exit 2: Refuse to let `source` GRADE (REQ-156):** A requirement whose only evidence is its own `source` declaration (`evidence: "source"`) is classed `unmeasured` by a dedicated rule naming circular evidence (`why = "requirement evidence 'source' is circular: citing the source declaration restates intent rather than measuring execution"`), NOT by an unclassified vocabulary fallback (no finding generated). In `gate()`, any requirement carrying circular or self-reported evidence presenting as `verified-done` or `retirable` raises a placement violation (exit 1).

## Test strategy

Seam: `plugins/reckon/skills/reckon/scripts/selftest.py`

| Case | What it verifies | Seam / Assertion |
|---|---|---|
| CASE-0620 | Headline output carries explicit cases and requirements denominators (X/Y (Z%)) | `selftest.py` check 18a |
| CASE-0621 | Weak-join warning carries explicit denominator (only N/D (pct%) of briefs) | `selftest.py` check 18c |
| CASE-0622 | Blocker table Coverage returned column prints denominator (+X/Y (+Z.Z pts)) | `selftest.py` check 18b |
| CASE-0623 | Markdown report What it can speak for table includes Measured and Of columns | `selftest.py` check clean ledger render |
| CASE-0624 | Read source to join creates cited edges at confidence 1.0 for brief frontmatter and registry citations | `selftest.py` check 19a |
| CASE-0625 | Refuse to let source grade classes circular source evidence as unmeasured with circular why | `selftest.py` check 19b |
| CASE-0626 | Placement check in `gate()` rejects requirement with circular source evidence classed verified-done | `selftest.py` check 19b expect |

## Allocated IDs

- **Surfaces:** SURF-031
- **Requirements:** REQ-155, REQ-156, REQ-157
- **Defects:** DEF-280, DEF-281
- **Cases:** CASE-0620..CASE-0626
