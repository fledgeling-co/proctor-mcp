# PRO-0040: `open -a Proctor` cannot launch Proctor while the agent is running

**ID:** PRO-0040
**Status:** Merged `091d6c3`
**Plan:** `docs/plans/plan-PRO-0040.md`
**Branch:** `ai/pro-0040` in `.worktrees/PRO-0040` (stopped before merge)
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/41-open-cannot-launch-proctor.md`
**Builds on:** PRO-0028 (`AgentRecovery`, the relaunch path), PRO-0033 and PRO-0037
(the yield-when-a-person-takes-the-machine behaviour), PRO-0041 (`AgentRecovery`'s
shared-TCC-record gate)

## Feature description

Opening Proctor should open Proctor, whether or not the agent is running.

Today it does not. The agent is a separate Mach-O living in
`Contents/MacOS/proctor-agent`, started independently by launchd, so it inherits
the bundle's `Info.plist` identity. LaunchServices records it as a live instance
of `app.fledgeling.procter`, `open -a Proctor` activates that instance instead of
launching anything, the agent has no UI, and `open` exits 0. Because the agent is
running almost always, Proctor is almost never openable.

Measured on this machine, 2026-08-15, on the installed build, with both processes up:

```
$ lsappinfo find bundleid=app.fledgeling.procter
ASN:0x0-0x4e4ac45e-"Proctor": ASN:0x0-0x4f483434-"Proctor":

$ lsappinfo info -only pid,bundlepath,LSDisplayName ASN:0x0-0x4f483434
"pid"=48218
"LSBundlePath"="/Applications/Proctor.app"
"LSDisplayName"="Proctor"
$ ps -p 48218 -o comm=
/Applications/Proctor.app/Contents/MacOS/proctor-agent
```

Two application records, one bundle path, one display name, and the second one is
the agent. That is the whole defect.

`killall Dock`, `lsregister -f` and repeated `open` calls do not clear it, so it is
not transient LaunchServices confusion that waiting fixes.

### Where it bites

- `scripts/install.sh` ends with `open`, so its final "opening Proctor" step is a
  silent no-op on every reinstall where the agent is already up. The installer
  reports success and the person sees no window and no menu-bar icon.
- PRO-0028's `AgentRecovery` and the app's own relaunch path both reopen the app
  through LaunchServices, so both inherit it.
- A person double-clicking Proctor in `/Applications` gets nothing, with no error
  to read. That is the worst version of it.

### What is not the bug

The UI app is correct in every other respect. Once `walkthroughCompleted` is set it
applies `.accessory`, orders the main window out and lives in the menu bar, so "no
window appears" after a successful launch is expected. `applicationShouldHandleReopen`
already calls `makeKeyAndOrderFront` and activates, so a reopen of a running UI app
correctly brings the window back. **No UI work is in scope.** Once the agent stops
holding the application record, both paths are already right.

## What causes the registration, precisely

`Sources/ProctorAgent/main.swift` opens with
`NSApplication.shared.setActivationPolicy(.accessory)`, and it has to — the comment
there records why. Touching `NSApplication` is what registers the process with
LaunchServices, and it registers it under `Bundle.main`'s identity. For a plain
Mach-O in `Contents/MacOS/`, `Bundle.main` is the enclosing `.app`.

So the fix has to change what identity the agent presents to LaunchServices, without
changing the identity it presents to TCC. Those are two different identities read
from two different places, which is what makes a cheap fix possible.

## The decision: an embedded `__TEXT,__info_plist` in the agent binary

**Decided: the agent binary carries its own Info.plist in a `__TEXT,__info_plist`
section, declaring `CFBundleIdentifier app.fledgeling.procter.agent`,
`CFBundleName "Proctor Agent"` and `LSUIElement true`. Nothing about the installed
bundle layout changes.**

The three options in the brief were measured against each other on this machine
before choosing, with a purpose-built probe (a binary that calls
`setActivationPolicy(.accessory)` and reports what `Bundle.main` resolved to,
placed in variant bundles and observed through `lsappinfo`).

| | LS record under the app id | `Bundle.main.bundlePath` | `Bundle.main.resourceURL` | installed layout |
|---|---|---|---|---|
| today: `Contents/MacOS/`, no embedded plist | **yes** | the `.app` | `Contents/Resources` | — |
| move to `Contents/Helpers/` | none at all | **the `Helpers` dir** | **the `Helpers` dir** | **changes** |
| embedded `__info_plist` (chosen) | **none** | the `.app` | `Contents/Resources` | unchanged |

Both candidate fixes clear the record. They differ in what else they break.

### Why not `Contents/Helpers/`

Moving the binary works, and costs more in three places.

`Bundle.main` stops resolving to the app. Measured: `bundlePath` and `resourceURL`
both become the `Helpers` directory and `bundleIdentifier` becomes nil. The run
HUD's character art is loaded through `Bundle.module` in
`Sources/ProctorAgent/Overlay/RunHUDCharacterView.swift` and
`Sources/ProctorCore/RunHUDMenuBar.swift`, and `Bundle.module` resolves through
`Bundle.main.resourceURL`. Moving the binary therefore means also relocating the
SwiftPM resource bundles that `scripts/build-app.sh` copies into
`Contents/Resources`, and duplicating ProctorCore's, because the UI app still needs
it there. That is a real chance of shipping a build whose HUD draws nothing.

It changes the installed layout, so `scripts/install.sh`, `scripts/doctor.sh:76`,
`Sources/ProctorShim/Install.swift:51` and `Sources/ProctorUI/AgentModel.swift:128`
all carry a path that has to move in step, plus `docs/architecture.md`. Every one of
those is a place a stale path ships a broken install.

And it buys nothing the chosen option does not already buy.

### Why not its own bundle identifier at the signature

This is the expensive option and it is the one to avoid, because it is the one that
costs a person their grants.

TCC matches a process against the recorded designated requirement. Measured on the
installed build:

```
$ codesign -d -r- /Applications/Proctor.app/Contents/MacOS/proctor-agent
designated => identifier "app.fledgeling.procter" and anchor apple generic
  and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[...]
  and certificate leaf[subject.OU] = H4HGFL52W7
```

The app's binary reports an identical requirement. There is **no path component**,
which is the fact the whole design rests on: TCC does not care where in the bundle
the binary sits. It cares about the signing identifier and the team.

`scripts/build-app.sh` already signs every nested binary with `-i "$BUNDLE_ID"`,
deliberately, and its comment says why. Changing the agent's *signing* identifier
would change that requirement, and both Accessibility and Screen Recording would
stop matching. Screen Recording cannot be granted silently on any macOS version, so
that is a person having to find a System Settings pane and click. It would also
break PRO-0041's `AgentRecovery` gate, which offers the Screen Recording restart
only when the window's own `CGPreflightScreenCaptureAccess()` agrees with the
agent — an inference that is only sound because the two binaries share a TCC record.

The chosen option leaves `-i "$BUNDLE_ID"` exactly as it is. The embedded plist is
read by LaunchServices and by `Bundle.main`; it is not what `codesign -i` writes.
**Accessibility and Screen Recording survive the upgrade with no re-prompt.**

### Why the plist carries `LSUIElement` and not `LSBackgroundOnly`

`LSBackgroundOnly` is the plist form of `.prohibited`, and `main.swift` already
records why the agent is `.accessory` and not `.prohibited`: prohibited is
documented as not permitting windows, and the cursor overlay is a window. Shipping
a plist that says background-only while the first line of Swift sets `.accessory`
is a contradiction, and LaunchServices reads the plist before that line runs.

`LSUIElement` is the accessory policy, which is what the code already asks for at
runtime. Declaring it in the plist is a small improvement on today: the Dock-tile
hazard `main.swift`'s comment describes is closed before the process starts, rather
than in its first statement.

### Why it registers nothing rather than registering as itself

Measured: an embedded plist with `LSUIElement` and no `CFBundleIdentifier` produces
no application record at all, while one carrying its own identifier produces a
record under that identifier. Both satisfy `open -a Proctor`.

The identifier is kept anyway. A process holding Accessibility and Screen Recording
should be nameable — in Activity Monitor, in `lsappinfo`, in a crash report — and
`app.fledgeling.procter.agent` says what it is and whose it is. The record it
creates is harmless because `LSUIElement` states the truth about it: there is
nothing there to activate. The cost of the alternative is a nil identity in every
diagnostic surface, which is worse for the person trying to understand what is
running on their Mac.

### Version keys are deliberately absent

The agent's plist carries three keys and no version. `scripts/check-release-version.sh`
reads the version from `Apps/Proctor/Info.plist`, and a second copy is a second
thing to drift. The agent already reports its build through `BuildInfo`, which reads
`_NSGetExecutablePath` and a build-plugin-generated constant rather than any plist.

## The consequence that must be fixed with it

`ContentionMonitor.ourOwnPids()` reads `Bundle.main.bundleIdentifier` to find
Proctor's own processes, so that somebody opening Proctor's own menu to release a
held run is not read as taking the machine back:

```swift
if let id = Bundle.main.bundleIdentifier {
    for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == id {
```

After this change that inferred identifier is the agent's, which no running
application matches, so the menu-bar app stops being recognised as Proctor's own.
The run would hold itself again on the way to being released. That is a direct
weakening of PRO-0033/PRO-0037's supervision behaviour and it ships in the same
change or not at all.

The fix names Proctor's identity rather than inferring it, which is what the rest of
the agent already does — `Wire.bundleIdentifier` is the constant behind the policy
store, the audit trail, the flow store and both keychain service names.

## Acceptance criteria

**AC1 — The agent holds no LaunchServices application record under the app's
identity.** With the agent running, `lsappinfo find bundleid=app.fledgeling.procter`
names only the UI app, or nothing when the UI app is not running.

**AC2 — Opening Proctor opens Proctor while the agent is running.** `open -a Proctor`
with the agent up launches the UI app; with the UI app also up it reopens its window.
Double-clicking in `/Applications` does the same.

**AC3 — The grants survive the upgrade with no re-prompt.** The installed agent's
designated requirement is unchanged, and after reinstalling over an existing grant
the agent reports Accessibility and Screen Recording still granted, with no consent
dialog shown.

**AC4 — Proctor still recognises its own processes.** The contention sample counts
the menu-bar app among Proctor's own pids, so releasing a held run from Proctor's own
menu is not read as a person taking the machine.

**AC5 — A release cannot regress this silently.** `scripts/build-app.sh` fails the
build if the agent binary ships without its identity section, **or if the agent's
signing identifier is anything other than the app's**, so the local install path and
`.github/workflows/release.yml` — which calls the same script — are held to it by the
same gate.

**AC6 — The workaround does not become the fix.** No path stops, kills or restarts
the agent in order to open the app. `scripts/install.sh` keeps its `open` and gains
no agent-stop.

## Scope

**In:** `Apps/Proctor/AgentInfo.plist` (new), the `ProctorAgent` target's linker
settings in `Package.swift`, the identity constants and the `ContentionMonitor` fix,
the `build-app.sh` gate, tests for AC4 and AC5, a `CHANGELOG.md` `[Unreleased]` entry,
and a note in `docs/architecture.md` recording that the agent has its own
LaunchServices identity and why.

**Out:** any change to the installed bundle layout; any change to signing, `-i`,
notarisation or the release workflow's steps; any UI change; anything in the Wave 7
Cua/iOS direction, which this does not touch.

## Risks

- **`unsafeFlags` and package consumption.** SwiftPM refuses `unsafeFlags` in a
  version-pinned dependency, and `ProctorReflector`'s README documents exactly that
  consumption shape. Measured: the restriction is product-scoped, and a throwaway
  package depending on this one by URL at `from: "1.0.0"` and importing
  `ProctorReflector` builds clean with the flags present on the `ProctorAgent`
  executable target. Held by a test is not possible; held by the fact that
  `ProctorReflector`'s target graph excludes `ProctorAgent`.
- **The linker flag's path.** The `-sectcreate` argument is a path resolved by the
  linker's working directory. Verified at build time rather than assumed; if a
  package-root-relative path does not resolve, the build fails loudly rather than
  silently omitting the section, and AC5's gate catches it either way.
- **Notarisation.** The embedded plist becomes sealed by the signature
  (`Info.plist=bound` where it was `not bound`). `codesign --verify --strict --deep`
  accepts it, measured on a probe bundle. Not submitted to Apple as part of this
  change, per the instruction not to notarise; the release workflow is unchanged and
  an embedded Info.plist in a helper tool is a standard, Apple-documented shape.

## Child work found

None.

## Out-of-family review

Ran on **grok** (`grok-4.6`), per this repo's fleet convention that the out-of-family
gates run on grok rather than Codex.

**First attempt was a lane failure, not a pass.** A ~45-line prompt returned only the
model's reasoning trace and no answer, exiting 0. It is recorded here rather than
counted as clean. The retry, at roughly half the length and with the question reduced
to the codesign/TCC mechanics, answered.

Confirmed:

- **TCC keys on the signing identifier and the stored `csreq`, not on
  `CFBundleIdentifier`.** Same `-i`, same designated requirement, so the existing
  Accessibility and Screen Recording rows still match and nobody is re-prompted. This
  is the claim the whole design rests on and it is now supported by both a direct
  measurement of the DR and an out-of-family read of the mechanism.
- **No Gatekeeper, notarisation or hardened-runtime objection** to a helper whose
  embedded `CFBundleIdentifier` disagrees with both its signing identifier and its
  enclosing bundle. That split is ordinary for helper tools.

Findings dispositioned:

- **Accepted, and it changed AC5.** A later `codesign` run that omits `-i` would take
  the embedded `CFBundleIdentifier` as the signing identifier, rewrite the designated
  requirement, and *only then* lose the TCC rows — silently, one release later. The
  build gate therefore asserts the agent's signing identifier as well as the presence
  of the section, so the trap fails the build rather than a person's grants.
- **Checked and does not apply.** `UserDefaults.standard` keys its suite on the main
  bundle identifier, so a helper that shares defaults with its app would diverge.
  Verified by grep: the agent uses no `UserDefaults` at all, and the only defaults key
  in the project (`walkthroughCompleted`) is read by the UI app, whose `Bundle.main` is
  unchanged. The agent's persistent state is the policy store, the audit trail, the
  flow store and two keychain services, and every one of those is keyed on the
  `Wire.bundleIdentifier` constant rather than on anything inferred.
- **Rejected, with reason.** Adding `CFBundleShortVersionString` to the agent plist so
  the tool is not "unversioned" in LaunchServices. The only surface that would show it
  is a diagnostic listing; `BuildInfo` already answers which build the agent is, which
  is what PRO-0030 exists for; and a second version string is a second thing that can
  disagree with the tag `scripts/check-release-version.sh` gates on.
- **Noted.** In a universal binary the section must be present in every slice. This
  build is thin arm64 today (measured), `-sectcreate` runs per slice at link time, and
  the AC5 gate reads the binary as actually built, so a future universal build is
  covered by the same check rather than by an assumption.
- **Already satisfied.** Adding the section invalidates the signature, so the helper
  must be signed before the bundle. `scripts/build-app.sh` already signs every nested
  binary first and the bundle last, deliberately, and the section is created at link
  time — before any signing.

One claim in the failed attempt's trace, that TCC held rows for both `procter` and
`proctor` spellings, could not be reproduced: the repository contains exactly one
spelling, `app.fledgeling.procter`, in all 33 occurrences. Treated as trace noise. It
would not affect this change either way, since the identifier is unchanged.

## Wave 7 direction

This change does not touch actuation, observation, the verdict layer or the
supervision surface, so `docs/features-to-triage/00-WAVE-7-DIRECTION.md` has nothing
to reverse here. The one adjacency is the direction's insistence that supervision must
not weaken: the `ContentionMonitor` fix above is that clause being honoured rather
than inherited.

## Progress

Delivered on `ai/pro-0040` in two commits: `3816b65` (the fix, the gate, the tests)
and `fef730b` (architecture note, CHANGELOG). Stopped before merge.

`swift test`: **937 tests in 105 suites** before, **943 in 106** after.

### Acceptance clauses and what closes each

| | Clause | Evidence |
|---|---|---|
| AC1 | The agent holds no LS record under the app's identity | Measured on the installed build. Before: two records under `app.fledgeling.procter`, one of them pid 48218 = `proctor-agent`. After: one record, pid 55524 = `Proctor`; the agent holds a separate record under `app.fledgeling.procter.agent`. |
| AC2 | Opening Proctor opens Proctor while the agent runs | Agent up, UI not running, no record under the app id: `open -a Proctor` launched the UI at t+1s and left the agent untouched. Run again with the UI up, the pid set was unchanged, so it reopened rather than spawning a second copy. |
| AC3 | The grants survive with no re-prompt | `codesign -d -r-` on the installed agent is **byte-identical** before and after (`diff` clean). The reinstalled agent reports Accessibility `granted` and Screen Recording `granted`, no consent dialog shown. `codesign -dv` reports `Identifier=app.fledgeling.procter` and `Info.plist entries=3`. |
| AC4 | Proctor still recognises its own processes | `WireIdentityTests`, 6 tests. The load-bearing one asserts the identity is named rather than inferred, in a process whose own `Bundle.main.bundleIdentifier` is not Proctor's — which is exactly the condition that broke the old code. |
| AC5 | A release cannot regress this silently | Both halves of the `build-app.sh` gate exercised. Agent plist sharing the app's identifier: build fails. A `codesign` run with `-i` dropped: build **exits 1**, reporting `Identifier=app.fledgeling.procter.agent`. Clean build exits 0. |
| AC6 | The workaround does not become the fix | Nothing in the diff stops, kills or restarts the agent (`git diff main` grep for `stopAgent|bootout|kickstart|killall|pkill|SIGKILL` on added lines: none). `scripts/install.sh` is untouched and still ends in `open -F "$APP_DEST"`. |

### The trap the review found is real, and now demonstrated

The out-of-family review predicted that a later `codesign` run omitting `-i` would
take the embedded `CFBundleIdentifier` as the signing identifier and lose the TCC
grants a release later, with nothing failing in between. That was tested rather than
taken on trust: with `-i` removed from the signing loop, `codesign -dv` reports
`Identifier=app.fledgeling.procter.agent`, which is a different designated
requirement and therefore a re-prompt for both grants. The gate catches it and exits
1. This is the single most valuable line of the change and it would not exist without
that review.

### Changed from the plan during work

The linker flags are applied **release-only** (`.when(configuration: .release)`).
Applied unconditionally they propagate to whatever links the target, and the test
bundle links this one: measured, `proctor-mcpPackageTests.xctest` came out carrying
the agent's identity and `LSUIElement`. `scripts/build-app.sh` always builds
`-c release` and then gates the result, so the artifact that ships is covered and the
test bundle is left alone.

### Verified, and what it could not cover

Installed with `PROCTOR_SKIP_NOTARIZE=1 scripts/install.sh`: Developer ID signed, not
notarised, nothing left this machine. The installed build reports
`0.1.0+3816b655a616.dirty`, so the measurements above are of this change.

Not covered: notarisation itself. `spctl --assess` reports the installed build as
`rejected / Unnotarized Developer ID`, which is the expected consequence of skipping
it and not a property of this change. `codesign --verify --strict --deep` passes, and
an embedded Info.plist in a helper tool is an ordinary shape that the review confirmed
raises no notarisation objection, but no submission was made.

## Child work found

**A pre-existing flake in `TakeoverWiringTests`, not introduced here.**
`"a batch that starts on the accessibility plane raises it at the first synthetic
step"` fails intermittently at `TakeoverWiringTests.swift:122` with
`(h.takeover.shows.count → 0) == 1`. Measured on a clean worktree at the base commit
`0545219` with none of this change present: **3 failures in 6 runs**, same test, same
line, same expectation. This branch measured 2 in 6. Every other suite is stable:
`--skip TakeoverWiringTests` is 931 tests, 6 runs, 6 green. Left alone deliberately,
since it belongs to PRO-0033/PRO-0037's takeover wiring rather than to this change.

Worth knowing separately: `swift test` **exits 0 on this failure**, so a caller
reading only the exit code sees green. The run summary line is the honest signal.
