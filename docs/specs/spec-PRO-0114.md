# PRO-0114: Supervision TUI and Menu Bar Status Extra On-Glass Witness

**ID:** PRO-0114
**Status:** Developer Review
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/106-supervision-tui-and-menu-bar-glass-witness.md`
**Defects:** DEF-310
**Requirements:** REQ-030, REQ-031, REQ-033, REQ-185
**Cases:** CASE-0710..CASE-0715
**Surfaces:** SURF-036

## Feature description

Provide automated pseudo-terminal (pty) and AppKit `NSMenu` hierarchy witnesses elevating REQ-030 (TUI rendering at 80x24 floor and 100x30 target), REQ-031 (Menu bar 20-command and 21-tool catalogue hierarchy), and REQ-033 (Supervision client readiness, switches, and history projection) from self-reported intent to verified observed outcomes.

1. **Supervision TUI Headless PTY Probe (`scripts/campaign/supervision_tui_pty_probe.py`):** Independent pty harness testing 5-pane TUI rendering at 80x24 floor & 100x30 target geometries, asserting 0 horizontal line overflow, DEC mode 2026 atomic frame synchronisation, uppercase active tab navigation ('1'..'5'), and clean teardown on 'q'.
2. **Interactive Latch State Mutation Witness (`SupervisionTUIPtyWitnessTests.swift`):** Validates that operator keypresses ('p' for pause/resume, 's' for stop) decode keys, mutate shared `RunControl` latch state, and dispatch structured control actions over the wire.
3. **AppKit NSMenu Extra Hierarchy Witness (`MenuBarHierarchyWitnessTests.swift`):** Live traversal of the AppKit `NSMenu` and `NSMenuItem` extra hierarchy verifying that all 20 declared commands in `CommandSurface.all` and 21 tools in `ToolCatalogue.all` populate the menu bar and status extra with title-casing, key equivalents, and dynamic enablement.
4. **Supervision Client Readiness and History Projection (`SupervisionTUIPtyWitnessTests.swift`):** Validates that supervision client queries doctor reports and history across IPC, projecting readiness grants, switches, and audit records into TUI panes (REQ-033).
5. **Elevating REQ-030, REQ-031, and REQ-033 to Observed:** Transitions REQ-030, REQ-031, and REQ-033 from `unknown` to `observed` with typed effect witnesses (`CASE-0710..CASE-0715`).

## Acceptance sketch

- `proctor tui` rendering is verified via an automated pty harness at both 80x24 and 100x30 geometries.
- Every command in the 21-tool catalogue and 20 menu bar commands is verified in the live AppKit `NSMenu` extra hierarchy.
- Latch status updates (Pause/Stop) initiated via TUI keypresses are witnessed in the agent's shared state.
- REQ-030, REQ-031, and REQ-033 transition to observed with independent test witnesses.

## Progress — PRO-0114

**Defects:** DEF-310
**Requirements:** REQ-030, REQ-031, REQ-033, REQ-185
**Cases:** CASE-0710..CASE-0715
**Surfaces:** SURF-036

- Built `scripts/campaign/supervision_tui_pty_probe.py` with standalone CLI and 5-scenario truth table verification.
- Added `test_supervision_tui_pty_probe_characterization` to `scripts/campaign/test_instruments.py`.
- Implemented `Tests/ProctorAgentTests/SupervisionTUIPtyWitnessTests.swift` covering 80x24 floor rendering, 100x30 target geometry, tab navigation, latch mutation dispatch, and readiness/history projection.
- Implemented `Tests/ProctorAgentTests/MenuBarHierarchyWitnessTests.swift` covering AppKit `NSMenu` hierarchy traversal and 21-tool catalogue verification.
- Registered SURF-036, REQ-185, DEF-310, and CASE-0710..CASE-0715, transitioning REQ-030, REQ-031, and REQ-033 to observed.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-310 | Supervision TUI 80x24/100x30 rendering and menu bar command hierarchy lacked automated pty and NSMenu on-glass effect witnesses | fixed |
