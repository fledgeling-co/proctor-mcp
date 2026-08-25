---
sources: [REQ-002, REQ-003, REQ-004, REQ-006, REQ-007, REQ-008, REQ-012, REQ-014]
status: retired
validated-by: REQ-002, REQ-003, REQ-004, REQ-006, REQ-007, REQ-008, REQ-012, REQ-014 via CASE-0003, CASE-0004, CASE-0005, CASE-0008, CASE-0009, CASE-0010
validated-rungs: effect-witness, metamorphic, outcome
validated-provider: AXUIElementPerformAction in Sources/ProctorAgent/AX/Actuator.swift; AXObserverCreate in Sources/ProctorAgent/AX/Observers.swift
---
# Effect witnesses for the eight effects that need a display server

**Wave 11, brief 2 of 4.** Reads `70` for the rung's contract; can run beside it. The two briefs
split the same twelve requirements by whether a witness needs a window server, because that split
decides which lane the case runs on and whether it can run in CI at all.

## The measurement

`campaign.py check` names twelve requirements whose external-effect claim has no witness. Four
are settled off-glass in `70`. These eight cannot be:

| Req | Effect | Provider | What a witness needs |
|---|---|---|---|
| REQ-003 | `device` | `CGEventPost` in `Actuation/ActuationBackend.swift` | a posted event observed by something that is not the poster |
| REQ-004 | `device` | `SCStream`/`SCShareableContent`/`SCFrameStatus` in `Capture/StreamCapture.swift` | a frame off a real display server with its status |
| REQ-007 | `device` | `CGEventTap` in `Session/ContentionMonitor.swift`; `NSEvent.addGlobalMonitorForEvents` | a tap that fires on an event it did not post |
| REQ-008 | `device` | `CGEventTap` in `Overlay/TakeoverOverlay.swift` | the same, for the input blocker |
| REQ-002 | `ipc` | `AXUIElementPerformAction` in `AX/Actuator.swift`; `AXObserverCreate` in `AX/Observers.swift` | an action performed on another process's element |
| REQ-012 | `ipc` | same AX pair | AX notifications arriving from another process |
| REQ-014 | `ipc` | same AX pair | the tri-observer read, across a real process boundary |
| REQ-006 | `ipc` | `NSPanel` over the window server in `Overlay/RunHUDPanel.swift` | the panel read back through `CGWindowListCopyWindowInfo` |

Under `swift test` there is no window server, no Accessibility grant and no host application, so
none of the eight can be witnessed where the rest of the suite lives. That is a property of the
lane rather than of the code, and it is the reason this brief is separate.

## Where the evidence already is

The `macos-glass` lane is attached and proved. It has eight `raster-visual` passes, each carrying
a `--capture-method` and a `--frame-status`, taken from a signed build launched on this machine
with its TCC grants intact. `SCFrameStatus complete` on those captures is already a device-class
effect observed by ScreenCaptureKit rather than by the code under test — the campaign simply never
recorded it as one, because the `effect-witness` rung did not exist when they were taken.

So four of the eight are a **promotion with a recorder named**, not new work:

- **REQ-004** is the closest. The capture path is the subject, `SCFrameStatus` is ScreenCaptureKit's
  own report, and the count is frames. Record the recorder as ScreenCaptureKit's per-frame status
  and the count as the number of complete frames the run took.
- **REQ-006** reads the HUD panel back through `CGWindowListCopyWindowInfo`, which is the window
  server describing the panel rather than Proctor describing it. Count is matching window entries.
- **REQ-003** needs the posted event seen by a receiver. The existing glass captures show the
  *result* of a post; a witness needs the post itself observed, and `CGEventTap` on a second
  process is the portable instrument for that.
- **REQ-002 / REQ-012 / REQ-014** need a real target application. Proctor's own status window is
  a legitimate target and removes the dependency on a third-party app being installed.

**REQ-007 and REQ-008 are the hard pair.** Both tap input, and a witness has to prove the tap
fired on an event the test did not post — otherwise the recorder and the driver are the same
thing. Drive them from a second process: post from a helper, tap in the agent, and let the tap's
own log be the recorder.

## Two rules that decide whether this is worth doing

**A model verdict never gates**, and neither does a filename. Every capture published here goes
through `capture-lineage.py`, which refuses one picture standing in for two cases. A campaign has
already been observed publishing twenty captures of six distinct images under twenty names, with
every gate it had clearing.

**Where a witness genuinely cannot be built, record the ceiling in structural terms rather than
marking the requirement `n/a`.** A recorded permanent limit counts against the total and stays
visible; an `n/a` disappears. The honest floor for anything unreachable here is a case resolved to
`inconclusive:` with the instrument named, which holds the gate shut, which is correct — "we do
not know" is a weaker claim than "no difference found".

## The conversion contract

- Cases on the `macos-glass` lane only. Nothing in this brief runs in CI, and the brief says so
  rather than leaving a green that a reader would take for a full one.
- Every promotion of an existing `raster-visual` pass keeps its capture manifest. A manifest cannot
  be reconstructed afterwards, so a promoted case that lost one is a new capture, not a re-label.
- Each case carries its sabotage: deny the grant, kill the target, or unshare the window, and show
  the count going to zero.
- The eight are expected to close as a mix of witnessed and structurally limited. Name the split in
  the report rather than reporting a count.

## What this brief does not do

It does not build a second machine, and it does not depend on the guest lane. `proctor-guest` and
`anvil-mac-node` are both stopped and neither is to be deleted; a witness needing a guest is out of
scope here and belongs with the VM work in `57`.
