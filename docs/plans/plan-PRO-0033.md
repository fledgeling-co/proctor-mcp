# Plan — PRO-0033: A person's click reaches Stop

**Spec:** `docs/specs/spec-PRO-0033.md`
**Plan size:** Standard
**Branch:** `ai/pro-0033` · **worktree:** `.worktrees/PRO-0033`

## Intent

One rule decides when the run panel steps aside — the plane the step is actually
travelling, and whether it will post inside the panel's own footprint — and a
person's click on Stop reaches Stop on the first press whether or not the
takeover block is armed. Fifteen clauses, A1 to A15, in the spec.

## The one coordinate decision, made once

The actuator posts `step.point` **raw** as a global screen point in Quartz space,
y-down from the top of the primary display (`Actuator.pointer`, line 553;
`dragPath`, line 642), and an AX frame states the same space. `cursorTarget(for:)`
and `cursorRoute(for:)` in `SessionCursor.swift` already return exactly those
values — they are what the drawn pointer travels to.

So **everything in this feature works in Quartz screen space**, and the single
conversion happens once, on the main thread, when the panel publishes its
geometry: AppKit `NSWindow.frame` → Quartz, with `primaryMaxY =
NSScreen.screens.first!.frame.maxY`, the constant `RunHUDPlacement.appKit` and
`CursorOverlay.appKitPoint` already use. `CGEvent.location` inside the tap is
already Quartz, so the tap compares directly. There is no second conversion and
no per-screen flip to get wrong (A13).

## Steps

### 1 — Core: the geometry and the gate predicate

`Sources/ProctorCore/RunHUDPlacement.swift`

- `quartz(from appKit: Rect, primaryMaxY: Double) -> Rect` — the inverse of the
  existing `appKit(from:primaryMaxY:)`, arrangement-wide. Round-trip tested.

New `Sources/ProctorCore/RunHUDGate.swift`

```swift
public enum RunHUDGate {
    /// Does anything this step will post land inside `panel`? Points are Quartz
    /// screen points, the space the actuator posts in.
    public static func stepsAside(points: [Point], panel: Rect?) -> Bool
}
```

Empty points, or a nil panel frame, return false: a step with nothing resolved
posts nowhere the panel can be, and a panel that is not on screen cannot be in
the way. A route is tested along every point (A-iv), not only its ends — a
straight segment between two points outside a rectangle can still cross it, so
the segment/rect intersection is what is computed, not point containment alone.

### 2 — Core: the model carries the gate separately from the statement

`Sources/ProctorCore/RunHUD.swift`

- `RunHUDModel.stepsAside: Bool`, beside `syntheticInFlight` (line 221).
  `syntheticInFlight` keeps its present meaning and keeps driving the exception
  row through `setPlaneStatement(synthetic:)` (line 444). The two part company:
  the statement is about the plane, the gate is about the plane *and* the
  geometry.
- `RunHUDEvent.stepApproaching` and `.stepActing` gain `stepsAside: Bool`. The
  compiler enumerates every construction site.
- Every place that clears `syntheticInFlight` clears `stepsAside` too — lines
  335, 342, 374, 388 (`stepRefused`, `stepFailed`, `yielded`, `runEnded`). The
  `.yielded` comment already explains why: a gate left open makes Resume itself
  unclickable.
- `RunHUDPanel.render()` (line 449) reads `feed.model.stepsAside`.

### 3 — Agent: the panel publishes its geometry

New `Sources/ProctorAgent/Overlay/RunHUDGeometry.swift` — a
`final class ... @unchecked Sendable` singleton holding two optional `Rect`s in
Quartz space (the panel frame, the Stop control's rect) behind one `NSLock`.
Reads copy the value out under the lock and return; nothing is held across any
work, and it shares no lock with anything that hops to main (A14).

`RunHUDPanel` publishes in `present(for:)`, at the end of `render()` (which
already runs on every state change and on the 1 Hz clock), and in `drag(by:)`;
it clears in `hide()`, `drawingChanged()`'s off branch, `takeDownAfterDrawingFault()`
and on `runEnded` (A13). `RunHUDContentView` exposes its `stopRect` in view
space; the panel converts view → window → screen → Quartz.

### 4 — Agent: the actuator declares before it posts

`Sources/ProctorAgent/AX/Actuator.swift`

At the **end** of `requireEventPlaneAvailable()` (line 690), after its
Secure Event Input guard passes, call a `@Sendable` declaration hook. A refused
step throws before reaching it and declares nothing (A4). Every synthetic route
reaches its post through this guard — lines 226, 429, 529, 563, 596 — and the
comment there states the property and why it holds: a route that skipped the
declaration would also skip the secure-input check.

The hook is a `nonisolated(unsafe) static var` on a small
`SyntheticPost` keeper (lock-guarded, in the agent), installed by the session at
run start and cleared at run end. It must not wait; it calls
`noteSyntheticPost()`, raises the takeover statement and arms the block (A6).

### 5 — Agent: the session computes the gate and arms alongside it

`Sources/ProctorAgent/Session/SessionAct.swift`, in `runSteps`

- Before each step, compute `stepsAside` from `RunHUDGate.stepsAside(points:
  panel:)` — points from `cursorRoute(for:)` when it returns ≥2, else
  `cursorTarget(for:)`; panel frame from `RunHUDGeometry`. For a certain
  synthetic kind the plane half is known; for `type`/`scroll` it is taken as
  possible, so the gate opens only when the target is under the panel (A2).
- Pass it on `.stepApproaching` (line 229) and `.stepActing` (line 255). The
  `await` on `hud(.stepActing…)` is the existing main-actor hop that orders the
  gate before `ax.perform` at line 272 — that ordering is the reason it is
  awaited and must not be loosened.
- `takeoverArm(for:)` (line 269) becomes conditional on `synthetic || stepsAside`
  rather than on `synthetic` alone, so the armed window is never narrower than
  the open gate (A7).
- **The gate is not closed in the `defer` at line 271 and not from the measured
  plane, and not held to the next step either.** It closes on the first of
  `.stepSettled`, `.stepRefused`, `.stepFailed`, `.yielded` and `.runEnded` —
  every path through `runSteps` reaches one. Closing it on `perform`'s return
  would restore hit-testing while Proctor's own posted events are still queued;
  holding it to the next step, which is what `syntheticInFlight` does at HEAD,
  leaves Stop dead across the settle and the gap, which is when somebody
  reaches for it (A3).

### 6 — Core: the tap's Stop route

`Sources/ProctorCore/Takeover.swift`, `InputBlock.Gate.decide`

Signature gains `location: Point?`, `stopRect: Rect?` and `postInFlight: Bool`.
Order inside `.mouseDown` / `.mouseUp`, after the existing `isOurs` test:

- `postInFlight` true ⇒ the Stop rect is not consulted at all. Proctor's own
  click happens inside its own declared post, so this makes A9 structural rather
  than an identity check — it holds even if both source fields were lost.
- `.mouseDown` inside `stopRect` ⇒ `.swallow`, the button recorded in
  `swallowedButtons` as it already is, **and a pending Stop recorded for that
  button**.
- `.mouseUp` for a button carrying a pending Stop ⇒ `.stopRun` when the up is
  inside the rect, `.swallow` when it is outside (a cancel). The pending record
  is what decides it, **not** a re-test of `postInFlight` or of the rect — a post
  beginning between somebody's down and their up would otherwise suppress the
  rect at the up and lose the press silently (A8b). The decision is taken on the
  up, matching how `RunHUDContentView.mouseUp` actuates, so no orphaned up
  escapes into the application after the run ends and the tap comes down (A8).

`InputBlocker.handle` reads `event.location` and the keeper's rect, and passes
`postInFlight` from the `SyntheticPost` keeper.

### 7 — Agent: the belt at the controls

`Sources/ProctorAgent/Overlay/RunHUDContentView.swift`

`mouseDown` and `mouseUp` return without setting `pressed` or actuating when
`InputBlock.isOurs` is true for the event's `cgEvent` source fields. A nil
`cgEvent`, or unreadable fields, is treated as a person's (A-iii): the geometric
gate is the primary enforcement, and failing this the other way would leave the
kill switch dead whenever AppKit synthesised an event without one.

## Acceptance criteria

Each is a `swift test` case unless marked. Filters match the Swift **function**
name, never the `@Test` display string.

| # | Clause | Test |
|---|---|---|
| 1 | A1 | `gateNeedsBothThePlaneAndThePoint` — synthetic outside the panel does not open it; synthetic inside does; a non-posting step never does whatever its kind |
| 2 | A2 | `aFallbackOpensItAndAnAccessibilitySuccessDoesNot` |
| 3 | A3 | `theGateClosesOnTheSettle`, `everyEndingClosesTheGate` — exhaustive over settled/refused/failed/yielded/runEnded |
| 4 | A4 | `aRefusedStepDeclaresNothing` |
| 5 | A5 | `aDeclarationCannotPrecedeAnAccessibilitySuccess` — the declaration hook is not called on a route that returns `.accessibility` |
| 6 | A6 | `theDeclarationOpensTheGraceWindow`, `theDeclarationRaisesTheStatement` |
| 7 | A7 | `armingIsNeverNarrowerThanTheGate` |
| 8 | A8 | `stopIsDecidedOnTheUp`, `theDownIsSwallowedAndPaired`, `anUpOutsideTheRectDoesNotStop` |
| 8b | A8b | `aPostBeginningMidClickDoesNotLoseThePress` |
| 9 | A9 | `aPostInFlightIgnoresTheStopRect`, `oursIsTestedBeforeTheRect` |
| 10 | A10 | `withTheGateClosedTheClickReachesTheControl` |
| 11 | A11 | `ourOwnEventNeverActuatesAControl`, `anUnreadableSourceIsTreatedAsAPerson` |
| 12 | A12 | `noTapWithTheSwitchUnset` (existing, must stay green) |
| 13 | A13 | `theQuartzFlipRoundTrips`, `aDisplayAboveTheMenuBarIsNotInverted`, `theRectIsClearedOnTeardown` |
| 14 | A14 | code reading — stated, not machine-witnessable |
| 15 | A15 | `refusalsAndLaneDemandAreUnchanged` (existing suites must stay green) |

Gate: `swift build` clean with no new warnings, `swift test` green, counts read
back before and after.

## Not machine-witnessable

The tap swallowing a real click, the panel receiving one, `ignoresMouseEvents`
taking effect in the window server, and the published rectangle matching what is
on screen. Named in the spec and repeated in the progress note rather than
implied.

## Plan review gate

**Mechanical path check: passed.** Every backtick-quoted path in this plan
exists, other than the two marked to be created (`RunHUDGate.swift`,
`RunHUDGeometry.swift`).

**Out-of-family review: grok-4.6, `xhigh`, read-only, 2026-08-15**, evidence
inlined at 25 lines with file reading suppressed. The first attempt at 35 lines
returned empty — a lane failure, retried once compacted rather than passed.
Two findings, **both accepted, and the first was a defect the spec's own A3 would
have shipped.**

| # | Finding | Disposition |
|---|---|---|
| 1 | Closing the gate at the next step leaves Stop dead across the settle and the gap between steps — which is when somebody actually reaches for it — and any path that reaches neither the next step nor run end never closes it | **Accepted; A3 rewritten.** It also caught that HEAD's behaviour quietly contradicts PRO-0026's A6 route 1, which claims the panel is clickable between steps. The gate now closes on the settle, and every one of the five endings is enumerated and tested. |
| 2 | A post beginning between a person's mouse-down and their mouse-up makes the in-flight rule suppress the rectangle at the up, so the press is swallowed and silently lost | **Accepted; A8b added.** The up follows a pending record made at the down and re-tests nothing. Its second half — that a Stop click during a post is passed through to the application — is **rejected on the design**: a person's event while armed is still swallowed by the ordinary rule, it merely is not read as a press. |
