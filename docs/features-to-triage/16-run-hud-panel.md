---
sources: [REQ-006]
status: retired
validated-by: REQ-006 via CASE-0008, CASE-0030, CASE-0065
validated-rungs: effect-witness, outcome
validated-provider: NSPanel over the window server in Sources/ProctorAgent/Overlay/RunHUDPanel.swift, readable back through CGWindowListCopyWindowInfo
---
# Run HUD — the overlay shown while Proctor drives an app

**Status:** untriaged · **Value:** high · **Effort:** high · **Source:** design session 2026-08-14

## What it is
A floating panel the agent shows while a run is in flight, so a person watching can see what Proctor is doing and stop it. Design is settled and rendered: **`mocks/run-hud.html`** is the reference (open it over HTTP, not `file://`).

## The design, in short
One direction survived review — the Ledger, a 352pt panel docked bottom-right:

- **A single live line at one type size.** The verb carries the state ("Pressing", "About to press", "Paused before", "never settled"), so there is no second line and no status label. Nothing truncates; copy is written short at the source.
- **A step counter** (`3/7`), tabular and fixed-width, so a value change never moves its neighbour. Every numeric slot in the panel follows this rule.
- **A progress rail** along the panel's own bottom edge, filled in the live colour.
- **A three-row trail** of recent steps with their settle times.
- **Run controls:** Pause and Stop.
- **One state variable** (`--live` in the mock) drives the character, the rail and the emphasised words together, so the panel changes colour as one object: vermilion running, amber blocked, red error, green finished, grey paused/idle.

Two rules that came out of review and are load-bearing:

- **Neutral ground, not the app palette.** The onboarding mock's warm porcelain reads as brown mud when it floats over someone else's app. The HUD is neutral graphite / neutral white with vermilion as the only colour on it.
- **Surface the exception, not the rule.** Accessibility is the normal plane and is never announced. A synthetic step says so in words, once: "Synthetic event — Acme Console must stay in front".

## Behaviour
- Click-through everywhere except its controls.
- Draggable by the grip.
- Honours `prefers-reduced-transparency` (solid background) and `prefers-reduced-motion`.
- Appears when a run starts, lingers briefly after it ends, and can be turned off entirely — the same off-switch shape as `PROCTOR_CURSOR`, because an unattended suite on a machine someone else is using should be able to leave the screen alone.

## Success looks like
A run driven from an MCP client shows the panel over the driven app; the live line and counter track the steps; Pause holds before the next step without killing the one in flight; Stop ends the run and the owning session's call returns a refusal naming that a person stopped it.

## Scope
- In: the panel, its states, the run controls, the off-switch.
- Out: the queue (separate brief), the character art (separate brief) — build the character's 38pt bay as an empty inset and leave it empty.

## Dependencies / notes
- **Blocked by the agent-panel-rendering fix.** This is the same shape of panel from the same process whose panel currently draws nothing.
- Needs the derived step descriptions to fill its live line.
- Light and dark are authored independently in the mock; both are in the reference.
