---
sources: [REQ-024, REQ-180, DEF-305]
status: retired
---
# Subprocess Actuation Witness for Cua Driver

- origin: intake sweep over BLOCK-0001 (REQ-024) and subprocess effect boundary · 2026-08-24
- audience: models driving native macOS UI via Cua actuation backend
- platforms: mac
- proposed-by-ai: true

## What and why
REQ-024 declares a `subprocess` effect for Cua actuation (`Process()` in `Actuation/CuaClients.swift`) and currently forms BLOCK-0001 because no external recorder witnesses the spawned driver process. Building an independent process-lifecycle witness that observes driver PID launch, argument passing, clean termination, and absence of orphaned daemon processes will unblock the case and close the effect boundary.

## Acceptance sketch
- An independent process-table recorder observes `cua-driver` spawn, execution, and exit.
- Subprocess exit codes and standard error output are captured and surfaced on driver failures.
- Process cleanup interlocks guarantee no orphaned driver processes remain on agent shutdown.
- REQ-024 transitions from unwitnessed to observed with a verified non-zero effect witness count.

## Assumptions made writing this
- Assuming process-table witnessing operates without root/sudo privileges using standard BSD/Darwin APIs (`proc_pidinfo` / `libproc`).
- Assuming driver subprocess execution is verified with both clean exit (code 0) and failure exit paths.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-024, REQ-180
- surface: SURF-001, SURF-003, SURF-035
- cases: CASE-0001, CASE-0003, CASE-0014, CASE-0026, CASE-0038, CASE-0069
- rungs reached: effect-witness, metamorphic, outcome
- provider: Process() in Sources/ProctorAgent/Actuation/CuaClients.swift — cua-driver and obscura
