# Spec PRO-0122 — iOS Simulator Boot Fixture Harness

**Brief:** `docs/features-to-triage/114-ios-simulator-boot-fixture-harness.md`
**Status:** Merged
**Created:** 2026-08-24
**Surfaces:** SURF-019
**Defects:** BLOCK-0001

## Context & Purpose
Provide a deterministic fixture and boot state harness for `proctor_ios` simulator verification in test campaigns, enabling mobile automation assertions to execute against live simulator hierarchies without requiring physical hardware.

## Acceptance Criteria
1. `IOSDeviceList` detects booted vs shutdown simulator instances reliably.
2. Missing simulator runtimes produce structured availability diagnostics rather than throwing unexpected exceptions.
3. Simulator boot-state transitions and device lifecycle are monitored through `IOSDevice`.
4. Effect witness verifies device list and boot state reporting.
