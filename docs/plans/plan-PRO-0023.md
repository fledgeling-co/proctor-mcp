# Plan — PRO-0023: Offer to install Obscura when it is missing

Spec: `docs/specs/spec-PRO-0023.md`. Tier: **Standard**. Branch `ai/pro-0023`, worktree
`.worktrees/PRO-0023`. Gate: `swift build` + `swift test` (544/66 green at `cae5f80`).

The shape follows PRO-0020's: the decision is pure and lives in `ProctorCore`, the agent
supplies one fact (does this file exist and is it executable) and the wiring is thin.

## 1. `Sources/ProctorCore/ToolPresence.swift` — new, pure

```swift
public struct ToolPresence: Codable, Sendable, Equatable {
    public var tool: String
    public var available: Bool
    public var path: String?          // where it was found
    public var searched: [String]     // every candidate binary path, in order
    public var missingCompanions: [String]
}

public struct ToolAbsence: Codable, Sendable, Equatable {
    public var tool: String
    public var missing: String        // includes what the answer is a claim about
    public var docs: String
    public var askThePerson: String   // capability, not a promise
}

public enum ToolLocator {
    public static func candidatePaths(binary:pathEnvironment:home:extraDirectories:) -> [String]
    public static func locate(binary:companions:pathEnvironment:home:extraDirectories:
                              isExecutable: (String) -> Bool) -> ToolPresence
}
```

`candidatePaths` splits `PATH` on `:`, drops empties, appends `extraDirectories`, expands a
leading `~` from `home`, drops anything not absolute, deduplicates preserving order, and
appends `/<binary>`. `locate` walks them in order, first hit wins; on a hit it checks each
companion beside it in the same directory.

## 2. `Sources/ProctorCore/ObscuraTool.swift` — new, pure

Binary name, `companions = ["obscura-worker"]`, `docs`, the five extra directories, the
`missing` / `askThePerson` sentences, `absence`, `installDestination = "~/.local/bin"`, and

```swift
public enum Architecture: String, Sendable { case appleSilicon, intel }
public static func installCommands(architecture: Architecture) -> [String]   // app-only
public static func hardwareArchitecture() -> Architecture                    // sysctlbyname
```

`hardwareArchitecture` reads `hw.optional.arm64` so Rosetta does not change the answer.

## 3. `BrowserTarget.withTool` — the handoff adjustment, pure

```swift
public static func withTool(_ handoff: BrowserHandoff, available: Bool,
                            absence: ToolAbsence) -> BrowserHandoff
```

Available, or `handoff.use == nil` (nothing was recommended, so nothing to repair) → returned
unchanged. Otherwise `use = nil`, `commands = nil`, `toolUnavailable = absence`; everything
else untouched. `BrowserHandoff` gains `public var toolUnavailable: ToolAbsence?` as its last
field with a defaulted init parameter, so PRO-0020's call sites are unchanged.

## 4. `Sources/ProctorAgent/Session/ToolProbe.swift` — new

A struct held by the `Session` actor (never a shared singleton), with two injected closures in
the repo's existing style (`RunControl`/`ContentionMonitor` use `@Sendable () -> Double`):

```swift
struct ToolProbe: Sendable {
    static let presentTTL = 300.0
    static let absentTTL  = 15.0
    var probe: @Sendable () -> ToolPresence = ToolProbe.obscuraOnDisk
    var now:   @Sendable () -> Double       = { Date().timeIntervalSince1970 }
    private var cached: (presence: ToolPresence, at: Double)?

    mutating func presence() -> ToolPresence   // cache-respecting; TTL depends on the answer
    mutating func refreshed() -> ToolPresence  // forces a probe and writes through
}
```

`obscuraOnDisk` supplies `ProcessInfo.processInfo.environment["PATH"]`, `NSHomeDirectory()`
and a predicate built from `FileManager.isExecutableFile` **plus a regular-file check**
(`isExecutableFile` is true for a directory with the execute bit), and runs nothing.

## 5. Wiring

- `Session.init` gains `tools: ToolProbe = ToolProbe()`; the field is `var`.
- Both `Session.browserHandoff` overloads return
  `BrowserTarget.withTool(handoff, available: tools.presence().available, absence: ObscuraTool.absence)`.
  Five call sites downstream are untouched.
- `SessionDoctor` calls `tools.refreshed()` once and fills the three new `DoctorReport`
  fields; `blockers` and `ready` are not touched.
- `DoctorReport` gains `obscuraAvailable: Bool`, `obscura: ToolPresence?`,
  `obscuraUnavailable: ToolAbsence?`, with defaulted init parameters.
- `ToolOutputSchemas`: three keys on `proctor_doctor`, and the existing `browser` sentence on
  the four routing tools gains a clause about `toolUnavailable`.

## 6. `Sources/ProctorUI/MainWindow.swift`

`Row("Obscura", …)` beside the Shortcuts CLI row, a `missingCompanions` row when non-empty, and
when `obscuraUnavailable != nil` a `Callout` plus **Copy install commands** /
**Open the project page** / **Re-check**. `Actions.open(_ urlString:)` is added beside
`openPane`. This is the only place `installCommands` is called.

## 7. Tests

| Clause | Test | File |
|---|---|---|
| 1 | `pathEntriesComeBeforeTheExplicitList`, `aLaunchdPathStillFindsHomebrew` | `Tests/ProctorCoreTests/ToolLocatorTests.swift` |
| 2 | `tildeIsExpandedFromTheSuppliedHome` | same |
| 3 | `nothingFoundReportsEverywhereItLooked` | same |
| 4 | `aNonExecutableCandidateIsNotAHit` | same |
| 5 | `aHalfInstallIsAvailableAndSaysWhatIsMissing` | same |
| 6 | `theAbsenceCarriesNoShellCommand` | same |
| 7 | `installCommandsAreArchitectureSpecific` | same |
| 8, 9, 10, 11 | `aMissingToolDropsTheRecommendationAndKeepsTheURL`, `apresentToolChangesNothing`, `aPageObscuraCannotOpenGainsNoAbsence`, `bothDetailLevelsCarryTheSameAbsence` | `Tests/ProctorCoreTests/BrowserTargetTests.swift` |
| 12 | `doctorReportsObscuraAndLeavesReadinessAlone` | `Tests/ProctorAgentTests/ObscuraPresenceWiringTests.swift` |
| 13 | `aDoctorCallWritesThroughToTheHandoffCache` | same |
| 14 | `handoffsShareOneProbe`, `theAbsentAnswerExpiresSooner` | same |
| 15 | `attachCarriesTheAbsenceThroughTheJSON` | same |
| 16 | `theToolSurfaceGainsNoVerb`, schema assertion | same |

Injected clock and probe counter are owned by each test (a final class box), so nothing leaks
between tests — the failure mode the PRO-0018 hang was made of.

## 8. Docs

README line 177 (the `proctor_doctor` row) and the Obscura paragraph at ~219; `CHANGELOG.md`
`## [Unreleased]`, prose through `/create-luke-content` per `CLAUDE.md`.

## Risks

- `DoctorReport`'s explicit initialiser is called in `SessionDoctor` and in tests; defaulted
  parameters keep both compiling.
- `ToolProbe` mutating inside an actor is fine; the closures must be `@Sendable`, matching
  `RunControl`.
- `sysctlbyname` in `ProctorCore` needs `import Darwin`, and is only reached from the UI.
