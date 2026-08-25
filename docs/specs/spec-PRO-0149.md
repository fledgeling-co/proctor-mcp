# Spec PRO-0149 — Skill Overlay Family Guidance Reader

**Brief:** `docs/features-to-triage/141-skill-overlay-family-guidance-reader.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-030
**Defects:** none

## Context & Purpose
A skill directory may carry a family-specific overlay beside its SKILL.md, and the tailings pass found one present and unread. An overlay that is never opened is guidance nobody follows, and nothing in the run says so.

## Acceptance Criteria
1. Loading a skill enumerates the family overlays sitting beside it.
2. An overlay that applies to the running family and was not read is reported rather than passed over.
3. The report names the overlay path so a reader can open it.
4. An absent overlay is distinguished from an unread one, because they are different findings.
