# Spec PRO-0130 — Operator State and Evidence Integrity Chain

**Brief:** `docs/features-to-triage/122-operator-state-and-evidence-integrity-chain.md`
**Status:** Merged
**Created:** 2026-08-24
**Surfaces:** SURF-012, SURF-015
**Defects:** none

## Context & Purpose
Establish complete cryptographic provenance chains and receipts for audit log rotation, policy modifications, and peer liveness detection, qualifying operator-state and evidence-integrity for tier promotion.

## Acceptance Criteria
1. Audit log rotation records hash-chained block headers and signatures for all discarded segments.
2. Operator policy mutations verify atomic filesystem writes and metadata preservation.
3. Peer liveness detection distinguishes active, hung, and terminated client sessions.
4. Evidence integrity coverage reaches the threshold required for tier promotion.
