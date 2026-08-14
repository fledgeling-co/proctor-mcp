# Plan — PRO-0015: Run HUD panel

**Spec:** `docs/specs/spec-PRO-0015.md` · **Design (binding):** `mocks/run-hud.html`
**Branch:** `ai/pro-0015` · **Worktree:** `.worktrees/PRO-0015`
**Tier:** Large. Gate: `swift build` + `swift test` (258 tests / 29 suites green at HEAD).

The design is settled. This plan renders it natively; it does not re-open it.

## The two architectural decisions, made here rather than mid-implementation

### 1. The event loop — `NSApplication.run()` replaces `CFRunLoopRun()`

The agent owns main with a bare `CFRunLoopRun()` and never dequeues an
`NSEvent`, so a panel button has no path to a click. Three routes exist:

| Route | Why not / why |
|---|---|
| A CGEventTap on mouse-down | Needs its own grant, sees every click on the machine, and would have to hit-test our own panel by hand. A kill switch that reads the whole machine's input is worse than no kill switch. |
| Keep `CFRunLoopRun()`, pump by hand from a `CFRunLoopObserver` (`NSApp.nextEvent(…dequeue: true)` → `sendEvent`) | Works, but it re-implements the AppKit loop badly: no autorelease-pool-per-iteration, no tracking modes, and the panel's own drag/hover handling then depends on a pump that runs only when some other source wakes the loop. |
| **`NSApplication.shared.run()`** | Chosen. It *is* a CFRunLoop run — `CFRunLoopRun()` and `NSApp.run()` both spin the main run loop; the second one also drains the event queue. |

The named regression to watch is settling, and it is already covered:
`Sources/ProctorAgent/AX/Observers.swift:63` adds every AX observer source to
`CFRunLoopMode.commonModes`, precisely so a modal or menu-tracking loop cannot
starve notifications. `NSApp.run()` spends its life in the default mode and
enters tracking modes only during a nested loop — both are in `commonModes`, so
notification delivery is unchanged. Belt and braces: the HUD's drag is
implemented with `mouseDown`/`mouseDragged` + `setFrameOrigin`, never
`performDrag(with:)` or a nested `nextEventMatchingMask` loop, so the agent
never enters a tracking mode of its own making.

What must not change, and how each is preserved:

- **The MCP socket server** — `Server.start()` runs its accept loop on its own
  threads and is started before the loop is entered. Untouched.
- **The cursor overlay** — already an `NSPanel` from this process; an event loop
  strictly adds to what it can do. `CATransaction.flush()` at each entry point
  stays (it is cheap and it is what the header documents).
- **Headless / unattended** — `NSApplication.shared` is already touched at line 1
  of `main.swift` for the activation policy, so an AppKit connection is a
  pre-existing condition, not a new one. `PROCTOR_HUD=0` suppresses the panel;
  the loop still runs, and a run with no panel behaves exactly as today.
- **`.accessory` activation policy** — unchanged and still claimed first. The
  panel is a `.nonactivatingPanel`, so a click on Pause never activates the agent
  and never takes focus from the app under test.
- **SIGTERM/SIGINT** — `DispatchSource` on a global queue calling `exit(0)`.
  Unaffected by which loop main is in.

### 2. One panel, sized to itself, on the screen holding the driven window

`CursorOverlay.swift`'s header records the measurement: a panel sized to the
union of the displays (26 Mpx backing) is accepted by the window server,
reported `onscreen=1, alpha=1`, and never presented. The HUD sidesteps this
class of bug rather than re-deriving it — it is a 352pt panel sized to its own
content, so it can never span displays. The only decision left is *which*
screen, and that is a pure function of the screen arrangement and the driven
window's frame (`RunHUDPlacement`), testable without a display.

## Files

### New — `Sources/ProctorCore` (pure, no window, no grant, fully testable)

| File | Contents |
|---|---|
| `RunHUD.swift` | `RunHUDPhase` (the mock's seven states), `RunHUDModel` (the rendered line, counter, fraction, trail, exception, pause label, phase), `RunHUDState` (the reducer: events in, model out), `RunHUDEvent`. Wording comes from `StepDescription`; no second wording table. |
| `RunHUDPlacement.swift` | `place(panel:in screens:targetWindow:inset:)` → screen index + origin, docked bottom-right at the mock's 34pt inset, clamped into the screen. Pure over `Rect`. |
| `OverlaySwitch.swift` | `OverlaySwitch.isOn(_ raw: String?)` — the `0/off/false/no` shape, shared by `PROCTOR_CURSOR` and `PROCTOR_HUD` so the two off-switches cannot drift. |

### New — `Sources/ProctorAgent`

| File | Contents |
|---|---|
| `Overlay/RunHUDPanel.swift` | `@MainActor final class RunHUDPanel` — the borderless non-activating `NSPanel` rendering `RunHUDModel`: live line, tabular counter, bottom-edge rail, three-row trail, run clock, Pause/Stop, grip, empty 38pt character bay. Neutral graphite / neutral white, vermilion `#FF6A3D` as the only colour, from the mock's tokens. Honours reduce-transparency and reduce-motion; re-reads the appearance on theme change. Records whether it presented, for the health report. |
| `Session/RunControl.swift` | The pause/stop latch. Lock-guarded, `@unchecked Sendable`, set from the main thread by the buttons, read by the `Session` actor between steps. Holds a paused run until resumed, with a backstop (15 min default, `PROCTOR_HUD_PAUSE_LIMIT` seconds) after which it gives up the same way a stop does. Injectable clock and sleep so the backstop is testable in milliseconds. |
| `Session/SessionHUD.swift` | The bridge: `hudRunBegan/hudStep/hudSettled/hudRunEnded`, each a no-op when the HUD is off; `haltCheckpoint(before:)` returning the refusal when a person stopped it or a pause expired. |

### Modified

| File | Change |
|---|---|
| `Sources/ProctorAgent/main.swift` | `CFRunLoopRun()` → `NSApplication.shared.run()`, with the reasoning above in the comment. |
| `Sources/ProctorAgent/Session/SessionAct.swift` | `runSteps` gains: the halt checkpoint before each step, the HUD events around each step, and the end-of-run event. One code path, so act / flow replay / stability / the CUA façade all get the panel and the kill switch identically. |
| `Sources/ProctorCore/Wire.swift` | One new `AgentError.Code`: `haltedByPerson`. The policy gate's `policyDenied` would report a person's decision as a configured rule. |
| `Sources/ProctorAgent/Session/SessionDoctor.swift` | A `hud` block: enabled, available, and the reason when it is not — so a silent absence never leaves someone believing they have a stop button they do not have. |
| `Sources/ProctorAgent/Overlay/CursorOverlay.swift` | `isEnabled` routes through `OverlaySwitch.isOn`. Two lines. |
| `CHANGELOG.md` | Unreleased entry (prose through `create-luke-content`). |

## The state machine

| Run event | Phase | Live line |
|---|---|---|
| batch begins | `travelling` | prospective line for step 0 |
| about to actuate step *n* | `travelling` | `StepDescription.line(…timing: .prospective)` |
| actuating step *n* | `acting` | `…timing: .present` |
| step refused (synthetic-plane refusal, policy) | `blocked` | `…outcome: .refused` |
| step failed / never settled | `error` | `…outcome: .failed` |
| paused before step *n* | `paused` | `Paused before <object>` |
| batch ends, all steps ran | `finished` | `Run complete` |
| stopped by a person | `paused` (grey, **not** red) | `Stopped by a person` |

`idle` exists in the model because the mock draws it, and is not reached in this
build: the panel appears when a run starts and goes when one ends. It becomes
real with the queue (PRO-0016).

Counter and rail count the batch in flight. The exception line is emitted only
for a synthetic-plane step and reads `Synthetic event — <App> must stay in
front`; the accessibility plane is never announced.

Linger: 3s after `finished` or a person's stop; 15s after `blocked` or `error`.

## What PRO-0016 and PRO-0017 receive

- The queue bar is **not built**. `RunHUDPanel` lays the trail, the queue slot and
  the footer as a vertical stack, so PRO-0016 inserts its bar between the trail
  and the footer without moving anything else, and `RunHUDModel` carries no queue
  field to strip out.
- The character bay is an empty 38pt dark inset at the left of the live line,
  drawn to the mock's radius and inner shadow. PRO-0017 drops assets into it.

## Test plan — one clause, one test

| Acceptance clause | Test |
|---|---|
| One live line, one size, derived wording | `RunHUDState` reducer over every phase; asserts the line equals `StepDescription`'s and that no second wording table exists |
| Counter is the batch in flight, tabular | reducer counter/fraction across a 7-step batch and across two batches of a sweep |
| Three-row trail, newest last, settle times | reducer trail capacity + ordering + ms |
| Exception surfaced once, only for synthetic | reducer: `ax` plane ⇒ no line; synthetic ⇒ exactly the mock's sentence |
| A person's stop is not drawn as a fault | reducer: stop ⇒ grey/paused phase, not `error` |
| Stop ends the run; finished steps survive; refusal on the first step that never ran | `Session` + `FakeAX`: stop after step 1 of 3 ⇒ 1 completed, `failedAt == 1`, `results[1].error.code == .haltedByPerson`, and `FakeAX.performed.count == 2` (nothing after the halt) |
| Stop with no step remaining does nothing | same harness, halt after the last step ⇒ run completes, no refusal |
| Pause holds before the next step, in-flight step completes | `RunControl`: paused ⇒ checkpoint blocks; resume ⇒ proceeds; the step already dispatched is untouched |
| The pause backstop gives up like a stop | `RunControl` with an injected clock: expiry ⇒ `.haltedByPerson` naming the backstop |
| A halt is audited alongside the step it interrupted | `Session` + capturing audit sink ⇒ a record for the halted index with the refusal reason |
| Off-switch is `PROCTOR_HUD`, the pointer's shape | `OverlaySwitch.isOn` truth table; `PROCTOR_CURSOR` unchanged |
| The panel is placed on the screen holding the driven window, docked bottom-right | `RunHUDPlacement` over one, two and disjoint-arrangement screens; never a union rect |
| Absence is reported, the run still proceeds | doctor `hud` block; and a run with the HUD off completes normally |

**Not machine-witnessable in this repo** (stated plainly in the report, never
dressed up as verification): that the panel renders, that a click reaches Pause,
the blur, the animation, the light/dark appearance, and the drag. `swift test`
has no window server and obscura is web-only. These are code-complete against
the mock and need a human glance.

## Plan review — out-of-family, grok `grok-4.6` (xhigh, read-only), 2026-08-14

Lane ran, no downgrade. Six findings; five accepted and folded in above, one
half-accepted.

1. **Accepted (High).** A borderless panel can report `canBecomeKey == false`
   and views reject first-mouse, so an inactive `.accessory` app never sees the
   click. `RunHUDPanel` overrides `canBecomeKey` and implements
   `acceptsFirstMouse(for:)` on the content view and every control.
2. **Accepted (High).** Above `.screenSaver` is a *shielding* level — clicks can
   fall through and the panel can sit over the lock screen. The HUD sits at
   `.statusBar` with `canJoinAllSpaces`, `stationary`, `fullScreenAuxiliary` and
   `hidesOnDeactivate = false`. The pointer overlay stays at `.screenSaver` and
   is click-through, so it may draw over the panel and cannot block it.
3. **Accepted (High).** A pause that waits holding the lock, or sleeps on the
   actor's executor, deadlocks Stop and starves the cooperative pool.
   `RunControl` holds its lock for a flag read only and parks with
   `await Task.sleep`.
4. **Accepted (Medium), as confirmation.** `NSApp.run()` still fires
   `commonModes` AX sources and leaves a socket server on its own threads alone;
   `CFRunLoopStop` would no longer exit the process. Termination already goes
   through `exit(0)` in the signal sources, so nothing changes there.
5. **Accepted (Medium).** Never call `activate(_:)` — an agent that activates
   takes focus from the app under test and breaks both settling and synthetic
   input. Only `orderFrontRegardless()`.
6. **Half accepted (Medium).** `sharingType = .none` adopted, so "never in a
   capture" is a property of the window rather than an argument about capture
   filters. Its second half — move the panel off the driven window — is
   **rejected**: the docked bottom-right position is the settled design. Its
   third — that a raw SwiftPM executable may get no WindowServer mouse events —
   does not apply: the agent ships inside `Proctor.app/Contents/MacOS` and is
   started by launchd as a GUI agent, which is why the pointer overlay already
   draws.

## Order of work

1. Core: `OverlaySwitch`, `RunHUDPlacement`, `RunHUD` state + tests (red → green).
2. `RunControl` + `haltedByPerson` + tests.
3. `runSteps` wiring + the `Session`/`FakeAX` halt tests.
4. `NSApplication.run()` + the panel.
5. Doctor block, CHANGELOG, spec progress note.
