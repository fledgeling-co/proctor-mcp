# Spec PRO-0153 — Arming Claim Verification

**Brief:** `docs/features-to-triage/145-an-arming-claim-nobody-checks.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
Every case carries an armedBy string saying what was done to make it fail, and nothing reads one. A case was found naming a test as its arm where that test passes with the fix removed. An arming claim is checkable by construction rather than by review.

## Acceptance Criteria
1. An arming claim names a change to apply and a test to run, in a form a tool can act on.
2. Applying the named change and running the named test produces a red result.
3. A claim whose named test stays green is reported with both, rather than counted as armed.
4. A claim that cannot be mechanically applied is reported as unverifiable, never as armed.
5. The verified-arm count is published with its denominator beside the armed ratio.
