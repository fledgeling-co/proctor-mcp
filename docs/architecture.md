# Architecture

Read this before changing anything in the transport, the actuation path, the
settle logic or the hashing. Each of those is load-bearing for a reason that is
not visible from the code alone.

## Process model

```
  MCP host (Claude Code, an editor, an SDK client)
      | spawns, stdio
      v
  proctor-shim ..................... no TCC grants, no state
      | connects, AF_UNIX SOCK_STREAM
      | ~/Library/Application Support/app.fledgeling.procter/agent.sock
      | 4-byte big-endian length prefix, then JSON
      v
  proctor-agent .................... inside ~/Applications/Proctor.app
      | launched by launchd as gui/$UID/app.fledgeling.procter.agent
      | -> its own responsible process, so TCC grants attach HERE
      |
      +-- AXUIElement ............. accessibility tree, observers, actuation
      +-- ScreenCaptureKit ........ window-scoped capture
      +-- CGEventPost ............. synthetic events, foreground only
      +-- Apple Events / shortcuts  declared app contracts
      +-- ProctorReflector client   styles and idle, apps you own only
```

The shim is disposable. It holds no permissions, so nothing is lost when a host
kills it, and running several hosts at once costs nothing but sockets.

The agent is long-lived. Retained `AXUIElement` references, warm trees and live
observers survive between tool calls, which is what lets a retained element keep
resolving after its window moves to another Space. A fresh enumeration would not
find it.

The grant follows the agent. macOS attributes a TCC grant to the responsible
process, walking up the process ancestry. A helper spawned by a host inherits
the host's identity; a helper under `node` hands accessibility to every Node
script on the machine; a helper from a temporary path has no stable designated
requirement and re-prompts on every version bump. launchd starts the agent with
no such ancestry, so the grant attaches to `app.fledgeling.procter` at a fixed
path and survives host changes and upgrades.

The agent has two identities, and they are not the same identity. To TCC it is
the application: every nested binary is signed `-i app.fledgeling.procter`, so
the designated requirement names that identifier and the team and carries no
path, which is what carries Accessibility and Screen Recording across an
upgrade. To LaunchServices it is `app.fledgeling.procter.agent`, declared in a
`__TEXT,__info_plist` section linked into the binary from
`Apps/Proctor/AgentInfo.plist`.

The second one exists because the first one is not enough. The agent claims the
accessory activation policy on its first line, which registers it with
LaunchServices; while it registered under the app's identifier, `open -a Proctor`
found a live instance, activated a process with no window, and exited 0. Proctor
could not be opened at all while its own agent was running. Separating the two
identities fixes that without touching the signature, which is the half a person
would have paid for — `scripts/build-app.sh` fails the build if the agent ever
ships without its own section, or with a signing identifier that is not the
app's.

Both sides derive the socket path from `Wire.socketPath`, so neither can drift
from the other. `PROCTOR_SOCKET` overrides it for both at once, which is how a
test binds a throwaway socket instead of the real one. Framing is a 4-byte
big-endian length followed by the payload; newline framing loses to captured
text containing newlines, which this data is full of.

## Two actuation planes

Actions travel through one of two fundamentally different mechanisms, and which
one ran changes what the result proves. `ActuationPlane` is therefore on every
step result, never inferred.

**Process-directed actuation** — `declared` (AppleScript sdef, the `shortcuts`
CLI), `accessibility` (`AXUIElementPerformAction`,
`AXUIElementSetAttributeValue`), `appleEvents`. These address a named element in
a named process. They do not go near the WindowServer event stream, so they:

- reach non-frontmost, occluded and other-Space windows,
- do not steal focus,
- are not blocked by Secure Event Input,
- and are unaffected by what the user is doing at the time.

This is the default plane, and it is what makes background testing possible.

**Event-stream injection** — `syntheticEvent`, via `CGEventPost`. There is one
event stream per session and it goes to whatever is frontmost. So these actions
need the target foreground, steal focus, are blocked by Secure Event Input, and
race any human at the keyboard. The step kinds `click`, `hover` and `dragPath`
have no accessibility equivalent and must use this plane.

The distinction is not a performance detail. A test that passed via
`syntheticEvent` proves something weaker than one that passed via
`accessibility` — it proves the app responds when it owns the screen, not that
the control is reachable. Never collapse the two into a single "it worked".

**The route, beside the plane.** `ActuationPlane` stays coarse because
`ForegroundReport` counts `syntheticEvent` on it, and splitting it would change
what "this run took the foreground" measures. But two steps can both report
`accessibility` and have got there differently, so `StepResult.route` names how:
`valueWrite`, `selectedText`, `scrollBar`, `scrollAction`, `action`,
`eventStream`, `appleEvent`, `declared`. That is what makes "an attribute write
was found rather than the foreground being taken" visible instead of inferred.
`type` and `scroll` each hold more than one accessibility route and try all of
them before conceding, and every write is judged by reading it back, because AX
reports success for a set the application then discards.

## The actuation backend seam

Since PRO-0044 the two planes above are one *backend* rather than the only way a
step can be performed. `ActuationBackend` has a single implementation on each
side of the seam: `NativeActuationBackend`, which forwards to the planes
described above, and `CuaActuationBackend`, which delegates to `cua-driver`. The
native one is the default and the delegated lane is chosen with
`PROCTOR_ACTUATION=cua`.

**Actuation is delegated; observation is not.** Proctor keeps its own
ScreenCaptureKit path, its own frame-status reporting and its own accessibility
walk, because a driver's screenshots carry no frame-status metadata and its own
documentation records that its tree is unreliable on some surfaces. A layer whose
product is catching other people's silent failures needs at least one channel it
can trust. So the backend is told what to strike and asked what it did, and is
never the authority on what is there or on what changed.

**A kind's plane is a question for the backend, not a property of the step.**
Proctor's own actuator can express a click only as a post into the shared event
stream, which is why `.click`, `.key`, `.hover` and `.dragPath` need the
foreground. That is a fact about this actuator rather than about clicking, so the
refusal, the foreground disclosure and the queue's lane demand all ask
`backgroundCapability(for:)` rather than consulting a list of kinds. The native
backend's answers reproduce the old lists exactly.

**Two more planes exist because a delegated step can be delivered in a way the
original four cannot describe.** `routedEvent` is an injected event delivered to
one process rather than to the shared stream: background-safe, and not the
accessibility plane. `unknown` is a step performed through a delivery mode this
build does not recognise, and it makes `ForegroundReport.note` non-nil, because
`note == nil` is the signal callers already read for "nothing to disclose".

**Addressing crosses the boundary by identity, never by position.** A target is
matched into the backend's view through its `(role, label)` ancestry, both sides
must agree about the element before anything is struck, and a target that moved,
is ambiguous, or cannot be seen is refused. No coordinate is substituted for an
element that failed to resolve, because a match resting on a position replays by
striking an absolute point.

## Settling

Settling is a conjunction of independent signals, never a sleep. `SettlePolicy`
sets the thresholds; `SettleReport` says what actually happened, including which
signals were even available.

The signals, ranked by how honest each is about the app being genuinely done:

| Reason | Meaning | Why it ranks here |
|---|---|---|
| `reflectorIdle` | The app said so itself, through `ProctorReflector`. | The only signal with access to the app's own notion of work in progress. Nothing outside the process can beat it. |
| `allSignalsQuiet` | AX notifications quiet for `axQuietMs` **and** `quietFrames` consecutive frames under `dirtyThreshold`. | Two independent observers agreeing. Strong, but both are external inferences. |
| `axQuietOnly` | No capture signal was available. | Blind to animation and to pixel work that raises no AX notification. |
| `captureQuietOnly` | No AX notifications were available. | Blind to state changes that do not repaint. |
| `timeout` | Nothing went quiet in `timeoutMs`. | Weakest. Reported, never hidden — a timed-out settle upstream of an assertion is the usual explanation for a mystery failure. |

`dirtyThreshold` defaults to 0.002 of frame area: below that, a change is a
cursor blink or a progress spinner, not the UI still moving. Treating it as
motion makes every window with a caret permanently unsettled.

`signals` lists what was available rather than what fired: "quiet" from an
observer that was never running is not evidence, and a report that cannot
distinguish the two makes flaky tests undiagnosable.

## Determinism through canonical hashing

`proctor_stability` answers "is this step nondeterministic?" before anyone
argues about whether it is correct. That only works if identical states hash
identically, so `Canonical` normalises before hashing.

What is removed:

- **Volatile text.** Clock times, ISO dates, elapsed-duration phrases, UUIDs and
  pointer-shaped hex are replaced with a placeholder. A window showing the time
  would otherwise diverge at step one of every run.
- **Sub-pixel geometry.** Frames are quantised to whole points
  (`defaultGeometryQuantum = 1.0`). Sub-pixel drift is not a state change, and
  treating it as one makes every animated view report as unstable.

What is deliberately kept:

- **Child order.** AX order is the focus order, so it is meaningful. Children are
  serialised in tree order, never sorted. Sorting would hide a real defect: a
  reordered tab sequence.
- **Sorted actions and object keys.** Those have no meaningful order, so they are
  sorted to keep the string stable.

The canonical form is a readable indented string, not an opaque digest, because
it is also what a divergence report diffs. A human looking at why two runs
disagreed needs to see the difference, not two hashes.

Two derived measures sit on top:

- `instability(hashes:)` — distinct states over N runs, scaled 0 to 1. One
  distinct hash is 0; N distinct hashes is 1.
- `firstDivergence(perRun:)` — the first step index where runs disagreed. A run
  that ended early counts as a divergence at its own length, because stopping is
  a state difference.

A flow whose `firstDivergence` is step 3 does not need its step 9 assertion
investigated. That ordering is the whole value of the instrument.

## Tri-observer disagreement

Three sources describe the same instant: the accessibility tree, the layer
geometry (reflector or AX frames), and the captured pixels. Where they disagree
that delta is a finding, not noise — an unexposed control, a ghost node, an
invisible-but-focusable element, a stale frame, a wrong hit target.
`Disagreement` records what each observer said, so the finding is arguable
rather than asserted. Smoothing these away would make Proctor report clean runs
on broken UI, which is the failure mode the whole design exists to prevent.
