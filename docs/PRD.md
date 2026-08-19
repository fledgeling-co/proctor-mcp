# Product Requirements Document — Proctor

| | |
|---|---|
| **Product** | Proctor — macOS computer-use agent and UI-testing harness |
| **Bundle identity** | `app.fledgeling.procter` (app) / `app.fledgeling.procter.agent` (LaunchServices) |
| **Released version** | v0.2.0, tagged, notarised and stapled 2026-08-17 |
| **Document status** | Revised 2026-08-19 against the tree at `ab53c5e` plus uncommitted work |
| **Repository** | `github.com/fledgeling-co/proctor-mcp` |
| **Minimum OS** | macOS 14 |
| **Language** | Swift 6, strict concurrency |
| **Measured gate** | 1,527 tests in 176 suites, green in 10.576s (`swift test`, 2026-08-19) |

Companion documents: `README.md` is the operator's entry point, `docs/architecture.md` explains
the load-bearing mechanisms, `ORCHESTRATOR.md` is the delivery ledger, `CHANGELOG.md` is the
release record, and `docs/specs/spec-PRO-*.md` carry the per-feature reasoning this document
summarises.

**The design of record** is `design/surfaces/proctor-surfaces.html` with its spec beside it —
every surface in sections 13 through 16, in every state. Section 13A describes it and section
13B the contract for converting it to SwiftUI.

**`vendor/fledgeling-plugins`** is a git submodule pinned to `main`, carrying the skills the
delivery pipeline and the design gates run on, so a fresh worktree needs no marketplace
install. Initialise with `git submodule update --init`.

---

## 1. What Proctor is

Proctor is a native macOS agent that gives a model computer use on a Mac and doubles as a UI
testing harness. It presents 21 tools over the Model Context Protocol, reads applications
through the accessibility tree and ScreenCaptureKit, drives them through two distinct actuation
planes, and records what it did in a redacting, sealed, hash-chained audit trail.

It ships as one signed bundle containing three executables and one embeddable library. The
long-lived agent holds the TCC grants; a permissionless shim speaks MCP to the host; a SwiftUI
app is the face of the thing. Nothing in the product requires a model to be in the loop for the
agent to run, and nothing requires the app to be open for a tool call to work.

## 2. The thesis, and what it rules out

> A result carrying no provenance is indistinguishable from a correct one.

Every answer Proctor returns records how it was obtained. A tree carries its revision, capture
time and derivation. A capture carries `SCFrameStatus`, its dirty-region bounds and whether the
pixels are fresh. A step carries the plane it travelled (`accessibility`, `declared`,
`appleEvents`, `syntheticEvent`, `routedEvent`, `unknown`) and the finer route within it
(`valueWrite`, `selectedText`, `scrollBar`, `scrollAction`, `action`, `eventStream`,
`appleEvent`, `declared`). A settle names which signals were even available, not merely that
things went quiet.

Three product decisions follow from that thesis, and each rules out a cheaper design:

**A missing capability is reported, never approximated.** `proctor_inspect` returns
`reflectorUnavailable` on an app that has not embedded ProctorReflector, because macOS has no
cross-process equivalent of `getComputedStyle` and a plausible guess about a colour is worse
than an absence. Assertions that need pixels return `skipped` when nothing is wired rather than
passing.

**A weaker proof is never dressed as a stronger one.** A step that passed through the shared
WindowServer event stream proves the app responds when it owns the screen; a step that passed
through the accessibility plane proves the control is reachable at all. The two are never
collapsed into "it worked".

**A lane that cannot witness something refuses rather than passing.** On the delegated witness
tier there is no accessibility tree and no frame status, so tree assertions and the tri-observer
`agree` check fail closed with `skipped("Unsupported on delegated tier")`.

## 3. Users and the jobs they bring

**Autonomous coding agents** (Claude Code, Cursor, Codex, custom MCP clients) are the primary
consumer. They attach to an app once, keep its tree warm, and drive it in the background while a
person keeps using the Mac. The tool descriptions are written for this reader, which is why they
carry measured caveats inline (1Password autofill presents as `AXButton` in Chrome and
`AXMenuItem` in Safari, and only the Chrome button honoured `press` — measured 2026-08-16).

**Mac engineers and QA** record flows, replay them, and ask whether a failure is a defect or
nondeterminism. `proctor_stability` answers that before anyone argues about correctness:
`instability` scales distinct states over N runs to 0–1, and `firstDivergence` names the first
step index where runs disagreed, so a flow diverging at step 3 does not need its step 9
assertion investigated.

**CI and matrix testing** runs against guests rather than the host, so a campaign cannot take
over the machine that scheduled it. Apple silicon hard-caps concurrent macOS VM guests at two,
so this scales across windows within a session rather than across many VMs.

**The person whose Mac it is** is a user of this product even when they never call a tool. The
run HUD, the takeover notice, the contention yield, the menu bar character and the switches card
exist for them, and several of the constraints in section 11 exist because a supervision surface
nobody can reach is not supervision.

## 4. Surfaces: what exists, and what is proposed

| Surface | Artifact | Status |
|---|---|---|
| MCP server | `proctor-shim` (stdio and HTTP) → `proctor-agent` | Built, shipped in v0.2.0 |
| Desktop app | `Proctor.app` — walkthrough, status window, menu bar, history | Built, shipped in v0.2.0 |
| Installer / service CLI | `proctor-shim install \| uninstall \| status \| serve` | Built, narrow by design |
| Embeddable library | `ProctorReflector` | Built, shipped as a SwiftPM product |
| **Operator CLI** | `proctor <verb>` over the same socket | **Proposed — not built.** Section 15 · drawn at `#cli/*` |
| **Supervision TUI** | `proctor tui` | **Proposed — not built.** Section 16 · 22 frames compiled |

Sections 5 through 14 describe built behaviour and are requirements in the sense that changes
must preserve them. Sections 15 and 16 specify surfaces that do not exist yet and are
requirements in the ordinary forward-looking sense.

---

## 5. Architecture

### 5.1 Process model

```
  MCP host (Claude Code, an editor, an SDK client)
      | spawns, stdio
      v
  proctor-shim ..................... no TCC grants, no state
      | AF_UNIX SOCK_STREAM, 4-byte big-endian length prefix + JSON
      | ~/Library/Application Support/app.fledgeling.procter/agent.sock
      v
  proctor-agent .................... inside Proctor.app
      | launchd gui/$UID/app.fledgeling.procter.agent, RunAtLoad, KeepAlive on failure
      |
      +-- AXUIElement ............. tree, observers, actuation
      +-- ScreenCaptureKit ........ window-scoped capture
      +-- CGEventPost ............. synthetic events, foreground only
      +-- Apple Events / shortcuts  declared app contracts
      +-- ProctorReflector client   styles and idle, apps you own only
      +-- Overlays ................ run HUD, takeover shield, cursor marker
      +-- Providers ............... lume, prlctl, cua-driver, simctl, maestro
```

The shim is disposable and holds no permissions, so several hosts can run at once for the cost
of a socket each. The agent is long-lived, which is what lets a retained `AXUIElement` keep
resolving after its window moves to another Space; a fresh enumeration would not find it.

### 5.2 Why launchd, and why two identities

macOS attributes a TCC grant to the *responsible* process, walking up the ancestry. A helper
spawned by an MCP host has the grant attributed to the host; a helper under `node` hands
Accessibility to every Node script on the machine; a helper from an `npx` temp path has no
stable designated requirement and re-prompts on every version bump. A launchd user agent is its
own responsible process, so the grant attaches to `app.fledgeling.procter` at a fixed path and
survives host changes and upgrades.

The agent then needs a *second* identity for a different subsystem. Every nested binary is signed
`-i app.fledgeling.procter`, so the designated requirement names that identifier and the team and
carries no path — that is what carries the grants across an upgrade. But the agent claims the
accessory activation policy on its first line, which registers it with LaunchServices; while it
registered under the app's identifier, `open -a Proctor` found a live instance, activated a
process with no window, and exited 0, so Proctor could not be opened while its own agent ran.
The fix is a `__TEXT,__info_plist` section linked in from `Apps/Proctor/AgentInfo.plist`
declaring `app.fledgeling.procter.agent`. `scripts/build-app.sh` fails the build when the section
is missing or the signing identifier is not the app's (PRO-0040).

That linker flag is release-configuration only. Measured during PRO-0040: an unconditional flag
put the agent's Info.plist into `proctor-mcpPackageTests.xctest`, so every test process ran
holding the agent's identity and `LSUIElement`.

### 5.3 Transport and framing

Both sides derive the socket path from `Wire.socketPath`, so neither can drift. `PROCTOR_SOCKET`
overrides it for both at once, which is how a test binds a throwaway socket. Framing is a 4-byte
big-endian length followed by the payload; newline framing loses to captured UI text containing
newlines, which is exactly what this carries. A frame over `Wire.maxFrameBytes` is refused with a
remedy naming `maxNodes`, `maxDepth` and `sinceRevision` rather than truncated.

### 5.4 The run loop, and the drawing-fault barrier

The agent runs `NSApplication.shared.run()` rather than a bare `CFRunLoopRun()`. Both spin the
same main run loop, but only AppKit's drains the event queue, and a Pause or Stop button nobody
can click is not a kill switch (PRO-0015). Three constraints hold that together: the HUD panel
drags via `mouseDragged` and `setFrameOrigin` rather than `performDrag`, it never calls
`activate(_:)`, and it ignores mouse events while a synthetic step is in flight — without the
last one a synthetic click posted under the panel can land on Stop and halt the run that posted
it. With `PROCTOR_HUD` off, `main.swift` keeps the old `CFRunLoopRun()` so an opted-out run has
the process shape that shipped before the HUD existed.

AppKit still raises `NSException`, Swift cannot catch one, and an uncaught one aborts the
process — which for a drawing fault in the HUD means the panel takes down the agent, the run and
the MCP server with it. `ProctorCatch` is a one-function Objective-C target that exists solely to
convert that into a caught failure (PRO-0022). It is its own target because SwiftPM has no
mixed-language ones.

### 5.5 Run-loop ownership and concurrency

`AXObserver` notifications are delivered only to a live `CFRunLoop`, and only the main thread has
one by default, so the run loop owns `main` and the socket accept loop runs on its own threads.
Inverting that gives a server that answers every call and never sees an accessibility
notification, which presents as settling that always times out.

The `Session` actor deliberately admits other work at every settle and capture suspension point.
That reentrancy is why steps from two clients interleaved before the queue existed, and it is why
a lane has to be held by a keeper *outside* the actor's own turn-taking (section 11.4).

---

## 6. Actuation

### 6.1 The two planes

**Process-directed** — `declared` (AppleScript sdef, the `shortcuts` CLI), `accessibility`
(`AXUIElementPerformAction`, `AXUIElementSetAttributeValue`), `appleEvents`. These address a named
element in a named process, never touching the WindowServer event stream. They reach non-frontmost,
occluded and other-Space windows, do not steal focus, are not blocked by Secure Event Input, and
are unaffected by what the person is doing. This is the default and it is what makes background
testing possible.

**Event-stream injection** — `syntheticEvent`, via `CGEventPost`. One event stream per session,
delivered to whatever is frontmost. These need the target foreground, steal focus, are blocked by
Secure Event Input, and race a human at the keyboard. The step kinds `click`, `hover` and
`dragPath` have no accessibility equivalent on Proctor's own actuator and must use this plane.

Two further planes exist because a delegated backend can deliver a step in a way the original four
cannot describe. `routedEvent` is an injected event delivered to one process rather than the shared
stream: background-safe, and not the accessibility plane. `unknown` is a step performed through a
delivery mode this build does not recognise, which makes `ForegroundReport.note` non-nil, because
`note == nil` is what callers already read as "nothing to disclose". A run holding either is never
described as background-safe, and `ForegroundReport` counts neither as taking the machine.

### 6.2 Routes, and read-back

`ActuationPlane` stays coarse because `ForegroundReport` counts `syntheticEvent` on it, and
splitting it would change what "this run took the foreground" measures. `StepResult.route` carries
the finer answer. `type` and `scroll` each hold more than one accessibility route and try all of
them before conceding the front: a field refusing an `AXValue` write is written through a selection
covering its whole value, and an element with no scroll action of its own is scrolled by the
enclosing scroll area's bar.

Every write is read back rather than believed, because AX reports success for a set the application
then discards. An accepted action is not an effective one, which is why the tool descriptions tell a
caller to compare `stateHash` across a step rather than trusting `ok`.

### 6.3 The backend seam

Since PRO-0044 the planes are one *backend* rather than the only way a step can be performed.
`ActuationBackend` has two implementations: `NativeActuationBackend`, which forwards to the planes
above, and `CuaActuationBackend`, which delegates to `cua-driver`. The native one is the default and
`PROCTOR_ACTUATION=cua` selects the other.

**Actuation is delegated; observation never is.** Proctor keeps its own ScreenCaptureKit path, its
own frame-status reporting and its own accessibility walk, because a driver's screenshots carry no
frame status and its own documentation records its tree as unreliable on some surfaces. A layer
whose product is catching other people's silent failures needs one channel it can trust. The backend
is told what to strike and asked what it did, and is never the authority on what is there.

PRO-0051 settled that the native planes stay the default, on three findings, any one of which would
have been enough: `appleScript` and `shortcut` have no Cua equivalent and are refused on the
delegated lane, so deleting the native planes would delete two published verbs; Cua returns only a
menu bar for a window on another Space, where a retained `AXUIElement` keeps resolving; and
`cua-driver` had never executed on the development machine. The lane is chosen by an operator and
is never entered by falling into it — no failure selects the other backend, the choice is read once
at startup, and `Session.actuator` is immutable, so a lane is fixed for the life of a session and
every record can name it honestly.

Addressing crosses the seam by identity, never by position. A target is matched into the backend's
view through its `(role, label)` ancestry, both sides must agree before anything is struck, and a
target that moved, is ambiguous, or cannot be seen is refused. No coordinate is substituted for an
element that failed to resolve, because a match resting on a position replays by striking an
absolute point.

Preflight runs on the first delegated step and checks version, signature, vocabulary and grants.
`PROCTOR_CUA_ALLOW_UNSIGNED` and `PROCTOR_CUA_ALLOW_UNSUPPORTED` bypass two of those checks and are
deliberately excluded from the switches card in the app: a one-click bypass of a signature check
does not belong beside "show the pointer".

### 6.4 Foreground demand

One value answers "will this batch take the foreground", computed before anything runs, and the
lane demand, the HUD and the menu bar all read it rather than re-deriving it. Three answers to one
question is how they drift apart.

A step's plane is not always knowable up front. `click`, `hover`, `dragPath` and `key` are certain,
since no accessibility expression exists for them. `type` into a field the accessibility plane
cannot write, and `scroll` with no scroll action available, are conditional — a property of the
element rather than of the request. So an up-front count is stated as a **floor**, never as a bare
"N of M", it revises upward when a fallback actually happens, and a finished run reports the planes
its steps actually travelled rather than a second prediction.

Asking for the foreground is not the same as needing it. Nothing activates an application except a
synthetic post, so `foreground: true` over a batch with no step that could ever post is reported as
`requestIgnored` rather than honoured. Before that rule it took the exclusive global lane, armed a
contention watch and announced a takeover for a run that then travelled the accessibility plane.

Which kinds are which belongs to the backend, so the refusal, the disclosure and the queue's lane
demand all ask `backgroundCapability(for:)` — `never`, `maybe` or `yes` — rather than consulting a
list of kinds.

---

## 7. Observation

### 7.1 The accessibility tree

`proctor_snapshot` returns a full or subtree walk with durable selectors (`AXIdentifier` where the
app provides one), bounds, actions and attributes, bounded by `maxDepth` and `maxNodes` and
diffable through `sinceRevision`. `TreeProvenance` records the revision, the capture timestamp and
how the tree was derived. `proctor_find` queries by role, subrole, title, label, identifier, value
substring, enabled, focused or available action, with `substring`, `exact` or `regex` matching, so
a caller does not have to dump a tree to locate one control.

Attaching is what makes the rest work: it warms the tree, applies `AXManualAccessibility` where the
app is Chromium- or Electron-based, starts long-lived observers and begins retaining element
references. Applying `AXManualAccessibility` is detectable by the target app and changes its
performance, so the response reports whether it was applied and any methodology written on the data
can disclose it.

### 7.2 Capture

Captures are window-scoped through ScreenCaptureKit and carry `SCFrameStatus`
(`complete`, `idle`, `blank`, `suspended`, `stopped`, `unknown`), pixel freshness, and a
dirty-region bounding box. Optional overlays are set-of-marks annotation, a coordinate grid, and a
pointer marker drawn in the target's own plane. `tileHashes` supports region-level change
detection.

Normalisation is sized by purpose rather than by one ceiling (PRO-0063). `targeting` caps the long
edge at 768, which is also exactly Gemini's tile boundary — it charges
`ceil(w/768) × ceil(h/768) × 258`, so 769 pixels costs double what 768 does. `verify` and `detail`
raise the ceiling for checking rendered state and reading fine text. The default long edge is 1568
with a matching pixel cap, because a near-square frame can sit under 1568 on each side and still be
over budget. `CaptureNormalization` reports the scale actually applied, the original and final
dimensions, both ceilings, which tier they came from, and an estimated vision-token cost on
Anthropic's published `width × height / 750` approximation — an estimate for one model family,
reported so the cost sits beside the capture, and never used to decide anything.

`proctor_zoom` crops a region or a node at native resolution with optional padding, for reading text
a normalised frame cannot resolve.

### 7.3 Settling

Settling is a conjunction of independent signals, never a sleep. `SettleReport.reason` ranks them by
honesty:

| Reason | Meaning |
|---|---|
| `reflectorIdle` | The app said so itself, through ProctorReflector. Nothing outside the process can beat it. |
| `allSignalsQuiet` | AX notifications quiet for `axQuietMs` **and** `quietFrames` consecutive frames under `dirtyThreshold`. |
| `axQuietOnly` | No capture signal was available. Blind to animation and to pixel work raising no AX notification. |
| `captureQuietOnly` | No AX notifications were available. Blind to state changes that do not repaint. |
| `timeout` | Nothing went quiet in `timeoutMs`. Reported, never hidden. |

`dirtyThreshold` defaults to 0.002 of frame area: below that a change is a cursor blink or a
spinner, and treating it as motion makes every window with a caret permanently unsettled.
`signals` lists what was *available* rather than what fired, because quiet from an observer that
was never running is not evidence.

### 7.4 Determinism

`Canonical` normalises before hashing so identical states hash identically. Removed: volatile text
(clock times, ISO dates, elapsed-duration phrases, UUIDs, pointer-shaped hex) and sub-pixel geometry,
quantised to whole points. Kept deliberately: child order, because AX order is focus order and
sorting would hide a reordered tab sequence; and sorted actions and object keys, which have no
meaningful order. The canonical form is a readable indented string rather than an opaque digest,
because it is also what a divergence report diffs.

`proctor_stability` replays a flow N times (default 5) and reports `instability` scaled 0–1 and
`firstDivergence` as the first disagreeing step index. A run that ended early counts as a divergence
at its own length, because stopping is a state difference. When the target is a browser showing a
page, `PageContentDisclosure` says so, because a score there measures the page's churn as much as
the app's (PRO-0038).

### 7.5 Tri-observer

Three sources describe one instant: the accessibility tree, the layer geometry (reflector or AX
frames) and the captured pixels. A disagreement is a finding — an unexposed control, a ghost node,
an invisible-but-focusable element, a stale frame, a wrong hit target — and `Disagreement` records
what each observer said so it is arguable rather than asserted. Smoothing these away would make
Proctor report clean runs on broken UI, which is the failure the whole design exists to prevent.

### 7.6 ProctorReflector

A library embedded in an app you own, behind `#if DEBUG || PROCTOR_REFLECTOR`. Once in,
`proctor_inspect` reads the view and layer hierarchy directly: resolved colours and fonts, corner
radii, opacity, constraints, and both CALayer model and presentation values, with a monotonic render
revision. Two things change: fidelity checking becomes measurement rather than eyeballing, and
settling gets `reflectorIdle`, the only signal with access to the app's own notion of work in
progress. It ships as a SwiftPM library product and speaks its own socket protocol.

---

## 8. The MCP surface

### 8.1 Transports

**stdio** is the default: `proctor-shim` or `proctor-shim serve`, spawned by the host, forwarding
over the Unix socket.

**HTTP** is `proctor-shim serve --remote [--host H] [--port N] [--token T]`, a minimal HTTP/1.1
listener speaking the MCP Streamable-HTTP request/response shape at `POST /mcp`. It forwards to the
same `MCPServer.response(for:)` the stdio path uses, so a tool behaves identically over either wire.
It binds `127.0.0.1:8787` by default and **refuses to start** on a non-loopback host without a
token, because an unauthenticated listener on a routable address is a Mac offered to the network.
The token is read from `--token` or `PROCTOR_MCP_TOKEN` so it need not appear in a process listing.
IPv6 is refused with a message naming the SSH-tunnel alternative. Concurrency is capped at 16
in-flight connections and bodies at 16MB; tool calls serialise at the agent regardless, so the cap
only bounds the front door.

Adding a network front door adds no permission. A remote caller reaches exactly the tools a local
one does, gated by the token.

Methods served: `initialize`, `tools/list`, `tools/call`, `resources/list`, `resources/read`,
`ping`, and the `notifications/initialized` notification.

### 8.2 Tool profiles

A host that needs the core loop should not be handed the whole catalogue as noise, so
`--profile` or `PROCTOR_PROFILE` trims what is advertised. The profiles nest —
`ax ⊂ core ⊂ scripting ⊂ full` — so widening the surface is one step out, and every profile carries
`proctor_apps` (nothing works before attach) and `proctor_doctor` (the run-first tool).

| Profile | Tools advertised |
|---|---|
| `ax` | apps, snapshot, find, menu, act, wait, assert, doctor — 8 |
| `core` | `ax` plus capture, zoom — 10 |
| `scripting` | `core` plus flow, stability, dictionary — 13 |
| `full` | the whole catalogue — 21 |

The profile is chosen where the shim launches, not negotiated in `initialize`: the shim is
stateless per message and the HTTP transport closes each connection, so a negotiated profile could
not survive to the `tools/list` call. **Trimming is discovery only** — `tools/call` still accepts
any tool name, so a profile is a noise control rather than a security boundary. An unrecognised
value falls back to `full` with a warning on stderr rather than a silently wrong surface.

### 8.3 The 21 tools

Each spec carries MCP's `readOnly`, `destructive` and `idempotent` annotations so a host can gate
on them without parsing English. `destructive` and `idempotent` are meaningful only where
`readOnly` is false, which is why read-only tools keep the harmless defaults.

| Tool | Actions / step kinds | Annotations |
|---|---|---|
| `proctor_apps` | `list`, `attach`, `activate`, `detach` | write, non-destructive, idempotent |
| `proctor_snapshot` | tree walk; `sinceRevision`, `maxDepth`, `maxNodes`, `root`, `includeInvisible` | read-only |
| `proctor_find` | predicate query; `match` ∈ `substring`, `exact`, `regex` | read-only |
| `proctor_act` | 22 step kinds: `press`, `setValue`, `focus`, `menu`, `type`, `key`, `scroll`, `increment`, `decrement`, `pick`, `confirm`, `cancel`, `raise`, `close`, `resize`, `move`, `dragPath`, `hover`, `click`, `shortcut`, `appleScript`, `waitFor` | write, **destructive**, non-idempotent |
| `proctor_capture` | window capture; `purpose` ∈ `targeting`, `verify`, `detail`; `annotate`, `grid`, `tileHashes`, `normalize` | read-only |
| `proctor_zoom` | region or node crop at native resolution | read-only |
| `proctor_wait` | `nodeExists`, `nodeGone`, `valueEquals`, `valueContains`, `enabled`, `focused`, `regionQuiet`, `reflectorIdle` | read-only |
| `proctor_assert` | 17 kinds: `exists`, `absent`, `valueEquals`, `valueContains`, `enabled`, `disabled`, `focused`, `hasLabel`, `frameEquals`, `containedIn`, `alignedWith`, `horizontalAlignment`, `minHitSize`, `contrast`, `focusOrder`, `regionMatches`, `agree` | read-only |
| `proctor_flow` | `start`, `stop`, `replay`, `list`, `show`, `delete` | write, **destructive**, non-idempotent |
| `proctor_stability` | N-run replay with per-step markers and optional tile hashes | write, **destructive**, non-idempotent |
| `proctor_inspect` | reflector styles, constraints, layer model and presentation values | read-only |
| `proctor_doctor` | health probe; `requestAccessibility`, `requestScreenRecording` trigger the real consent dialogs | read-only |
| `proctor_unlock` | `status`, `open`, `close`, `unlock`, `relock`, `lock` | write, **destructive**, non-idempotent |
| `proctor_computer` | Anthropic computer-use schema façade | write, non-destructive, idempotent |
| `proctor_openai_computer` | OpenAI computer-use schema façade, batched | write, non-destructive, idempotent |
| `proctor_menu` | menu bar enumeration with key equivalents | read-only |
| `proctor_dictionary` | AppleScript `.sdef` terminology, `summaryOnly` and `refresh` | read-only |
| `proctor_policy` | `status`, `configure`, `approve`, `revoke`, `audit` | write, non-destructive, idempotent |
| `proctor_kill` | `list`, `kill`; `match` ∈ `substring`, `exact`; `force` | write, **destructive**, non-idempotent |
| `proctor_ios` | `list`, `boot`, `open`, `screenshot`, `flow` | write, non-destructive, non-idempotent |
| `proctor_guest` | `list`, `status`, `start`, `stop`, `clone`, `reach`; `provider` ∈ `lume`, `prlctl` | write, **destructive**, non-idempotent |

Granularity is one tool per decision, with actuation batched: a six-step login is one `act` call,
not six round trips plus five settles. The catalogue is defined once in `ProctorCore` and both the
shim's advertisement and the agent's dispatch read it, which is what stops the two drifting.

`proctor_act` also carries `captureEach`, `pointerMarks`, `diffEach` and `record`, so a batch can
produce per-step evidence, a per-step tree diff, and a recorded flow in the same call.

### 8.4 Resources

Four read-only MCP resources re-project state the agent already holds. They add no capability, only
a second way to read what exists, and the shim maps `uri` to the agent's internal `key` from one
table so the two cannot drift.

| URI | Contents |
|---|---|
| `proctor://display` | Attached displays with frame, visible frame and backing scale. Needs no grant. |
| `proctor://windows` | Running applications, and window handles with frames and Space membership for attached apps. |
| `proctor://frontmost` | The foreground app with pid, bundle id and name, plus its main window handle when attached. |
| `proctor://screenshot/latest` | The most recent capture's path and freshness metadata, never the bytes. Cache-only: reading never triggers a capture, so it needs no Screen Recording grant and returns `{cached:false}` until one has been taken. |

### 8.5 The computer-use façades

A model trained on Anthropic's `computer` tool or OpenAI's batched computer tool emits actions in a
fixed schema, and `CUATranslator` maps those onto Proctor's `ActionStep` vocabulary so such a model
drives Proctor unmodified. Two facts shape every mapping. CUA coordinates are relative to the
screenshot the model was shown, and the façade screenshots a single window, so the origin is that
window's top-left and a point maps `global = windowOrigin + cuaPoint / scale`. And the mapped kinds
are Proctor's synthetic ones, so a façade run is frontmost driving by definition and is reported as
`plane: syntheticEvent` rather than dressed up as background-safe.

---

## 9. Machines and witness tiers

Every run says which machine it is on. `Machine` carries `kind` (`host` or `guest`), the guest's
name as its own provider knows it, the provider that reached it, the platform (`macos`, `linux`,
`windows`) and the witness tier. `tier` has **no default**, deliberately and uniquely among its
parameters: a default of `native` would let a construction site that forgot to say describe a Linux
guest as carrying a frame-status channel and an accessibility tree it does not have, and every
assertion the tier gate exists to skip would then evaluate against nothing and pass. Absent is
detectable; wrong is not.

**Native tier** — the Mac host, a macOS guest under `lume`, or a remote Mac over SSH. Full
accessibility tree, `SCFrameStatus`, tri-observer `agree`, fidelity audit, determinism scoring.

**Delegated tier** — Windows or Linux guests, or remote containers through the Cua backend.
Coordinate actuation and screenshots only. Tree-based assertions and `agree` fail closed with
`skipped("Unsupported on delegated tier")`, never a false pass.

Guest sessions carry `gst-` handles, distinct from host window ids. `proctor_guest reach` forwards
the remote agent's Unix socket over SSH `StreamLocal` (`ssh -L local.sock:remote.sock`).

**Proctor owns no VM lifecycle.** Detection is a filesystem read through `ToolLocator`; listing a
guest is a separate act gated behind `proctor_guest`, so a health check never runs `lume` or
`prlctl`. Creating a guest, granting TCC inside one, and cloning the result are things a person
does with the provider's own CLI; the grant-once-then-clone recipe is documented on the guest lane
rather than automated.

**The auto-route gate.** This process cannot yet perform a step *inside* a guest — `reach`
describes the tunnel, it does not attach — so a configured `PROCTOR_GUEST` plus a batch that would
take the host is a **refusal naming the guest**, never a silent host run and never a fallback.
Executing on the host while naming a guest would hand back a verdict that looks fine and measures
the plumbing. A session already marked as a guest is already elsewhere and is not refused.

---

## 10. Lanes

`proctor_doctor` derives five lanes from the grants and the located tools rather than letting each
lane announce itself, so a lane cannot claim to be ready while the thing it needs is missing. Each
reports `ready`, `unavailable` or `unconfirmed`, and `unconfirmed` reads false wherever a boolean is
wanted — a lane nothing has established is not the same as one known to be broken, and sending
somebody to fix the second when they have the first is the defect PRO-0041 closed.

| Lane | Needs | Notes |
|---|---|---|
| `mac` | Accessibility and Screen Recording | Needs no external tool. What stops it is a permission. |
| `browser` | `obscura`, plus `browser-use` when the second lane is named | Advisory only; never affects `ready`. |
| `ios` | `simctl` (Xcode), `maestro` | Deep links plus Maestro flows. |
| `cua` | `cua-driver` | Off unless `PROCTOR_ACTUATION=cua`. |
| `guest` | `lume`, `prlctl` | Located, never executed by a health check. |

`ready` is untouched by every lane, because Proctor drives native macOS applications with no
Obscura, no Xcode, no `cua-driver` and no Maestro. A health report that failed on an advisory tool
would be lying about what is broken.

### 10.1 The browser boundary

Proctor owns native macOS applications. A page in Chrome or Safari is not one: walking its
accessibility tree trades the DOM, computed styles, the console, the network log and a selector that
survives a re-render for a flattened tree and a set of coordinates. When a result's target is a
browser showing a page, it carries a `browser` object naming Obscura as the tool for the page, with
the URL, command templates and Obscura's own measured limits. **Nothing is refused** — the native
chrome around the page (toolbar, tab bar, menus, sheets) stays Proctor's, and a web view inside a
native Mac app is not routed at all, since reaching it means attaching to the host process.

Two facts the object states out loud: Obscura runs its own engine and cookie jar, so following the
advice restarts at a URL rather than continuing that window's signed-in session; and a step into
page content still hashes, but over a browser's render tree.

**Proctor never installs anything.** When Obscura is absent the object says so and carries no
command, because a command in a tool result is something a model will run, and the install is a
download of an unsigned binary by a process holding Accessibility and Screen Recording. The commands
live in the status window, one click from the clipboard, beside a Re-check. Detection reads the
filesystem and never executes what it finds, because the directories a launchd agent must check by
name — `~/.local/bin`, `~/.cargo/bin`, `/opt/homebrew/bin` — are writable by anything.

**An installed web app is an app, not a tab.** A site installed as a Mac application gets its own
bundle identifier; Proctor recognises one, names no browser tool for it, and drives it as an
application. The address is still reported so a caller who disagrees is not guessing.

Two fields let a host gate without reading English. `surface` is `browserWindow` or
`installedWebApp`. `flags` carries five booleans describing whichever instrument the handoff points
at, Proctor included when it is the one driving: `actsOutsideThisWindow`, `autonomous`,
`canActAsThisPerson`, `outsideTheAuditTrail`, `billed`. `canActAsThisPerson` states a capability
rather than an assertion about a particular run, because Proctor cannot see which profile an
operator will give a tool.

### 10.2 The second browser lane

Some of Obscura's limits stop a job rather than degrading it, and a page living inside the browser
itself (`chrome://`, an extension page, DevTools) has no equivalent in its engine. For those Proctor
can name the `browser-use` CLI, with a `why` field saying which rule chose it. Two independent gates
stand in front: `PROCTOR_SECOND_LANE=browser-use` in the agent's launchd environment decides whether
the tool may be **named** at all, and finding the binary decides whether the lane is **usable**.
Unset is Obscura-only.

The switch exists because of what the tool is: browser-use is an autonomous agent, its default local
mode drives a real browser with real credentials, and nothing it does reaches Proctor's audit trail.
It ships **no command templates**, only prose about which mode to run it in — installing a CLI is
consent to have a file, not consent for a process holding Accessibility to name that file to a model
with a shell. Routing is on the URL scheme and nothing else.

Two refusals are deliberate. It is **never a fallback**, because a missing Obscura is a fact about
the machine rather than about the page, so an ordinary web page is never handed to an autonomous
agent. And it is **never pointed at the browser's own configuration, credential, extension or
history pages, or at DevTools**: an agent acting as this person has no business where their saved
passwords live.

### 10.3 The iOS lane

`proctor_ios` lists and boots simulators, opens deep links, screenshots, and runs flows.
The lane exists to prevent a verdict that reports "sent" as if it meant "arrived": measured
2026-08-15, the same `simctl openurl` run twice exited 0 both times with identical process state and
only the second changed nothing on the device. No verdict is computed from exit status alone;
`pixelEvidence` and `changeThreshold` add a pixel witness.

Maestro is a **flow-level seam and deliberately not an `ActuationBackend`** — that protocol performs
a step, Maestro executes a file, and nothing turns a Maestro command into an `ActionStep`. Measured
2026-08-15 with maestro 2.4.0: five identical passing runs produced an identical per-command status
vector and per-command durations spreading 7x on an unchanged command, so the score basis is the
status vector and never the timings.

---

## 11. Supervision

A run that draws nothing and can be halted by nobody is what opting out is opting out of, so
every drawing switch defaults **on** and every capability switch defaults **off**.

### 11.1 The run HUD

A borderless `NSPanel` drawn by the agent process, one per screen, showing the current step in
derived English, a run character, a target badge, the queue state, and Pause and Stop buttons.
Step text is **derived, never supplied** (PRO-0014): text originating outside Proctor — an app's own
accessibility title, or a name a model supplied — travels in a fenced `Object` type carrying its
provenance, is sanitised, and is quoted whichever side it came from, because an app's own title
carries the same clause-injection payload a model's does.

The character has seven states (`idle`, `travelling`, `acting`, `blocked`, `paused`, `finished`,
`error`), shipped at 1x, 2x and 3x inside the binary's resource bundle. An agent holding these
permissions has no business reaching the network to draw itself, and a picture fetched mid-run is a
picture that can fail mid-run.

Pause carries a limit so a forgotten pause cannot park the machine forever: `PROCTOR_HUD_PAUSE_LIMIT`,
default 900 seconds.

### 11.2 The takeover shield and the cursor overlay

Before a batch takes the foreground, a translucent veil and a label appear on every display saying
Proctor is driving this Mac (`PROCTOR_TAKEOVER`). The cursor overlay draws a marker where Proctor
is about to act, in the target's own plane, so a step is visible before it lands
(`PROCTOR_CURSOR`).

`PROCTOR_TAKEOVER_INPUT` is a separate, off-by-default **capability**: a `CGEventTap` that swallows
the person's own keyboard and mouse while a synthetic step is posted, so their typing cannot land in
the app under test. It is the same API a keylogger uses, on a grant this process already holds, so it
takes a second press with the disclosure on screen, and two invariants hold it: **Stop always works**,
and **the block never survives the process**.

Turning a capability *off* never asks for confirmation. A person withdrawing a capability must not be
argued with, and the asymmetry mirrors the defaults'.

The catalogue also pairs each capability with the drawing switch that announces it, and warns when
the pair is wrong. Holding somebody's keyboard with the takeover notice off is a Mac that stops
responding for no stated reason.

### 11.3 Contention yield

A run posting synthetic events holds the one event stream the person's keyboard and mouse go into.
`PROCTOR_YIELD` pauses the run on the latch Pause already uses when a person starts using the machine.

The failure that matters is not missing a person; it is Proctor reading its **own** events as
somebody else's and pausing itself forever, halting every synthetic run on its first step. Three
independent filters keep them apart, each failing toward "this was ours":

1. **Hardware shape.** Measured 2026-08-14: an event Proctor posts carries Proctor's pid in
   `.eventSourceUnixProcessID`; a real hardware event carries 0. So a person's input is an event
   that came from the hardware, not "an event that is not ours" — stating it the other way round
   compiles, passes a test written against it, and in production reads the driven app's own echoes
   as a person.
2. **Our tag.** Every `CGEventSource` the actuator builds carries `ProctorEventTag.value` in its
   user data, and it survives to the event (measured, same date). Independent of (1).
3. **A grace window.** Anything arriving within `graceSeconds` of Proctor's last synthetic post is
   discarded whatever it looks like, because monitors deliver asynchronously and an app can emit its
   own events in response to ours.

Measured and rejected: `CGEventSource.secondsSinceLastEventType(.hidSystemState, …)` is reset by
Proctor's own posts (3.108s → 0.298s across one posted `mouseMoved`), so it cannot separate them.

`PROCTOR_YIELD_INPUT` is the off-by-default capability that observes input to notice a person at the
first keystroke rather than at the next window change; it decays after `PROCTOR_YIELD_INPUT_WINDOW`,
default 10s. It deliberately does **not** require a second press — it intercepts nothing, and a
confirmation there would train people to click through the two that matter.

### 11.4 The run queue

One agent sits behind one socket and any number of MCP clients can connect. Before the queue, two
sessions driving the same Mac interleaved their steps and the second one's synthetic click landed in
whatever window the first had just raised. Three lanes are the whole model:

- **Reads never join the line.** `snapshot`, `find`, `capture`, `menu`, `zoom` and `assert` observe
  without mutating and never reach the step loop. This claims reads never *queue*; it is not a claim
  about the `Session` actor, which admits other work at every settle.
- **Process-directed actuation contends per app.** An accessibility press is IPC to one process, so
  two sessions driving different apps genuinely run in parallel; the same app serialises.
- **Synthetic events contend globally.** One at a time anywhere on the machine, and the run that
  *raises* an app also holds that app's lane, because raising changes where everyone else's clicks
  land. `proctor_apps activate` therefore takes its turn too.

A waiting run has a ceiling — `PROCTOR_QUEUE_WAIT_LIMIT`, default 45 seconds — after which it
returns saying so rather than activating. A person can also drop a waiting run from the HUD. The two
refusals are distinguishable on purpose: a busy-machine refusal is safe to retry, a person's is a
reason to ask first. Every hold names whose run it is (PRO-0037).

### 11.5 Run history

The audit trail is folded back into runs before anything draws it, because a person does not think
in events — the unit is "that thing it just did", one tool call with its steps inside. What leaves
the projection is exactly what a surface draws: no redacted `value` or `script` fingerprints, no
post-state hash, no key ids, and no session handle ids, since `app-3` is meaningless once the agent
restarts. An application is identified by bundle id, the durable identity the policy gate already
judges on.

Retention: `PROCTOR_HISTORY_DAYS` default 14, `PROCTOR_HISTORY_ENTRIES` default 10,000. A permanent
complete record of what an agent did on somebody's Mac is a surveillance artifact whether or not
anyone meant it to be. **The trail rotates in whole rather than pruning from the front**, because
the chain is anchored over its own prefix: removing entries from the front leaves the first survivor
linked to a record that is gone, and the verifier is right to call that broken. The alternative —
a signed truncation record — converts "removing history is unrepresentable" into "removing history
is permitted when signed", and the first property is the one worth keeping. The first record of a
new trail commits to what the old one held.

---

## 12. Governance

### 12.1 The policy gate

`AppPolicy` holds `allow`, `block` and `sensitive` bundle-id sets and **fails closed**: an app that
cannot be identified, or one an allow list does not name, is refused rather than driven. It is inert
until configured — an empty policy allows every app — so installing the mechanism changes nothing
until an operator uses it. A `sensitive` app requires an `ApprovalToken`, which carries its bundle
id, an issue time and an expiry, and is checked against both.

Flow replay and stability replay pass back through the gate rather than around it (PRO-0012): a
recorded flow is a stored program, and a gate that only judged live calls would be bypassed by
recording once.

### 12.2 The audit trail

Four properties, built in four separate pieces because they fail in different places.

**Redaction.** A value that passed through `type`, `setValue` or a script body is stored as
length-plus-SHA-256, never in the clear, so the log proves what was entered without becoming the
biggest secret leak in the system.

**Sealing at rest** (PRO-0013). Each JSONL line is sealed on its own with its own ephemeral key, so
an append stays one `write(2)` of one line and two concurrent appends can never share a nonce.
Sealing takes a **public** key kept beside the log; opening takes the private key in the Keychain.
That asymmetry is required by how the agent runs: it records while nobody is present — between a
restart and the first unlock is exactly when it works alone — so a scheme needing the secret to
append would go dark in the case the trail exists for. What it does not claim: it hides content, not
the existence of entries. Line count, timing and rough size stay visible.

**Chaining and signing** (PRO-0032). Sealing needs only the public key, so anyone who could write the
directory could append a well-formed entry that opened cleanly. Each record is chained to the one
before it and the link is signed. A chain alone catches deletion and reordering but its links are
public and recomputable, so it catches an accident rather than an attacker; a signature alone catches
a forged entry and not a deleted one. Together, an inserted entry has no valid signature, a deleted
one breaks a link, a reordered pair breaks two, and an edited one fails both. `KeyClass` records
whether the signer was `secureElement` or `software` per entry, and the verifier compares that claim
against how the key is actually stored, so a software signer cannot claim the stronger class. A line
carrying no chain fields is reported as pre-signing rather than as forged.

The claim is stated narrowly on purpose: anything running as this user can ask the signer to sign, so
a compromised agent can sign a lie it was told to write. **A clean verdict cannot be manufactured off
this machine, and a fault verdict can always be forced by destroying the key.** Detection, not
prevention.

**What is recorded.** Tool, app, bundle id, window, node, step kind, outcome
(`ok | failed | refused | recommended`), post-state hash, redacted value and script, reason, run id,
sequence, duration, plane, effect, backend, observer, machine token (`host` or `guest:<name>`), and
the lane recommendation Proctor made — so a handoff Proctor recommended is in the record beside the
actions it performed.

### 12.3 The filesystem jail and process control

`PROCTOR_FS_ROOTS` declares the roots a path must land at or under. Resolution goes through
`realpath(3)` and is part of the decision rather than an optimisation, because a lexical check cannot
see a symlink inside the root pointing out of it. A refusal names where the path resolved and which
roots were in force, so a model can act on it rather than retrying. Undeclared roots admit
everything, exactly as an empty policy allows every app.

`proctor_kill` lists and terminates processes for test setup and teardown, by bundle id, name, pid or
substring match, with `force` for `SIGKILL`.

### 12.4 Screen unlock

`proctor_unlock` opens a short, TTL-bounded turn, asks macOS to evaluate the screen-unlock right —
which runs an installed SecurityAgent mechanism, which asks the in-agent broker, which sees the open
turn and allows — then relocks when the turn ends or a human touches the machine. Every unlock is its
own turn; nothing holds the door open across a session, and a crashed client cannot leave it open.

The safety properties live in the pieces around it: the authorization rule keeps
`use-login-window-ui` so a human is never locked out, the broker answers only a verified peer, and
the turn self-expires. The broker starts whether or not the login-path plugin is installed; with no
plugin armed it never receives a connection.

---

## 13. The desktop app (built)

`Proctor.app` starts as a regular app so its first-run window can appear, then demotes itself to
accessory once setup is done. An app that is already an accessory at launch never presents its
SwiftUI `Window` scene, so a first run would show nothing at all. It registers itself as a login item
so the menu-bar icon is present after a reboot; a failure there is logged rather than surfaced,
because a missing login item costs convenience rather than function.

**Walkthrough** — three steps: what Proctor is, the two grants as one hero sheet, and the connect
snippet. The permission step asks macOS for the real consent dialog rather than only linking to
Settings, plays the grant back the moment it lands, and advances on its own once both are granted.
Auto-advance is armed only after the intro, so it cannot skip the step that says what Proctor is.

**Status window** — seven sections: Permissions (what macOS holds about Proctor, which Proctor can
only read), Tools (what is on this machine, with copyable install commands and a Re-check that names
what it checked), Switches (the eight runtime switches with their live values and where each came
from), Activity, Connect (the host configuration snippet), Agent (build identity, restart, relaunch)
and Footer. The switch values come **from the agent over the wire**, because the window is launched
by LaunchServices and the agent by launchd, so the window's own `ProcessInfo` describes a different
process's environment — and would describe it plausibly, which is worse than not knowing.

**Menu bar** — the character when idle, the live tool-in-flight line, the foreground disclosure, and
Pause and Stop, which appear only while there is a run for them to act on. The panel switch is
disabled on an agent launched with `PROCTOR_HUD` off, because that launch runs a bare run loop and a
panel drawn then would carry buttons nobody could click; hiding stays available and reversible within
the launch.

**History window** — the folded run history described in section 11.5.

**Quit means everything off.** Any quit path stops the background agent as well as the window; both
return at the next login, since the LaunchAgent plist and the login-item registration persist. A
relaunch is explicitly not a quit — the agent holds the grants and may be running something.

Rules that must hold in a window are written as pure functions in `ProctorCore`
(`StatusChecks`, `SwitchCatalogue`, `WindowPresentation`, `RunHUDPlacement`), because `Package.swift`
declares no `ProctorUI` test target and `swift test` has no window server, so a rule written in a
view body is a rule this repo cannot prove.

---

## 13A. The design system, and the surface set of record

Every surface in sections 13 through 16 is drawn, in every state, at
`design/surfaces/proctor-surfaces.html`, with its reasoning at
`design/surfaces/proctor-surfaces-spec.md`. **That set is the design of record.** A surface
that disagrees with it is a defect in one of the two, and the disagreement is resolved by
changing one of them rather than by leaving both.

The set holds **51 states across 17 surfaces on three platforms**, plus the state grid, the
destructive-action table and the five flows. It is rebuilt with
`python3 design/surfaces/assemble.py` from `design/surfaces/parts/` and the compiled
terminal frames in `design/surfaces/tui/`.

### 13A.1 Direction

**Invigilator.** Proctor's job is witnessing, so the surfaces take the register of a
certification document: a cool ink-on-paper ground, hairline rules, and a bronze seal colour
confined to three things — the provenance chip, the focus ring, and the one primary action
per view. Red is held out of the rest of the palette so that **Stop is the loudest thing on
any surface carrying it**.

The signature is the **provenance chip**: plane, route, tier and machine in one component,
in the same shape, on every surface that reports a result. Section 2's thesis says a result
carrying no provenance is indistinguishable from a correct one; the chip is that thesis made
visible to the person watching, rather than only to the model reading the wire.

Two looks were rejected deliberately, and both are recorded because they are the defaults a
generative tool reaches for: a warm-paper editorial register, and dark-with-one-acid-accent,
which is the reflex for every developer tool. The runner-up was **Instrument**, a denser
hairline lab-panel register that would have served the queue and history tables better and
the walkthrough worse.

### 13A.2 The label ramp departs from the kit, on purpose

Apple's light secondary label tier at 50% measures **3.98:1** against white and cannot carry
meaning; the tertiary tier at 25% measures **1.83:1** and can never carry text at all. The
same tier names pass in dark and fail in light, which is why the failure is invisible to a
reviewer who checked one appearance.

The set therefore lifts secondary to 68% and tertiary to 56%, and keeps the 25% tier for
exactly the two jobs the platform uses it for — dividers, and the disabled state, which WCAG
1.4.3 exempts and the native grammar requires to dim rather than disappear.

### 13A.3 Tokens

| Token | Light | Dark | Tier |
|---|---|---|---|
| titlebar / unified toolbar | 33 / 52pt | — | kit |
| control regular / large / XL | 24 / 28 / 36pt | — | kit |
| body type | 13pt | — | kit |
| sidebar / row (medium) | 256 / 32pt | — | kit |
| selection / popover radius | 8 / 20pt | — | kit |
| alert button | 228×28pt | — | kit |
| `--win` / `--chrome` | `#FFFFFF` / `#F4F5F7` | `#1E1E1E` / `#2C2C2E` | kit |
| `--ground` / `--sunken` | `#EFF0F3` / `#E9EBEF` | `#17181C` / `#202024` | direction |
| `--ink` / `-2` / `-3` / `-4` | 85 / 68 / 56 / 25% black | 100 / 74 / 60 / 25% white | mixed — see 13A.2 |
| `--accent` / `--accent-ink` | `#8A6224` / `#6F4D1C` | `#D2A059` / `#E4BC81` | direction |
| `--danger` / `--ok` / `--warn` | `#B3261E` / `#1F6B4A` / `#8A5A00` | `#F1897F` / `#74C79B` / `#E3B76A` | direction |
| terminal ground / ink | `#14161B` / `#E9EAED` | same | direction |

Light and dark are **authored independently**. Nothing here is derived by inverting the
other, because an inverted dark scheme is how graphite becomes pure black.

### 13A.4 The terminal frames are compiled, never drawn

The 22 frames behind section 16 were compiled from declarative specs by `tui-design`'s
compiler, which does the cell arithmetic with the same width function a capture is measured
with. That matters because a hand-drawn terminal mock counts characters, and characters are
not cells: `len("🚀 Deploy")` is 8 and it occupies 9, and one wide glyph puts every later
column off by one so the border never closes.

The first compile returned six fit findings — four panels one row short of their own
content, one text block, one table — each a defect a drawn frame would have hidden.

### 13A.5 What the set's own gates report

| Gate | Result |
|---|---|
| `mock_check.py` (mac-craft) | metrics 15/15 · tokens · casing · cursor · keyboard 83 semantic controls, 0 non-semantic · accessibility queries 3/3 |
| `ux-lint.py` (ux-craft) | 5,814 elements · 0 failures · 0 warnings |
| `tui_gates.py` + `tui_design_gates.py` | 22 frames · 0 failures on both suites |

Both HTML linters additionally report contrast failures that all resolve text against one
background the elements are nowhere near — a cascade fallback for selectors whose ancestry a
source-only reader cannot trace. Measured in the render against the actual painted ground,
every flagged pair sits between 5.4:1 and 18.1:1; the three exceptions are the 25% disabled
tier. The spec carries the measured table.

---

## 13B. From mock to SwiftUI

The set is the specification for `Sources/ProctorUI`, and converting it is the work in
`docs/features-to-triage/58-swiftui-conversion-direction.md` and briefs 59–69. Three
constraints decide the method, and they are recorded here because they bind any future
surface work, not only this wave.

**A rule in a view body is a rule this repo cannot prove.** `Package.swift` declares no
`ProctorUI` test target and `swift test` has no window server. So every design decision
becomes a pure value in `ProctorCore` first, with a test, and the view reads it —
the pattern `StatusChecks`, `SwitchCatalogue`, `WindowPresentation` and `RunHUDPlacement`
already follow. The token table above is generated into Swift from the mock's own token
block rather than transcribed, so the two cannot drift.

**Fidelity is measured through ProctorReflector, not through a DOM.** The usual instrument
diffs computed styles on a rendered page; SwiftUI has none, and macOS has no cross-process
computed-style API at all (section 7.6). `ProctorReflector` is the answer the product
already ships: embedded in `ProctorUI` behind `#if DEBUG`, `proctor_inspect` measures
Proctor's own view tree. The conversion is verified by **Proctor driving Proctor**, which is
also the shortest demonstration of the product that exists.

The instrument is narrower than it first appears, and the narrowing is recorded rather than
discovered later. The Reflector walks AppKit views; a SwiftUI subtree appears as its
`NSHostingView` and whatever backing views SwiftUI created, and no resolved SwiftUI modifier
value is readable from outside the framework. So identifiers, roles, geometry and pixels are
settled fully; layer-level style is settled only where SwiftUI materialises it; and everything
else is reported inconclusive with its reason rather than as agreement.

**Every converted control sets a durable accessibility identifier** from a `ProctorCore`
constant. The Cua research found that an opaque per-snapshot element handle survives replay
only by re-clicking absolute coordinates, which is exactly what a layout change breaks;
Proctor's counter-claim is the durable selector, and the app cannot make that claim about
other people's software while its own views expose nothing to select on.


---

## 14. The terminal surface today (built, and narrow)

`proctor-shim` is the only command-line entry point, and it is deliberately small: everything it
does is either forwarding or the one thing it is allowed to write.

| Command | Effect |
|---|---|
| `proctor-shim [serve]` | Speak MCP over stdio, forwarding to the agent. |
| `proctor-shim serve --remote [--host H] [--port N] [--token T]` | Speak MCP over HTTP. |
| `proctor-shim serve --profile P` | Advertise `ax`, `core`, `scripting` or `full`. |
| `proctor-shim install` | Write `~/Library/LaunchAgents/app.fledgeling.procter.agent.plist`, bootstrap and kickstart it, then print the host config. |
| `proctor-shim uninstall` | Bootout and remove the plist. |
| `proctor-shim status` | Report whether the agent is reachable; exit 0 when it is. |
| `proctor-shim --version` / `--help` | Build descriptor; usage. |

Supporting scripts: `scripts/install.sh` (build, sign, notarise, install — notarising by default),
`scripts/notarize.sh`, `scripts/build-app.sh`, `scripts/uninstall.sh`, `scripts/doctor.sh`,
`scripts/test.sh`, `scripts/check-release-version.sh`.

**The gap this leaves.** No capability of the product is reachable from a shell. A person cannot
snapshot a window, replay a flow, run an assertion or read the queue without an MCP host in the loop,
and a machine reached over SSH has no supervision surface at all, because the HUD and the status
window both need a GUI session on the machine being driven. Sections 15 and 16 specify the two
surfaces that close that.

---

## 15. Proposed — the `proctor` operator CLI

**Status: not built.** Nothing in `Sources/` implements this today; `proctor-shim` covers only the
seven commands in section 14.

Drawn in the surface set at `#cli/catalogue/all`, `#cli/doctor/human`, `#cli/doctor/json`,
`#cli/act/ok`, `#cli/act/refused`, `#cli/act/assertfail`, `#cli/act/stability` and
`#cli/install/flow`. Specified for delivery in `docs/features-to-triage/68-the-operator-cli.md`.

### 15.1 Why

Four jobs currently have no path. Debugging a selector that fails needs a model in the loop to issue
each call. CI cannot run a flow and assert on the result without embedding an MCP client. A campaign
cannot be scripted in a shell. And a defect report cannot carry a reproduction command, because there
is no command to carry.

The agent already exposes every capability over a socket with a stable request/response contract, so
the CLI is a second front end to work that exists rather than new capability.

### 15.2 Requirements

**One binary, one verb per tool.** `proctor <tool> <action> [flags]`, covering the 21 tools in
section 8.3 — `proctor apps list`, `proctor snapshot --window w:1`, `proctor find --role AXButton`,
`proctor act --step click --node …`, `proctor capture --purpose verify`, `proctor assert`,
`proctor flow record|replay|list|show|delete`, `proctor stability`, `proctor doctor`,
`proctor policy status|configure|approve|revoke|audit`, `proctor guest`, `proctor ios`,
`proctor menu`, `proctor dictionary`, `proctor kill`, `proctor unlock`, `proctor inspect`,
`proctor zoom`, `proctor wait`. The existing `install`, `uninstall`, `status` and `serve` verbs move
under the same binary, with `proctor-shim` kept as an alias so existing host configurations keep
working.

**A CLI call is not a privilege bypass.** It reaches the agent over the same socket, passes the same
policy gate, takes a lane in the same run queue, appears in the same audit trail and run history, and
is disclosed on the same HUD. The only thing that differs is who called. Records must be able to say
that, so the audit trail needs an actor field distinguishing a CLI caller from an MCP one.

**Two output contracts.** Human-readable tables by default. `--json` emits the exact wire object the
MCP tool returns, unaltered, so a script and a model see the same bytes and a bug reproduces
identically through either front end.

**Exit codes carry the verdict**, because a CI step reads an exit code rather than prose: `0` the call
succeeded and any assertion passed, `1` the call succeeded and an assertion or determinism check
failed, `2` usage error, `3` agent unreachable, `4` refused by the policy gate or the guest-route
gate, `5` refused for a missing grant or lane.

**Handle resolution sugar.** Handles live in the agent and survive between invocations, so a
stateless CLI process can use them, but a person should not be copying `win:3:3` by hand.
`--app com.apple.TextEdit` and `--window front` resolve at call time and print the handle they chose.

**It never installs anything**, for the reason section 10.1 gives: the same process holds
Accessibility and Screen Recording. It prints commands for a person to run.

**`proctor doctor --json` is the CI readiness probe**, exiting non-zero when `ready` is false, with
`--lane <name>` to gate on one lane rather than the whole report.

**Shell completion** for zsh and bash, generated from the tool catalogue so it cannot drift.

### 15.3 Open decisions

Whether `proctor act` accepts a step batch as JSON on stdin, as repeated flags, or both. Repeated
flags are pleasant for one step and unusable for six, which is the shape the batching design exists
for; stdin JSON is the honest match for a batch and awkward interactively.

Whether the CLI holds a session identity across invocations. Attachment state lives in the agent, so
handles already persist, but "which session is this" affects queue attribution and the hold
attribution the HUD shows. A per-invocation session makes every CLI call a new session in the queue;
a stable per-terminal session needs somewhere to keep the id.

### 15.4 Out of scope for the CLI

It does not gain a capability the MCP surface lacks, it does not embed a model, and it does not
implement its own actuation or capture path.

---

## 16. Proposed — the `proctor tui` supervision surface

**Status: not built.** Every screen is compiled at `design/surfaces/tui/` — 11 screens at
100×30 and 80×24, 22 frames, all passing both terminal gate suites. Specified for delivery in
`docs/features-to-triage/69-the-supervision-tui.md`.

### 16.1 Why

Supervision today is a floating panel and a SwiftUI window, and both need a GUI session on the
machine being driven. The remote HTTP transport and the SSH `StreamLocal` guest reach both created
the case they do not cover: an operator driving a Mac over SSH sees no run line, no queue, no
history, and has no Stop button. The kill switch exists and is unreachable, which is the same failure
the HUD's event-loop work (PRO-0015) fixed locally.

### 16.2 Requirements

**A client, never a privileged process.** It speaks the same socket the shim does, holds no TCC
grants, and needs neither Accessibility nor Screen Recording itself. It must run over SSH on a
machine with no window server.

**Five panes**, each already backed by data the agent produces:

| Pane | Source |
|---|---|
| Run | The derived step description the HUD draws, plus plane, route, target and elapsed. |
| Queue | The three lanes, who holds each, the waiting count, and each hold's attribution. |
| Readiness | `proctor_doctor`: grants, the five lanes, located tools, secure-input state, build identity, machine. |
| History | The folded run projection of section 11.5. |
| Switches | The eight switches with their live values and the source each came from — read-only. |

**Stop and Pause write the same latch.** `RunControl.shared` is what the panel's buttons write and
what the run loop reads, so a terminal Stop is the same kill switch rather than a second one. Drop-a-
waiting-run is available for the same reason a person can drop one from the HUD.

**Updates are pushed, not polled.** The scheduler already exposes `observe`, and a supervision
surface that polls is one that shows stale state exactly when a run is moving fastest.

**Degradation is explicit.** An unreachable agent shows the same reason and the same remedy
`proctor status` prints, and the pane says the data is stale rather than showing the last good frame
as though it were current.

**No images.** The character has a text state per the seven states in section 11.1, and layout works
at 80 columns.

### 16.3 Open decisions

Whether the TUI may attach over the remote HTTP transport as well as the local socket. It would make
supervision available wherever the tools are, and it would put Stop behind a bearer token on a
network front door — a stronger gate than the local socket has, and one that needs deciding rather
than inheriting.

Whether a read-only mode is worth having, for watching a run without the ability to halt it.

### 16.4 Out of scope for the TUI

It does not issue tool calls, author flows, or edit policy. It watches and it halts.

---

## 17. macOS platform decisions and constraints

Each row is a decision forced by the platform, with what it costs. The measured ones carry their
date; the rest are structural.

| Constraint | Decision it forced |
|---|---|
| TCC attributes a grant to the *responsible* process, walking up the ancestry | The privileged half is a launchd user agent with a fixed path and a team-scoped designated requirement, not a host-spawned helper (§5.2). |
| Ad-hoc signing ties grants to exact bytes | Every shipped build is Developer ID signed, notarised and stapled, so grants survive an upgrade (§20). |
| Claiming an activation policy registers the process with LaunchServices | The agent carries a second identity in a `__TEXT,__info_plist` section, or `open -a Proctor` activates a windowless process and the app cannot be opened while its agent runs (§5.2). |
| `AXObserver` notifications need a live `CFRunLoop` on the main thread | The run loop owns `main`; the socket accept loop runs on its own threads (§5.5). |
| `CFRunLoopRun()` does not drain the event queue | The agent runs `NSApplication.shared.run()`, or the Stop button can never receive a click (§5.4). |
| AppKit raises `NSException`; Swift cannot catch one; an uncaught one aborts | `ProctorCatch`, a one-function Objective-C target, since SwiftPM has no mixed-language targets (§5.4). |
| One WindowServer event stream per session, delivered to the frontmost app | Synthetic steps need the foreground, contend globally in the queue, and are reported as a weaker proof than accessibility ones (§6.1, §11.4). |
| Secure Event Input blocks synthetic posts | Process-directed actuation is the default plane and is unaffected; `secureEventInputActive` is on the doctor report. |
| AX reports success for a set the application then discards | Every write is read back; `stateHash` comparison is documented as the real check (§6.2). |
| No cross-process computed-style API exists on macOS | `proctor_inspect` returns `reflectorUnavailable` rather than approximating; ProctorReflector removes the ceiling for apps you own (§7.6). |
| Chromium and Electron apps expose no web tree until asked | Attach applies `AXManualAccessibility` and reports that it did, since it is detectable and changes the app's performance (§7.1). |
| Chrome may still return an empty web tree | The tool description names `--force-renderer-accessibility` as the remedy. |
| An installed web app carries a `com.google.Chrome.app.…`-shaped bundle id | Recognised as an application and driven directly; no browser tool is named for it (§10.1). |
| Proctor's own posts reset `secondsSinceLastEventType(.hidSystemState)` (3.108s → 0.298s, measured 2026-08-14) | Contention detection uses source pid, an event tag, and a grace window instead (§11.3). |
| A posted event carries Proctor's pid; hardware carries 0 (measured 2026-08-14) | A person is detected by hardware provenance, never by "not ours" (§11.3). |
| Apple silicon hard-caps concurrent macOS VM guests at two | Scaling is across windows within a session; more real parallelism is a hardware purchase (§3). |
| A synthetic click can land on the HUD's own Stop button | The panel ignores mouse events while a synthetic step is in flight (§5.4). |
| ScreenCaptureKit cannot photograph a window with `sharingType = .none` | The HUD and takeover overlay are excluded from captures by design, so a capture of the app under test is not contaminated by Proctor's own chrome — and two campaign cases are `n/a` rather than passing (§21). |
| `simctl openurl` exits 0 whether or not the deep link changed anything (measured 2026-08-15) | No iOS verdict is computed from exit status alone (§10.3). |
| Maestro per-command durations spread 7x on an unchanged command (maestro 2.4.0, measured 2026-08-15) | The determinism basis is the per-command status vector, never timings (§10.3). |
| 1Password autofill is `AXButton` in Chrome and `AXMenuItem` in Safari; only the Chrome button honoured `press` (measured 2026-08-16) | Documented in the tool description, with `stateHash` comparison as the check. |
| Gemini charges vision by 768-pixel tiles | The `targeting` tier caps the long edge at exactly 768 (§7.2). |
| Newlines occur throughout captured UI text | The socket frames with a 4-byte length prefix rather than newlines (§5.3). |
| The status window and the agent are different processes with different environments | Switch values travel over the wire from the agent; the window never reads its own `ProcessInfo` for them (§13). |
| Linker settings propagate to anything linking the target, including the test bundle | The agent's `-sectcreate` flag is release-only, after it was measured putting `LSUIElement` into the test process (§5.2). |

---

## 18. Configuration reference

Eight switches have a home in the status window (`SwitchCatalogue`). Drawing switches default **on**;
capability and lane switches default **off**, and for a capability, **off wins from either source**,
so a person can always decline one.

| Variable | Class | Timing | Effect |
|---|---|---|---|
| `PROCTOR_HUD` | drawing | live | The run panel with Pause and Stop. |
| `PROCTOR_CURSOR` | drawing | next start | A pointer drawn where Proctor is about to act. |
| `PROCTOR_TAKEOVER` | drawing | next start | The tint and label on every display while Proctor drives. |
| `PROCTOR_YIELD` | drawing | next start | Pause a run when somebody starts using the machine. |
| `PROCTOR_YIELD_INPUT` | capability | next start | Observe input to notice a person at the first keystroke. |
| `PROCTOR_TAKEOVER_INPUT` | capability | next start | Event tap swallowing the person's input during a synthetic step. Second press required. |
| `PROCTOR_SECOND_LANE` | lane | next start | `browser-use` — may the second browser lane be named. Second press required. |
| `PROCTOR_ACTUATION` | lane | next start | `cua` — delegate steps to `cua-driver`. |

Deliberately not in that card, because a one-click bypass of a signature check does not belong beside
a drawing toggle: the numeric tuning variables, the policy and jail configuration, and the two Cua
preflight bypasses.

| Variable | Default | Effect |
|---|---|---|
| `PROCTOR_SOCKET` | derived | Overrides the socket path for agent and shim at once. |
| `PROCTOR_PROFILE` | `full` | Advertised tool profile. |
| `PROCTOR_MCP_TOKEN` | unset | Bearer token for the HTTP transport. Required for a non-loopback bind. |
| `PROCTOR_GUEST` | unset | The guest a takeover batch should land on. Arms the auto-route refusal gate. |
| `PROCTOR_FS_ROOTS` | unset | Filesystem jail roots. Unset admits everything. |
| `PROCTOR_QUEUE_WAIT_LIMIT` | 45s | Ceiling on how long a run waits for a lane. |
| `PROCTOR_HUD_PAUSE_LIMIT` | 900s | Ceiling on a pause. |
| `PROCTOR_HISTORY_DAYS` | 14 | Audit retention window. |
| `PROCTOR_HISTORY_ENTRIES` | 10,000 | Audit retention count. |
| `PROCTOR_YIELD_INPUT_WINDOW` | 10s | Decay window on the input-watch signal. |
| `PROCTOR_CUA_TRANSPORT` | endpoint | `oneshot` selects the per-call transport. |
| `PROCTOR_CUA_ALLOW_UNSIGNED` | off | Bypass the driver signature check in preflight. |
| `PROCTOR_CUA_ALLOW_UNSUPPORTED` | off | Bypass the driver version check in preflight. |
| `PROCTOR_REFLECTOR` | off | Compiles ProctorReflector into a non-DEBUG build. |

Build and test only: `PROCTOR_SIGN_IDENTITY`, `PROCTOR_NOTARY_PROFILE`, `PROCTOR_SKIP_NOTARIZE`,
`PROCTOR_FORCE_BUILD`, `PROCTOR_PLIST`, `PROCTOR_CHANGELOG`, `PROCTOR_REGENERATE_TOOLCHAIN`,
`PROCTOR_TEST_LOG`, `PROCTOR_LIVE_MAESTRO`, and the generated
`PROCTOR_TOOL_NAMES` / `PROCTOR_TOOL_DIRECTORIES` / `PROCTOR_TOOL_COMPANIONS` arrays in
`scripts/generated/toolchain-search.sh`.

---

## 19. Non-functional requirements

**Concurrency.** Swift 6 strict concurrency across every target: `Sendable` conformance, actor
isolation, and no synchronous lock held across a suspension point. The decision halves of every
feature are pure values with no clock they were not handed, no filesystem and no actor, which is what
makes the queue model, the canonical hasher, the CUA translator, the policy gate, the jail, the guest
parsers, the iOS verdict ladder and the Maestro score basis provable on a machine with no Xcode, no
grants, no window server and none of the external tools installed.

**Latency.** A multi-step batch is one socket round trip. Settling is signal-driven rather than timed,
so a quiet app returns as soon as both observers agree rather than after a fixed sleep. Captures
default to a purpose-sized frame rather than the vision ceiling.

**Resource behaviour.** The HTTP front door caps at 16 concurrent connections and 16MB bodies. The
audit trail rotates at 14 days or 10,000 entries. A frame over the wire limit is refused with a
remedy rather than truncated.

**Failure posture.** The policy gate, the jail, the guest route and the witness tier all fail closed.
A grant that could not be confirmed reads as `unconfirmed` rather than as granted or denied, and
`unconfirmed` reads false wherever a boolean is required.

**Isolation.** No tool result carries a shell command for an install. No health check spawns a
subprocess. No text produced by an external tool reaches a tool result — only Proctor's own sentence,
the failing stage, and values Proctor parsed, because a child's stdout is prompt injection on the
first call a model makes.

---

## 20. Packaging, signing and release

Every build that leaves the machine is Developer ID signed with the hardened runtime, notarised with
Apple, and stapled. This is not a distribution nicety: the TCC grants key on the team-scoped
Developer ID signature, so a signed build keeps its grants across upgrades, while ad-hoc signing ties
them to the exact bytes and throws them away on the next rebuild. Ad-hoc is for a throwaway build run
once on the build machine.

Three paths must stay in step, because a release that skips notarisation reaches users as a Gatekeeper
block:

- `scripts/install.sh` — auto-detects the Developer ID identity and notarises by default, keychain
  profile `proctor`; `PROCTOR_SKIP_NOTARIZE=1` for a local-only build.
- `scripts/notarize.sh` — submits and staples, taking either a local keychain profile or an App Store
  Connect API key from the environment.
- `.github/workflows/release.yml` — builds, signs, notarises, staples and publishes on a `v*` tag.

`scripts/build-app.sh` fails the build when the agent binary ships without its `__TEXT,__info_plist`
section or with a signing identifier that is not the app's.

`CHANGELOG.md` follows Keep a Changelog and SemVer, and its heading format is load-bearing:
`release.yml` extracts the section matching the tagged version, so a heading it cannot match ships
empty release notes. Entry prose goes through the `create-luke-content` skill in the `marketing`
format rather than being written by hand.

Bundle configuration: `LSMinimumSystemVersion` 14, `LSUIElement` false (the app demotes itself at
runtime), `NSAccessibilityUsageDescription` and `NSScreenCaptureUsageDescription` present. Verified
2026-08-19 on the installed artifact: `spctl -a -vv /Applications/Proctor.app` returns accepted,
source `Notarized Developer ID`, identity `Developer ID Application: Luke Rhodes (H4HGFL52W7)`, and
`stapler validate` passes.

---

## 21. Quality gates and current measurements

| Gate | Requirement | Last measured |
|---|---|---|
| Unit and integration suite | `swift test` green, no failures, no timeouts | **1,527 tests in 176 suites, 10.576s**, 2026-08-19 |
| Feature backlog | Every ledger item merged or retired with a recorded reason | 61 merged, 2 retired of 63 (PRO-0031 absorbed by PRO-0050; PRO-0039 retired) |
| UI test campaign | Every armed case passes or is `n/a` with a structural reason | **26 pass, 2 n/a of 28**, all 28 armed, 2026-08-19 |
| Surface set | The design of record passes its own gates | ux-lint 0/0 · 22 terminal frames clean on both suites · `mock_check.py` metrics 15/15, 2026-08-19 |
| Gatekeeper | Installed bundle accepted and stapled | Accepted, `Notarized Developer ID`, 2026-08-19 |

Acceptance evidence is Swift-shaped rather than Playwright-shaped: a red-then-green test per
acceptance clause plus the affected-test sweep. "Verified by code reading" is not acceptance.

Two campaign cases are permanently `n/a` and must not be restored to `pass` on a substitute artifact.
CASE-0008 (run HUD raster) and CASE-0010 (takeover shield raster) are structurally unreachable,
because both surfaces set `sharingType = .none` so ScreenCaptureKit cannot photograph them. That
exclusion is deliberate — evidence must not change because somebody was watching — so the correct
campaign state is an unreachable oracle rather than a pass proved against a design sprite or a
transparent frame. Measured: window-scoped capture of the shield returned `SCFrameStatus=complete`
frames that were 100% transparent.

`docs/test-campaign/ledger.md` and `REPORT.md` still describe the pre-fix run (23 pass, 3 fail) and
are stale against `cases.json` and `strict-ratchet.json`, which record the three resolutions dated
2026-08-19. Regenerate both before quoting them.

---

## 22. Open work

**In the working tree, not yet committed.** `Sources/ProctorCore/WindowPresentation.swift` and its
tests, plus the `ProctorUIApp` reopen wiring, close the defect where a closed status window could not
be reopened through `proctor_apps activate` or `open -a` — AppKit's `hasVisibleWindows` reads true
while only the menu-bar extras item is up, so reopen activated a process showing nothing. Also
uncommitted: `docs/test-campaign/`, `scripts/build_test_campaign.py`, `scripts/campaign/`,
`design/surfaces/` and the `vendor/fledgeling-plugins` submodule.

**Wave 9 is specced and unscheduled.** `docs/features-to-triage/58-swiftui-conversion-direction.md`
plus briefs 59–69 convert the surface set to SwiftUI: the token generator, the fidelity harness,
seven surface conversions, and the two proposed binaries in sections 15 and 16. Ids are not yet
allocated in `docs/feature-specs/LEDGER.md`, whose last allocated is 63. Build order is stated in
the direction file and is not brief order — the fidelity harness (brief 67) is built second,
because the fidelity records for the surface briefs are unwritable without it.

**Recorded and not scheduled**, carried out of the wave-6 sweep as questions rather than work:

- A model told "Obscura is missing" may install it anyway, and Proctor cannot remove a model's reach
  by withholding a command (from PRO-0023).
- The takeover overlay signals *mechanism* rather than *consequence*, so an all-accessibility run can
  delete a file through `AXPress` in silence (from PRO-0026, finding 10).

**Child work logged in specs and not promoted:** the per-lane readiness block and the policy-posture
block are on the wire and unrendered in the status window; the walkthrough's "Already allowed? Open
System Settings" line is unresolved from PRO-0041; a stale *granted* permission row carries no
caveat, deliberately, and whether it should is open; and the Cua client's child-process descriptor
and process-group hygiene was accepted as child work from PRO-0050's out-of-family review.

---

## 23. Non-goals

**Proctor installs nothing.** Not Obscura, not `browser-use`, not `cua-driver`, not Maestro. It
detects by reading the filesystem, never by executing what it finds, and it prints commands in the
status window where a person runs them.

**Proctor does not drive pages.** A page in a browser goes to Obscura with the reasons stated; the
native chrome around it stays Proctor's. A web view inside a native app is not routed at all.

**Proctor owns no VM lifecycle.** Creating a guest, granting TCC inside it and cloning the result are
done with the provider's own CLI.

**Proctor reads no mail.** When a mail MCP server is connected to the same host, an emailed code can
be read from it and fed back through `setValue`, but those tool names are not Proctor's and `doctor`
does not report them.

**The audit trail claims detection, not prevention.** Anything running as this user can ask the signer
to sign, so a compromised agent can sign a lie it was told to write. Sealing hides content, not the
existence, timing or rough size of entries.

**Tool profiles are noise control, not a security boundary.** `tools/call` accepts any tool name
whatever profile is advertised.

**The `policy` block in `proctor_doctor` reports shape and posture, never rules.** It carries no
bundle id, no path, no key id and no token, and it is described as a convention rather than a
boundary.

**No automatic lane fallback, anywhere.** A missing Obscura never promotes a page to the autonomous
lane. A failing native step never selects the Cua backend. A configured guest never silently runs on
the host. A default that changes when some condition becomes true contaminates a determinism score
across runs exactly as a mid-flight fallback contaminates one within a run, and worse, because nobody
chose it. Moving a default is a release with notes saying so.

**`ready` does not depend on any optional tool.** Proctor drives native macOS applications with no
Obscura, no Xcode, no `cua-driver` and no Maestro.

---

## 24. Traceability

The 63 feature items are recorded in `docs/feature-specs/LEDGER.md` with one spec at
`docs/specs/spec-PRO-NNNN.md` and, where one was written, a plan at `docs/plans/plan-PRO-NNNN.md`.
`ORCHESTRATOR.md` carries the wave structure, the dependency order, the merge commits and the
decisions that later work must not re-litigate.

| Wave | Items | What it delivered |
|---|---|---|
| 1–2 | PRO-0001 … 0010 | CUA façades, set-of-marks, menu key equivalents, scripting dictionary, policy gate and audit trail, capture normalisation, zoom, MCP resources, process kill and FS jail, pointer overlay |
| 3 | PRO-0011 … 0017 | Derived step descriptions, stability pointer markers, re-gated replay, audit encryption, the run HUD panel, the multi-session queue, the character assets |
| 4 | PRO-0018 … 0022 | Contention yield, foreground disclosure, Obscura routing, the menu bar switch, the drawing-fault barrier |
| 5 | PRO-0023 … 0028 | Obscura install offer, the second browser lane, background preference and in-plane pointer, the takeover overlay, the idle character, Re-check honesty |
| 6 | PRO-0029 … 0042 | The switch catalogue, build identity, the signed audit chain, Stop reachability, browser catalogue determinism, hold attribution, the reopen and doctor-hang fixes, alignment assertions |
| 7 | PRO-0043 … 0055 | Cua as an actuation backend, delegated gating and supervision, run history, iOS deep links, Maestro flows, whole-toolchain doctor, the native-planes decision, gate stability |
| 8 | PRO-0056 … 0063 | Machine identity, witness tiers, lume and prlctl providers, `proctor_guest`, SSH reach, the auto-route gate, the machine-aware overlay, purpose-sized captures |

---

## 25. Glossary

**Plane** — the mechanism a step travelled through: `accessibility`, `declared`, `appleEvents`,
`syntheticEvent`, `routedEvent`, `unknown`. Coarse, because `ForegroundReport` counts on it.

**Route** — how a step got there within its plane: `action`, `valueWrite`, `selectedText`,
`scrollBar`, `scrollAction`, `eventStream`, `appleEvent`, `declared`.

**Backend** — which implementation performed the step: `NativeActuationBackend` or
`CuaActuationBackend`. Chosen once per session and immutable.

**Lane (toolchain)** — a capability this machine may or may not have: `mac`, `browser`, `ios`, `cua`,
`guest`. Derived from grants and located tools.

**Lane (queue)** — what a run contends for: one app's accessibility plane, or the single system event
stream. Reads take no lane.

**Witness tier** — how much of Proctor's observation a machine supports: `native` or `delegated`.

**Machine** — where a run lands: the host, or a guest named by its provider.

**Settle** — the conjunction of independent quiet signals after a step, with a reason naming which
were available.

**Instability** — distinct canonical states over N replays, scaled 0 to 1.

**First divergence** — the first step index at which two replays disagreed.
