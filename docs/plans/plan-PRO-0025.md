# Plan — PRO-0025: Prefer the background, and draw the pointer in the target's plane

**Spec:** `docs/specs/spec-PRO-0025.md`
**Branch / worktree:** `ai/pro-0025` · `.worktrees/PRO-0025`
**Tier:** Standard. Two independent halves, five files touched in Core, four in Agent.

## Plan review (out-of-family: grok-4.6, xhigh, read-only, 2026-08-15)

Ten findings. Five sharpened the implementation and are folded in above; the
rest were the reviewer reading a plan without the code.

| # | Finding | Disposition |
|---|---|---|
| 5 | "Select the whole value" needs a length the selected-text path never reads, and the restore is undefined if the original range read failed | **Accepted.** The route now *requires* both a readable `AXValue` (for the length) and a readable original `AXSelectedTextRange` (to restore) before it is attempted; missing either drops the route. |
| 6 | The ancestor scroll-bar write picks no axis and splits no 2D delta | **Accepted.** Each non-zero axis is written on its own bar, and the route counts as taken only if every axis attempted took. Sign and mapping stay `current + delta/100`, identical to the existing branch. |
| 8 | `held` needs a defined predicate: immediately above, or anywhere above? | **Accepted, and made strict.** Immediately above: a window between the panel and the target would be drawn *under* the pointer while being *above* the target, which is a smaller version of the same lie. A false demotion costs a dimmed pointer, which is the safe direction. Label renamed to `order:`. |
| 3, 4 | The `type` ladder's prose is ambiguous and no rung assigns a route | **Accepted as a clarification.** value → read back → selected text → read back → refuse/post, and every rung returns its own `ActuationRoute`. |
| 9 | `Session` is an actor and the overlay is `@MainActor`; and which screen's panel gets restacked | **Answered.** The plane is computed on the session actor (the window-list read is nonisolated) and passed as a value across the existing hop. Only the surface the pointer is on is restacked; the others hold a pointer at zero opacity, so their level is not observable. |
| 1, 2, 7 | Inert API, `conditional` set, `decide`'s return | Non-issues: `notice()` already returns `String?`, `ForegroundReport.from` sets the flag, `Session.conditionalKinds` is `[.type, .scroll]`, and `decide` returns `PointerPlane`. |
| 10 | `type`'s fallback calls `activate()`, a raise `raises` does not count | Covered: that path is only reachable when `requestedForeground && conditionalSteps > 0`, which is exactly `mightPost`. An inert batch can never reach it. |

## Order of work

The halves do not share a file. Background first (it is the one with a
scheduling consequence), pointer second.

### 1 — `ForegroundDemand` (Core)

`Sources/ProctorCore/ForegroundDemand.swift`

- Add `mightPost`, restate `takesForeground` as `mightPost || raises`, add
  `requestWasInert`.
- `notice()` returns nil when `requestWasInert`.
- `ForegroundReport` gains `requestIgnored: Bool` (defaulted in the memberwise
  init so existing call sites compile) and `ForegroundReport.from` sets it from
  the demand. `note` states it once when nothing else is being said.

`Sources/ProctorCore/RunQueue.swift`

- `LaneDemand.forBatch` takes `conditional: Set<ActionStep.Kind>` and passes it
  through. Update the doc comment: the lane is "might post, or raises".

`Sources/ProctorAgent/Session/SessionQueue.swift`

- `lanes(for:window:foreground:)` passes `Self.conditionalKinds`.

### 2 — Routes and route reporting (Core + Agent)

`Sources/ProctorCore/Wire.swift`

- `public enum ActuationRoute: String, Codable, Sendable` — `action`,
  `valueWrite`, `selectedText`, `scrollBar`, `scrollAction`, `eventStream`,
  `appleEvent`, `declared`.
- `StepResult.route: ActuationRoute?`, defaulted `nil` in the memberwise init so
  the existing call sites in flow replay and stability keep compiling.
- `public struct Actuation { plane, route }`.

`Sources/ProctorAgent/Contracts.swift` — `perform` returns `Actuation`.

`Sources/ProctorAgent/AX/AXEngineImpl.swift` — pass through.

`Sources/ProctorAgent/AX/Actuator.swift`

- Every `return .accessibility` becomes an `Actuation` carrying its route.
- `type`: value write **+ read-back** → range-select + selected-text write **+
  read-back**, restoring the original range on failure → existing refusal /
  synthetic post.
- `scroll`: existing bar write (read-back added) → page action → **new**
  ancestor `AXScrollArea` walk, bounded to 12 parents, taking the first area
  whose `AXVerticalScrollBar` / `AXHorizontalScrollBar` element is settable,
  writing `AXValue` on that bar with `current + delta/100` clamped, read back →
  existing refusal / synthetic wheel.
- Helper `AXWrite.tookEffect(_:_:expected:)` style read-back lives beside the
  write helpers, not inline in each branch.

`Sources/ProctorAgent/Session/SessionAct.swift` — `let outcome = try ax.perform(…)`;
`outcome.plane` everywhere the old `plane` was used; `route: outcome.route` on the
successful `StepResult`.

`Tests/ProctorAgentTests/Fakes.swift` — the fake AX engine returns `Actuation`;
give it a settable `route` so a wiring test can assert one travels.

### 3 — The pointer's plane (Core + Agent)

`Sources/ProctorCore/PointerPlane.swift` (new)

```swift
public enum PointerPlane: Equatable, Sendable {
    case inPlane(above: UInt32)
    case floatingDimmed
    case hidden
}
public enum PointerPlanePolicy {
    public static let dimmedOpacity: Float = 0.32
    public static func decide(targetWindowID: UInt32?, targetIsOnScreen: Bool) -> PointerPlane
    /// Did the restack hold? `order` is the on-screen window list, front to back.
    public static func held(panel: UInt32, above target: UInt32, in order: [UInt32]) -> Bool
}
```

`held` is where the verification lives, and it is a pure function over a list so
it can be tested: the panel must appear, the target must appear, and the panel's
index must be smaller.

`Sources/ProctorAgent/Overlay/CursorOverlay.swift`

- `Surface` gains nothing; the overlay gains
  `func place(for plane: PointerPlane, panelOf surface: Surface)`.
- `inPlane(id)` → `panel.level = .normal`, `panel.orderFrontRegardless()`,
  `panel.order(.above, relativeTo: Int(id))`, then read the window list back and
  call `held`; on failure fall through to the dimmed treatment.
- `floatingDimmed` → `panel.level = .screenSaver`, pointer opacity multiplied by
  `dimmedOpacity` and the ring's stroke dashed, so it is dimmed *and* marked.
- `hidden` → `hide()`.
- The three public entry points (`travel`, `click`, `drag`) take the plane; every
  new drawing statement stays inside the existing `ProctorCatchNSException`
  barrier and inside a single `CATransaction`.
- Header comment: append the M1/M2/M3 measurement, in the style of the existing
  union-panel measurement, so the next reader does not re-derive it.

`Sources/ProctorAgent/Session/SessionCursor.swift`

- `showCursor(for:window:)` resolves the plane once per step:
  `CGWindowIndex.records(option: .optionOnScreenOnly, pid:)` → on-screen-ness →
  `PointerPlanePolicy.decide(targetWindowID: window.cgWindowID, …)`, and hands it
  to the overlay. Guarded by `CursorOverlay.isEnabled` **before** any window-list
  read, so `PROCTOR_CURSOR=0` costs nothing.

`Sources/ProctorAgent/Session/SessionAct.swift` — pass `window` to `showCursor`.

## Tests, one per clause

| Clause | Test | Suite |
|---|---|---|
| A1 | a `press`-only batch with `foreground: true` reports `takesForeground == false` and takes no global lane | `ForegroundDisclosureTests`, `RunQueueTests` |
| A2 | a `type` batch with `foreground: true` still takes the global lane; a `click` batch still does | `RunQueueTests` |
| A3 | `ForegroundReport.requestIgnored` and its note | `ForegroundDisclosureTests` |
| A4 | fake element refusing `AXValue`, accepting a full-range `AXSelectedText`, reports `.accessibility` / `route == .selectedText` | `ProctorAgentTests` (actuator-level fake) |
| A5 | ancestor scroll area's bar takes the write | same |
| A5b | a write accepted but not taken falls through to the next route | same |
| A6 | `StepResult.route` survives encode/decode and is set on a successful step | `ProctorCoreTests`, `ForegroundWiringTests` |
| A7 | `decide` returns `.inPlane` for an on-screen correlated target | `ProctorCoreTests` (new `PointerPlaneTests`) |
| A7b | `held` is false when the panel is behind the target or absent | same |
| A8 | `decide` returns `.hidden` for an off-screen target | same |
| A9 | `decide` returns `.floatingDimmed` for on-screen with no id | same |
| A10 | `showCursor` performs no window-list read and no overlay call when disabled | `ProctorAgentTests` |
| A11 | unchanged; the one-panel-per-screen construction is not touched | — |

A4/A5/A5b need an actuator-level fake for `AXUIElement`, which does not exist
today — `Actuator` calls `AXWrite`/`AXRead` statically against real elements.
Rather than inventing an AX mock layer, the route-selection **order** is
extracted into a pure decision function over element capability flags
(`ValueWritable`, `SelectionWritable`, …) which the actuator then executes; the
test drives the decision function. What the test therefore proves is the order
and the fall-through, not that `AXSelectedText` works against a real NSTextView.
That gap is stated, not papered over.

## What cannot be witnessed by `swift test`

The restack, the occlusion, the dim, the presentation of any panel, the real
`AXSelectedText` write against a real text view, and the real scroll-bar write.
All need a window server or a live app. The restack and the occlusion **are**
measured, by the probes recorded in the spec; the rest is code-complete and
named as unverified in the progress note.

## Risks

- **Level change is the sharp edge.** A `.normal`-level full-screen transparent
  panel is in the same band as the user's windows. It is click-through and
  non-activating so it cannot receive input, but a mistake here is visible on
  every display. Mitigation: the level only changes while a plane is being
  applied; the panel returns to the floating level for `floatingDimmed`.
- **`ForegroundReport` and `StepResult` are wire types.** Both gain optional /
  defaulted fields only, so an older reader is unaffected.
