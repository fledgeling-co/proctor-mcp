# Spec PRO-0160 — Control Census Across Every Surface

**Brief:** `docs/features-to-triage/152-thirty-eight-surfaces-that-declare-no-controls.md`
**Status:** Ready for AI
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
