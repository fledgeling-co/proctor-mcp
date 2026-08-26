---
sources: [REQ-024, REQ-180, DEF-305]
status: retired
validated-by: REQ-024, REQ-180 via CASE-0026, CASE-0087, CASE-0700, CASE-0701, CASE-0702
validated-rungs: effect-witness, outcome
validated-provider: Process() in Sources/ProctorAgent/Actuation/CuaClients.swift — cua-driver and obscura
---
# Subprocess Actuation Witness for Cua Driver

- origin: intake sweep over BLOCK-0001 (REQ-024) and subprocess effect boundary · 2026-08-24
- audience: models driving native macOS UI via Cua actuation backend
- platforms: mac
- proposed-by-ai: true

## What and why
REQ-024 declares a `subprocess` effect for Cua actuation (`Process()` in `Sources/ProctorAgent/Actuation/CuaClients.swift`) and currently forms BLOCK-0001 because no external recorder witnesses the spawned driver process. Building an independent process-lifecycle witness that observes driver PID launch, argument passing, clean termination, and absence of orphaned daemon processes will unblock the case and close the effect boundary.

## Acceptance sketch
- An independent process-table recorder observes `cua-driver` spawn, execution, and exit.
- Subprocess exit codes and standard error output are captured and surfaced on driver failures.
- Process cleanup interlocks guarantee no orphaned driver processes remain on agent shutdown.
- REQ-024 transitions from unwitnessed to observed with a verified non-zero effect witness count.

## Assumptions made writing this
- Assuming process-table witnessing operates without root/sudo privileges using standard BSD/Darwin APIs (`proc_pidinfo` / `libproc`).
- Assuming driver subprocess execution is verified with both clean exit (code 0) and failure exit paths.
