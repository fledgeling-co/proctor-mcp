# Spec PRO-0150 — Capture Directory Identity Manifest

**Brief:** `docs/features-to-triage/142-capture-directory-identity-manifest.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-027
**Defects:** none

## Context & Purpose
The tailings crossref probe R4 could not check capture identity because no capture directory was found, and an unrunnable probe is not a passing one. A manifest gives the probe a population to check against and makes the absence of one legible.

## Acceptance Criteria
1. The capture store carries a manifest naming every image, its digest and the subject it depicts.
2. A probe over an absent directory reports 'not checked' with the path it looked for, never a clean result.
3. An image present on disk and absent from the manifest is reported, and so is the reverse.
4. The manifest is generated from the directory rather than hand-maintained, so it cannot drift silently.
