# `proctor_doctor` can hang forever waiting on the Screen Recording probe

## The measurement

`Session.doctor(verbose:)` has exactly one `await` in it:

```swift
let screenRecordingGranted = await Self.probeScreenRecording()
...
/// Screen Recording has no query API. Asking ScreenCaptureKit for shareable
/// content either answers or throws, and the throw is the denial.
private static func probeScreenRecording() async -> Bool {
    do {
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return true
    } catch {
        return false
    }
}
```

The comment states the model the code is built on: **either answers or throws**. Measured
on this machine, 2026-08-15, it can do neither.

`swift test --filter ObscuraPresenceWiringTests` hangs deterministically, killed at its
deadline every time. Sampling the process shows **no Proctor frame on any thread** — the
work is parked in a suspended Swift continuation with no stack to sample, which is what an
`await` that never resumes looks like. The six tests that hang are exactly the six that call
`session.doctor(...)`, and `doctor` awaits nothing else.

Two controls, both of which matter for the diagnosis:

- The same call from a **plain `swift` script** answered `granted` in **0.04s**. So the API
  is not broken on this machine and the grant is real; something about the test host
  (`swiftpm-testing-helper` loading an `.xctest` bundle) makes the completion never arrive.
- The **full suite was green three times earlier the same day** (692 tests, 3.1s / 3.3s /
  4.4s) and hangs now, with no change to the tree between. So this is a **latent** defect
  that an environmental change exposes, not a regression somebody wrote.

`swift test --skip ObscuraPresenceWiringTests --skip BrowserLaneWiringTests` passes 673
tests in 82 suites in 3.8s, which is how the wave 6 merges were gated while this is open,
disclosed at each merge.

## Why this is a product defect and not only a test defect

`proctor_doctor` is the **first call the Proctor skill tells a model to make**, before it has
established anything. An unbounded await there means a host can hang on the opening move of a
campaign with nothing to read and no way to tell a hang from a slow machine. The agent is a
properly signed bundle and answers, so this is unlikely rather than impossible in production;
"unlikely" is not the property a health check should have.

## The decision this turns on

**What `doctor` should report when the platform will not answer.** The current code has two
states and needs three, and the third is not obviously `false`:

- Reporting **denied** is what the existing `catch` does, and it is a lie of the useful kind:
  it is the safe answer, and it sends a person to System Settings to grant a permission they
  may already have granted.
- Reporting **unknown** is honest and costs every consumer a third case to handle, including
  `ready` and `blockers`, which are booleans today.

Whichever is chosen, the probe needs a bound. Say what the bound is, and say it in the
report rather than only in a comment, because the comment currently asserts something the
measurement contradicts.

## Interactions to respect

- **PRO-0028 established that macOS caches this answer per process for the process's life**,
  which is why the "Re-check now" row was deleted and `AgentRecovery` replaced it. A timeout
  that caches a timed-out answer for the life of the agent would be worse than the hang: the
  agent would report denied forever after one slow probe. Say what is cached and for how long.
- `AgentModel.swift` in `Sources/ProctorUI` carries the same reasoning for the window's own
  probe and will want the same answer.

## Not in scope

Making ScreenCaptureKit answer. This is about what Proctor does when it does not.
