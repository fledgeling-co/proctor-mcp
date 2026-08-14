# PRO-0026 — implementation plan

**Spec:** `docs/specs/spec-PRO-0026.md` · **Branch** `ai/pro-0026` · **Worktree**
`.worktrees/PRO-0026`

Written alongside the build rather than ahead of it: the spec's decision — which
of the brief's three readings ships — could not be settled without the three tap
probes (T1, T2, T3), and those probes are what fixed the shape of the code.

## Size

Standard. Two new files, four touched, one new suite per side.

## Order of work, and why

1. **Probe first.** `CGEventTap` semantics are the kind of thing that reads
   obvious and behaves otherwise, and this repo's record is that reasoning about
   the event stream is how a feature like this fails (PRO-0018's own gate note
   says the same). T1 changed the design before a line of it was written: a
   swallow-all tap eats Proctor's own posted events.
2. **`Sources/ProctorCore/Takeover.swift`** — every decision as a pure value:
   the two switches, when the statement shows, what it says, how it is drawn,
   `InputBlock.Gate`, the panic chords, the arm deadline, `TakeoverReport`.
3. **`Sources/ProctorAgent/Overlay/TakeoverOverlay.swift`** — the panels on the
   main actor and `InputBlocker` on a thread of its own. No policy: it maps
   `CGEventType` to `InputEventKind` in one place and asks Core.
4. **`Sources/ProctorAgent/Session/SessionTakeover.swift`** — the seam
   (`TakeoverDriving`), the live implementation, and the run's four calls.
5. **Wiring** in `runSteps`, `ActResult`, flow replay and `proctor_doctor`.
6. **Tests** — `Tests/ProctorCoreTests/TakeoverTests.swift` (the decisions) and
   `Tests/ProctorAgentTests/TakeoverWiringTests.swift` (the run's calls, against
   a fake).
7. **The capture measurement (T4)**, which is the clause that cannot be a test.

## Files

| File | Change |
|---|---|
| `Sources/ProctorCore/Takeover.swift` | new — the whole decision surface |
| `Sources/ProctorAgent/Overlay/TakeoverOverlay.swift` | new — panels + `InputBlocker` |
| `Sources/ProctorAgent/Session/SessionTakeover.swift` | new — the seam and the run's calls |
| `Sources/ProctorAgent/Session/SessionAct.swift` | raise, arm, release, report |
| `Sources/ProctorAgent/Session/Session.swift` | `takeover` seam + `takeoverShown` |
| `Sources/ProctorAgent/Session/ContentionMonitor.swift` | `noteUserInput()` on the protocol |
| `Sources/ProctorAgent/Contracts.swift` | `Grants.inputMonitoringState()` |
| `Sources/ProctorAgent/Dispatch.swift` | the `takeover` block on doctor |
| `Sources/ProctorCore/Wire.swift` | `ActResult.takeover` |
| `Sources/ProctorAgent/Session/SessionFlow.swift` | the same block on a replay |

## The three things that could go wrong, and what stops each

- **The block eats Proctor's own events** (T1 says it would). Stopped by
  `InputBlock.isOurs` being the only pass rule and by
  `ourOwnEventsAlwaysPass`, which is exhaustive over every event kind.
- **The block outlives what armed it.** Stopped by the deadline living on the
  tap's own run loop rather than with the caller, by `stopAll` at run end, and
  by the tap being a Mach port this process owns (T3).
- **The tint enters a capture.** Stopped by window scoping and by
  `sharingType = .none`; proved by T4 rather than argued.

## What is deliberately not built

A settings surface for the `PROCTOR_*` switches, and routing a person's click on
Stop through the tap so it lands on the first press rather than the second. Both
are recorded as child work on the spec.
