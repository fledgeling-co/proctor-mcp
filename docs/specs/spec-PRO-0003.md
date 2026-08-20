# PRO-0003: Menu-bar key-equivalents

**ID:** PRO-0003
**Status:** Merged
**Created:** 2026-08-13
**Last updated:** 2026-08-13
**Plan:** docs/plans/plan-PRO-0003.md

## Feature description

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

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S0 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible — behind the scenes. Adds menu-bar enumeration with each item’s keyboard shortcut and enabled state.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Data & scope]` Pure AX read (AXMenuBar + cmd char/modifiers); no new permission. (existing AX access)
- `[Operations]` Dynamically-populated menus are noted as a limitation, not fabricated. (honesty over coverage)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0003` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).

---

## Progress — 2026-08-13 (branch ai/pro-0003)

**Delivered.** New read-only tool `proctor_menu` enumerates the attached app's menu bar with reconstructed key-equivalents. Advertised tool count 14 → 15 on this branch.

- **Pure logic (tested):** `Sources/ProctorCore/MenuKeyEquivalent.swift` — Carbon modifier decode (⌘ implied unless the no-command bit is set), key resolution (printable cmdChar → virtual keycode → menu glyph), normalised shortcut string (`cmd+shift+n`), and `RawMenuItem`→`[MenuItem]` flatten (drops separators, marks lazily-unpopulated submenus without fabricating contents).
- **AX walk (compile-verified):** `Sources/ProctorAgent/AX/MenuBarReader.swift` reads `AXMenuBar` + the `AXMenuItemCmd*` attributes; never presses to populate a lazy submenu. Wired via `AXEngine.menuBar(app:)`, `Session.menuBar(app:window:)`, and the `proctor_menu` dispatch case.
- **Invocation:** each row carries `key`+`modifiers` in the exact `act` `key`-step shape (synthetic/foreground) and the `menuPath` for the background-safe `menu` step — both from the one walk. No `act` change.

**Gate:** `swift build` clean; `swift test` 95 tests / 14 suites pass (adds `@Suite("Menu key-equivalents")`, 12 tests). Codex out-of-family gate opted out (external-model-clis: off); run in-family.

**Status:** In Review — committed to `ai/pro-0003`, not merged.
