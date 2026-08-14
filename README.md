# Proctor

Proctor is a macOS UI testing capability exposed over MCP: any model that speaks
MCP can drive a real Mac app — read its accessibility tree, act on its controls,
capture its windows, and assert against what it finds. It is built around the
idea that a result with no provenance is indistinguishable from a correct one,
so every tree carries its revision, every screenshot carries its freshness, and
every action reports which plane it travelled through.

## Why it is shaped this way

Proctor ships as an `.app` bundle registered as a launchd user agent, with a
separate permissionless stdio shim as the thing an MCP host actually launches.
That looks like more moving parts than a single binary needs. It is the only
shape that works.

The Accessibility API cannot be used from a sandboxed app at all — Apple's
Developer Technical Support has confirmed there is no entitlement combination
that permits it. So the privileged core is unsandboxed, and the question becomes
who macOS thinks is asking.

macOS attributes a TCC grant to the **responsible process**, which it finds by
walking up the process ancestry rather than by looking at the binary that made
the call. The consequences are concrete:

- A helper spawned by an MCP host gets the grant attributed to the host app. You
  grant Accessibility to your editor, not to the test tool.
- A helper spawned under `node` gets it attributed to `node` — which hands
  accessibility control of your machine to every Node script on it.
- A helper running from an `npx` temp path loses the responsibility chain
  entirely, and re-prompts on every version bump, because both the path and the
  designated requirement change.

A launchd-launched agent is its own responsible process. The grant attaches to a
stable bundle identity at a fixed path, the consent dialog shows a real name and
icon instead of a nameless binary, and the grant survives upgrades and changes of
host. macOS 27 also replaces the legacy PPPC profile path for Accessibility with
declarative App Settings, which expects a bundle — so this is the
forward-compatible shape as well as the working one.

The shim holds no permissions and keeps no state. It speaks MCP over stdio and
forwards length-prefixed JSON to the agent over a Unix socket. Your MCP host can
be restarted, replaced or run twenty times over; the grants stay where they are.

## Install

```
scripts/install.sh
```

That builds the release binaries, assembles `Proctor.app`, signs it with the
Developer ID identity in your keychain (falling back to ad-hoc only if there is
none), notarises it when a `proctor` notary profile is set up, installs it to
`/Applications`, registers `app.fledgeling.procter.agent` as a per-user launchd
agent, and waits for the socket.

Then open Proctor. On a first run it walks you through what it does and asks
macOS for each grant in turn, moving on by itself as each one lands. Afterwards
it leaves the Dock and lives in the menu bar, where the same window is a status
panel: what is granted, what is attached, what the agent is signed with, and the
snippet to paste into your MCP host. "Run Setup Again…" replays the walkthrough.

The menu bar item is the run HUD's own character, in the state the run is in, so
a glance at the top of the screen answers what Proctor is doing without finding
the panel. Its menu shows and hides that panel at once for the current run, and
carries Pause and Stop while a run is live, because the panel is the kill switch
and putting it away must not put the kill switch away. When Proctor is
unreachable or missing a permission it needs, the item goes back to the status
symbol: that is the more urgent thing to say.

The install auto-detects your Developer ID identity, so a normal run is signed,
not ad-hoc — which matters because an ad-hoc signature ties the grants to those
exact bytes and every rebuild silently revokes them (the symptom is elements not
being found, not a permission error). Pass a specific identity if you have more
than one:

```
scripts/install.sh "Developer ID Application: Your Name (TEAMID)"
```

A fresh build is notarised automatically when a notary keychain profile named
`proctor` exists (`PROCTOR_SKIP_NOTARIZE=1` skips it, `PROCTOR_NOTARY_PROFILE`
names another). Without one it installs signed but not notarised, which is fine
on this Mac; distribution to other Macs needs it.

The two grants go to **Proctor** — not to your terminal, not to your MCP host:

| Grant | Pane | Notes |
|---|---|---|
| Accessibility | Privacy & Security > Accessibility | Everything except capture depends on it. |
| Screen Recording | Privacy & Security > Screen Recording | Needed for `proctor_capture` and for the pixel signal in settling. |

Screen Recording can never be granted silently, on any macOS version. There is
no profile, no entitlement and no scripted path — a human has to click the
switch. Any tool that claims otherwise is describing a version of macOS that
does not exist. After granting it, macOS may want the process restarted:

```
launchctl kickstart -k gui/$(id -u)/app.fledgeling.procter.agent
```

Proctor installs to `/Applications`, which is where the pane's file picker
opens, so if it is not already listed you can add it with the + button without
hunting for the path.

Register the shim with your host:

```
claude mcp add proctor -- ~/Applications/Proctor.app/Contents/MacOS/proctor-shim serve
```

Check the install with `scripts/doctor.sh` (filesystem and launchd only, runs
without the agent) or the `proctor_doctor` tool (grants, observers, live state).
Remove it with `scripts/uninstall.sh`, optionally `--purge`.

### Remote access

The shim also speaks MCP over HTTP, for a model that is not on this Mac:

```
~/Applications/Proctor.app/Contents/MacOS/proctor-shim serve --remote
```

That binds `127.0.0.1:8787` and serves the same tools at `POST /mcp` as
newline-free JSON-RPC — identical to the stdio path, forwarded to the same
agent. `GET /health` answers unauthenticated for liveness. A network front door
adds no permission: a remote caller reaches exactly the tools a local one does.

Authentication is optional but bounded by where it binds. A loopback bind runs
unauthenticated for local use; **any non-loopback `--host` requires a token**, or
the shim refuses to start. Set the token out of the process listing:

```
PROCTOR_MCP_TOKEN=$(openssl rand -hex 32) proctor-shim serve --remote --host 0.0.0.0 --port 8787
```

Clients then send `Authorization: Bearer <token>`. The safer shape for remote
work is to keep the loopback bind and reach it over an SSH tunnel
(`ssh -L 8787:127.0.0.1:8787 mac`), which needs no token and exposes nothing.
Against the unauthenticated loopback case, two things close the browser
cross-origin path: `POST /mcp` requires `Content-Type: application/json` (which
a cross-origin "simple request" cannot set without a CORS preflight this server
never grants), and a present `Origin` is matched on its exact host, so
`localhost.evil.com` is refused where a prefix check would have let it through.

To run it on another Mac it also has to be notarised, which needs your own Apple
credentials — they are never stored in this repo:

```
xcrun notarytool store-credentials proctor \
    --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
scripts/notarize.sh proctor
```

`scripts/install.sh` signs with your Developer ID and notarises by default (see
Install above), so an ordinary build already has stable grants — an ad-hoc
signature, which ties the TCC grant to the exact bytes and is revoked on every
rebuild, only happens as a fallback when no Developer ID identity is present.
Released builds are signed and notarised in CI by `.github/workflows/release.yml`
on a `v*` tag; `scripts/build-app.sh` prints the signing details for a manual run.

## Tools

| Tool | What it does |
|---|---|
| `proctor_apps` | Enumerate running apps and windows, and attach to the ones under test. Attaching warms the tree, applies `AXManualAccessibility` for Chromium and Electron apps, starts observers, and retains element references that keep resolving across Spaces. |
| `proctor_snapshot` | Return the pruned semantic accessibility tree for a window, with a stable node id on every node. Pass `sinceRevision` for a diff instead of a full tree. |
| `proctor_find` | Return only the nodes matching a predicate, so locating one button does not cost a whole tree. Prefer `identifier`, the one selector a developer sets deliberately. |
| `proctor_act` | Run a sequence of steps, settling after each and returning per-step outcome, actuation plane, post-state hash and tree diff. A six-step flow is one call. |
| `proctor_capture` | Screenshot a window through a window-scoped ScreenCaptureKit filter, with frame status, dirty-rect coverage, frames waited and a `trustworthy` verdict. Optionally burns numbered marks over interactable elements (with a mark→node map) plus a reference grid, or normalises the frame to the vision-API ceiling and reports the exact scale factor applied. |
| `proctor_zoom` | Return a native-resolution PNG crop of one region or one accessibility element, for reading small text a normalised whole-window capture loses. Carries the same freshness metadata as `proctor_capture`; the compose path is `find → zoom → assert`. |
| `proctor_wait` | Block until a nameable condition holds — an element appearing, a value reaching a target, a region going quiet, the app's own idle endpoint — bounded by a timeout. |
| `proctor_assert` | Evaluate assertions and return pass/fail with the observed value beside the expected one. Covers tree, geometry, pixels and accessibility auditing. |
| `proctor_flow` | Record, list, show, replay and delete named step sequences. A recorded flow stores its selectors and per-step hashes, so a divergent replay says where and how. |
| `proctor_stability` | Replay a flow N times and report `firstDivergence` and a per-step instability score. This is what separates a real defect from a flaky test. |
| `proctor_inspect` | Read resolved styles and layer geometry from an app embedding `ProctorReflector`: colours, fonts, radii, opacity, constraints, and CALayer model versus presentation values. |
| `proctor_doctor` | Report agent liveness, TCC grants with the exact fix for the running OS, attachments, observer health, Secure Event Input, and whether the shortcuts CLI and Obscura are installed. |
| `proctor_unlock` | Open, evaluate and end a screen-unlock turn, when the login-path authorization plugin is installed and armed. Each turn is TTL-bounded so a crashed caller cannot leave the screen unlockable, and the password prompt stays a fallback. |
| `proctor_computer` | Accept a single Anthropic `computer` action in its stock schema and run it against a window, so a model trained on that tool drives Proctor with no prompt changes. Additive; synthetic-event actions, reported `plane=syntheticEvent`. |
| `proctor_openai_computer` | The same adapter for the OpenAI `openai_computer` schema — one action or a batch, stopping at the first failure with `failedAt`. Also additive, also synthetic-event. |
| `proctor_menu` | Walk the attached app's menu bar and return every item with its path, enabled state and reconstructed key-equivalent. A pure accessibility read that reaches background apps; invoke by shortcut (`key`) or background-safe (`menu` step). |
| `proctor_dictionary` | Read an app's scripting definition (sdef) — suites, commands, classes, properties — as structured data, so the Apple-Events plane is self-describing. Reports `scriptable=false` plainly rather than erroring; cached per app handle. |
| `proctor_policy` | Operator safety plumbing: a fail-closed policy gate (allow / block / sensitive by bundle id, with TTL-bounded approval tokens) and a redacting audit trail that stores typed values as length + SHA-256, never in the clear. |
| `proctor_kill` | List and terminate processes for test setup and teardown, so a campaign resets state between runs. Termination goes through the same `proctor_policy` gate and audit; the kernel, launchd and the agent itself are never signalled. |

## What it can and cannot do

**It reaches background windows.** Actions go through the process-directed plane
by default — `AXUIElementPerformAction`, `AXUIElementSetAttributeValue`, Apple
Events — which addresses a specific element in a specific process. That reaches
non-frontmost, occluded and other-Space windows without stealing focus, and
Secure Event Input does not block it.

**Synthetic-event actions are a different mode, and are reported as one.** The
step kinds `click`, `hover` and `dragPath` post events into the single
WindowServer stream. They need the target foreground, they are blocked by Secure
Event Input, and they are returned with `plane=syntheticEvent` so a result is
never mistaken for a background-safe one. Reserve them for what accessibility
genuinely cannot express.

**The background route is taken wherever one exists.** `type` and `scroll`
prefer the accessibility plane and try more than one route on it before
conceding the front: a field that refuses an `AXValue` write is written through
a selection covering its whole value, and an element with no scroll action of
its own is scrolled by the enclosing scroll area's bar. Every write is read back
rather than believed, because AX reports success for a set the application then
discards. Each step result says which route it took in `route` — `valueWrite`,
`selectedText`, `scrollBar`, `scrollAction`, `action`, `eventStream`,
`appleEvent`, `declared` — beside the coarser `plane`. And `foreground: true`
over a batch where no step could use it is ignored rather than honoured, since
nothing brings an application forward except a synthetic post; the `foreground`
block reports that as `requestIgnored`.

**There is no cross-process computed-style API on macOS.** Nothing is equivalent
to `getComputedStyle` across a process boundary. For an app you do not own, the
ceiling is the accessibility tree plus pixels — which is a real ceiling, not a
temporary gap. `proctor_inspect` returns `reflectorUnavailable` rather than
approximating, because a plausible guess about a colour is worse than an absence.
For apps you do own, `ProctorReflector` removes the ceiling.

**Parallelism is bounded by hardware, not by software.** Apple silicon hard-caps
concurrent macOS VM guests at two, so you cannot fan a campaign out across many
virtual machines. Scaling happens across windows within one session — attach to
several apps, keep their trees warm, drive them in the background — and past
that, more real parallelism is a hardware purchase.

**It does not drive pages in a browser, and says so.** Proctor owns native macOS
applications. A page in Chrome or Safari is not one: walking its accessibility
tree trades the DOM, computed styles, the console, the network log and a selector
that survives a re-render for a flattened tree and a set of coordinates. When a
result's target is a browser showing a page, it carries a `browser` object naming
[Obscura](https://github.com/h4ckf0r0day/obscura) as the tool for the page, with
the page's URL, command templates and Obscura's own measured limits. Nothing is
refused — the native chrome around the page (toolbar, tab bar, menus, sheets)
stays Proctor's, and driving it is what Proctor is for. Two things the object
says out loud, because both are easy to get wrong: Obscura runs its own engine
with its own cookie jar, so following the advice restarts at a URL rather than
continuing that window's signed-in session; and a step into page content still
hashes, but over a browser's render tree, so a determinism score there measures
the page's churn as much as the app's. A web view inside a native Mac app is
**not** routed — reaching it means attaching to the host process, which is
Proctor's job.

When Obscura is not installed, the object says so instead of naming a command
this Mac does not have: no `use`, no command templates, and a `toolUnavailable`
saying who installs it. It carries no shell command, deliberately — a command in
a tool result is something a model will run, and the install is a download of an
unsigned binary from the internet by a process holding Accessibility and Screen
Recording. **Proctor never installs anything.** The commands live in the status
window, one click from the clipboard, beside a Re-check. Detection reads the
filesystem and never executes what it finds, because the directories a launchd
agent has to check by name — `~/.local/bin`, `~/.cargo/bin`, `/opt/homebrew/bin`
— are ones anything can write to. `proctor_doctor` reports `obscuraAvailable`
and every path it looked at, and never lets it affect `ready`: Proctor drives
native applications without it.

**There is a second lane, and it is off unless you turn it on.** Some of Obscura's
measured limits stop a job rather than degrading it, and a page that lives inside
the browser itself — `chrome://`, an extension page, DevTools — has no equivalent
in Obscura's engine at all. For those, Proctor can name the
[browser-use](https://docs.browser-use.com) CLI instead, and the `why` field says
which rule chose it, so the advice is checkable rather than oracular. Two gates
stand in front of it, and they do different jobs: `PROCTOR_SECOND_LANE=browser-use`
in the agent's launchd environment decides whether the tool may be **named** at
all, and finding the binary decides whether the lane is **usable**. Unset is
Obscura-only. The reason for the switch is what the tool is: browser-use is an
autonomous agent, its default local mode drives a real browser with real
credentials, and nothing it does reaches Proctor's audit trail — so the handoff
says all three at both detail levels, and it ships **no command templates** for
that lane, only prose about which mode to run it in. Installing a CLI is consent
to have a file; it is not consent for a process holding Accessibility to name that
file to a model with a shell. Routing is on the URL's scheme and nothing else: the
step kind and the accessibility shape were examined and neither discriminates
between the lanes. Two things it will not do, both deliberate. It is **never a
fallback** — a missing Obscura is a fact about the machine, not about the page, so
an ordinary web page is never handed to an autonomous agent because the bounded
reader is absent. And it is **never pointed at the browser's own configuration,
credential, extension or history pages**, or at DevTools: an agent acting as this
person has no business in the place their saved passwords live.

**It does not see inside a window it was not granted.** No Accessibility grant
means an empty tree; no Screen Recording grant means no pixels. Neither
degrades gracefully into something that looks like a test result.

## ProctorReflector

`ProctorReflector` is a library you embed in an app you own, behind `#if DEBUG`.
Once it is in, `proctor_inspect` can read the view and layer hierarchy directly:
resolved colours and fonts, corner radii, opacity, constraints, and both the
CALayer model values and the presentation values, with a monotonic render
revision.

Two things change. Fidelity checking stops being eyeballing and becomes
measurement — you can assert that a colour is the token you intended rather than
that a screenshot looks about right. And settling gets its most honest signal:
the app reports its own idle state, so `SettleReport.reason` can be
`reflectorIdle` instead of inferring quiet from the outside.

## Troubleshooting

**"Elements not found", repeatedly.** Nearly always a missing Accessibility
grant. A denied grant returns an empty tree, not an error, so a model reads it as
a flaky lookup and retries forever. Run `scripts/doctor.sh`, then
`proctor_doctor`. If you rebuilt the app, an ad-hoc signature change has revoked
the grant and you need to re-tick both switches.

**An empty tree in an Electron or Chromium app.** Those apps do not expose an
accessibility tree until `AXManualAccessibility` is set on them, and then the
tree takes a moment to build. `proctor_apps` applies the flag on attach and
reports whether it took. If the tree is still empty, it is not yet warm — wait
and re-snapshot. Note that applying the flag is detectable by the target app and
changes its performance, which is why the response says so: any methodology
written on this data should disclose it.

**A screenshot that looks stale, on an off-screen window.** This is real
ScreenCaptureKit behaviour, not a bug in Proctor. Off-screen windows may emit
complete frames only when the pointer moves on their display. A stale frame is
byte-for-byte indistinguishable from a correct one, which is exactly why every
capture carries frame status, dirty-rect count and coverage, frames waited, and
a `trustworthy` flag with a caveat naming the reason. Check `trustworthy` before
you believe a picture.

**Synthetic actions silently doing nothing.** Secure Event Input is active —
usually a focused password field or a terminal in secure keyboard entry mode.
`scripts/doctor.sh` names the process holding it. Process-directed actions still
work.

## Repository layout

| Path | What |
|---|---|
| `Sources/ProctorCore` | Wire contract, tool catalogue, canonical hashing, transport. |
| `Sources/ProctorAgent` | The privileged core. Runs inside `Proctor.app` under launchd. |
| `Sources/ProctorShim` | The permissionless stdio MCP front end. Holds no grants. |
| `Sources/ProctorReflector` | Embeddable in-process style and layer source. |
| `Apps/Proctor` | Bundle `Info.plist` and icon. |
| `scripts` | `build-app.sh`, `install.sh`, `uninstall.sh`, `doctor.sh`, `notarize.sh`. |
| `docs/architecture.md` | Process model, planes, settling, determinism. Read before changing anything load-bearing. |
