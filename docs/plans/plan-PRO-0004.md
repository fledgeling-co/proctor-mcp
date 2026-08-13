# Plan — PRO-0004: App scripting-dictionary introspection

**Spec:** docs/specs/spec-PRO-0004.md · **Branch:** ai/pro-0004 · **Tier:** Small
**Gate:** `swift build` + `swift test` (Swift package; web design/e2e stages N/A)

## Goal

A read-only tool that reads an attached app's scripting definition (sdef) — suites,
commands, classes, properties, enumerations — returns it as structured data plus a
one-line capability summary, and caches it per app-handle (so a relaunch invalidates
it). This makes the Apple-Events plane self-describing so an agent can choose the
scripting route where it is exact and fall back to AX where it is not.

## Approach (matches the existing idiom)

Split pure parsing (unit-testable in ProctorCore, the repo's only test target) from
IO (Session, verified by build). Same split as `CUAFacade` (pure) ↔ `SessionCUA`
(execution), and `SetOfMarks` (pure) ↔ `Session.annotateCapture`.

- **ProctorCore/ScriptingDictionary.swift** (new, pure):
  - Codable `AppScriptingDictionary` { appName, scriptable, suites[], counts, summary }
    with nested Suite/Command/Parameter/Class/Property/Enumeration/Enumerator models.
  - `ScriptingDictionary.parse(sdefXML:appName:) -> AppScriptingDictionary` using
    Foundation `XMLDocument` with `.nodeLoadExternalEntitiesNever` (no XXE: the sdef
    DOCTYPE references an external DTD we must never fetch — the app bundle is
    untrusted input). Handles `command`/`parameter`/`direct-parameter`/`result`,
    `class` + `class-extension`, `property`, `element`, `enumeration`/`enumerator`.
  - `scriptable` = at least one command exists. Empty/malformed input returns a
    not-scriptable dictionary rather than throwing — "not scriptable" is a valid
    answer that feeds route selection, not an error.
  - `summary(for:)` → one deterministic line: app name, scriptability, counts, a few
    command names; or a route hint when not scriptable.
  - `ScriptingDictionaryCache` value type keyed by `AppHandle.id` (which embeds
    `pid:epoch`), so a relaunch (new epoch) misses and a re-read hits.

- **ProctorAgent/Session/SessionDictionary.swift** (new, IO):
  - `func dictionary(app:window:summaryOnly:refresh:) async throws -> JSONValue`.
  - Resolve the AppHandle from `app` or (via windowHandle) `window`; else
    invalidArguments / appNotFound.
  - Cache lookup by handle id unless `refresh`; on miss, resolve the bundle URL via
    `NSRunningApplication(processIdentifier:)`, run `/usr/bin/sdef <bundle>` (it
    resolves xi:includes and merges terminology; drain-then-wait avoids a pipe
    deadlock), parse the output, store, return.
  - A non-scriptable / sdef-less app returns a normal result (`scriptable:false`,
    caveat), never an error. `summaryOnly` omits the heavy `suites` array.
  - Cache entry dropped on detach (mirrors window/revision cleanup).

- **Wiring (shared files, union-merge friendly — append at the end of each list):**
  - ToolCatalogue.swift: add `dictionary` spec; append to `all` (14 → 15).
  - ToolProfiles.swift: add `proctor_dictionary` to the `scripting` cluster (it is a
    scripting-plane introspection tool). Nesting stays ax⊂core⊂scripting⊂full.
  - ToolOutputSchemas.swift: add a bespoke output schema.
  - Dispatch.swift: route `proctor_dictionary` → `session.dictionary(...)`.

## Acceptance clauses → proving test (all pure ProctorCore, red→green)

1. A representative sdef parses into suites with commands (name+code), classes
   (name+code+properties), enumerations → `parsesSdefIntoStructure`.
2. Counts aggregate across suites → `countsAggregateAcrossSuites`.
3. `class-extension` captured, its properties counted → `classExtensionCaptured`.
4. Capability summary is one line naming app + scriptability + counts →
   `summaryIsOneLine`.
5. An app with no commands is `scriptable:false` with a route-hint summary →
   `noCommandsIsNotScriptable`.
6. Malformed/empty sdef → not-scriptable result, no throw → `emptyInputDoesNotThrow`.
7. Cache hits for the same handle, misses after relaunch (new epoch, same pid) →
   `cacheInvalidatesOnRelaunch`.
8. Tool advertised (count 15), read-only, non-destructive, in scripting profile,
   object output schema → `dictionaryToolAdvertised` + `dictionaryInScriptingProfile`
   + updated catalogue count test.

Tool-count assertion moves 14 → 15 on this branch (orchestrator reconciles at merge).

## Out of scope (per spec)

Executing arbitrary scripting commands — actuation stays through `proctor_act`
(`appleScript`/`shortcut` steps) with settle + provenance. This tool only reads.
