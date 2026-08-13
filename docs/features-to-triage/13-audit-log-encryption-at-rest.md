# Encryption-at-rest for the JSONL audit log

**Status:** untriaged · **Value:** high (security) · **Effort:** med · **Source:** deferred child of PRO-0005 (scheduled 2026-08-13 via whats-left ingest)
<!-- Promoted from ORCHESTRATOR.md "Deferred children" on the reader's all-three answer. Was an explicit exclusion in the PRO-0005 spec. -->

## What it is
Encrypt the redacting JSONL audit log on disk, rather than writing it in plaintext.

## The gap
PRO-0005 redacts secrets from the audit trail but writes the result as plaintext JSONL. It was an explicit spec exclusion, not an oversight. The log records what the tool did to the machine, so on a shared or multi-user system it is exactly the file you would not want readable at rest.

## Scope
- In: encrypt the audit log at rest (key handling via Keychain or an equivalent macOS-native path); decrypt on read for the tools that consume it.
- Out: changing what is logged or how it is redacted; transport security (this is at-rest only).

## Success looks like
The audit log on disk is unreadable without the key, and the tools that read it still work.

## Dependencies / notes
- Parent: PRO-0005.
- Key management is the real design question — resolve it at triage/plan, not here. Keychain is the likely home.
- Pairs with the replay-gate child (12).
