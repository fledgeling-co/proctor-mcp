# PRO-0022: A drawing fault must not kill the agent

**ID:** PRO-0022
**Status:** Merged
**Created:** 2026-08-14
**Last updated:** 2026-08-14
**Brief:** `docs/features-to-triage/23-drawing-fault-must-not-kill-the-agent.md`
**Commit:** `b4a29e5`

## Feature description

<!-- Derived from docs/features-to-triage/23-drawing-fault-must-not-kill-the-agent.md -->

On 2026-08-14, the run HUD aborted the process due to an unhandled AppKit exception in `RunHUDContentView.drawLiveLine` (`NSInvalidArgumentException` / attempt to insert nil into CoreText attributes dictionary). Because `proctor-agent` is the supervision surface and kill-switch, an exception on the drawing path took down the agent, the run in flight, and the MCP server.

An annotation must never kill the thing it annotates.

### What it does

- Catches drawing faults across the `draw(_:)` pass via an Objective-C exception boundary target (`ProctorCatch`).
- Latches the fault in `RunHUDAvailability` and disables the panel so subsequent display cycles do not fault again.
- Reports the fault and its reason through `proctor_doctor` / `RunHUDAvailability`.
- Lets the agent and the active run proceed uninterrupted.

## Implementation retrospective

- Shipped in commit `b4a29e5` on 2026-08-14.
- Introduced `ProctorCatch` target in `Package.swift` providing `@try/@catch` barrier (`ProctorCatchException`).
- Added `DrawingFaultBarrierTests` asserting exception isolation and availability latching.
