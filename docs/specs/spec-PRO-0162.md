# Spec PRO-0162 — Cut or Record Every Durable Boundary

**Brief:** `docs/features-to-triage/154-seven-durable-boundaries-nobody-cut.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-012
**Defects:** none

## Context & Purpose
Forty-three of fifty durable boundaries are cut. The seven that are not sit across four journeys, which are recorded non-critical for that reason rather than because the work matters less.

## Acceptance Criteria
1. Each uncut boundary is cut, or recorded as structurally uncuttable with the reason.
2. A journey whose five cuts exist is promoted to critical on evidence rather than assertion.
3. A cut names the observable it reads and a channel distinct from the one that performed the step.
4. The boundaries-cut fraction is published on every run whether it moved or not.

## What the first pass at this found, and why the row stays open

**The journey's list of cut boundaries is asserted on the journey, not derived from cases.**
A case carries a journey field and no boundary field, so nothing ties a cut to the thing that cuts it: an
asserted cut and a cut with a passing effect-rung case behind it are the same five strings in the
same list. The fraction `43/50` was therefore a count of assertions.

That showed up immediately. JRN-006's own note read *"no case witnesses the encrypted bytes on
disk independently of the code that wrote them"* while CASE-0061 was already doing exactly that —
driving a real audited run and reading the sealed bytes back through a fresh file handle rather
than `AuditLog.readTrail`. The case existed, carried no journey, and nothing joined the two. It is
attached now, with what it does and does not cover recorded: the seals are opened with
`AuditSeal.open`, ProctorCore's own, so the witness is a different module from the reader under
test rather than an independent implementation.

So the work this row still owes, in order:

1. A case declares the boundary it cuts, and the journey's list is **derived** from
   passing effect-rung cases rather than declared beside them. Until then criterion 1 cannot be
   checked, because "cut" is not an observable.
2. The remaining six: JRN-002 and JRN-007 at `user-acknowledged`, JRN-006 at `user-acknowledged`,
   and JRN-008 at `provider-effect`, `client-persisted` and `user-acknowledged`. Each journey's
   note already names what is owed; none is recorded as structurally uncuttable, and on reading
   them none is — JRN-002's note says the run HUD draws an account of a background batch, and
   JRN-008's live lane needs a simulator runtime that this machine has.
3. Criterion 2's promotion to critical follows from 1, not from the count.

## The count, measured rather than asserted — 2026-08-27

`scripts/campaign/journey_census.py` derives a cut from the cases that declare
one and compares it against what each journey claims. First run:

    10 journey(s) · 44 of 50 boundaries claimed cut
      with a passing effect-rung case naming them   1
      asserted, with no case behind them            43

So `boundaries 44/50 cut` was a count of assertions, and the one cut with a case
behind it is the one attached earlier this wave. Six of the ten journeys are
marked critical on that count.

The census REPORTS rather than rewrites. Deriving the list and writing it would
drop the campaign's boundary count to 1 and take the critical-journey rule down
with it in the same commit — two changes, one of them unmeasured. The number
moves when cases are written, which is the work this row is for, and the ratchet
at 43 means a journey cannot claim a new cut without one.

Criterion 1 is now checkable: a cut is a passing case at or above the `outcome`
rung, attached to the journey, naming the boundary. Criterion 2's promotion to
critical follows from that rather than from the claim.

## Verify
- `python3 scripts/campaign/journey_census.py --gate` — exit 0, ratchet 43 held, 44 of 50 boundaries claimed, 1 evidenced, 43 asserted-only.
- `python3 scripts/campaign/test_instruments.py` — `test_a_journey_cut_has_a_case_behind_it` arms in both directions (exit 0 on clean tree, exit 1 on increased asserted-only cut or invalid boundary name).
- `docs/test-campaign/evidence/PRO-0162/journey-census.txt` — full journey cut census breakdown recorded.

**Moves:** none.

