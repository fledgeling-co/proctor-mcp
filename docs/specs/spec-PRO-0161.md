# Spec PRO-0161 — Raise or Record Every Case Below the Effect Rung

**Brief:** `docs/features-to-triage/153-forty-one-cases-that-only-prove-something-rendered.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none
**Moves:** warrant.surface-conformance from 84.0 to 84.3

## Context & Purpose
497 cases pass and 438 are checked. Forty-one stand at a rung that reads a fact off the source and witnesses no effect; sixteen were never watched to fail.

## Acceptance Criteria
1. Each case below the effect rung is routed: raised, or recorded as permanently structural with the reason.
2. A raised case names the observable it reads and the channel it reads it through.
3. The sixteen unarmed cases are armed, or recorded as unarmable with what prevents it.
4. The checked count is published beside the pass count wherever either appears.

## Verify
- `python3 scripts/campaign/rung_routing.py docs/test-campaign --gate` — exit 0, 0 undecided, 30 structural, 13 raisable.
- `python3 scripts/campaign/test_instruments.py` — `test_every_sub_effect_rung_case_is_routed` arms in both directions (exit 0 on clean tree, exit 1 naming unroutable case on fixture).
- `docs/test-campaign/evidence/PRO-0161/rung-routing.txt` — full routing breakdown recorded.

## What this establishes, and why **Moves:** was corrected
`scripts/campaign/rung_routing.py` classes every case below the effect rung as either permanently structural
(30 cases, where the claim is about absence or static source properties that no execution can witness)
or raisable (13 cases, where a running build exhibits an observable that can be read).
Routing records the classification onto `docs/test-campaign/cases.json` without altering the oracle rungs,
so `warrant.surface-conformance` stays at 84.3% until the 13 raisable cases are rewritten with effect rungs.
The aspirational `Moves:` declaration was corrected to `none` following the same rule that caught PRO-0163.

