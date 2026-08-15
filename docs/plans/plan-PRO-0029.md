# Plan — PRO-0029: A home for the PROCTOR_* switches

**Spec:** `docs/specs/spec-PRO-0029.md`
**Branch:** `ai/pro-0029` · **Worktree:** `.worktrees/PRO-0029`
**Tier:** Standard. Six new files, four touched, no protocol break.

## Shape

The whole design turns on one decision: **the existing read-once call sites do not
change how they read.** `CursorOverlay.isEnabled`, `InputBlocker.isEnabled`,
`TakeoverOverlay.isEnabled`, `ContentionMonitor.enabled/inputObserved`,
`SessionHUD.hudEnabledByDefault`, `BrowserUseTool.enabled` and
`CuaDriverTool.laneSelected` all take a `[String: String]` environment. So instead
of rewriting seven call sites to consult a preference store, the agent computes an
**effective environment** once at start — the process environment with the saved
preferences overlaid according to the precedence rule — and the existing sites read
that.

That keeps every piece of settled reasoning intact (read-once stays read-once, the
opt-in shapes stay as they are) and makes the diff a redirect rather than a
rewrite. It also means the precedence rule lives in exactly one pure function.

## Files

### New, in `Sources/ProctorCore/`

1. **`SwitchCatalogue.swift`** — the eight switches as a value. Per switch: the
   variable name, its class (`drawing` / `capability` / `lane`), its default, its
   accepted on-value for the two lane switches, and whether it applies live or at
   next start. Plus `pairing(...)` for the two `_INPUT` coupling warnings.
2. **`SwitchResolution.swift`** — the precedence rule. `resolve(switch:environment:
   saved:) -> Resolution`, carrying `on`, `rawValue`, `source`
   (`environment`/`saved`/`default`), and `locked`. Two-part rule: ordinary
   switches take the environment first and lock when it is present; the two
   capability switches AND the environment with the saved value and never lock.
   Also `effectiveEnvironment(processEnvironment:saved:) -> [String: String]`, the
   overlay the agent installs at start.
3. **`SwitchStore.swift`** — `SavedSwitches: Codable`, the path derived from
   `Wire.bundleIdentifier`, tolerant decode (unknown keys ignored, corrupt file
   returns defaults), atomic write, `0700` dir / `0600` file. `load(from:)` and
   `save(_:to:)` take a URL so tests use a temp directory.

### Touched

4. **`Sources/ProctorCore/Wire.swift`** — `DoctorReport.switches: [SwitchState]?`,
   optional, appended after `policy`, following the `lanes` precedent.
5. **`Sources/ProctorAgent/main.swift`** — install the effective environment as the
   **first** statement, before anything can touch a `static let` that reads the
   environment. This ordering is the one real hazard in the change.
6. **`Sources/ProctorAgent/Session/SessionDoctor.swift`** — populate `switches`
   from the resolver.
7. **`Sources/ProctorUI/MainWindow.swift`** — a `SwitchesSection` card between
   Tools and Activity, in the existing `Card`/`SectionTitle`/`Callout` idiom.
8. **`Sources/ProctorUI/AgentModel.swift`** — load/save the store, expose rows,
   drive `Actions.restartAgent()`.

### Environment holder

`ProctorEnvironment` (a small `enum` with a `nonisolated(unsafe) static var` set
once at start, in `ProctorCore`) is what the seven call sites read instead of
`ProcessInfo.processInfo.environment`. Set-once, read-many, before concurrency
starts. The alternative — threading an environment parameter through seven types —
touches far more code for no behavioural gain.

## Order of work

1. `SwitchCatalogue` + `SwitchResolution` + their tests. All of clauses 1–12 land
   here and none of them needs a window server.
2. `SwitchStore` + tests (clauses 13, 14).
3. `Wire` field + decode test (clause 15).
4. `ProctorEnvironment`, `main.swift` ordering, the seven call-site redirects.
5. `SessionDoctor` population.
6. The UI card.
7. `swift build`, `./scripts/test.sh`, then the by-eye pass against a private agent.

## Tests

All in `Tests/ProctorCoreTests/`. Table-driven where the spec's clause is a table.
The drift test (clause 2) asserts each catalogue entry's variable equals the real
constant — `CuaDriverTool.laneEnv`, `BrowserUseTool.laneVariable` — and, for the
literals, that resolving through the catalogue agrees with calling the original
function directly. That is what actually catches drift: comparing two strings that
were both typed by hand catches nothing, but comparing the catalogue's answer to
`ContentionMonitor.inputObserved`'s own answer over the same dictionary does.

## Verification honesty

`Package.swift` declares `ProctorCoreTests` and `ProctorAgentTests` and no
`ProctorUI` target, and there is no window server under `swift test`. So clauses
1–15 are machine-witnessed and clauses 16–20 need a person to look. The by-eye pass
runs a locally built agent on a private `PROCTOR_SOCKET`, never replacing
`/Applications/Proctor.app` — two sibling runners are in flight. Proctor is not
driven through Proctor: that knocked the installed agent over twice on PRO-0036's
run.
