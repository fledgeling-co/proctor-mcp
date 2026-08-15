# Plan — PRO-0048: Drive iOS through deep links

**Spec:** `docs/specs/spec-PRO-0048.md`
**Branch:** `ai/pro-0048` · **Worktree:** `.worktrees/PRO-0048`
**Tier:** Standard — one new tool, one new pure module, one new session extension, three modified
surfaces, no protocol break.

## Shape of the change

Pure decision logic goes in `ProctorCore` where it is testable on a machine with no Xcode and no
simulator; everything that touches a subprocess or the session's state goes in a `Session` extension
alongside the other lanes. That split is what makes ten of the eleven acceptance clauses provable in
`swift test` without a booted device.

```
ProctorCore (pure, no I/O)          ProctorAgent (subprocess, actor state)
  IOSDevice.swift                     Session/SessionIOS.swift
  SimctlLocator.swift                 Session/Session.swift        (handle rejection, boot registry)
  ToolCatalogue.swift  (+ proctor_ios)Session/SessionDoctor.swift  (simctl row)
  Policy.swift         (+ iOS rule)   Session/ToolProbe.swift      (+ simctl probe)
                                      Dispatch.swift               (+ route)
```

## Files

### New — `Sources/ProctorCore/IOSDevice.swift`

Everything here is a pure function or a value type. No `Process`, no `FileManager`, no clock it is not
given.

- `IOSDevice` — udid, name, runtime, deviceTypeIdentifier, state, isAvailable, plus
  `bootedByThisSession` set by the caller. `handleID` is `"dev-" + udid.prefix(8)` lowercased.
- `IOSDeviceList.parse(_ json: Data) throws -> [IOSDevice]` — decodes `simctl list -j devices`. The
  runtime key (`com.apple.CoreSimulator.SimRuntime.iOS-18-2`) is turned into a readable runtime
  (`iOS 18.2`). Empty runtime buckets and `isAvailable: false` entries are kept and marked, not
  dropped: a device that exists but is unavailable is a different answer from one that does not exist.
- `IOSHandle.isDeviceHandle(_ id: String) -> Bool` — the `dev-` prefix test, and
  `IOSHandle.rejection(for:tool:)` producing the one refusal message, which names the ceiling and
  points at `proctor_ios` action `screenshot`.
- `SimctlFailure.decode(exitCode:stderr:) -> String` — the two measured classes into prose. Matches on
  the stable substrings, not on the whole message: `-10814` / `NSOSStatusErrorDomain` → "no installed
  app claims this URL scheme"; `SimError` + `405` or "Unable to lookup in current state" → "the device
  is not booted". Anything else returns the trimmed stderr with the exit code, never an empty string.
- `DeepLinkEvidence` — `delivered: Bool`, `exitCode: Int32`, `targetRunningBefore: Bool?`,
  `targetRunningAfter: Bool?`, `pidBefore/pidAfter: Int?`, `changedFraction: Double?`,
  `meanDifference: Double?`, `handlerResolved: String?`.
- `DeepLinkVerdict.decide(_ evidence:) -> (verdict: String, note: String)` — the whole table, pure:
  - not delivered → `refused` + the decoded reason
  - delivered, `targetRunningAfter == true`, screen changed → `targetChanged`
  - delivered, screen changed, target not running or not resolved → `screenChanged` + the note that
    the change could not be attributed
  - delivered, no screen change → `deliveredOnly` + "inconclusive: a deep link to the screen the app
    is already on is indistinguishable from one the app ignored"
  - `launchedNow` is computed separately (`pidBefore == nil && pidAfter != nil`) and never folded into
    the verdict.
  - Screen change is `changedFraction >= IOSPixel.changeThreshold` (default `0.0005`). Calibration in
    the spec: idle floor 0.00000, smallest real navigation 0.00204, app switch 0.79822. A nil fraction
    means the channel was off or failed and is reported as unavailable, never as "unchanged".
- `DeepLinkTarget.split(url:) -> (clear: String, redactable: String)` — `scheme://host` in the clear,
  path plus query plus fragment as the redactable remainder. A URL with no host keeps the scheme only.
- `IOSPolicy.decide(handler: String?, policy: AppPolicy, hasValidToken: Bool) -> PolicyDecision` — the
  asymmetric rule: block matches `handler` **or** `"ios:" + handler`; allow-list and sensitive match
  `"ios:" + handler` only; a nil handler is refused when an allow list is in force. Delegates to
  `AppPolicy.decide` for the shared shape so the refusal prose stays identical.
- `SchemeMap.build(apps:) -> [String: String]` and `SchemeMap.handler(for url:in:)` — pure over
  `[(bundleId: String, schemes: [String])]`. The caller does the plist reading; this does the mapping,
  lowercasing schemes, and returns nil for `http`/`https` because a universal link's handler is not
  determined by a scheme claim.

### New — `Sources/ProctorCore/SimctlLocator.swift`

Filesystem-only, following `ToolLocator`'s rule that detection never executes a binary. Resolves the
developer directory from, in order: a supplied `DEVELOPER_DIR`, the symlink target of
`/var/db/xcode_select_link` (root-owned; verified on this machine to point at
`/Applications/Xcode.app/Contents/Developer`), then `/Applications/Xcode.app/Contents/Developer`.
Returns a `ToolPresence(tool: "simctl", …)` with `searched` carrying every candidate
`<devdir>/usr/bin/simctl`. Both the symlink read and the executable test are injected predicates, so
AC8 is provable both ways with no Xcode involved.

### New — `Sources/ProctorAgent/Session/SessionIOS.swift`

The impure half. One bounded subprocess runner used by every action: absolute path from
`SimctlLocator`, argument array, stdout/stderr drained to EOF before `waitUntilExit` (the deadlock
`runSdef` already documents), a timeout that terminates the child, and a hard cap on captured output.

- `iosList()` — `simctl list -j devices`, parsed, each device carrying `capabilities` (what this lane
  can and cannot do) and `bootedByThisSession`. Read-only, ungated, audited only as activity.
- `iosBoot(device:timeoutMs:)` — device-scoped gate and audit, `simctl boot <udid>`, then polls
  `list -j` until `Booted` or the bound expires, reporting which. Records the udid in the
  session-scoped booted set. Never issues `shutdown`.
- `iosScreenshot(device:path:)` — `simctl io <udid> screenshot`, returning a result whose
  `trustworthy` is `false` and whose `caveat` names `simctl io` and the absent `SCFrameStatus`.
- `iosOpen(device:url:bundleId:pixelEvidence:timeoutMs:)` — the main path, in order:
  1. resolve the device, refuse if not `Booted` (no implicit boot),
  2. resolve the URL's handler via `listapps` + each bundle's `Info.plist` `CFBundleURLTypes`
     (cached per device, invalidated on a `listapps` change), reconcile against any caller-supplied
     `bundleId` and report a mismatch,
  3. gate on the resolved handler through `IOSPolicy`, writing a refusal record on refusal,
  4. sample the "before" evidence: target job presence and pid from
     `simctl spawn <udid> launchctl list`, and a before screenshot,
  5. `simctl openurl`,
  6. sample "after", compare frames with `PixelCompare.meanDifference` plus a changed-pixel fraction,
  7. `DeepLinkVerdict.decide`, audit, return evidence + verdict + both frame paths.

  The changed-pixel fraction is a small addition to `PixelCompare` (`changedFraction(_:_:region:threshold:)`)
  sharing the existing rasterisation, rather than a second image path.

### Modified

- **`Sources/ProctorCore/ToolCatalogue.swift`** — the `proctor_ios` spec. `readOnly: false`,
  `destructive: false`, `idempotent: false`. The description states, in the tool surface itself: this
  is a device lane not a window lane; `proctor_snapshot`/`find`/`assert`/`act` do not work against a
  device handle; what each verdict does and does not claim; that a device frame carries no frame
  status; and that `open` never boots. Added to `all`.
- **`Sources/ProctorAgent/Dispatch.swift`** — `case "proctor_ios"` with the four actions.
- **`Sources/ProctorAgent/Session/Session.swift`** — `windowHandle(_:)` checks
  `IOSHandle.isDeviceHandle` first and throws the named refusal instead of `windowNotFound`; the
  session-scoped `bootedDevices: Set<String>`.
- **`Sources/ProctorAgent/Session/SessionDoctor.swift`** — the simctl `ToolPresence` appended to
  `tools`. Not a grant, not a blocker, `ready` untouched: Proctor drives Mac apps without Xcode,
  exactly as it does without Obscura.
- **`Sources/ProctorAgent/Session/ToolProbe.swift`** — a third `ToolProbe` for simctl in `ToolProbes`,
  with the long/short TTL pair. Xcode does not appear mid-session often, so both sides are long.
- **`Sources/ProctorCore/Policy.swift`** — `IOSPolicy` lives in `IOSDevice.swift`; `Policy.swift` is
  untouched except for an `internal` hook if `decide`'s refusal prose needs sharing. Preference is no
  change at all to a file the audit chain depends on.
- **`CHANGELOG.md`** — one entry under `## [Unreleased]`, prose through `/create-luke-content`.

### Tests

`Tests/ProctorCoreTests/IOSLaneTests.swift` (new) plus a fixture
`Tests/ProctorCoreTests/Fixtures/simctl-devices.json` captured from this machine.

| AC | Test |
|---|---|
| AC1 | parse the fixture: 3 iOS 18.2 devices, one `Booted`; empty runtime buckets survive; runtime key renders as `iOS 18.2` |
| AC2 | `isDeviceHandle("dev-29fea02e")` true, `"w-1"` false; rejection text names the ceiling and `proctor_ios` action `screenshot` |
| AC3 | table-driven over every evidence combination, including the two measured `openurl` calls that differed only in pixels |
| AC4 | the real stderr strings captured in the spec decode to the two sentences; an unknown failure keeps its text |
| AC5 | `open` against a `Shutdown` device returns a refusal naming the state, and the command list contains no `boot` |
| AC6 | scheme map from a fixture resolves `maps://` to `com.apple.Maps`; `https://` resolves to nil; the six policy cases (bare-id allow does not authorise, `ios:` allow does, block on either spelling blocks, unresolved refused under an allow list, caller mismatch reported) |
| AC7 | `DeepLinkTarget.split` on `myapp://host/path?token=secret` puts `myapp://host` in the clear and the rest in a `Redaction`; the token does not appear in the record |
| AC8 | `SimctlLocator` with an injected predicate: found via `DEVELOPER_DIR`, found via the symlink, absent with every candidate in `searched` |
| AC9 | the booted registry marks only what this session booted; a source-level assertion that no `"shutdown"` argument is constructed anywhere in `SessionIOS.swift` |
| AC10 | the device capture result builder returns `trustworthy: false` with a caveat naming `simctl io` |
| AC11 | `ToolCatalogue.all.count == 20` (four existing assertions updated), `proctor_ios` dispatchable, description contains the ceiling sentence |

**The four existing count assertions** are at `ProctorCoreTests.swift:197`, `:1036`, `:2336` and
`ObscuraPresenceWiringTests.swift:223` — all move 19 → 20.

**Filter discipline:** `swift test --filter` matches the Swift function name, never the `@Test` display
string, and a filter that matches nothing reports green. Every filtered run has its `with N tests`
count read back before the result is believed.

## Order of work

1. `IOSDevice.swift` + fixture + AC1/AC3/AC4/AC6/AC7 tests — the whole decision layer, red then green,
   with no subprocess anywhere.
2. `SimctlLocator.swift` + AC8.
3. `ToolCatalogue` entry + the four count updates + AC11.
4. `SessionIOS.swift` + `Dispatch` route + AC5/AC9/AC10.
5. Handle rejection in `Session.windowHandle` + AC2.
6. Doctor row + `ToolProbe`.
7. Full `swift build` + `swift test`, counts before and after.
8. Live verification against the booted iPhone 16 Pro, reported not committed.
9. `CHANGELOG.md`, spec status → In Review, commit.

## Risks

- **`simctl spawn launchctl list` is the softest dependency.** It is used read-only and its failure
  degrades the `targetRunning` rung to unavailable rather than failing the call, so the lane keeps
  working with a weaker verdict.
- **Reading 30 `Info.plist` files per device** for the scheme map is the slowest step. Cached per
  device and invalidated on a `listapps` change; the cost falls on the first `open` only.
- **The pixel threshold is a default, not a law.** It is exposed per call and documented with the
  calibration behind it.
- **Swift 6 strict concurrency:** `Session` is a reentrant actor, so isolation drops at every `await`.
  The scheme-map cache and the booted set are actor state read and written without an intervening
  `await`, or re-read after one; no cross-`await` assumption is held.

## Amended during work

The out-of-family plan gate changed five things after this plan was written. They are described in
full in the spec's Progress section; in file terms:

- `SessionIOSProcess.swift` gained `settleDeviceScreen` (the after-sample was being taken before the
  app had painted) and `comparisonRegion` (the status-bar clock is excluded from the comparison).
- The subprocess runner drains to EOF and discards past the output cap rather than stopping, and
  reports `truncated`.
- `DeepLinkVerdict` gained `deliveredUnobserved` and `targetGone`.
- `DeepLinkEvidence` carries the `changeThreshold` it was judged against, so a caller who raised it
  can still re-judge the same numbers.
- `Session` gained `iosBusyDevices`, serialising iOS work per device so a reentrant actor cannot
  interleave a second call with a before/after pair.

`proctor_ios` also ships a fourth action, `screenshot`, which the spec's review section explains.
