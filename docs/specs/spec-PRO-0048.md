# PRO-0048: Drive iOS through deep links

**ID:** PRO-0048
**Status:** Merged `8d2fde6`
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0048.md`
**Brief:** `docs/features-to-triage/49-drive-ios-through-deep-links.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` (wave 7 architecture; this spec follows it)
**Lane reference:** `diolog-plugins/plugins/acceptance-e2e/skills/acceptance-e2e/SKILL.md` — the iOS lane
is Maestro on the Simulator, navigating deep-link-first with `xcrun simctl openurl`. This item ships
the deep-link half; PRO-0049 ships the Maestro half on the handle model defined here.

## Feature description

> Proctor drives macOS. A large share of the UI worth testing is an iOS app, and the cheapest
> reliable way into an iOS app's state is not clicking through it: it is opening the URL that puts
> it where you want it.
>
> Let a caller target an iOS Simulator, list what is available, and put an app into a named state by
> opening a deep link, with the result reported in Proctor's own shape.
>
> The hard parts, named: a simulator is not a window and Proctor's whole model is windows;
> `openurl` returning zero proves the URL was delivered, not that the app went anywhere; the
> simulator's accessibility tree is not reachable the way a Mac app's is; and booting and shutting
> down simulators is slow and stateful.
>
> `xcrun simctl` is part of Xcode, not macOS. A machine without Xcode has no lane here at all, which
> is a `proctor_doctor` row rather than a runtime surprise.

## What was measured before designing

Every decision below rests on a probe run on this machine on 2026-08-15 (Xcode 26 at
`/Applications/Xcode.app/Contents/Developer`, iPhone 16 Pro `29FEA02E…` booted, `Simulator.app` **not
running**). These are the numbers, not recollections:

| Probe | Result |
|---|---|
| `openurl` with a scheme no app claims | **exit 194**, `NSOSStatusErrorDomain code=-10814` (app not found) |
| `openurl` to a shut-down device | **exit 149**, `com.apple.CoreSimulator.SimError code=405`, "Unable to lookup in current state: Shutdown" |
| `openurl` with a claimed scheme | exit 0 |
| `openurl https://example.com/one` (Safari already running) | exit 0 · pid **unchanged** · screen **changed** |
| the **same** `openurl` again, immediately | exit 0 · pid **unchanged** · screen **byte-identical** |
| `openurl maps://?q=London` | exit 0 · **new pid 33877** for `UIKitApplication:com.apple.Maps` · screen changed |
| `simctl io <udid> screenshot` with Simulator.app closed | works, ~140 ms, 1206×2622 PNG |
| two screenshots 3 s apart, device idle | mean channel difference **exactly 0.000000** |

Calibration of the pixel channel, same instrument as `PixelCompare.meanDifference`, plus a
changed-pixel fraction at a per-channel threshold of 8/255:

| Case | changed-pixel fraction | mean difference |
|---|---|---|
| idle device, nothing done | 0.00000 | 0.000000 |
| deep link that changed nothing (repeat of the same URL) | 0.00000 | 0.000000 |
| modest navigation (Safari page change) | 0.00204 | 0.000838 |
| app switch (Safari → Maps) | 0.79822 | 0.207729 |

Two things follow and they shape the whole design. **The idle floor is exactly zero**, so "anything
changed at all" is a usable signal rather than a noisy one. And **the two `openurl` calls that
differed in outcome were identical in exit code and identical in process state** — the only channel
that separated them was pixels. That is the silent-success case this wave exists to catch, reproduced
in four commands.

## The four hard parts, answered

### 1. A simulator is not a window: a device handle is a new kind, and it is not a fiction

An iOS target is **a new handle kind on a new tool**, not a simulator dressed up as an app.

- New tool **`proctor_ios`** with actions `list`, `boot` and `open`. A device handle has its own id
  prefix — `dev-<first 8 of udid>` — and is returned only by this tool.
- **Every tool that takes `window` or `app` rejects a device handle by name.** A `dev-` handle passed
  to `proctor_snapshot`, `proctor_find`, `proctor_act`, `proctor_capture`, `proctor_assert` or any
  other window-taking tool fails with one specific error that says what it is and what is not
  available, rather than falling through to "unknown window". The brief's failure mode — a model that
  believes it can snapshot an iOS app because it holds a handle — is prevented at the point of
  misuse, not only in prose a model may not have read.
- The rejection is the load-bearing part of this decision. Folding simulators into `proctor_apps`
  would have made every window-taking tool accept the handle and fail somewhere deep, or worse,
  succeed against `Simulator.app`'s own chrome and report it as the app under test.

**A device handle still has a legal way to be looked at.** Rejecting the handle from every observation
tool while Proctor itself takes device screenshots for evidence would leave a campaign no way to see
what it just did. So `proctor_ios` carries a fourth action, **`screenshot`**, returning a
device-surface frame, and `open` returns the paths of the before/after frames it already captured.
The `proctor_capture` refusal names that route rather than only saying no.

**A device frame is not a ScreenCaptureKit frame, and says so.** `simctl io screenshot` carries no
`SCFrameStatus`, no dirty-rectangle coverage and no completeness signal — the same absence this wave's
direction file refuses to accept from Cua's screenshots. Every device frame is therefore returned with
`trustworthy: false` and a caveat naming the reason: it is a device-surface capture whose freshness
cannot be established the way a window capture's can. Proctor keeps its own capture path for Mac
windows precisely so frame status is known at the point of capture; it cannot know it here, and says
so rather than letting a device frame inherit a Mac frame's credibility.

**What `Simulator.app` is, and is not.** `Simulator.app` is an ordinary Mac app with an ordinary Mac
window, and a caller may attach to it through `proctor_apps` like anything else. What comes back is
Simulator's own chrome. Proctor does not claim, anywhere, that the elements in that tree are the iOS
app's elements. `proctor_ios list` therefore does **not** hand out a Mac window handle for a device:
offering one would be an invitation to treat the chrome as the app. A caller who wants Mac-side
pixels of a visible simulator attaches to `Simulator.app` deliberately and owns that choice.

### 2. Delivered is not navigated: a three-rung evidence ladder and a verdict that never overclaims

`open` returns an `evidence` object with three independently-reported rungs and one `verdict`. No rung
is inferred from another.

| Rung | What it is | What it proves | Available when |
|---|---|---|---|
| `delivered` | `simctl openurl` exit status, with the failure text decoded | the URL reached CoreSimulator and something claimed the scheme | always |
| `targetRunning` | `UIKitApplication:<bundleId>` present in `simctl spawn <udid> launchctl list`, with its pid, sampled before and after | the resolved target app is running now, and whether this call started it (`launchedNow`, a pid that did not exist before) | when the URL resolves to a handler, or the caller names `bundleId` |
| `screenChanged` | device-surface screenshots before and after, compared with `PixelCompare` | the device's screen is not what it was | when the pixel channel is enabled (default on) |

Verdicts, and each is a claim Proctor can defend:

- **`targetChanged`** — delivered, the resolved target app's job is present, **and** the screen
  changed. The strongest thing this lane can say, and the only verdict that attributes the change to
  the app the URL named.
- **`screenChanged`** — delivered and the screen changed, but the change cannot be attributed: no
  handler resolved, or the target's job is not present. A universal link Safari swallowed, a
  SpringBoard "Open in…?" sheet and a notification banner all land here. Deliberately a separate,
  weaker verdict rather than the top one.
- **`deliveredOnly`** — delivered, and nothing observable changed. **This is not a failure.** A deep
  link to the screen the app is already on produces exactly this, as measured above. It is reported
  as inconclusive with that reason stated, because reporting it as success would be the silent
  success, and reporting it as failure would make a correct no-op look like a defect.
- **`refused`** — non-zero exit, with the two failure classes decoded into prose: exit 194 / OSStatus
  −10814 becomes "no installed app claims this URL scheme", and SimError 405 becomes "the device is
  not booted".

`launchedNow` rides alongside as its own field rather than as a verdict, because "this call started
the app" and "the app is where the URL pointed" are different facts and most deep links land on an
app that is already warm.

**The word "navigated" is deliberately absent.** An earlier draft used it for delivered-plus-screen-
changed; out-of-family review pointed out that a device-global changed-pixel fraction cannot
distinguish the target app moving from a banner, a sheet, or another app entirely, so the label named
a claim the evidence could not carry. Splitting it into `targetChanged` and `screenChanged` is the fix.

**The ceiling, stated in the result and not only here:** the frontmost application on the device is
not observable through the channels this lane uses — `simctl openurl`, `simctl spawn launchctl list`,
`simctl io screenshot` and `simctl listapps`. Proctor therefore never claims "the app is in the
foreground showing screen X". `targetChanged` means the target's job is running and the device's
screen changed; it does not mean the app reached the screen the URL named. The result carries that
sentence. Whether a deeper FrontBoard signal exists on the host is recorded as child work rather than
asserted impossible.

`simctl` catches more than expected and the spec says so rather than overstating the danger: an
unclaimed scheme and an unbooted device are both non-zero exits. The silent-success class that
remains is narrower and real — **a claimed scheme whose path the app ignores**, which exits 0 and may
change nothing.

### 3. The accessibility ceiling, stated rather than implied

The Mac's `AXUIElement` API does not cross into a simulated device. This lane offers no accessibility
tree, no element handles, no geometry assertions and no actuation steps against an iOS target. What it
offers instead is named in the `capabilities` block on every device in `list` — process liveness,
device-surface pixels, and installed-app metadata — and the same block names what is absent and why.
PRO-0049 adds Maestro's own view hierarchy as a fourth channel; nothing in this item pretends to have
it early.

Concretely, the honest parity statement carried in the tool description: *this is a device lane, not a
window lane. `proctor_snapshot`, `proctor_find`, `proctor_assert` and `proctor_act` do not work
against a device handle and are refused if tried.*

### 4. Lifecycle: `open` never boots, `boot` is explicit, and Proctor never shuts anything down

- **`open` requires a booted device** and refuses otherwise with the device named and its state. It
  never boots implicitly. Folding a stateful 20-to-60-second side effect into a call whose result is
  "did this navigate" would make the timing meaningless and the audit record ambiguous.
- **`boot` exists, is explicit, is gated and audited, and is bounded by a timeout.** It polls
  `simctl list -j devices` until the device reports `Booted` or the bound expires, and reports which
  it was. The alternative — refuse to boot at all — was considered and rejected: a model holding a
  shell will run `xcrun simctl boot` itself, outside the gate and outside the trail, which is a worse
  outcome than Proctor doing it under both.
- **Proctor never shuts a device down, and never reboots one.** A running simulator holds state
  somebody may be mid-way through, and discarding it is unrecoverable. Devices this agent booted are
  marked **`bootedByThisSession`** in every subsequent `list` — named for what it is, because the
  marking lives in session memory and does not survive the agent restarting. A device booted by a
  previous session is indistinguishable from one a person booted, and the field's name says so rather
  than implying a durable record. Shutdown stays a person's decision, taken in Xcode or a shell.

## Gating, the audit trail, and supervision

The wave direction requires that every delegated call is still gated and recorded. This lane
actuates — a deep link changes an app's state — so it goes through the same two rails as everything
else, with two adjustments that the platform difference forces.

**The gate judges the app the URL actually reaches, never a name the caller supplied.** `SessionPolicy`
already carries this rule in its own words — passing "the bundle id a recording carries, or one a
caller supplied" would have the gate judge a name instead of the app under the pointer. A design that
gated `open` on a caller-declared `bundleId` would reopen exactly that hole: allow-list
`ios:com.myco.app`, declare that name, open `onepassword://`. So:

- **The URL is resolved to its handler on the device.** `simctl listapps <udid>` gives every installed
  app's bundle path; each bundle's `Info.plist` carries `CFBundleURLTypes` → `CFBundleURLSchemes`.
  Measured: `maps` resolves to `com.apple.Maps` this way. The scheme→handler map is built from the
  filesystem, cached per device, and invalidated when `listapps` changes.
- **The resolved handler is the gate key.** A caller-supplied `bundleId` is a **consistency check**,
  not the key: a mismatch between what the caller expected and what the device resolved is reported,
  and refused when an allow list is in force.
- **An unresolvable URL is refused whenever an allow list is in force.** `https://` universal links
  are the important case: their handler depends on associated domains, which is not readable from the
  bundle, so Proctor cannot say which app will receive them. It says so rather than guessing, and the
  fail-closed behaviour matches an unidentifiable Mac app today.

**The policy gate is platform-blind and must not silently widen.** `AppPolicy` keys on bundle
identifier, and an iOS app and a Mac app can share one. The rule, asymmetric on purpose:

- **Block** matches either the bare bundle id or the qualified key `ios:<bundleId>`. An operator who
  blocked `com.example.app` has blocked it on both platforms. Blocking more than intended is safe.
- **Allow-list mode and the sensitive set** match the qualified key `ios:<bundleId>` only. A Mac app
  on the allow list never silently authorises the iOS app of the same identifier. Allowing more than
  intended is not safe, so it does not happen by omission.

**Which actions are gated, and on what.** `list` and `screenshot` are read-only device
introspection and are **not** gated on an app policy — there is no app being driven, and gating them
on an allow list would make the lane undiscoverable. `boot` is device-scoped: it drives no
application, so it is gated on the device rather than a bundle id, and audited. `open` is the only
app-scoped action and carries the resolution rule above.

**The trail records the URL without recording its secrets.** A deep link routinely carries a token in
its query string. The audit record stores the **scheme and host in the clear** — enough to know which
app and which entry point — and the **path and query as a `Redaction`** (length plus SHA-256), which
is the treatment `type` text already gets. A trail that proved which screen was opened by storing an
auth token in plaintext would be the wrong trade.

**What the trail attests to, stated plainly** (the direction file asks for this and it differs from
the macOS lane): for an iOS action, Proctor records that **it issued the command and what the
evidence channels reported afterwards**. It does not attest that the app reached a particular screen,
because nothing available to it establishes that. The record carries the verdict, so a reader sees
`deliveredOnly` rather than an unqualified "ok".

**Supervision.** iOS actions appear in the run HUD activity feed like any other tool call, and Stop
applies: an in-flight `simctl` subprocess is terminated on stop and the partial result reported. The
lane does **not** take the machine's exclusive turn from `RunQueue`: measured above, `openurl` and
`screenshot` both work with `Simulator.app` closed, post no events into the Mac's input system, and
raise no window, so holding the machine's turn would block Mac runs for no contention that exists.

## Xcode detection, and the coupling to PRO-0050

`xcrun simctl` ships with Xcode, so a machine without it has no lane. That is reported, not
discovered at runtime.

Detection follows `ToolLocator`'s existing rule — **read the filesystem, never run the binary** — and
resolves the active developer directory from, in order: `DEVELOPER_DIR` in the environment, the
root-owned symlink `/var/db/xcode_select_link`, then `/Applications/Xcode.app/Contents/Developer`.
The row is a `ToolPresence` entry named `simctl` in the existing `tools` array on `DoctorReport`,
which the field's own documentation names as the growth surface for exactly this. No new top-level
boolean, and no new report shape.

`simctl` is then executed at that resolved absolute path when the lane runs — which is the same thing
`/usr/bin/sdef` and `/usr/bin/shortcuts` already do in this agent. The distinction that keeps
`ToolLocator`'s rule intact: detection never executes anything, and execution only ever targets a
path under a root-owned developer directory, never a user-writable `PATH` directory.

**Coupling recorded, not pre-empted.** PRO-0050 reshapes the doctor report into a toolchain view and
is not merged. This item adds one row in the shape the current report supports and does not invent a
toolchain section; PRO-0050 folds it in. Recorded under child work.

## Coordination with PRO-0044 (Cua)

PRO-0044 is in flight moving macOS actuation to Cua. This lane is a **peer** of it behind the same
Proctor surface, not a consumer: nothing here calls Cua, and nothing here depends on an unmerged Cua
seam. The two lanes share the gate, the trail, the HUD and the tool surface, and share nothing else.

## Acceptance criteria

Each clause names the test that proves it. Pure logic is tested against fixtures captured from real
`simctl` output on this machine; the live-device clauses are guarded so a machine without Xcode skips
rather than fails.

1. **AC1 — devices are listed with state and runtime.** `simctl list -j devices` output parses into
   device records carrying udid, name, runtime, device type, state and availability, with unavailable
   runtimes and empty runtime buckets handled. *Fixture test over the captured JSON.*
2. **AC2 — a device handle is not a window handle, and the refusal names the route that works.** A
   `dev-` handle passed to a window-taking tool is refused with an error naming the ceiling and
   pointing at `proctor_ios` action `screenshot`, not with "unknown window". *Test over the handle
   classifier and the refusal text.*
3. **AC3 — the verdict ladder never overclaims.** Given evidence (exit status, target job present
   before/after, pixel difference), the pure verdict function returns `targetChanged`,
   `screenChanged`, `deliveredOnly` or `refused` exactly as the table specifies; `screenChanged` is
   returned rather than `targetChanged` whenever the change cannot be attributed to the resolved
   target; `deliveredOnly` is reported as inconclusive with its reason rather than as success or
   failure. *Table-driven test over every combination, including the measured no-op case.*
4. **AC4 — the two failure exits decode into prose.** Exit 194 with OSStatus −10814 decodes to "no
   installed app claims this URL scheme"; SimError 405 decodes to "the device is not booted". *Test
   over the real stderr text captured above.*
5. **AC5 — `open` refuses an unbooted device and never boots implicitly.** *Test that the unbooted
   path returns a refusal naming the device state and issues no boot command.*
6. **AC6 — the gate judges the resolved handler, and does not widen on a shared bundle id.** A URL
   resolves to its handler through `CFBundleURLSchemes`; the gate keys on that handler and not on a
   caller-supplied name; a caller-supplied name that disagrees is reported and refused under an allow
   list; an unresolvable URL (a universal link) is refused under an allow list; an allow list
   containing `com.example.app` does not authorise the iOS target of the same id while
   `ios:com.example.app` does; a block on either spelling blocks the iOS target. *Tests over the
   scheme-map builder and the qualified-key policy decision.*
7. **AC7 — the URL is recorded without its secrets.** The audit record for an `open` carries the
   scheme and host in the clear and the path and query as a length-plus-hash redaction. *Test over the
   record builder with a URL carrying a query token.*
8. **AC8 — a machine without Xcode reports the absence rather than failing at runtime.**
   `proctor_doctor` carries a `simctl` row in `tools` with the searched paths; the lane's tools refuse
   with that absence named when it is missing. *Test over the locator with an injected filesystem
   predicate, both present and absent.*
9. **AC9 — Proctor never shuts a device down, and is honest about what it remembers.** No code path
   issues `shutdown`; devices booted by this session are marked `bootedByThisSession`. *Test over the
   booted-device registry plus a source-level assertion that no shutdown argument is constructed.*
10. **AC10 — a device frame declares that its freshness is unknown.** A device-surface screenshot is
    returned with `trustworthy: false` and a caveat naming `simctl io` and the absent frame status,
    never inheriting a window capture's credibility. *Test over the device capture result builder.*
11. **AC11 — the tool surface grows by exactly one and stays coherent.** `ToolCatalogue.all.count` is
    20, `proctor_ios` is dispatchable, and its description states the accessibility ceiling in the
    terms above. *Existing catalogue tests updated plus a description-content assertion.*

**Live verification, run once by hand and reported rather than committed as a gate:** the measured
sequence above re-run through the shipped tool against the booted iPhone 16 Pro — a deep link that
changes the screen, the same link again producing `deliveredOnly`, and a link that launches an app
cold producing `targetChanged` with `launchedNow`.

## Out-of-family review

The design was reviewed by `grok-4.6` (effort xhigh) before planning, with the four decisions inlined.
It changed four things, and the changes are in the spec above rather than in a note beside it:

- **The word `navigated` overclaimed.** A device-global changed-pixel fraction cannot tell the target
  app moving from a banner or a sheet. Split into `targetChanged` and `screenChanged`.
- **Rejecting the device handle from every observation tool left a campaign no way to look**, while
  Proctor was taking device screenshots for its own evidence. Added the `screenshot` action, the
  before/after frame paths on `open`, and a refusal that names the route.
- **Gating on a caller-supplied bundle id reopened the hole `SessionPolicy` exists to close.** The
  gate now resolves the URL to its handler and judges that; the claim was checked against the machine
  before it was accepted — `CFBundleURLTypes` is readable from each app's bundle, and `maps` resolves
  to `com.apple.Maps`.
- **`bootedByProctor` was folklore unless it survives the agent.** Renamed `bootedByThisSession`,
  which is what it is.

It also observed that "frontmost is unobservable via simctl" is a choice rather than a fact, since
FrontBoard state lives on the host under CoreSimulator. A probe for such a signal found none in the
channels this lane uses, so the ceiling stands as written and the deeper question is recorded as child
work rather than settled by assertion. Its remaining point — that no gated `shutdown` is a CI leak
rather than a wrong default — was already recorded as child work and stays there.

## Assumptions

- `simctl spawn <udid> launchctl list` is a supported way to read app liveness. It is used read-only
  and its absence degrades the `launched` rung to unavailable rather than failing the call.
- The pixel threshold separating "changed" from "unchanged" is set from the calibration above with a
  wide margin — the idle floor measured exactly zero and the smallest real navigation measured 0.002
  changed-pixel fraction. The default is documented and overridable per call.
- Screenshot comparison is whole-screen. A region-scoped comparison is a natural extension and is not
  built here.

## Child work found

- **PRO-0050 coupling.** The `simctl` row lands in the existing `tools` array. When PRO-0050 reshapes
  the report into a toolchain view, this row plus the Xcode developer-directory resolution should move
  into that structure, and the developer-directory path itself is worth surfacing there.
- **Maestro presence detection** belongs with PRO-0049, which owns that binary. This item detects only
  `simctl`.
- **Region-scoped screen-change evidence** — comparing a named rectangle of the device screen rather
  than the whole of it, which would make the pixel rung far sharper for an app whose chrome animates.
- **A frontmost-app signal on the device.** Out-of-family review noted that FrontBoard state lives on
  the host under CoreSimulator. No such signal was found in the channels this lane uses, so the
  ceiling stands, but a route to it would upgrade `targetChanged` from "the job is running and the
  screen moved" to a genuine attribution and is worth a spike.
- **Universal-link handler resolution.** `https://` deep links resolve through associated domains,
  which is not readable from an app bundle, so they are gated as unresolvable today. Reading the
  device's association state would close that gap.
- **A device-side settle** — repeating the screenshot until N consecutive frames are quiet, mirroring
  the Mac settle on the pixel channel. Affordable at the measured ~140 ms per capture, and the natural
  home for it is alongside PRO-0049's flow work.
- **`shutdown` as an explicit, confirmed action**, if the reader later wants Proctor to be able to
  clean up what it booted. Deliberately excluded here.

## Progress

**Delivered on `ai/pro-0048`, worktree `.worktrees/PRO-0048`.** `swift build` and `swift test` green:
**943 tests before, 971 after** (22 in `IOSLaneTests`, 6 in `IOSLaneWiringTests`), one pre-existing
test updated because it pins the contents of the doctor report's `tools` array and the new `simctl`
row belongs in it.

New: `Sources/ProctorCore/IOSDevice.swift` (the whole decision layer, pure),
`Sources/ProctorCore/SimctlLocator.swift`, `Sources/ProctorAgent/Session/SessionIOS.swift` (gate,
audit, evidence), `Sources/ProctorAgent/Session/SessionIOSProcess.swift` (subprocesses and pixels).
Modified: the tool catalogue, `Dispatch`, `Session.windowHandle`, `SessionDoctor`, `ToolProbe`, and
`PixelCompare` (which gained `changedFraction`, the instrument the verdict turns on).

### What the plan review changed, and it changed the design twice

The out-of-family plan gate ran on `grok-4.6`. Its first attempt died at the deadline mid-reasoning
because it chose to read the repository; the retry, with file reading forbidden and the design
inlined, produced the two findings that mattered most in this whole item, both of them real defects
in code that was already written:

- **The after-sample was taken too early to see anything.** `simctl openurl` returns when SpringBoard
  has accepted the URL, well before the app has been woken, laid out or painted, so a real navigation
  would have been reported as `deliveredOnly` on almost every call. Every manual measurement behind
  this spec had slept two seconds before looking, and the code had not. Fixed with a bounded
  device-side settle that waits for consecutive quiet frames rather than a guessed interval, which is
  the same principle the macOS lane settles on and was originally filed as child work. The live run
  settled in 3062 ms over 5 samples for a real app switch.
- **The output cap could wedge the child.** The drain stopped reading at the cap, which leaves the
  subprocess blocked on a write nobody is reading until the watchdog kills it, turning a large
  `listapps` into a timeout. It now drains to EOF and discards past the cap, and reports `truncated`.

Three further changes came from the same review: the status-bar band is excluded from the pixel
comparison (the clock is the one moving thing nobody caused, and a digit change is the same order of
magnitude as the smallest real navigation); `deliveredUnobserved` and `targetGone` were added, because
"nobody looked" is not "nothing happened" and an app that dies while handling a deep link must never
be filed under a screen that changed; and a per-device guard serialises iOS work, since this actor is
reentrant and a second call would otherwise interleave with a before/after pair.

### Live verification, against the booted iPhone 16 Pro

Run through the shipped code path, reported rather than committed as a gate:

| Call | Result |
|---|---|
| `list` | 1 booted, `iPhone 16 Pro`, `iOS 18.2`, `bootedByThisSession: false` |
| `open maps://?q=Edinburgh` from Safari | **`targetChanged`**, handler `com.apple.Maps` resolved from the filesystem, changed fraction 0.618, settle 3062 ms / 5 samples |
| the same URL again | **`deliveredOnly`**, changed fraction 0.0, identical exit code |
| `open proctor-nope-xyz://go` | **`refused`**, exit 194, "no installed app claims this URL scheme" |
| `open prefs://` | **`refused`**, handler `com.apple.Preferences` resolved, simctl declined it |
| `screenshot` | `trustworthy: false` with the frame-status caveat |
| `open` against a `Shutdown` device | refused naming the state, and nothing was booted |

The second row and the third are the point of the feature: same command, same exit status, same
process state, and only the pixel channel separates a navigation from a no-op.

One behaviour worth naming because it surprised the first live run: **a non-zero `simctl` exit is a
`refused` verdict in the result, not a thrown error.** That is deliberate and consistent with the rest
of the lane, which reports evidence rather than failing, but it means a caller checking for an
exception will see success. The verdict is the thing to branch on.

### The completeness gate, and the contradiction it found

The work was reviewed out of family by `grok-4.6` against its own four requirements and came back
**complete**, with one criticism worth the whole gate: every device frame is reported
`trustworthy: false` because `simctl` gives no `SCFrameStatus`, and the screen-change channel built
from those same frames is then allowed to mint `targetChanged`. A channel declared untrustworthy was
doing attributive work with nothing said about it.

That is real. A frame whose freshness cannot be confirmed can in principle be stale, and a stale frame
on either side of the comparison moves the answer in either direction. The settle reduces it, since a
frame would have to be stale consistently across several samples to survive, but it does not remove
it. Rather than quietly drop the channel (it is the only thing that separates a navigation from a
no-op) or quietly keep it, the limit is now stated where the claim is made: `IOSPixel.channelCaveat`
rides on every `open` result whose verdict rests on pixels, and says that the channel is the best
evidence available for a simulated device rather than the evidence a window capture carries.

Its second point is also taken: the source scan that forbids a `shutdown` argument catches a literal
and not a computed string, so it is a tripwire on the obvious regression rather than a proof of the
property. The test now says so rather than implying more.
