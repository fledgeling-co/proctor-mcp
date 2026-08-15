# Plan — PRO-0041: `proctor_doctor` stops waiting forever, and says so

**Spec:** `docs/specs/spec-PRO-0041.md`
**Branch:** `ai/pro-0041` · **Worktree:** `.worktrees/PRO-0041`
**Size tier:** Standard (small mechanism, four consumer surfaces, wire-visible)

## Shape

One new pure decision in Core, one new platform binding in the agent, four consumers taught
the third state, and the two hanging suites given an injected probe.

The decision logic is pure and clock-injected so it tests without a window server or a
platform call — the shape `AgentRecovery.decide` and `MenuBarIcon.block` already use. The
platform binding is the only part that touches ScreenCaptureKit, and it takes the platform
call as a closure so the bound is testable with a call that answers, throws, or never
returns.

## Steps

### 1. `Sources/ProctorCore/GrantProbe.swift` (new) — the state and the pure keeper

- `public enum GrantState: String, Codable, Sendable { case granted, denied, unconfirmed }`.
- `public enum GrantProbe` namespace carrying the bound (`1.5`) and the backoff schedule
  (`[2, 10, 60, 300]`, capped at the last).
- `public final class GrantProbeKeeper: @unchecked Sendable` — an `NSLock` guarding
  `definite: GrantState?`, `probeStartedAt: Double?`, `attempts: Int`. Every transition is
  one synchronous critical section with no `await` inside it (clause A9). Methods:
  - `decide(now:) -> Decision` where `Decision` is `.cached(GrantState)`, `.start`,
    `.join`, or `.unconfirmed` — pure, total, and the whole of the coalescing/backoff rule.
  - `record(definite:now:)` — writes the cache, clears in-flight, resets `attempts`.
  - `abandon(now:)` — marks the bound exceeded, increments `attempts`.
  - `cachedDefinite()` — for the timing-out waiter to re-read before answering (clause A8).
- Rules encoded: a definite answer is cached for process life and always wins; an
  unconfirmed answer is never cached; a caller inside the bound joins; a caller past the
  bound but inside the backoff gets `.unconfirmed` without starting a probe; a caller past
  the backoff starts a fresh probe.

### 2. `Sources/ProctorAgent/Session/ScreenRecordingProbe.swift` (new) — the bound

- `struct ScreenRecordingProbe: Sendable` with a `platform: @Sendable () async -> GrantState`
  closure and a keeper, plus `.live` using `SCShareableContent.excludingDesktopWindows`.
- `func state() async -> GrantState`: ask the keeper; on `.start` run the **unstructured**
  bound — `withCheckedContinuation` + `Task.detached` for the platform call + `Task.detached`
  for the sleep + a resume-once lock (M4/M5: a structured `withTaskGroup` race never
  returns). The platform task records its definite answer in the keeper whenever it lands,
  including late (clause A6). The timing-out path calls `abandon` then `cachedDefinite()`
  and returns that if present (clause A8).
- The stale comment ("either answers or throws") is replaced with what was measured.

### 3. `Sources/ProctorCore/Wire.swift` — the wire

- `DoctorReport.Grant` gains `public var state: String?`, optional so an older agent's
  report still decodes (the `agentBuild` precedent), carrying `GrantState.rawValue` (the
  `secondLane: String` precedent).
- `granted: Bool` documented as **confirmed granted** and derived from `state` at
  construction; a convenience initialiser takes `GrantState` and sets both so the two
  cannot disagree.
- A helper mapping a `nil` state back to `granted ? .granted : .denied` for old reports.

### 4. `Sources/ProctorAgent/Session/SessionDoctor.swift` — the report

- Take the probe from the session rather than the private static.
- Build the Screen Recording grant from `GrantState`.
- `howToFix` per state: unchanged Settings text for `denied`; for `unconfirmed`, text that
  names the 1.5s bound, says the probe did not answer, and points at re-running
  `proctor_doctor` or restarting the agent — **not** System Settings (clause A3).
- The blocker for an unconfirmed required grant names it as unconfirmed, not as a denial.
- `ready` stays `blockers.isEmpty`, so unconfirmed ⇒ `ready: false` (clause A2).

### 5. `Sources/ProctorAgent/Session/Session.swift` — injection

- `init` gains `screenRecording: ScreenRecordingProbe = .live`, stored. This is what
  restores the full suite (clause A10).

### 6. `Sources/ProctorCore/RunHUDMenuBar.swift` — the menu bar

- `MenuBarBlock` gains `case unconfirmedGrant`, symbol `questionmark.circle` — it must not
  wear the missing-permission triangle for a fault the machine has not been shown to have.
- `block(requiredGrantsGranted:secureEventInputActive:ready:)` gains
  `requiredGrantsUnconfirmed:`, ordered after `.missingGrant` and before `.secureInput`
  (both are "permissions unclear"; secure input is the momentary one). The total
  `if !ready { return .missingGrant }` fallback stays.

### 7. `Sources/ProctorCore/AgentRecovery.swift` — the offer's sentence

- `decide` takes the agent's Screen Recording `GrantState` in place of the bare Bool. The
  restart is still offered for both `denied` and `unconfirmed` when the window's own read
  says granted — a restart is right for a wedged process — but the `unconfirmed` sentence
  says the probe did not answer rather than claiming a stale earlier answer (clause A5).

### 8. `Sources/ProctorUI/` — the window

- `AgentModel`: add `requiredGrantsUnconfirmed`; feed it to `block(...)`; pass the grant
  state to `AgentRecovery.decide`.
- `MainWindow.GrantRow`: branch on state — an unconfirmed grant shows its own label, no
  **Open Settings** button, and keeps **How** with the corrected `howToFix` (clause A4).
- `Walkthrough` is deliberately untouched (spec assumption).

### 9. `Sources/ProctorCore/ToolOutputSchemas.swift`

- The `proctor_doctor` prose names the tri-state and the bound, so the bound is in the
  report rather than only in a comment.

### 10. Tests

- `Tests/ProctorCoreTests/GrantProbeTests.swift` (new) — the keeper against an injected
  clock: cache/never-cache, coalescing, backoff, no starvation, late answer.
- `Tests/ProctorAgentTests/ScreenRecordingProbeWiringTests.swift` (new) — the bound with the
  platform call driven as a closure: answers, throws, and **never answers** (the last must
  return within the bound, which is the regression test for this whole item).
- Update `MenuBarReadinessTests`, `RunHUDMenuBarTests`, `AgentRecoveryTests` for the new
  input and case.
- Inject an instant probe into `ObscuraPresenceWiringTests` and `BrowserLaneWiringTests`,
  then run `swift test` with **no `--skip`** and read the count back.

## Verification

`swift build` clean, then `swift test` unskipped with the count read back (baseline: 673 in
82 suites *with* the two skips). Each clause gets a test; the never-answers case is proven
red→green by running it against the unbounded code path first.
