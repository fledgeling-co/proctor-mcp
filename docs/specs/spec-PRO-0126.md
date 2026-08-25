# Spec PRO-0126 — Headless Simulator Provisioning and Teardown Hook

**Brief:** `docs/features-to-triage/118-headless-simulator-provisioning-and-teardown-hook.md`
**Status:** Merged
**Created:** 2026-08-24
**Surfaces:** SURF-019
**Defects:** none

## Context & Purpose
Provide an automated provisioning and teardown hook for ephemeral headless simulator instances in CI environments, preventing orphaned processes and device state leakage.

## Acceptance Criteria
1. Ephemeral simulator instances are created with isolated data containers.
2. Simulator launches in headless mode without window server presentation.
3. Teardown hook terminates simulator processes and removes scratch directories on completion.
4. Resource cleanup handlers recover from interrupted test executions cleanly.
