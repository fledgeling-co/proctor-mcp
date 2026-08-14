# Plan — PRO-0021: Menu bar switch for the panel, and the icon as the character

**Spec:** `docs/specs/spec-PRO-0021.md` · **Tier:** Standard · **Branch:** `ai/PRO-0021`

## Shape

One reducer (`RunHUDFeed`, agent, lock-guarded, off the main actor), two consumers:
the panel renders it, and `proctor_recent_activity` projects it onto the socket for
the menu bar. One new internal verb, `proctor_hud`, carries the switch and the run
controls the other way. New menu bar art at 22pt in `ProctorCore`'s bundle.

## Steps

### 1. Art — `design/character/build-sprites.py`
Parameterise `CANVAS` / `CASE_HEIGHT` / `BASELINE` / output directory into a small
`Size` record; run the existing pipeline twice from the same sheet. Panel stays
`38 / 29 / 35` → `Sources/ProctorAgent/Resources/character`. Menu bar is
`22 / 19 / 21` → `Sources/ProctorCore/Resources/character-menubar`. Nothing else
about the slicer changes; the sheet is not regenerated.

Verify the panel set is byte-identical to what is committed (a refactor that moved a
pixel would be a silent regression).

### 2. Core
- `RunHUDCharacter.menuBarSide = 22`, and `menuBarAssetURL(asset:scale:)` over
  `Bundle.module` (Foundation only — Core stays AppKit-free).
- `RunHUDMotion.menuBar(for:reduceMotion:)` — travelling and acting play their four
  frames; every other phase, and everything under Reduce Motion, is one frame.
- `RunHUDMotion.frameIndex(in:elapsed:)` — which frame is up at an elapsed time, so
  the timer-driven menu bar view is arithmetic that tests can walk.
- `RunHUDModel.menuBarPhase` — `visible ? phase : .idle`, so an ending is held for
  the linger and then the character rests.
- `MenuBarIcon.decide(reachable:ready:phase:)` → `.symbol(String)` or
  `.character(RunHUDPhase)`; readiness outranks the character.
- `RunHUDControl` — the verb's action vocabulary (`show/hide/pause/resume/stop`) and
  its parse, so an unknown action is refused in one testable place.
- Package: `ProctorCore` gains `resources: [.copy("Resources/character-menubar")]`.

### 3. Agent
- New `Sources/ProctorAgent/Overlay/RunHUDFeed.swift`: owns `RunHUDState`, `drawing`
  (seeded from `OverlaySwitch.isOn("PROCTOR_HUD", …)`), `canShow` (mirrors
  `eventLoopRunning`), and the last driven-window rect. `apply`, `setQueue`,
  `setDrawing`, `model`, `snapshot` (phase / running / drawing / canShow).
- `RunHUDPanel`: drop the `state` property, read `RunHUDFeed.shared.model`; `present`
  guards on `drawing`; `setDrawing(false)` orders out immediately and records the
  availability reason; `setDrawing(true)` re-presents mid-run from the remembered
  window rect. `markEventLoopRunning` also sets the feed's `canShow`.
- `SessionHUD`: `hud(_:)` and `hudRunBegan` reduce unconditionally through the feed
  and hop to the main actor to render only when drawing. `hudStatus()` grows the
  third case (hidden from the menu bar — stop path intact).
- `Session.drawsHUD` becomes a read-through to the feed so a mid-run toggle is seen
  by the next step; the AX lookup in `SessionAct` stays gated on it.
- `Dispatch`: `proctor_hud` internal verb (never in `ToolCatalogue`), and `hud` added
  to `recentActivity`'s result.
- Hide and show go through the existing `RunHUDPanel.auditSink`, like hold and clear:
  they change whether a person has a stop button on screen.

### 4. ProctorUI
- `AgentModel`: two timers — activity at 0.5s, doctor at 2s, each with its own
  in-flight guard. Parse `hud` into `hudPhase` / `hudRunning` / `hudDrawing` /
  `hudCanShow`. Add `setPanel(visible:)`, `pauseRun()`, `resumeRun()`, `stopRun()`
  over `proctor_hud`, each applying the returned state at once.
- New `Sources/ProctorUI/MenuBarCharacter.swift`: decodes the Core assets to
  `NSImage` once, and a small `@Observable` clock that ticks only while the phase
  animates. `interpolation(.none)`, `isTemplate = false`, 22×22.
- `ProctorUIApp`: `MenuBarExtra` label becomes `MenuBarIcon.decide(...)`; the menu
  gains a Show Run Panel toggle (disabled with its reason when `canShow` is false)
  and Pause/Resume + Stop while a run is live. No Hold, no Clear.

### 5. Tests
`ProctorCoreTests` — menu bar motion policy, frame index, `menuBarPhase`, icon
decision, action parse, asset manifest at every density on one 22px footprint.
`ProctorAgentTests` — the feed reduces with no panel; `drawing` starts from the
environment; hide/show round-trip through the verb; the verb is absent from
`ToolCatalogue`; the three doctor notes; hide leaves the stop path and Stop through
the verb reaches `RunControl`; hide/show is audited.

### 6. Docs
`docs/design/run-hud-character.md` gains the menu bar rendition and the measured
reason for 22pt. `CHANGELOG.md` `[Unreleased]`.

## Risks
- `RunHUDPanel.swift` is contended; the state-ownership move is the largest edit and
  is kept to the smallest diff that works.
- Nothing here that draws is machine-witnessable from `swift test`.
