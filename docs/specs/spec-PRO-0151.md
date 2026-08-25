# Spec PRO-0151 — Session Claim Provenance Audit Gate

**Brief:** `docs/features-to-triage/143-session-claim-provenance-audit-gate.md`
**Status:** Ready for AI
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
The tailings audit partitions a session's assertions into eight classes and gates on the result, but it runs once by hand. Run as a standing gate over the repository's own delivery notes and ledger rows, the same partition catches a false figure before it propagates into a document another session plans from.

## Acceptance Criteria
1. The gate partitions every claim in the audited artifacts into the eight classes, leaving none unplaced.
2. A standing contradicted or laundered row blocks regardless of how much else is clean.
3. Every row names its evidence: a path with a line, or a command with its exit code.
4. A probe that could not run is reported as not checked, with its reason, rather than counted as clean.
