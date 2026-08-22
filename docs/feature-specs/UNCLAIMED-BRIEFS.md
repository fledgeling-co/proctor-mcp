# Briefs no spec claims

Every brief in `docs/features-to-triage/` should be cited by exactly one spec in
`docs/specs/`, so that a reckoning can say what happened to it. The four below
cannot be, and each one's reason is recorded here rather than left as an absence —
a brief nothing claims and a brief nobody decided about look identical otherwise,
and those are opposite conclusions.

`scripts/campaign/spec_citation_measure.py` reads this file. A row whose reason is
empty is not a row: it fails the check the same way a missing row does.

| Brief | Where it went | Why no spec claims it |
|---|---|---|
| `23-drawing-fault-must-not-kill-the-agent.md` | PRO-0022, Merged 2026-08-14 | The ledger row exists and the work shipped; `docs/specs/spec-PRO-0022.md` was never written, so there is no spec to carry the citation. DEF-215. |
| `40-page-scoped-refusal.md` | PRO-0039, Retired 2026-08-15 | Retired unbuilt — the brief's own banner says so, and names PRO-0039. No spec was written, so nothing can cite it. DEF-215. |
| `85-proctoragents-mutants-mostly-survive.md` | PRO-0092, Ready for AI | Allocated and held for a quiet machine; its mutation runner scores a timeout as a kill. The spec is written at plan time, and the citation with it. |
| `96-what-1-1-0-still-groups-and-still-grades.md` | untriaged | Filed 2026-08-22 and not yet triaged. No id, so no spec; triage writes the citation when it mints one. |
