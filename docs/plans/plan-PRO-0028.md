# Plan — PRO-0028: Re-check now says what it checks

**Spec:** `docs/specs/spec-PRO-0028.md` · **Tier:** Small · **Branch:** `ai/PRO-0028`

## Files

| File | Change |
|---|---|
| `Sources/ProctorCore/AgentRecovery.swift` | **New.** The pure decision and its sentences. |
| `Sources/ProctorUI/AgentModel.swift` | Publish `recovery`; recompute it wherever an input lands; `take(_:)` routes the two offers to the two existing actions. |
| `Sources/ProctorUI/ProctorUIApp.swift` | Delete the `Re-check now` row; add the conditional block below the stale-build block. |
| `Tests/ProctorCoreTests/AgentRecoveryTests.swift` | **New.** One test per acceptance clause a test can reach. |
| `CHANGELOG.md` | `Unreleased ▸ Changed` entry, written through create-luke-content. |

## The Core type

```swift
public enum AgentRecovery {
    public enum Kind: Equatable, Sendable { case startAgent, restartAgent }
    public struct Offer: Equatable, Sendable { let kind: Kind; let reason, action: String }

    public static func decide(applying: Bool,
                              reachable: Bool,
                              agentSeesScreenRecording: Bool,
                              windowSeesScreenRecording: Bool?,
                              runInFlight: Bool) -> Offer?
}
```

Rules, in this order — the order is the design:

1. `applying` → nil. A restart is in flight; the agent is legitimately unreachable during
   it, and a second click would stack a second `SIGKILL` on a process mid-launch.
2. `!reachable` → `.startAgent`, *"Proctor's agent is not answering. Nothing can run until
   it is back."*
3. `agentSeesScreenRecording` → nil.
4. `windowSeesScreenRecording != true` → nil. A restart cures a stale answer, never an
   absent permission; the status window owns the grant flow.
5. otherwise → `.restartAgent`, *"Screen Recording is granted, but the agent is still
   reading macOS's earlier answer."*, plus *" Restarting stops the run in flight."* when
   `runInFlight`.

## The UI wiring

`AgentModel` gains `private(set) var recovery: AgentRecovery.Offer?`, recomputed in
`apply(_:)` (the doctor report), in `applyHUD(_:)` (`hudRunning`, on the faster 0.5s
cadence) and at both ends of `reprobeAfterGrant` (`isApplying`). The window's own
preflight is read in `refreshDoctor()` beside the build stamps — a cheap local call at a
cadence that already exists, no new timer, the way PRO-0027 rode this tick.

In `MenuBarContent`, immediately after the `model.buildReplaced` block:

```swift
if let recovery = model.recovery {
    Divider()
    Text(recovery.reason)
    Button(recovery.action) { model.take(recovery) }
}
```

`take(_:)` routes `.startAgent` to `Actions.ensureAgent()` on a background queue then
`refresh()`, exactly as `AppDelegate` does at launch, and `.restartAgent` to the existing
private `reprobeAfterGrant()` — so the hand-driven route and the in-app grant route are
literally one path.

Delete `Button("Re-check now") { model.refresh() }`. `refresh()` itself stays: it is
called by `startPolling`, both prompts, and the status window.

## Tests (Core only — there is no `ProctorUI` test target)

| Clause | Test |
|---|---|
| A2 | healthy → nil; agent denying a grant the window sees → restart; no other grant is an input |
| A3 | window read denied or nil → nil, in both cases; the sentence claims staleness only where confirmed |
| A4 | `runInFlight` appends the cost sentence and changes nothing else |
| A5 | button titles are `Start Agent` / `Restart Agent`, no ellipsis; sentences stay ≤120 chars |
| A7 | `applying` suppresses every offer, whatever the other inputs say |
| A8 | unreachable → start, for every combination of the two grant reads; never restart |

A1 and A6 are read off the diff — A1 is an absence in a SwiftUI view, A6 is that
`reprobeAfterGrant` is byte-identical apart from two `recomputeRecovery()` calls and now
has a second caller.

## Gate

`swift build` (no new warnings; three pre-exist in `ProctorUI`) + `swift test`, reading
back the `with N tests` count on any filtered run, and breaking each new rule once to
confirm the tests are load-bearing.
