# Plan — PRO-0024: A second browser lane for what Obscura cannot do

Spec: `docs/specs/spec-PRO-0024.md`. Tier: **Standard**. Branch `ai/pro-0024`, worktree
`.worktrees/PRO-0024`. Gate: `swift build` + `swift test` (610/78 green at `5fe12e9`).

Same shape as PRO-0020 and PRO-0023: the decision is pure and lives in `ProctorCore`, the
agent supplies facts (two `stat` sweeps and one environment read) and the wiring is thin.

## 1. `Sources/ProctorCore/BrowserTarget.swift` — the catalogue and the decision

**`KnownBrowser` gains `chromiumFamily: Bool`.** Chromium, Chrome, Edge, Brave, Arc, Vivaldi,
Opera, Opera GX true; Safari, Safari TP, Orion, DuckDuckGo, Firefox (all channels), Zen false.
Prefix rules carry the flag, so a channel variant inherits.

**A browser-internal scheme list** — `chrome`, `chrome-extension`, `chrome-untrusted`,
`chrome-search`, `chrome-native`, `chrome-error`, `isolated-app`, `devtools`, `edge`, `brave`,
`vivaldi`, `opera`, `arc`. **Not `about`.** `isWebScheme` is untouched.

**The lane and the gate:**

```swift
public enum BrowserLane: String { case obscura = "obscura", browserUse = "browser-use" }
public enum SecondLaneState: String { case off, enabled, unavailable }

public struct BrowserLanes: Sendable, Equatable {
    public var obscuraAvailable: Bool
    public var secondLane: SecondLaneState
    /// The ONE place the environment and the two presences become a gate.
    public static func make(obscura: ToolPresence, browserUse: ToolPresence,
                            environment: [String: String]) -> BrowserLanes
}
```

`make` reads `PROCTOR_SECOND_LANE`: unset/empty/not naming the tool -> `.off` whatever is on
disk; naming it -> `.enabled` when present, `.unavailable` when absent.

**`handoff(for:probe:detail:lanes:)`** replaces `handoff(...)` + `withTool(...)`. **No default
argument** — every call site passes `lanes`, and PRO-0020's suite is updated rather than
shielded, because a default would let a forgotten site claim Obscura is installed.

The ladder, in the spec's order, over the URL PRO-0020 already resolves:

0. no URL -> skip to 4.
1. every distinct rendered URL is browser-internal, `chromiumFamily`, `secondLane == .enabled`
   -> browserUse; `.unavailable` -> no lane + `BrowserUseTool.absence`.
2. every distinct URL browser-internal otherwise -> no lane, `notOpenable`.
3. a URL that is neither `http(s)` nor internal -> no lane; `file:`/`data:` get
   `notAnInstrument`, everything else keeps `notOpenable`.
4. `!obscuraAvailable`, `chromiumFamily`, `.enabled` -> browserUse **and** keep
   `toolUnavailable = ObscuraTool.absence`; `.unavailable` -> no lane + both absences.
5. `obscuraAvailable` -> obscura.
6. otherwise -> no lane + `ObscuraTool.absence`.

**Lane-dependent text.** `boundary(for:)`, `continuity(for:)`, `caveats(for:)`,
`commands(for:)`. browser-use's boundary + continuity carry the autonomy, the real-credential
default mode and the audit-trail gap at **both** detail levels; `commands(for: .browserUse)` is
`nil`, absent rather than empty.

**`note: String?` -> `notes: [String]?`**, built only when `lane == .obscura`, fixed order:
private network (PRO-0020's), then PDF (`URL(string:)?.path.lowercased().hasSuffix(".pdf")`).
`nil` when empty. **No viewport note.**

**`why: String?`** after `use`, a full sentence, at both detail levels whenever a lane is named.

## 2. `Sources/ProctorCore/BrowserUseTool.swift` — new, pure, small

`binary = "browser-use"`, `companions: []`, `docs`, `laneVariable = "PROCTOR_SECOND_LANE"`,
`extraDirectories = ObscuraTool.extraDirectories`, `enabled(environment:)`, and an `absence`
used only in the `unavailable` state. No `installCommands`, deliberately, with a header saying
why.

## 3. `Sources/ProctorAgent/Session/ToolProbe.swift` — a second probe in a container

`ToolProbe`'s TTLs become instance properties (defaulting 300/15) and it gains a
`browserUseOnDisk` static. New `ToolProbes`, holding both probes and the **injected
environment**:

```swift
final class ToolProbes: Sendable {
    let obscura: ToolProbe
    let browserUse: ToolProbe          // 300s both ways
    let environment: [String: String]  // injected; never read from ProcessInfo in a test
    var lanes: BrowserLanes            // via BrowserLanes.make
    func refreshBoth() -> (obscura: ToolPresence, browserUse: ToolPresence)
}
```

`Session.tools` becomes `ToolProbes`; `Session.withTool` becomes `Session.lanes`.

## 4. `Sources/ProctorAgent/Session/SessionDoctor.swift` + `Wire.swift`

`DoctorReport` gains `tools: [ToolPresence]` (obscura then browser-use, always both) and
`secondLane: String` (`off` / `enabled` / `unavailable`). `obscuraAvailable`, `obscura`,
`obscuraUnavailable` unchanged, documented as the compatibility spelling. `doctor()` calls
`refreshBoth()` so one call writes through both caches.

## 5. `Sources/ProctorUI/MainWindow.swift`

One `Row` under Obscura's, rendered only when the browser-use entry in `tools` is available:
`"second lane on"` / `"found, lane off"`, plus one caption line naming `PROCTOR_SECOND_LANE`.
No callout, no buttons, no command text.

## 6. Schema, README, CHANGELOG

`ToolCatalogue`'s `proctor_doctor` output schema documents `tools` and `secondLane`. README's
browser section gains the lane, the gate and the routing table in three lines. CHANGELOG under
`## [Unreleased]`, prose through create-luke-content.

## 7. Tests

| Clause | Where |
|---|---|
| 1, 3-8, 9-13 | `Tests/ProctorCoreTests/BrowserLaneTests.swift` (new suite) |
| 2 (the gate) | same file — a loop over 4 gate x 3 scheme x 2 browser x 2 obscura combinations asserting the encoded JSON never contains `browser-use` unless both halves hold |
| 14-17 | `Tests/ProctorAgentTests/BrowserLaneWiringTests.swift` (new suite) |
| 18 | existing catalogue test extended |

`Tests/ProctorAgentTests/BrowserRoutingTests.swift` and `ObscuraPresenceWiringTests.swift`
move to `ToolProbes`; `BrowserHandoffToolAvailabilityTests` moves to `lanes:`. No test injects
a shared singleton, and every clock is injected — the two traps this repo has already paid for.

## Revision after the completeness critic (2026-08-15)

Four changes to the ladder above, all argued in the spec's critic section:

- **Rule 4 is deleted.** The second lane is never a fallback for an ordinary page; a missing
  Obscura falls to rule 6. `whyObscuraAbsent` went with it, and with it the only path by which
  an `http(s)` page or an app-level handoff could reach the second lane.
- **A deny list inside the enabled branch.** `BrowserTarget.sensitiveInternalHosts` plus the
  whole `devtools:` scheme. Checked inside `case .enabled` so the lane-off path stays
  byte-for-byte PRO-0020's.
- **Rule 1 requires that every rendered area reported a URL**, so a window read only in part is
  not routed on the part that was read.
- **`proctor_doctor.tools` and the status row follow the variable**, not presence, so the
  gate is one invariant across every surface rather than three.
