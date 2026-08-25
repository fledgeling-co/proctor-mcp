# Spec PRO-0131 — High-DPI Display Scale Factor Injection Helper

**Brief:** `docs/features-to-triage/123-high-dpi-display-scale-factor-injection-helper.md`
**Status:** Merged
**Created:** 2026-08-24
**Surfaces:** SURF-007
**Defects:** none

## Context & Purpose
Provide a display scale factor injection helper to simulate standard and high-density display scaling in test harnesses during headless and visual test runs.

## Acceptance Criteria
1. Injected display density settings configure rendering geometry transparently.
2. Layout calculations adjust frame dimensions according to the active scale factor.
3. Asset selection and point-to-pixel coordinate transforms operate deterministically.
4. Environment state resets automatically upon test teardown.
