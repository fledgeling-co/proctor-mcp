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

That builds the release binaries, assembles `Proctor.app`, installs it to
`~/Applications`, registers `app.fledgeling.procter.agent` with launchd, waits
for the socket, and opens the two System Settings panes you need.

Then grant both, to **Proctor** — not to your terminal, not to your MCP host:

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

Register the shim with your host:

```
claude mcp add proctor -- ~/Applications/Proctor.app/Contents/MacOS/proctor-shim serve
```

Check the install with `scripts/doctor.sh` (filesystem and launchd only, runs
without the agent) or the `proctor_doctor` tool (grants, observers, live state).
Remove it with `scripts/uninstall.sh`, optionally `--purge`.

The development build is ad-hoc signed, which ties the TCC grant to the exact
bytes of that build. Every rebuild revokes the grants, and the symptom is
"elements not found" rather than a permission error. That is the cost of ad-hoc
signing and it is fine for development; distribution needs a Developer ID
signature and notarisation, which `scripts/build-app.sh` prints.

## Tools

| Tool | What it does |
|---|---|
| `proctor_apps` | Enumerate running apps and windows, and attach to the ones under test. Attaching warms the tree, applies `AXManualAccessibility` for Chromium and Electron apps, starts observers, and retains element references that keep resolving across Spaces. |
| `proctor_snapshot` | Return the pruned semantic accessibility tree for a window, with a stable node id on every node. Pass `sinceRevision` for a diff instead of a full tree. |
| `proctor_find` | Return only the nodes matching a predicate, so locating one button does not cost a whole tree. Prefer `identifier`, the one selector a developer sets deliberately. |
| `proctor_act` | Run a sequence of steps, settling after each and returning per-step outcome, actuation plane, post-state hash and tree diff. A six-step flow is one call. |
| `proctor_capture` | Screenshot a window through a window-scoped ScreenCaptureKit filter, with frame status, dirty-rect coverage, frames waited and a `trustworthy` verdict. |
| `proctor_wait` | Block until a nameable condition holds — an element appearing, a value reaching a target, a region going quiet, the app's own idle endpoint — bounded by a timeout. |
| `proctor_assert` | Evaluate assertions and return pass/fail with the observed value beside the expected one. Covers tree, geometry, pixels and accessibility auditing. |
| `proctor_flow` | Record, list, show, replay and delete named step sequences. A recorded flow stores its selectors and per-step hashes, so a divergent replay says where and how. |
| `proctor_stability` | Replay a flow N times and report `firstDivergence` and a per-step instability score. This is what separates a real defect from a flaky test. |
| `proctor_inspect` | Read resolved styles and layer geometry from an app embedding `ProctorReflector`: colours, fonts, radii, opacity, constraints, and CALayer model versus presentation values. |
| `proctor_doctor` | Report agent liveness, TCC grants with the exact fix for the running OS, attachments, observer health, Secure Event Input, and shortcuts CLI availability. |

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
| `scripts` | `build-app.sh`, `install.sh`, `uninstall.sh`, `doctor.sh`. |
| `docs/architecture.md` | Process model, planes, settling, determinism. Read before changing anything load-bearing. |
