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
      | ~/Library/Application Support/app.fledgeling.proctor/agent.sock
      | 4-byte big-endian length prefix, then JSON
      v
  proctor-agent .................... inside ~/Applications/Proctor.app
      | launched by launchd as gui/$UID/app.fledgeling.proctor.agent
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
no such ancestry, so the grant attaches to `app.fledgeling.proctor` at a fixed
path and survives host changes and upgrades.

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
