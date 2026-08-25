---
sources: [REQ-011, REQ-031]
status: retired
---
# The menu bar, and the complete command surface

**Wave 9, brief 4 of 11.** Reads `58`, `59`, and lands after `61`. Mock anchors:
`#mac/menubar/idle`, `…/running`, `…/foreground`, `…/down`, and `#mac/menus/all`.

## The problem

Two gaps, and the second is the one that matters.

**The extras menu has three states in the mock and one in the app.** The shipped
`MenuBarContent` draws a live line and conditional Pause/Stop. The mock adds the
foreground disclosure — the state where a run is *about to* take the machine and has not
yet — which is the only moment a person can act on the information.

**There is no menu bar.** `ProctorUIApp` declares `Window`, `Window` and `MenuBarExtra`, and
the `.commands` block carries one item. The native grammar is explicit and the HIG is cited
in `mac-craft`'s foundation: every toolbar command also exists as a menu command, because
people hide and customise toolbars, and a toolbar-only command can disappear. The app
currently ships a Pause and a Stop reachable from a floating panel and a menu-bar extra,
and from no menu at all — which means a person who has hidden the panel and does not know
about the extras item has no path to the kill switch.

The mock draws the whole command surface: Proctor, Run, Window, Help, with shortcuts.

## What it should do

Four extras states, and a real menu bar carrying every command.

| Extras state | Shows |
|---|---|
| idle | the character, the last run, Pause and Stop dimmed |
| running | the live line, the provenance chip, Pause highlighted |
| foreground | what the batch will do to the machine, stated as a floor |
| down | the agent is not answering, and the action that starts it |

## The conversion contract

- `CommandSurface` in `ProctorCore`: every command, its title, its shortcut, the menu it
  belongs to, and whether it is enabled in a given run state. Pure, and the single source
  for both the menu bar and the extras menu.
- `RunHUDMenuBar` already owns part of this and has tests; extend it rather than adding a
  parallel table.

## Acceptance

1. **Every command reachable from the run panel or the extras menu is also in the menu bar.**
   A test enumerates both and fails on a command present in one and absent from the other.
   This is the clause the brief exists for.
2. Pause and Stop are present in every state and disabled rather than absent where they do
   not apply; the test asserts presence in all four.
3. The foreground disclosure is stated as a floor. `ForegroundDemand` already computes it and
   already refuses to print a bare "N of M" where a conditional step could add to N — the
   menu reads that value and does not re-derive it.
4. Shortcuts are unique across the whole surface, and the test proves it.
5. The panel switch is disabled when the agent was launched with `PROCTOR_HUD` off, with the
   reason stated rather than left as a greyed item nobody can explain.

## The hard parts, named

**Three answers to one question is how they drift.** The foreground demand is computed once,
in `ForegroundDemand`, and the panel, the menu bar and the extras menu all read it. Do not
let the menu compute its own.

**The character carries state by shape, not only by colour.** The mock's seven states each
change the figure's posture, so the state survives greyscale and a colourblind reader.
Brief 63 owns the asset set; this brief owns which state the menu bar shows when.

## Out of scope

- Settings is a real window via ⌘, per the platform grammar. This app has no Settings window
  and the switches live in the status window instead. That is a defensible choice for a
  background agent and this brief does not change it — but it is worth recording as a
  deliberate deviation rather than an oversight.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-011, REQ-031
- surface: SURF-010, SURF-036
- cases: CASE-0013, CASE-0037, CASE-0258, CASE-0259, CASE-0260, CASE-0266
- rungs reached: effect-witness, outcome, raster-visual
- provider: none
