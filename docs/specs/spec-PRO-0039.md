# PRO-0039: Page-scoped refusal

**ID:** PRO-0039
**Status:** Retired
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/40-page-scoped-refusal.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md`

## Feature description

<!-- Derived from docs/features-to-triage/40-page-scoped-refusal.md -->

Proposed a policy rule that would refuse direct accessibility-plane actuation into web page content (`AXWebArea`) within known browsers, while leaving browser application chrome (toolbars, tabs, menus) drivable.

## Retirement reason

Retired 2026-08-15 unbuilt during Wave 7 triage. The brief was drafted when Proctor directly performed AX actuation on browser windows and gave advisory routing recommendations. With the architectural pivot to Cua (PRO-0044), browser tabs are bound to windows and driven over CDP rather than AX coordinates, changing the boundary underneath the brief. Policy gating over delegated calls was deferred to be re-derived from the new architecture in subsequent waves.
