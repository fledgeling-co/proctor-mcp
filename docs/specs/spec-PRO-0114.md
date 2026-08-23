# PRO-0114: Supervision TUI and Menu Bar Status Extra On-Glass Witness

**ID:** PRO-0114
**Status:** Ready for Plan
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/106-supervision-tui-and-menu-bar-glass-witness.md`

## Feature description

Provide automated pseudo-terminal (pty) and NSMenu hierarchy witnesses elevating REQ-030 (TUI rendering at 80x24 floor and 100x30 target) and REQ-031 (Menu bar 21-command hierarchy) from self-reported intent to verified observed outcomes.

## Acceptance sketch

- `proctor tui` rendering is verified via an automated pty harness at both 80x24 and 100x30 geometries.
- Every command in the 21-tool catalogue is verified in the live `NSMenu` extra hierarchy.
- Latch status updates (Pause/Stop) initiated via TUI keypresses are witnessed in the agent's shared state.
- REQ-030 and REQ-031 transition from unknown to observed with independent test witnesses.

## Assumptions made writing this

- Assuming pty harness runs headlessly without requiring interactive user terminal input.
- Assuming AppKit menu inspection queries the live NSStatusBar item.
