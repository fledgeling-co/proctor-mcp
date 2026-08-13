# Plan — PRO-0003: Menu-bar key-equivalents

**Spec:** docs/specs/spec-PRO-0003.md (Status: Ready for Plan)
**Branch:** ai/pro-0003
**Gate:** `swift build && swift test` from the worktree root (Swift package; web design/e2e stages N/A).
**Plan size:** Small — one new read-only tool, one new pure-logic unit in ProctorCore, one AX walk in the agent. No new plane, no new permission, no transport change.

## Goal

Add `proctor_menu`, a read-only tool that walks the target app's `AXMenuBar` and returns, for
every non-separator item: its **menu path**, **title**, **enabled** state, and its **normalised
key-equivalent** (`cmd+shift+n`) decomposed into the exact `key` + `modifiers` the existing `act`
`key` step consumes. Submenus that only populate on open are reported as an unpopulated node, not
fabricated.

## Design decisions (grounded in the codebase)

Follows the repo's established split (see PRO-0002 / `SetOfMarks`, `PointerPath`, `CUATranslator`):
**load-bearing pure logic lives in `ProctorCore` and is unit-tested; the OS-touching AX read lives
in the agent and is compile-verified, not unit-tested** (the test target is `ProctorCoreTests`,
which links `ProctorCore` only). The key-equivalent reconstruction is the load-bearing part, so it
is pure and is where the red→green tests land.

1. **Pure reconstruction + flatten → `Sources/ProctorCore/MenuKeyEquivalent.swift` (new).**
   - `MenuKeyEquivalent.modifiers(fromCarbonMask:)` — decode the Carbon menu modifier bitmask.
     **Command is implied unless the no-command bit is set**; this is the load-bearing detail:
     `shift = 0x01`, `option = 0x02`, `control = 0x04`, `noCommand = 0x08`. So mask `0` → `[cmd]`,
     mask `0x08` → `[]`, mask `0x09` → `[shift]`. Canonical order `cmd, ctrl, opt, shift`.
   - `MenuKeyEquivalent.keyName(char:virtualKey:glyph:)` — resolve the key: a usable printable
     `cmdChar` first (lowercased; function-key/control scalars are *not* usable and fall through),
     else `cmdVirtualKey` via a keycode→name table, else `cmdGlyph` via a glyph→name table. Names
     are exactly those the `act` `key` step accepts (KeyCodes vocabulary): `n`, `left`, `f2`, …
   - `MenuKeyEquivalent.shortcut(...)` — the normalised string, cmd-first, `+`-joined, e.g.
     `cmd+shift+n`; `nil` when no key resolves.
   - `MenuItem` (Codable, public) output row + `RawMenuItem` (public) input node.
   - `flatten(bar:)` — DFS `RawMenuItem` tree → `[MenuItem]` with menu paths, dropping separators,
     emitting parent rows with `hasSubmenu`, and marking a lazily-empty submenu `submenuPopulated:
     false` **without** descending into (fabricating) it.

2. **Tool surface → `Sources/ProctorCore/ToolCatalogue.swift` + `ToolOutputSchemas.swift` +
   `ToolProfiles.swift`.** Append `menu` spec (read-only, non-destructive, idempotent) to `all`;
   add its bespoke output schema; add `proctor_menu` to the `ax` profile list (so it flows through
   `ax ⊂ core ⊂ scripting ⊂ full`). Advertised tool count 14 → **15**.

3. **AX walk → `Sources/ProctorAgent/AX/MenuBarReader.swift` (new).** Reads `AXMenuBar` from the
   app element and builds the `RawMenuItem` tree, reading the menu-item cmd attributes by their raw
   AX strings (`AXMenuItemCmdChar`, `AXMenuItemCmdVirtualKey`, `AXMenuItemCmdGlyph`,
   `AXMenuItemCmdModifiers`) + `AXEnabled` + `AXTitle`, mirroring how `Actuator.menu` already walks
   the bar and how `AXAttr.manualAccessibility` uses a raw string constant. A submenu present but
   empty at read time is recorded as `submenuUnpopulated` (lazy-menu honesty), not descended.

4. **Protocol + engine → `Contracts.swift` (`AXEngine.menuBar(app:)`) + `AXEngineImpl.swift`.**
   `AXEngineImpl` is the sole conformer, so the protocol addition touches one implementation.

5. **Session + dispatch → `Session/SessionMenu.swift` (new) + `Dispatch.swift`.** `proctor_menu`
   accepts `app` (an app handle) or `window` (its app is resolved); returns `{app, itemCount,
   items, note}` where `note` carries the lazy-menu limitation. Keeping the session method in its
   own extension file avoids editing the large `Session.swift`.

## Invocation-by-key-equivalent (the spec's "act invokes via its key-equivalent")

No `act` change is needed. Each `MenuItem` carries `key` + `modifiers` in the exact shape the
existing `act` `key` step reads, so an agent enumerates the menu, finds "New", and issues
`{kind:key, key:"n", modifiers:["cmd","shift"]}`. That step is synthetic-event/foreground (per
`architecture.md`); for a **background-safe** invocation the same enumeration also yields the
`menuPath`, which the existing `menu` step actuates through the accessibility plane. Both routes
come from the one enumeration; the tool description states this rather than implying a synthetic key
reaches a background window.

## Scope

**In:** menu-bar walk with per-item path, title, enabled state, normalised shortcut string, and the
`key`+`modifiers` decomposition; lazy-submenu limitation reported honestly.
**Out:** opening lazy submenus to populate them; a new actuation plane; changing `act`. Pure AX
read; no new permission.

## Files

| File | Change |
|---|---|
| `Sources/ProctorCore/MenuKeyEquivalent.swift` | NEW — modifier/key/glyph reconstruction, `MenuItem`, `RawMenuItem`, flatten |
| `Sources/ProctorCore/ToolCatalogue.swift` | `menu` spec; append to `all` (14→15) |
| `Sources/ProctorCore/ToolOutputSchemas.swift` | bespoke `proctor_menu` output schema |
| `Sources/ProctorCore/ToolProfiles.swift` | add `proctor_menu` to the `ax` list |
| `Sources/ProctorAgent/AX/MenuBarReader.swift` | NEW — AXMenuBar walk → `RawMenuItem` |
| `Sources/ProctorAgent/Contracts.swift` | `AXEngine.menuBar(app:)` |
| `Sources/ProctorAgent/AX/AXEngineImpl.swift` | conform: `menuBar(app:)` |
| `Sources/ProctorAgent/Session/SessionMenu.swift` | NEW — `Session.menuBar(app:window:)` |
| `Sources/ProctorAgent/Dispatch.swift` | `proctor_menu` case + arg decode |
| `Tests/ProctorCoreTests/ProctorCoreTests.swift` | `@Suite("Menu key-equivalents")`; bump count 14→15 |

## Test plan (Swift-shaped, per acceptance clause)

Unit tests on `MenuKeyEquivalent` (pure, no app/grant needed):
- **AC1 modifier decode:** the Carbon mask maps correctly, command implied unless no-command bit
  set: `0→[cmd]`, `0x01→[cmd,shift]`, `0x02→[cmd,opt]`, `0x04→[cmd,ctrl]`, `0x08→[]`,
  `0x09→[shift]`, `0x07→[cmd,ctrl,opt,shift]` (canonical order).
- **AC2 normalised string:** `char:"N", mask:0 → "cmd+n"`; `char:"N", mask:0x01 → "cmd+shift+n"`
  (matches the spec example); no resolvable key → `nil`.
- **AC3 non-character equivalents:** `virtualKey:<left> → "left"` so `mask:0 → "cmd+left"`;
  `virtualKey:<f2> , mask:0x08 → "f2"`; a glyph (e.g. page-up, escape) resolves to its key name.
- **AC4 catalogue:** `ToolCatalogue.all.count == 15`; `proctor_menu` is read-only, non-destructive,
  idempotent, object schema, `proctor_` prefix, and present in every profile via `ax`.
- **AC5 flatten:** a `RawMenuItem` tree yields the right rows — parent rows carry `hasSubmenu`,
  leaves carry their shortcut, **separators are dropped**, and a **lazily-empty submenu is one row
  with `submenuPopulated:false` and no fabricated children beneath it**.

Gate: `swift build && swift test` green from the worktree; affected-test sweep = the full
`ProctorCoreTests` target (the only target compiling the changed `ProctorCore`). The AX walk in
`MenuBarReader`/`AXEngineImpl` is compile-verified by `swift build`, matching how `MarkRenderer` and
the `CGEventPost` actuation are not unit-tested.

## Non-breaking / risk notes
- New tool + new files; the only edits to shared merge surfaces are additive: append one spec to
  `all`, one schema, one profile-list entry, one dispatch case, one protocol method. A union merge
  is mechanical. Tool-count assertion updated 14→15 on this branch; the orchestrator reconciles the
  final count at merge.
- Menu-item cmd attributes read by raw AX string (as `AXManualAccessibility` already is), so no
  dependency on an SDK Swift export.
