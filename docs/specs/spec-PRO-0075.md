# PRO-0075: what the 0.8.0 campaign found

**ID:** PRO-0075 · **Status:** Merged · **Created:** 2026-08-20
**Branch:** `ai/wave-9` · **Report:** `docs/test-campaign/REPORT.md`

## The problem

Wave 9 closed with every gate green and four acceptance clauses carried as "needs a live
agent". `test-campaign` 0.8.0 then arrived with a plane the campaign had never had: a check
that a published picture depicts what it is filed under. It failed on the first run, over a
campaign that was passing everything else.

## What changed

**The vendored skill.** The repo's gates ran test-campaign 0.5.0 while the installed skill was
0.8.0, so three of the gates it now owns did not exist here. The submodule is pinned forward
and the vendored scripts match the installed skill byte for byte.

**Six product fixes**, each found by measuring rather than reviewing. They are listed with
their evidence in the report; the two that generalise:

- A value-level check cannot see a rendered surface. `commandsMissingFromMenuBar` compares the
  catalogue against its own `surfaces` field, so it passed while three commands declared for
  the menu bar were never declared to SwiftUI at all. The rendered menu is settled by driving
  `proctor_menu` against the running app, which is a campaign case rather than a unit test.
- A safety net with a literal scanner has a hole the shape of a line break. The drift test
  that reconciles the agent's grant names with Core's classification map scans for
  `.init(name: "`, and a grant written across two lines was invisible to it. Both sets lacked
  the name equally, set equality held, and the name fell to a default that filtered the new
  permission out of the window while the CLI and the TUI both drew it.

**Two design divergences left open**, both already recorded as carried clauses at merge:
PRO-0066's A2 (five older MainWindow sections still carry literals) and PRO-0067's A3. The
campaign measured what those carries left open rather than closing them.

## Verification

Suite 1,657 tests in 197 suites. Campaign 42 cases over 17 surfaces: 41 pass, 41 armed, 1
inconclusive; strict ratchet 36 → 41; lineage ratchet pinned at 3 with the seeded swap caught
in both directions.

`campaign.py check` exits 1 on the one inconclusive case. It is declared with its resume point
in the report rather than resolved to `n/a`, because it could have been reached: photographing
the status window drawing its fourth permission row needs the wave-9 build installed over the
operator's own, which is their decision rather than this run's.
