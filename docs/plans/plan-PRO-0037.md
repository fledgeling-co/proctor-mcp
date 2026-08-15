# Plan — PRO-0037: A hold names whose run it is

**Spec:** `docs/specs/spec-PRO-0037.md` · **Branch:** `ai/pro-0037` · **Worktree:** `.worktrees/PRO-0037`
**Tier:** Standard — one new value type, one behavioural change to the latch, one
new field on the scheduler's ticket, and three surfaces reading it. No new
subsystem, no new dependency, no schema migration.

## Shape of the change

Four moves, in this order, because each one is the ground the next stands on:

1. **A value that can be attributed** (`HoldAttribution`) — pure, in Core, so the
   display arithmetic and the wording are provable with no window.
2. **The latch learns whose the automatic hold is** (`RunControl`) — the fix for
   the silent stall, `begin()`'s cross-run wipe, and the backstop's
   misattribution. Pure agent logic, no AppKit.
3. **The keeper carries it** (`RunScheduler`, `RunTicketInfo`) — the join, on the
   outside of the reentrant actor, published by the one place contention policy
   lives.
4. **The surfaces read it** — queue bar model, the `yield` wire block, the health
   report, and the panel's drawing.

Then `activate` takes its lanes, which is independent of 1–4 and can land last.

## 1 · `HoldAttribution` — the value

**New:** `Sources/ProctorCore/HoldAttribution.swift`

```
public struct HoldDisplay: Codable, Sendable, Equatable {
    public var index: Int          // 0-based, into the screen list given
    public var isMain: Bool
    public var name: String        // "the main display" | "display 2"
}

public struct HoldAttribution: Codable, Sendable, Equatable {
    public var reason: YieldReason
    public var session: String     // RunSessionIdentity.label — derived, never supplied
    public var app: String?        // the app under test, nil when unknown
    public var display: HoldDisplay?
    public var line: String        // the whole sentence, built here so one table owns it
}
```

- `HoldAttribution.display(for windowFrame: Rect?, in screens: [Rect])` calls
  `RunHUDPlacement.screenIndex(for:in:)` — reused, not re-derived — and names the
  result. `screens.isEmpty` ⇒ nil display rather than a guess.
- The name: `isMain ? "the main display" : "display \(index + 1)"`. `isMain` is
  passed in by the caller from `CGMainDisplayID()`; Core does not read
  CoreGraphics.
- `line` composes from the parts it has, degrading rather than printing "nil":
  `"\(reason.line) — \(session)"`, plus `" · \(app)"` and
  `" on \(display.name)"` when each is present. `reason.line` is PRO-0018's
  settled wording and is not rewritten.

**Tests** (`Tests/ProctorCoreTests/HoldAttributionTests.swift`) — A1:
`theDisplayIsTheOneHoldingMostOfTheWindow`, `aWindowOffEveryScreenTakesTheNearest`,
`theMainDisplayIsNamedAsSuch`, `noScreensMeansNoDisplay`,
`theLineDegradesRatherThanPrintingNil`, `theSessionIsTheDerivedLabel`.

## 2 · `RunControl` — the yield gains an owner

**Edit:** `Sources/ProctorAgent/Session/RunControl.swift`

Still one flag set, one `pausedAt`, one `yieldHeldTotal`, one `pauseLimit`. What
is added is a key and a per-run expiry set.

```
private var yieldReason: YieldReason?
private var yieldOwner: Int?            // NEW — which run read it
private var yieldHold: HoldAttribution? // NEW — what it is attributed to
private var expired: Set<Int> = []      // NEW — runs the backstop gave up on
```

- `yield(_ reason:, run: Int, hold: HoldAttribution)` sets all three; unchanged
  otherwise (one clock, started on the first cause).
- `release()` unchanged, plus clearing `yieldOwner`/`yieldHold`.
- `isPaused(run:)` → `pausedByPerson || yieldOwner == run`. The bare `isPaused`
  stays for the panel's "is anything held" read and means
  `pausedByPerson || yieldReason != nil`.
- `checkpoint(run:probe:)` — the run key threads through; `look(run:)` becomes:
  - `stopped` ⇒ `.stopped` (a person's Stop is about the machine).
  - `expired.contains(run)` ⇒ `.pauseExpired` for that run, consumed.
  - not `isPaused(run:)` ⇒ nil.
  - past the bound: if the cause was **this run's yield**, mark `expired.insert(run)`
    and clear the yield without touching global `stopped`. If the cause was a
    **person's pause**, set global `stopped` exactly as at HEAD.
- `begin(run:)` clears `pausedByPerson`, `stopped`, `personResumePending` as at
  HEAD (settled: a new run is a new live line), clears `expired.remove(run)`, and
  clears the yield **only when `yieldOwner == run`**. `pausedAt`/`yieldHeldTotal`
  clear only when nothing is left holding.
- `heldBy: HoldAttribution?` accessor, so a caller can read the current
  attribution without entering the session.

Every mutation stays inside the lock and never across a wait — the deadlock note
at the top of the file still governs.

**Tests** (`Tests/ProctorAgentTests/YieldWiringTests.swift`, extended) — A3/A4/A5:
`aYieldParksOnlyItsOwner`, `aPersonsPauseParksEveryRun`,
`beginDoesNotEraseAnotherRunsHold`, `beginClearsItsOwnHold`,
`anExpiredYieldGivesUpOnlyItsOwner`, `aSiblingIsNeverToldAPersonStoppedIt`,
`anExpiredPersonsPauseStillReachesEveryRun`, `oneClockStillBoundsTheRun`
(the flapping bound from PRO-0018 still holds).

## 3 · The keeper carries the join

**Edit:** `Sources/ProctorCore/RunQueue.swift` — `RunTicketInfo.held: HoldAttribution?`,
defaulted nil in `init` so every existing construction compiles unchanged.

**Edit:** `Sources/ProctorAgent/Session/RunScheduler.swift`

- `@TaskLocal static var currentRun: Int = 0` — the ticket id, readable from
  inside the reentrant actor because task-locals travel with the task.
- `func hold(run: Int, _ attribution: HoldAttribution)` sets `active[run]?.held`
  and publishes. `func unhold(run: Int)` clears it and publishes. Both no-op for
  an id that is not active, so a Stop racing a release cannot resurrect a hold on
  a released ticket.

**Edit:** `Sources/ProctorAgent/Session/SessionQueue.swift` — wrap `body()` in
`RunScheduler.$currentRun.withValue(ticket.id)` alongside the existing
`$holdingLanes`, so one `withValue` chain carries both.

**Tests** (`Tests/ProctorAgentTests/RunQueueWiringTests.swift`, extended) — A2:
`aHoldLandsOnItsOwnTicket`, `aHoldLeavesOtherTicketsAlone`,
`unholdClearsIt`, `aReleasedTicketCannotBeHeld`,
`everyEndingPathLeavesNothingHeld` (release, person's Resume, Stop, backstop, run
end — the five, driven through the session).

## 4 · Session publishes, and the surfaces read

**Edit:** `Sources/ProctorAgent/Session/Session.swift`

- `foregroundBegan(demand:app:window:)` gains the driven window's `Rect` and
  stores it on `YieldRun`, so the attribution can be built at yield time without
  re-resolving a handle.
- `attribution(for:run:)` builds `HoldAttribution` from the reason,
  `SessionIdentity.current.label`, the app name, and the display from
  `CGGetActiveDisplayList`/`CGDisplayBounds`/`CGMainDisplayID` folded through
  `HoldAttribution.display(for:in:)`.
- `contentionProbe(run:step:)` — on `.yielded`, `runControl.yield(reason, run:
  RunScheduler.currentRun, hold: attribution)` then
  `await runScheduler.hold(run: RunScheduler.currentRun, attribution)`. On
  `.released`, `runControl.release()` then `await runScheduler.unhold(run:)`.
- `disarmContention(run:)` publishes `unhold` for the ending paths (Stop, the
  backstop, the run simply finishing), which is the invariant A2 pins.
- `yieldJSON` gains `session`, `app`, `display`, and takes its `line` from the
  attribution rather than from `reason.line`, so one table owns the wording.
  Shape when nothing is held is unchanged.

**Edit:** `Sources/ProctorAgent/Session/SessionHUD.swift` — `hudRunControlBegin()`
→ `runControl.begin(run: RunScheduler.currentRun)`; `haltCheckpoint` takes the run.

**Edit:** `Sources/ProctorAgent/Session/SessionAct.swift` — pass `window.frame` to
`foregroundBegan`; pass the run key to `haltCheckpoint`.

**Edit:** `Sources/ProctorAgent/Session/SessionQueue.swift` — `queueStatus()`'s
`activeRuns` entries gain `held` (null or the attribution's object), A9.

**Edit:** `Sources/ProctorCore/RunHUD.swift` — `RunQueueModel.hold:
HoldAttribution?`; `Row.held: Bool`; `visible` gains `|| hold != nil`; `label`
returns the attribution's `line` when held. `from(_:live:now:expanded:)` reads
`RunTicketInfo.held` for both the running and waiting projections.

**Edit:** `Sources/ProctorAgent/Overlay/RunHUDContentView.swift` — the bar's label
already renders a string; a held row's mark reuses the existing `pos` slot glyph
(`▸` today for a running row) with a paused mark, in the existing `--ink-3`
weight. No second line, no new colour.

**Tests:**
- `Tests/ProctorCoreTests/RunHUDTests.swift` — A6:
  `theBarSaysWhoIsHeld`, `aHoldKeepsTheBarOnScreen`,
  `theHeldRowIsMarkedAndTheOthersAreNot`,
  `aHeldQueueAndAHeldRunReadDifferently`.
- `Tests/ProctorCoreTests/RunHUDMenuBarTests.swift` — A7:
  `theGlyphLadderIsUnchangedForAHeldRun`.
- `Tests/ProctorAgentTests/RunHUDMenuBarWiringTests.swift` — A7:
  `theYieldBlockNamesTheSessionAppAndDisplay`,
  `theYieldBlockIsUnchangedWhenNothingIsHeld`.
- `Tests/ProctorAgentTests/RunQueueWiringTests.swift` — A9:
  `theHealthReportMarksAHeldRun`.

## 5 · `activate` takes its lanes

**Edit:** `Sources/ProctorAgent/Session/SessionActivate.swift` — after
`enforcePolicy(...)` and before `NSWorkspace.openApplication`, wrap the remainder
in `scheduled(lanes:summary:)`:

```
let lanes = LaneDemand.forActivate(app: known?.id)   // .global always, + .app(id) when attached
let summary = "Activate · \(name ?? bundleId ?? "an app")"
```

`known` is the attached handle the policy gate already resolved
(`running.flatMap { attachedApp(pid:) }`) — the only key in the same space a
batch uses.

**Edit:** `Sources/ProctorCore/RunQueue.swift` — `LaneDemand.forActivate(app:)`,
a named constructor beside `forBatch` so the two lane decisions sit together.

**Edit:** `Sources/ProctorCore/ToolCatalogue.swift` — the `activate` description
gains one sentence: it now waits its turn when another run holds the machine, and
can come back saying the machine was busy or that a person dropped it, with
nothing activated either way.

**Tests:**
- `Tests/ProctorCoreTests/RunQueueTests.swift` — A8:
  `activateTakesTheGlobalLane`, `activateTakesTheAppLaneWhenAttached`,
  `activateTakesNoAppLaneWhenUnattached`.
- `Tests/ProctorAgentTests/RunQueueWiringTests.swift` — A8:
  `aQueuedActivateIsRefusedWithoutActivating`.
- `Tests/ProctorCoreTests/ProctorCoreTests.swift` — A8: the catalogue text.

## Order of work, and the gate at each step

1. `HoldAttribution` + its tests → `swift test --filter HoldAttributionTests`.
2. `RunControl` + its tests → `swift test --filter YieldWiringTests`.
3. Scheduler + ticket + task-local → `swift test --filter RunQueueWiringTests`.
4. Session publish + surfaces → the HUD and menu-bar filters.
5. `activate` lanes + catalogue.
6. Full `swift build` + `swift test`, counts read back before and after.

`swift test --filter` matches the Swift **function** name, not the `@Test`
display string, and a filter that matches nothing reports green — so every
filtered run has its `with N tests` count read back before it is believed.

## Risks, and what each is pinned by

| risk | pinned by |
|---|---|
| The scheduler's copy outlives the latch's yield | `everyEndingPathLeavesNothingHeld` — all five paths |
| A run beginning wipes a live hold (found by the gate) | `beginDoesNotEraseAnotherRunsHold` |
| A sibling reports "a person stopped this run" | `aSiblingIsNeverToldAPersonStoppedIt` |
| Splitting the parking rule loses the backstop | `oneClockStillBoundsTheRun`, and PRO-0018's flapping test kept green |
| `RunControl.shared` / `ContentionMonitor.shared` leaking across suites | every test injects its own, as `YieldWiringTests` already does |
| A changed `yield` wire block breaking the UI's poll | `theYieldBlockIsUnchangedWhenNothingIsHeld` |
