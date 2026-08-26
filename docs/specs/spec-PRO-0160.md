# Spec PRO-0160 — Control Census Across Every Surface

**Brief:** `docs/features-to-triage/152-thirty-eight-surfaces-that-declare-no-controls.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-008
**Defects:** none

## Context & Purpose
The control census reads four of thirty-four, and both numbers come from two surfaces of forty. The fraction describes 5% of the surface list rather than the product.

## Acceptance Criteria
1. Every surface offering controls declares them, taken from its own source of truth.
2. A surface with genuinely no controls declares an empty list rather than being absent.
3. The actuated count is published against the full declared list.
4. A declared control no case actuates is named, not counted only in aggregate.

## Verify
- `python3 scripts/campaign/control_census.py --gate` — exit 0, 40 of 40 surfaces declare a list, 17 of 82 controls actuated.
- `campaign.py check` — exit 0; it refused while any surface declared controls nothing actuated.
- `swift test --filter InstallerControlTests` · `WalkthroughControlTests` · `RunHUDControlTests` — 12 tests, exit 0.

## What the numbers moved from, and why the denominator grew
`4 of 34 declared control(s) actuated, across 2 surface(s)` came from two surfaces of forty, so
the fraction described the surface list. It now reads `17 of 82 across 7`. The rise in the
denominator is the result: 31 engines and instruments carry an explicit empty list, two
interactive surfaces that genuinely offer nothing carry one with a reason, and five interactive
surfaces declare what their own source draws.

## What this deliberately does not do
It does not actuate the remaining 65 controls. Each needs a case that drives it and reads an
effect outside it, and the census names every one rather than reporting the aggregate — which is
criterion 4 rather than a gap in it.

**Moves:** none.
