# PRO-0115: Subprocess Actuation Witness for Cua Driver

**ID:** PRO-0115
**Status:** Developer Review
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/107-subprocess-actuation-witness-for-cua-driver.md`
**Defects:** DEF-305
**Requirements:** REQ-024, REQ-180
**Cases:** CASE-0700..CASE-0702
**Surfaces:** SURF-035

## Feature description

Build an independent process-lifecycle recorder observing `cua-driver` execution, argument passing, and clean termination without orphaned daemon processes, unblocking BLOCK-0001 and elevating REQ-024.

1. **Subprocess Lifecycle Recorder (`scripts/campaign/subprocess_witness.py`):** Independent recorder that monitors `cua-driver` process launch, argument vectors (`["serve", "--stdio"]`, `["call", "--json", ...]`), exit codes, stderr capture, and Darwin process table state.
2. **Process Cleanup & Daemon Shutdown Interlock (`CuaClients.swift`):** Explicit `stop()` and `deinit` termination interlocks ensuring child driver daemon processes are terminated and waited for, preventing orphaned background processes.
3. **Exit Code & Stderr Capture on Failure:** Standard error output and non-zero exit statuses are captured across endpoint and oneshot transports and propagated into structured `AgentError` messages.
4. **Subprocess Effect Witness Suite (`CuaSubprocessWitnessTests.swift`):** Dedicated test suite observing real child process spawns, sentinel file creation, argument verification, and nonzero effect witness counts.
5. **Unblocking BLOCK-0001 & Elevating REQ-024:** Transitions REQ-024 from `vacuous` to `observed` with an explicit effect witness case at oracle rung `effect-witness`, closing the unmeasured effect boundary.

## Acceptance sketch

- Process-table recorder observes `cua-driver` spawn, execution, and exit.
- Subprocess exit codes and standard error are captured on driver failures.
- No orphaned driver processes remain on agent shutdown.
- REQ-024 transitions to observed with a verified non-zero effect witness count.

## Progress — PRO-0115

**Defects:** DEF-305
**Requirements:** REQ-024, REQ-180
**Cases:** CASE-0700..CASE-0702
**Surfaces:** SURF-035

- Built `scripts/campaign/subprocess_witness.py` with standalone CLI, process table inspection, orphan detection, and 5-scenario truth table verification.
- Updated `CuaClients.swift` (`CuaEndpointTransport` and `CuaOneShotTransport`) with stderr pipe capture, clean termination on `stop()`, and `deinit` cleanup interlock.
- Implemented `Tests/ProctorAgentTests/CuaSubprocessWitnessTests.swift` covering endpoint lifecycle, oneshot stderr capture, and subprocess effect witnessing.
- Added `test_subprocess_witness_characterization` to `scripts/campaign/test_instruments.py`.
- Registered SURF-035, REQ-180, DEF-305, and CASE-0700..CASE-0702, transitioning REQ-024 to observed.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-305 | Cua actuation subprocess unmeasured effect boundary, missing stderr capture on failure, and daemon orphan interlock (BLOCK-0001) | fixed |
