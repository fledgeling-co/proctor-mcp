# Spec PRO-0123 — Tart and Lume Guest VM Virtualization Fixture

**Brief:** `docs/features-to-triage/115-tart-and-lume-guest-vm-virtualization-fixture.md`
**Status:** Merged
**Created:** 2026-08-24
**Surfaces:** SURF-013
**Defects:** BLOCK-0004

## Context & Purpose
Provide a multi-architecture guest virtualization fixture runner for Tart and Lume backends, enabling guest VM attachment, lifecycle control, and multi-session queue verification in test campaigns.

## Acceptance Criteria
1. `GuestProvider` detects local Tart and Lume virtual machine images.
2. Guest attachment establishes socket communication and registers guest agent identity.
3. Capacity manager enforces two-slot concurrency limit and queues excess requests.
4. Stop commands cleanly terminate guest instances and verify shutdown state.
