---
sources: [REQ-030, REQ-031, REQ-033]
status: retired
---
# Supervision TUI and Menu Bar Status Extra On-Glass Witness

- origin: intake sweep over unmeasured/unknown requirements (REQ-030, REQ-031, REQ-033) · 2026-08-24
- audience: operators supervising unattended agent runs over SSH or menu bar
- platforms: mac
- proposed-by-ai: true

## What and why
Proctor provides a five-pane supervision TUI over SSH (`proctor tui`) and a menu bar status item extra with 21 tool commands. Currently, requirements REQ-030 (TUI rendering at 80x24 and 100x30) and REQ-031 (menu bar command enumeration) stand on self-reported assertions without independent terminal pty and NSMenu inspection. Providing dedicated on-glass and pty effect witnesses will elevate these surfaces from self-reported intent to verified observable outcomes.

## Acceptance sketch
- `proctor tui` rendering is verified via an automated pseudo-terminal (pty) harness at both 80x24 minimum and 100x30 target geometries.
- Every command declared in the 21-tool catalogue is verified to exist in the running `NSMenu` extra hierarchy.
- Latch status updates (Pause/Stop) initiated via TUI keypresses are independently witnessed in the agent's shared state store.
- REQ-030, REQ-031, and REQ-033 transition from `unknown` to `observed` with independent test witnesses.

## Assumptions made writing this
- Assuming the pty harness runs headlessly without requiring interactive user terminal input.
- Assuming AppKit menu inspection queries the live `NSStatusBar` item rather than a mock model.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-030, REQ-031, REQ-033
- surface: SURF-010, SURF-017, SURF-036
- cases: CASE-0013, CASE-0033, CASE-0034, CASE-0035, CASE-0036, CASE-0037
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: Terminal.paint in Sources/ProctorCLI/TUI/Terminal.swift; scripts/campaign/supervision_tui_pty_probe.py
