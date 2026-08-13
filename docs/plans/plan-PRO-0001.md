# Plan PRO-0001: CUA schema façade (Anthropic + OpenAI)

**Spec:** [spec-PRO-0001.md](../specs/spec-PRO-0001.md) · **Status:** Ready for Work
**Plan tier:** Standard (one new pure module + two additive tools + one execution path; ~5 files)

## Objective

Expose the stock **Anthropic `computer`** action schema and the **OpenAI
`openai_computer`** batched-action schema as two additive, opt-in MCP tools that
translate those actions onto Proctor's existing `act` / `capture` paths. A model
trained on either schema drives Proctor unmodified; the native eleven-tool
surface is unchanged; every translated step is auditable in the result.

## Assumption correction (binding assumption found wrong)

The spec assumes both schemas "map onto existing act **+ hit-test**". There is
**no hit-test primitive in the codebase** — no `AXUIElementCopyElementAtPosition`
/ element-at-point exists anywhere in `Sources/`. So the coordinate→AX
optimisation the spec leans on is not shippable as "reuse". The feature is
therefore delivered on the **point-actuation plane**, which is complete and
correct: `click`, `hover`, `dragPath`, `key`, `type`, `scroll` all already
actuate at a supplied point. The coordinate→AX upgrade is preserved as a clean,
unit-tested seam and deferred as a child (see Deferred). This matches the spec's
own wording — "map onto AX targets **where possible**, falling back to point
actuation" — where, today, the fallback is the whole path.

## Coordinate model

CUA coordinates are relative to the screenshot the model was shown. The façade's
`screenshot` maps to a **window-scoped** capture (Proctor's whole design), so the
model's origin is the target window's top-left. Proctor synthetic actuation
(`CGEvent`) takes **global screen points**. The translator therefore maps
`global = windowOrigin + cuaPoint / scale`. `scale` defaults to 1.0 (point
space); retina pixel-space handling is exposed as a tool arg and reported as a
child. This mapping is pure and unit-tested.

## Actuation plane and `foreground`

CUA is frontmost-screen driving by definition (screenshot the visible screen,
click a pixel). The mapped step kinds (`click`, `hover`, `dragPath`, `key`) are
Proctor's synthetic-event kinds, which require `foreground: true` (SessionAct
refusal). The façade therefore defaults `foreground: true` and says so. Proctor's
background-safety is the *native* surface's advantage, not the façade's — the
façade honestly reports `plane: syntheticEvent` on every actuated step.

## Files

1. **`Sources/ProctorCore/CUAFacade.swift`** (new, pure) — the translator.
   - `CUASchema` (`.anthropic` / `.openai`).
   - `CUAStep`: `{ operation: .act(ActionStep) | .screenshot | .wait(ms), action: String, summary: String }`.
   - `CUATranslator.anthropic(_ action: JSONValue, windowFrame: Rect, scale: Double) throws -> [CUAStep]`
     (one action → 1..n steps; double/triple click → N click steps).
   - `CUATranslator.openai(_ actions: JSONValue, windowFrame: Rect, scale: Double) throws -> [CUAStep]`
     (single object or array → flattened plan).
   - Helpers (exposed for tests): `globalPoint`, `parseKeyCombo` (xdotool combo →
     `(key, modifiers)`), `parseKeys` (OpenAI `keys[]` → `(key, modifiers)`).
   - Unmapped actions throw `AgentError(.invalidArguments)` with the offending
     name — never silently dropped.

2. **`Sources/ProctorCore/ToolCatalogue.swift`** — add `proctor_computer` and
   `proctor_openai_computer` (readOnly false). Native eleven untouched.

3. **`Sources/ProctorAgent/Session/SessionCUA.swift`** (new) — execution.
   `computerUse(schema:window:payload:scale:foreground:) async throws -> JSONValue`:
   resolve window frame → translate → run each `CUAStep` in order (act-steps via
   the existing `runSteps` machinery so settle/hash/diff/provenance come free;
   screenshot via `capture`; wait via a bounded settle). Stop on first error,
   report `failedAt`. Result carries per-step `{ action, summary, plane, ok,
   stateHash, settle, error?, capture? }` — the translation provenance.

4. **`Sources/ProctorAgent/Dispatch.swift`** — route both tool names; decode
   `window`, `action`/`actions`, `scale`, `foreground`; call `session.computerUse`.

5. **`Tests/ProctorCoreTests/ProctorCoreTests.swift`** — bump catalogue count
   11→13; add a `CUA schema façade` suite (one test per acceptance clause below).

## Acceptance clauses → tests (red→green)

- Anthropic `left_click [x,y]` → one `.act(click)` at `windowOrigin + [x,y]`.
- Anthropic `type` → `.act(type)` carrying the text.
- Anthropic `key "cmd+s"` → `.act(key)` key=`s` modifiers=`[cmd]`; `"Return"` →
  key=`return` no mods; `"ctrl+shift+t"` → key=`t` mods=`ctrl,shift`.
- Anthropic `mouse_move` → `.act(hover)` at mapped global point.
- Anthropic `scroll` (direction+amount) → `.act(scroll)` with the right delta sign.
- Anthropic `screenshot` → `.screenshot`.
- Anthropic `double_click` → two `.act(click)` steps at the mapped point.
- Anthropic `left_click_drag` → `.act(dragPath)` path `[start, end]` in global coords.
- Anthropic `wait` → `.wait(ms)`.
- Anthropic unknown action → throws.
- OpenAI batch `[click, type, keypress]` → flattened plan; `keypress ["ctrl","c"]`
  → key=`c` mods=`ctrl`; `scroll` → scroll step; `drag` path → dragPath in global.
- Coordinate mapping: `scale=2` halves the CUA offset before adding the origin.
- Catalogue: 13 tools; the two new ones are not read-only.

## Gate

`swift build && swift test` from the worktree root. No running app is required —
the translator is pure and the execution path is covered structurally by the
existing act machinery it reuses.

## Deferred children

- **PRO-0001a — coordinate→AX hit-test upgrade.** Add `elementAtPoint` to
  `AXEngine`/`AXEngineImpl` (`AXUIElementCopyElementAtPosition`), resolve a CUA
  point to a node id, and emit an accessibility `press` instead of a synthetic
  click when one resolves — upgrading determinism and background-safety. Depends
  on this feature. Untestable without a running app.
- **PRO-0001b — retina pixel-space coordinates.** Feed the capture's real backing
  scale into the coordinate map so a model given a 2x screenshot clicks the right
  point automatically. Depends on this feature.
