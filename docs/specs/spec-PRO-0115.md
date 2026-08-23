# PRO-0115: Subprocess Actuation Witness for Cua Driver

**ID:** PRO-0115
**Status:** Ready for Plan
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/107-subprocess-actuation-witness-for-cua-driver.md`

## Feature description

Build an independent process-lifecycle recorder observing `cua-driver` execution, argument passing, and clean termination without orphaned daemon processes, unblocking BLOCK-0001 and elevating REQ-024.

## Acceptance sketch

- Process-table recorder observes `cua-driver` spawn, execution, and exit.
- Subprocess exit codes and standard error are captured on driver failures.
- No orphaned driver processes remain on agent shutdown.
- REQ-024 transitions to observed with a verified non-zero effect witness count.

## Assumptions made writing this

- Assuming process-table witnessing operates without root/sudo privileges via Darwin libproc/proc_pidinfo.
