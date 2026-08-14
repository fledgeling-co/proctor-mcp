# Plan — PRO-0018: Notice when a person is taking the machine back, and yield

**Spec:** `docs/specs/spec-PRO-0018.md` (revised — the input monitor ships **off**,
the mechanism is `NSEvent`, not a `CGEventTap`, and contention is a **state** with
an observable release).
**Tier:** Standard. Two new files, one refactor of `RunControl`'s internals, and
additive edits to eight existing files.
**Branch:** `ai/pro-0018` in `.worktrees/PRO-0018`
**Gate:** `swift build` + `swift test`. 500 tests / 64 suites are green at HEAD and stay green.

## Files

```
NEW  Sources/ProctorCore/Contention.swift              pure: reasons, sample, watch, records
NEW  Sources/ProctorAgent/Session/ContentionMonitor.swift  AppKit half: frontmost cache, optional NSEvent monitor
     Sources/ProctorAgent/AX/Actuator.swift            one tagged event-source factory (4 sites + 3 helpers)
     Sources/ProctorAgent/Session/RunControl.swift     one latch, two causes, one clock; probe on checkpoint
     Sources/ProctorAgent/Session/SessionAct.swift     arm/disarm, expectedPid from a MEASURED plane, yields on the result
     Sources/ProctorAgent/Session/SessionHUD.swift     the probe: sample → yield/release → HUD + audit
     Sources/ProctorAgent/Session/Session.swift        yield state per run; `yield` in the foreground wire block
     Sources/ProctorCore/RunHUD.swift                  RunHUDEvent.yielded / .unyielded
     Sources/ProctorCore/Wire.swift                    ActResult.yields
     Sources/ProctorUI/AgentModel.swift                read the yield block
     Sources/ProctorUI/ProctorUIApp.swift              state it on the activity line
```

## 1. `ProctorCore/Contention.swift` — the whole of the logic, as a value

```swift
public enum YieldReason: String, Codable, Sendable, CaseIterable {
    case secureInput, userInput, frontmostChanged      // declaration order IS precedence
    public var line: String                            // the panel's one line (A6)
}

public enum ProctorEventTag { public static let value: Int64 }   // the actuator's stamp

public struct ContentionSample: Sendable, Equatable {
    var expectedPid: Int32?      // the pid Proctor has DEMONSTRABLY put in front; nil before
    var frontmostPid: Int32?
    var secureInput: Bool
    var lastUserInputAt: Double? // monotonic; nil when the monitor is off or nothing arrived
    var now: Double
}

public struct ContentionWatch: Sendable {
    public var inputWindow: Double = 10          // A-viii, substitutable
    public private(set) var reason: YieldReason?
    public enum Change: Equatable { case yielded(YieldReason), released(YieldReason), none }
    public mutating func sample(_ s: ContentionSample) -> Change
    public mutating func resumedByPerson()       // A5: override the current episode
}

public struct YieldRecord: Codable, Sendable, Equatable {
    var reason: String; var step: Int?; var heldMs: Int; var endedBy: String
    static func note(for records: [YieldRecord]) -> String?
}
```

`sample` computes the set of conditions that hold, subtracts the overridden ones,
takes the highest-precedence survivor, and diffs it against `reason`. A reason
leaves the overridden set the moment its own condition goes false, which is
exactly A5's "re-arms only once that reason has cleared and recurred".

`frontmostChanged` holds only when `expectedPid != nil && frontmostPid != nil &&
frontmostPid != expectedPid` — so A2 is true by construction: before Proctor has
taken the front there is nothing to take back, and a front Proctor moved moves
both sides of the comparison.

`userInput` holds while `now - lastUserInputAt < inputWindow`.

## 2. `Actuator` — one tagged source

`static func eventSource() -> CGEventSource?` builds the `.hidSystemState` source
and sets `userData = ProctorEventTag.value`. Replaces the four inline
constructions and the three in `warpCursor`/`postUnicode`/`post`. No behavioural
change to any post; the tag rides on the source and lands on every event
(measured 2026-08-14, spec table M4).

## 3. `RunControl` — one latch, two causes, one clock

Internals change; the three buttons do not.

```swift
private var pausedByPerson = false
private var yieldReason: YieldReason?
private var pausedAt: Double?          // set when the first cause latches, cleared when both go
var paused: Bool { pausedByPerson || yieldReason != nil }

func pause()   // sets pausedByPerson          (unchanged externally)
func resume()  // clears BOTH                  (unchanged externally)
func stop()    // clears everything            (unchanged externally)
func yield(_ reason: YieldReason)
func release()                                  // clears only the yield
var cause: (person: Bool, yield: YieldReason?)

func checkpoint(probe: (@Sendable () async -> Void)? = nil) async -> Halt?
```

`checkpoint` runs `probe` once **before** the first `look()` and once per poll
while parked. That is what lets a yield begin at a checkpoint and end while the
run is already parked, with no second timer. The backstop reads `pausedAt` exactly
as it does now, so A4 holds by construction: a yield is bounded by the same
`pauseLimit` and gives up through the same `.pauseExpired`.

## 4. `ContentionMonitor` — the AppKit half, no policy

`@unchecked Sendable` class behind an `NSLock`, mirroring `RunHUDFeed`'s shape.

- `frontmostPid` seeded from `NSWorkspace.shared.frontmostApplication` and kept by
  `NSWorkspace.didActivateApplicationNotification`.
- `arm(observeInput:)` / `disarm()`. The `NSEvent.addGlobalMonitorForEvents`
  monitor is installed **only** when `observeInput` and only between those calls;
  `disarm` removes it; `deinit` disarms.
- Mask: `[.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]`.
  Not `.mouseMoved` — Proctor warps the cursor constantly.
- The handler runs three filters and records nothing but a timestamp:
  1. `event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ProctorEventTag.value` → drop
  2. `now - lastSyntheticPostAt < graceSeconds` (0.25) → drop
  3. otherwise `lastUserInputAt = now`
- `noteSyntheticPost()` is called by the session whenever a step reports
  `plane == .syntheticEvent`, and on `stepActing` of a certainly-synthetic step.
- `setExpectedPid(_:)` is called **only** from a measured `.syntheticEvent` plane
  or a settled `raise` (A-vi), never from the prediction.
- A `Sampling` protocol over `sample(now:) -> ContentionSample` so a test drives a
  fake with no AppKit at all.

## 5. Wiring

In `runSteps`, beside PRO-0019's `foregroundBegan`/`foregroundEnded` pair:

```
armed = Session.yieldEnabled && demand.takesForeground
contention.arm(observeInput: Session.yieldInputEnabled)   // when armed
… haltCheckpoint(probe: contentionProbe(run:))
… on each settled step: if plane == .syntheticEvent { monitor.noteSyntheticPost();
                                                       monitor.setExpectedPid(app.pid) }
… also arms mid-run the first time a step MEASURES .syntheticEvent (A1's "or")
contention.disarm()
```

`Session.contentionProbe` is the only place policy lives: sample → `watch.sample`
→ on `.yielded` call `runControl.yield`, `hudFeed.apply(.yielded(reason))`, the
audit line `run.yielded`, and append an open `YieldRecord`; on `.released` the
mirror with `.unyielded` and `run.resumed`.

A person's Resume goes through `SessionHUD.hudControl(.resume)`, which already
calls `runControl.resume()`; it gains `watch.resumedByPerson()` so A5's override
holds and closes the open record as `endedBy: person`.

Switches: `Session.yieldEnabled` = `OverlaySwitch.isOn("PROCTOR_YIELD", …)`
(default **on**); `Session.yieldInputEnabled` reads `PROCTOR_YIELD_INPUT` with the
**opposite** default — unset means off — so it is a deliberate opt-in and not an
off-switch. Both are static functions over an environment dictionary, so both are
tested as parsing.

## 6. Reporting

- `RunHUDEvent.yielded(reason:)` → phase `.paused`, tone quiet, line
  `reason.line`, `syntheticInFlight = false`. `.unyielded` reduces like `.resumed`.
- `ActResult.yields: [YieldRecord]?` — nil when empty, so every existing result
  encodes byte-identically. `yieldNote` rides alongside in the object, the way
  `captures` and `browser` already do. Flow replay emits the same two.
- `Session.foregroundJSON` gains `yield: {active, reason, line}`;
  `AgentModel.ForegroundStatus` reads it; `MenuBarContent.activityLine` states it
  ahead of "Taking the foreground now", because a held run is not taking anything.

## 7. Tests — `ContentionTests` in Core, wiring tests in `ProctorAgentTests`

| clause | test |
|---|---|
| A1 | `anAccessibilityRunNeverYields` (all-`press` batch, contending sample, runs to completion) · `aMeasuredFallbackArmsMidRun` |
| A2 | `proctorsOwnForegroundChangesNeverYield` — a whole synthetic batch's samples, zero yields · `noExpectedPidMeansNoContention` |
| A3 | `frontmostYieldsAndReleases` · `secureInputYieldsAndReleases` · `secureInputOutranksFrontmost` |
| A4 | `aYieldExpiresThroughTheSameBackstop` (ms `pauseLimit` → `.pauseExpired`) · `oneClockForBothCauses` |
| A5 | `resumeOverridesTheCurrentEpisode` · `andRearmsOnlyAfterItClearsAndRecurs` · `aPersonsPauseSurvivesARelease` |
| A6 | `theYieldedLineSaysWhy` — three reasons × (line, phase, tone, pauseLabel) |
| A7 | `theMenuBarStatesTheYield` — wire block shape · `theIconLadderIsUnchanged` |
| A8 | `aYieldedRunSaysSoAfterwards` · `aRunWithNoYieldEncodesAsItDoesAtHEAD` |
| A9 | `theInputMonitorIsOffUnlessAskedFor` (both switches' parsing) · `armingIsGatedOnBothSwitches` (fake monitor) |
| filters | `ourOwnEventsAreFilteredOut` — tag match, grace window, and the pair together |

## Risks

- **`NSEvent` global monitors deliver on the main run loop**; the session is an
  actor. Everything crosses through the lock-protected monitor, never an await
  under a lock — `RunHUDFeed`'s shape exactly.
- **The tag's survival to a real `NSEvent` is unwitnessable here.** Filter 3 is
  the belt: even with no tag at all, a Proctor-posted event inside the 250 ms
  grace is discarded. Both filters are tested; the round trip is stated as
  untestable rather than dressed up.
- **`SessionAct.runSteps` and `RunHUD.swift`** are the hot merge files. Every edit
  is additive and sits beside PRO-0019's pair.
