# Plan — PRO-0019: A foreground-only run is obvious before it takes the machine

**Spec:** `docs/specs/spec-PRO-0019.md` · **Tier:** Small · **Branch:** `ai/PRO-0019-foreground-disclosure`

## Files

| File | Change |
|---|---|
| `Sources/ProctorCore/ForegroundDemand.swift` | **new** — `ForegroundDemand`, `ForegroundReport`, the three wording phrasings |
| `Sources/ProctorCore/RunQueue.swift` | `LaneDemand.forBatch` re-expressed through `ForegroundDemand.takesForeground` |
| `Sources/ProctorCore/RunHUD.swift` | `runBegan` carries the demand; `stepSettled` carries the plane; `syntheticInFlight` on the model; exception row holds the up-front line and revises upward |
| `Sources/ProctorCore/Wire.swift` | `ActResult.foreground` (optional, defaulted — old call sites keep compiling) |
| `Sources/ProctorAgent/Session/SessionAct.swift` | `conditionalKinds`; `foregroundDemand(for:foreground:)`; pass demand into `hudRunBegan`; pass plane into `stepSettled`; build the report into `ActResult`; record the live demand for the menu bar |
| `Sources/ProctorAgent/Session/SessionQueue.swift` | `lanes(for:…)` routes through the shared demand |
| `Sources/ProctorAgent/Session/SessionHUD.swift` | `hudRunBegan` takes the demand |
| `Sources/ProctorAgent/Session/SessionFlow.swift` | replay reports the same block in place of its free-text `note` |
| `Sources/ProctorAgent/Session/Session.swift` | live foreground state alongside the activity ring; `recentActivity` gains the `foreground` block |
| `Sources/ProctorAgent/Overlay/RunHUDPanel.swift` | `ignoresMouseEvents` reads `syntheticInFlight`; `begin` takes the demand |
| `Sources/ProctorUI/AgentModel.swift` | decode the `foreground` block |
| `Sources/ProctorUI/ProctorUIApp.swift` | activity line states it; one leading case in `menuIcon` |
| `CHANGELOG.md` | Unreleased entry |

## Order

1. Core value + wording, with tests (A1, A2 wording).
2. `LaneDemand` through it — equivalence test against the HEAD predicate (A1, A7).
3. HUD reducer: demand on `runBegan`, plane on `stepSettled`, `syntheticInFlight`, upward revision (A2, A3, A4).
4. Panel: mouse gate off the new flag (A4).
5. Agent wiring: demand computed once per batch, `ActResult.foreground`, flow replay block (A6).
6. Live state + `recent_activity` block (A5, agent half).
7. UI: model decode, menu line, glyph (A5, UI half — not machine-witnessable).
8. `swift build` + `swift test`; changelog.

## Risks

- **Contended files.** `Wire.swift` and `RunHUDPanel.swift` are shared with the two live siblings; changes there are additive and small. `ProctorUIApp.swift` collides with PRO-0021's menu-bar work — the glyph change is one leading `case` by design.
- **`ForegroundReport` on `ActResult` is `Codable`** — golden JSON shape tests exist for step artifacts, not for `ActResult`; the field is optional so absent-vs-present is a decode-safe addition.
