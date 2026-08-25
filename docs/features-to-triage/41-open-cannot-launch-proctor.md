---
sources: [REQ-026]
status: retired
validated-by: REQ-026 via CASE-0027
validated-rungs: outcome
validated-provider: none
---
# `open -a Proctor` cannot launch Proctor while the agent is running

## The problem

Measured on this machine, 2026-08-15, immediately after a clean reinstall:

```
$ lsappinfo find bundleid=app.fledgeling.procter
ASN:0x0-0x4e24f201-"Proctor":
$ lsappinfo info -only pid,bundlepath ASN:0x0-0x4e24f201
"pid"=17556
"LSBundlePath"="/Applications/Proctor.app"
$ ps -p 17556
/Applications/Proctor.app/Contents/MacOS/proctor-agent
```

LaunchServices believes the application `app.fledgeling.procter` is already
running, and the process it names is **`proctor-agent`** rather than the UI app.
The agent is a separate Mach-O living inside `Contents/MacOS/`, started
independently by launchd, and it therefore inherits the bundle's Info.plist
identity. `open -a Proctor` sees a live instance of that bundle id and activates
it instead of launching anything. The agent has no UI, so nothing appears, and
`open` exits 0.

The consequence is that **Proctor cannot be opened by any normal means whenever
its own agent is running**, which is almost always. Confirmed by elimination:
booting the agent out cleared the ASN, and the very next `open -a` launched the
real UI app, which then restarted the agent itself through `Actions.ensureAgent()`.

`killall Dock`, `lsregister -f`, and repeated `open` calls all failed to clear it,
so this is not transient LaunchServices confusion that waiting fixes.

## Where it bites

- **`scripts/install.sh` ends with `open`**, so its final "==> opening Proctor"
  step is a silent no-op on every reinstall where the agent is already up. The
  installer reports success and the person sees no window and no menu bar icon.
- **PRO-0028's `AgentRecovery`** and the app's own relaunch path both assume the
  app can be reopened. Any path that goes through LaunchServices has this
  problem.
- **A person double-clicking Proctor in `/Applications` gets nothing**, which is
  the worst version of it because there is no error to read.

## What it should do

Opening Proctor should open Proctor, whether or not the agent is running.

## The hard parts, named

- **The fix is a decision about bundle layout, and the options differ in what
  they cost.** The agent could get its own bundle identifier; it could move out
  of `Contents/MacOS/` into `Contents/Helpers/` or a `.xpc`; or its plist entry
  could mark it background-only so LaunchServices does not treat it as an
  instance of the app. Each changes the installed layout, and the TCC grants key
  on the team-scoped Developer ID signature, so the spec must say explicitly
  whether the chosen layout preserves Accessibility and Screen Recording across
  the upgrade or re-prompts for them. **Re-prompting is a real cost to a person
  and it is the thing to design around, not to discover.**
- **`scripts/install.sh`, `scripts/notarize.sh` and
  `.github/workflows/release.yml` all have to move together**, per the repo's own
  release convention. A layout change that only lands in the local installer
  ships a broken release.
- **The workaround must not become the fix.** Stopping the agent so the app can
  launch is what got the app up today, and it is wrong as a shipped behaviour:
  opening a window should never take down the thing an MCP host is talking to.

## Worth knowing

The UI app is correct in every other respect: `walkthroughCompleted` is set, so
it applies `.accessory`, orders the main window out and lives in the menu bar,
which is why "no window appears" is expected once it *has* launched and is not
itself the bug.
EOF
