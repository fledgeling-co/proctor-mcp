# Spec PRO-0167 — Path Citations That Resolve From the Root

**Brief:** `docs/features-to-triage/159-repository-relative-path-citation-resolver.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-024
**Defects:** none

## Context & Purpose
An external audit reported a cited path as existing nowhere, over a file that exists — the citation was a bare filename. A citation an outside reader cannot resolve is a citation that fails silently.

## Acceptance Criteria
1. A path citation in a durable artifact resolves from the repository root.
2. A bare filename that resolves to exactly one file is reported with the repository-relative path that would fix it.
3. A bare filename matching several files is reported as ambiguous rather than resolved to the first.
4. The check prints how many citations it examined.
