# Spec PRO-0170 — Continuous Claim Verification Between Waves

**Brief:** `docs/features-to-triage/162-autonomous-audit-worklist-continuous-verifier.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
The claim audit runs once at session close, by which time a wrong figure has propagated into files other sessions plan from. Run between waves it catches the same claims before they travel.

## Acceptance Criteria
1. Durable artifacts touched by a wave are re-checked against the registries when that wave closes.
2. A claim that contradicts a registry is reported before the next wave opens.
3. The check is incremental: it examines what the wave touched rather than the whole tree.
4. A wave that touched no durable artifact says so rather than reporting a clean check it did not make.
