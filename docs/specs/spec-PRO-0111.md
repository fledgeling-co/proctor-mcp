# PRO-0111: Audit of the three recorded limits

**ID:** PRO-0111
**Status:** In Progress
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/103-the-three-recorded-limits-audit.md`
**Requirements:** REQ-160, REQ-161, REQ-162 · **Defects:** DEF-141, DEF-151, DEF-180, DEF-285 · **Cases:** CASE-0630..CASE-0638

## Feature description

Audit, formalize, and establish reproducible test instruments and characterization probes for the three historical recorded limits in the campaign inventory:
1. **DEF-141 (Filesystem Certification Scope vs Read-Isolation Contract):** Formalizes the exact boundary of REQ-055 (writes witnessed across two calls over the application-support root) and defines REQ-160 as the distinct Filesystem Read-Isolation Policy Contract, verified by `ReadIsolationPolicyTests.swift`.
2. **DEF-151 (Real Hardware Keyboard Input Yield Characterization):** Establishes an explicit characterization probe `scripts/campaign/hardware_yield_probe.py` and unit test suite `HardwareInputBoundaryTests.swift` proving the boundary between kernel `IOHIDEvent` dispatch (`sourcePid == 0`) and synthetic user-space `CGEvent` injection (`sourcePid > 0`), with full matrix verification of tagging and grace period filtering.
3. **DEF-180 (Screen Recording TCC Dynamic Re-probe Lifecycle):** Establishes an explicit characterization probe `scripts/campaign/dynamic_grant_probe.py` and test suite `DynamicGrantProbeTests.swift`, formalizing the per-process caching invariant while adding an explicit dynamic invalidation seam (`GrantProbeKeeper.invalidateDefinite()` and `ScreenRecordingProbe.invalidate()`) enabling on-demand re-probing without daemon restart.

## Acceptance criteria

1. **A1 (Filesystem Read-Isolation Contract):** REQ-160 formally defines the read-isolation contract across `PolicyStore`, `CaptureEngine`, `FlowStore`, and `Maestro`. Verified by CASE-0630..CASE-0632 in `Tests/ProctorAgentTests/ReadIsolationPolicyTests.swift`.
2. **A2 (Hardware Input Event Source Characterization):** REQ-161 and probe `scripts/campaign/hardware_yield_probe.py` assert the truth table and OS event-source non-forgery boundary for kernel `IOHIDEvent` (`sourcePid == 0`) vs synthetic `CGEvent` (`sourcePid > 0`). Verified by CASE-0633..CASE-0635 in `Tests/ProctorCoreTests/HardwareInputBoundaryTests.swift`.
3. **A3 (Screen Recording Dynamic Re-probe Lifecycle):** REQ-162 and probe `scripts/campaign/dynamic_grant_probe.py` verify that `GrantProbeKeeper` caches definite verdicts for process lifetime by default, while `invalidateDefinite()` clears the cache and resets backoff for fresh platform queries. Verified by CASE-0636..CASE-0638 in `Tests/ProctorCoreTests/DynamicGrantProbeTests.swift`.
4. **A4 (Campaign Gate Cleanliness):** All campaign gate instruments (`test_instruments.py`, `defect_gate.py`, `spec_citation_measure.py`, `shot_disposition.py`, `capture-lineage.py`) pass cleanly.

## Defects

| ID | Title | Status | Resolution / Boundary |
|---|---|---|---|
| DEF-141 | REQ-055's original sentence certified reads, the whole run and every operator path; the witness watches writes, two calls and one root | Fixed | Formalized REQ-055 write-witness scope and defined REQ-160 read-isolation policy contract. Verified by CASE-0630..0632. |
| DEF-151 | Whether the userInput yield fires for a real hand on a real keyboard is still unproved | Fixed | Formalized kernel IOHIDEvent (sourcePid == 0) vs synthetic CGEvent (sourcePid > 0) boundary with characterization probe and test suite. Verified by CASE-0633..0635. |
| DEF-180 | A Screen Recording answer is frozen for the life of the agent process, so a revoked grant is reported as granted until it restarts | Fixed | Formalized TCC caching policy and added explicit dynamic invalidation seam for on-demand re-probing. Verified by CASE-0636..0638. |
| DEF-285 | Unprivileged user-space processes cannot forge kernel IOHIDEvent sourcePid 0 without driver entitlements | Fixed | Audited and verified that WindowServer overrides kCGEventSourceUnixProcessID on unprivileged user-space posts, proving PersonInput.isAPerson non-forgery boundary. Verified by CASE-0633..0635. |

