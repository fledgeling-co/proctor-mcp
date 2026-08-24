---
generated-by: reckon
reckon-sources: [SURF-012, REQ-015]
status: to-triage
---

# Operator State and Evidence Integrity Chain

- origin: docs/test-campaign/evidence.html · 2026-08-24
- audience: Security auditors and compliance operators reviewing cryptographic audit logs and state transitions
- platforms: mac
- proposed-by-ai: false

## What and why
Cryptographic audit trails and operator state persistence guarantee that all agent actions, policy modifications, and run queue transitions are tamper-evident. When evidence figures for operator state or audit rotation lack complete verification receipts, evidence integrity gates cannot certify the audit plane. Establishing complete provenance chains for all state transition figures ensures audit integrity is provable under external inspection.

## Acceptance sketch
- Audit log rotation records hash-chained block headers and signatures for all discarded segments
- Operator policy mutations verify atomic filesystem writes and metadata preservation
- Peer liveness detection distinguishes active, hung, and terminated client sessions
- State transition figures trace directly to cryptographic receipts in the evidence store
- Evidence integrity coverage reaches the threshold required for tier promotion

## Assumptions made writing this
- Assuming cryptographic verification utilizes standard hashing algorithms and local key stores
- Assuming audit trail entries are append-only and immutable during active execution
