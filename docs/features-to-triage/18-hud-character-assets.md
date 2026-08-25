---
sources: [REQ-006]
status: retired
---
# HUD character — sprite assets and state binding

**Status:** untriaged · **Value:** med · **Effort:** med · **Source:** design session 2026-08-14 · **Spec:** `docs/design/run-hud-character.md`

## What it is
The run HUD's companion character: a compact-Mac pixel sprite that changes with run state, sitting in a 38pt inset bay at the left of the live line.

Chosen after four concepts were generated and looked at (`design/character/concept-*.jpg`). A glass-gel orb, a Luxo-style desk lamp and an illustrated owl were rejected — the orb had no personality, the lamp's arms and joints vanished below about 60pt, and the owl read as sticker art on a native panel. The sprite won on the test the others failed: pixel art is the only one of the four that gains legibility as it shrinks, and all seven states were verified distinguishable at 38px.

## The rule that governs it
The **screen is the expression**. Arms and lean are secondary and are expected to disappear at small sizes — that is by design, and it means any new state must be readable from its screen glyph alone.

Seven states: idle (dot eyes), travelling (leaning, speed lines), acting (filled vermilion screen, arm pressing), blocked (bold `!`), paused (grey pause bars — the only grey screen, so it is distinguishable without colour), finished (checkmark, sparkles), error (`X`, tilted, smoke).

## What exists and what is owed
Existing: `design/character/sprite-states-sheet-42b853.png` (all seven in one render) and `design/character/states/*.png` (sliced, wired into the mock).

Owed before shipping:

1. **Real alpha.** Every render carries a charcoal background. The mock seats the character in a dark inset bay, which hides this *and* keeps the white body legible on the light panel — so the bay stays regardless — but the shipping assets need cutting out.
2. **Even footprints.** The slices are hand-estimated and the character drifts slightly between cells. Re-crop to a common baseline so it does not jump as state changes.
3. **Animation frames.** Idle, travelling and acting want 4–6 frame loops rather than the CSS transform stand-ins in the mock.
4. **@2x and @3x.**

## Success looks like
The character changes with run state in the built HUD, holds a stable footprint across all seven states, is legible in both appearances, and animates without the agent process drawing frames — commit the loop to the render server, as the cursor overlay's own commentary argues.

## Scope
- In: asset production, the state→asset binding, the frame loops, the bay.
- Out: the character's design. It is settled; re-opening it is a separate decision.

## Dependencies / notes
- Depends on the run HUD panel.
- Regeneration guidance is in `docs/design/run-hud-character.md`. Two facts worth keeping: `style: "openai"` is the model that honours exclusions, and asking for a **transparent** background is what summons a painted checkerboard — ask for flat charcoal instead. Regenerate the whole sheet, never one cell, or the character drifts.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-006
- surface: SURF-004
- cases: CASE-0004, CASE-0008, CASE-0021, CASE-0030, CASE-0032, CASE-0065
- rungs reached: effect-witness, outcome
- provider: NSPanel over the window server in Sources/ProctorAgent/Overlay/RunHUDPanel.swift, readable back through CGWindowListCopyWindowInfo
