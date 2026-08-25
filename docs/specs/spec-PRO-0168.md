# Spec PRO-0168 — An Intentional No-Op Says So

**Brief:** `docs/features-to-triage/160-release-stub-and-no-op-verification-attestation.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-002
**Defects:** none

## Context & Purpose
A static scan cannot tell a deliberate null implementation from an unfinished one, and this repository has both shapes: a NullContentionMonitor whose emptiness is the design, and a Reflector inert outside DEBUG.

## Acceptance Criteria
1. An intentional empty body carries an attestation a scan can read.
2. A null implementation's safe default is asserted by a test rather than assumed.
3. An empty body with no attestation is reported.
4. The report separates production stubs from test doubles, which are a different question.
