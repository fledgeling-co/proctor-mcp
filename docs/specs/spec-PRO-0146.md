# Spec PRO-0146 — Continuous Spec-Symbol Citation Linter

**Brief:** `docs/features-to-triage/138-continuous-spec-symbol-citation-linter.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-025
**Defects:** none

## Context & Purpose
Provide an automated continuous citation linter to validate symbol references across all specification documents against the production source tree.

## Acceptance Criteria
1. Citation linter scans all specification documents for referenced types, functions, and protocols.
2. Referenced symbols are resolved against the current production source tree.
3. Renamed or deleted symbols produce line-anchored diagnostic warnings.
4. Pre-commit gates prevent introduction of ungrounded symbol citations.
