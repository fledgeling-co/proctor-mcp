---
sources: [REQ-011, REQ-031]
status: retired
---
# Menu-bar enumeration with key-equivalents

**Status:** untriaged · **Value:** med-high · **Effort:** easy · **Source:** zavora-ai/computer-use-mcp (`list_menu_bar`)
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
A tool (or a `find` mode) that enumerates the target app's menu bar and, for each item, returns its **key-equivalent** — the keyboard shortcut, e.g. `cmd+shift+n` — alongside the menu path and enabled state.

## Why (for computer use / testing)
Pressing a shortcut is more robust and faster than walking `AXMenuBar` → submenu → item, which is slow, focus-sensitive, and brittle across localisations. Surfacing the shortcut lets the agent choose the keystroke path when one exists. Proctor already has the AX access, so this is cheap and high-yield.

## Proposed approach on Proctor
- Walk `AXMenuBar` for the attached app, reading `AXMenuItemCmdChar` / `AXMenuItemCmdModifiers` (and the glyph variants) to reconstruct the key-equivalent.
- Return menu path, title, enabled state, and the normalised shortcut string per item.
- Feed shortcuts into `act` so a step can say "invoke New" and Proctor presses the shortcut rather than navigating the menu.

## Scope
- In: menu-bar walk with key-equivalents, enabled state, normalised shortcut strings.
- Out: dynamically-generated menus that only populate on open (note the limitation; don't fabricate).

## Success looks like
`list_menu_bar` returns each item with its shortcut, and an `act` step invokes a menu command via its key-equivalent instead of a menu walk, on a background window.

## Dependencies / notes
- Pure AX; no new plane, no new permission.
- Complements the AppleEvents driver (04) as a third actuation route.
- Not obviously site-relevant on its own.
- Licensing: reimplement on AX APIs; MIT source.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-011, REQ-031
- surface: SURF-010, SURF-036
- cases: CASE-0013, CASE-0037, CASE-0258, CASE-0259, CASE-0260, CASE-0266
- rungs reached: effect-witness, outcome, raster-visual
- provider: none
