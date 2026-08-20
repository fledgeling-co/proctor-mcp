# PRO-0078 — Effect witnesses on glass: device and AX

**Status:** To Do → Ready for AI · **Brief:** `docs/features-to-triage/71-effect-witnesses-on-glass.md`
· **Lane:** `macos-glass` · **Branch:** `ai/pro-0078` · **Ledger id:** allocated upstream, not written here.

## What this closes

`campaign.py check` names twelve requirements whose external-effect claim rests on no witness.
Eight of them cannot be witnessed under `swift test`, because there is no window server, no
Accessibility grant and no host application in that process. This item builds the witness for
those eight on a real build launched on this machine with its TCC grants intact, and records a
structural ceiling wherever the instrument cannot reach.

| Req | Effect | The thing that must be observed | Recorder |
|---|---|---|---|
| REQ-003 | `device` | `CGEventPost` from the agent entering the session event stream | a listen-only `CGEventTap` in a separate observer process |
| REQ-004 | `device` | a frame off a real display server, with the channel's own verdict on it | ScreenCaptureKit's per-frame `SCFrameStatus` |
| REQ-007 | `device` | the contention watch firing on an event the agent did not post | the agent's own `CGEventTap`, via the run's `yields` |
| REQ-008 | `device` | the input blocker swallowing an event the agent did not post | the same tap's swallow counter, via `takeover.swallowed` |
| REQ-002 | `ipc` | an accessibility action landing in another process without taking the front | `CGWindowListCopyWindowInfo`, read from a third process |
| REQ-006 | `ipc` | the run HUD panel existing as far as the window server is concerned | `CGWindowListCopyWindowInfo`, read from a third process |
| REQ-012 | `ipc` | AX notifications arriving from another process | `SettleReport.axNotificationsSeen` |
| REQ-014 | `ipc` | the tri-observer read crossing a real process boundary | the target's AX server and ScreenCaptureKit, two channels neither of which is the other |

The rung is `effect-witness`, and it owes three fields the other rungs do not: a recorder, an
effect class, and a count that is not zero. `references/effect-boundary.md` §5 sets the four
parts that make a witness causal rather than circumstantial, and part 4 — sabotage flips it — is
the one this spec spends most of its acceptance clauses on.

## What is deliberately not in scope

No second machine and no guest lane. `proctor-guest` and `anvil-mac-node` are both stopped and
neither is touched; a witness that needs a guest belongs with the VM work in brief `57`.

Nothing here runs in CI. Every case is `macos-glass`, and the report says so rather than leaving
a green a reader would take for a full one.

No product behaviour changes. This item adds evidence and the harness that produces it. A product
defect it catches gets a surgical fix and its own defect record; anything else noticed in passing
is flagged rather than changed.

The installed `/Applications/Proctor.app` stays where it is. Every measurement runs against
`.build/Proctor.app` on a private socket, which is the recipe PRO-0036 and PRO-0075 both used.

## The lane, and what proves it

`campaign.json` already carries a `laneProof` record for `macos-glass`: `.build/Proctor.app`,
built by `PROCTOR_SIGN_IDENTITY='Developer ID Application: Luke Rhodes (H4HGFL52W7)' bash
scripts/build-app.sh`, attached by `glass_probe` reading a pid that owns CG windows out of
`CGWindowListCopyWindowInfo`. That record is not rewritten. This item re-establishes the same
three facts for its own run and records them in each case's note, because a lane proof from
yesterday's build says nothing about today's process.

The TCC grants key on the team-scoped Developer ID designated requirement, so a fresh signed
build keeps Accessibility, Screen Recording and Input Monitoring. Ad-hoc signing would throw them
away, and REQ-007 and REQ-008 need Input Monitoring specifically: `CGEvent.tapCreate` returns nil
without it and the block fails open with a reason.

## Behaviour

### A1 — REQ-004, frames off a display server

Driving `proctor_capture` against a window the agent did not draw produces a `CaptureResult`
carrying ScreenCaptureKit's own `frameStatus` and the number of frames waited for. The recorder is
`SCFrameStatus`, which is ScreenCaptureKit's report rather than Proctor's; the count is the number
of frames the stream delivered before one was complete enough to hand back.

The capture is published with a manifest row naming the CG window id the agent resolved, its
channel, its `frameStatus`, its sha256 and the conditions of the run. A manifest cannot be
reconstructed afterwards, so the capture is taken with `capture_with_manifest.py` rather than
labelled later.

**Sabotage.** With no such window on screen the call refuses and the count is zero.

### A2 — REQ-006, the HUD as the window server sees it

While a synthetic run is in flight, `CGWindowListCopyWindowInfo` read from a third process lists
the agent's HUD panel: owner pid equal to the agent's, the panel's level, its bounds, and
`sharingState` 0 at the shipping default. The recorder is the window server's own list. The count
is matching window entries.

**Sabotage.** With `PROCTOR_HUD=0` the same probe over the same run returns zero matching entries.

### A3 — REQ-003, a post seen by something that is not the poster

A separate observer process holds a listen-only `CGEventTap` on the session while the agent runs a
synthetic step. Events reaching that tap carry `.eventSourceUnixProcessID` equal to the agent's
pid and `.eventSourceUserData` equal to `ProctorEventTag.value` (`0x5052_4F43_544F_5200`), which
the actuator stamps on its own source in `AX/Actuator.swift`. The recorder is the observer's tap.
The count is tagged events observed.

`CGEventSource.counterForEventType(.combinedSessionState, …)` is read either side of the run as a
second channel. It needs no grant, it is the window server's own accounting, and it is recorded
beside the tap count rather than in place of it.

**Sabotage.** The same target driven on the accessibility plane posts nothing, and both the tap
count and the counter delta are zero.

### A4 — REQ-007, the watch fires on an event the run did not post

With `PROCTOR_YIELD=1` and `PROCTOR_TAKEOVER_INPUT=1`, a helper process posts input into the
session while the agent is mid-run. `InputBlock.isOurs` is false for that event — it carries the
helper's pid, not the agent's, and not the tag — so the agent's tap swallows it and hands it to
the contention monitor through `onPersonInput`. The run yields, and the yield appears in the run
result's `yields` array with its reason and held milliseconds.

The recorder is the agent's own `CGEventTap`. The driver is a different process from the recorder,
which is the whole point: a tap that fires only on what the test posted through the same code path
proves nothing about the tap.

**Sabotage, two-way.** The helper posts the identical event with
`.eventSourceUserData = ProctorEventTag.value`. `isOurs` is then true, the tap passes it, nothing
is swallowed, and the run does not yield. Same event, one field different, opposite outcome — so
the yield is reading the event rather than a clock.

`PersonInput.isAPerson` is a separate predicate and it will not fire here, because it demands
`sourcePid == 0` and a helper process cannot forge that. That is deliberate in the product: a
process is not a person. The witness therefore stands on the block's path rather than on the
global `NSEvent` monitor, and the spec says so rather than implying both were exercised.

### A5 — REQ-008, the blocker's own count

The same run reports `takeover.swallowed` greater than zero, from the same tap. The recorder is
the tap's swallow counter as `TakeoverReport` carries it; the effect class is `device`; the count
is the number of the helper's events that did not reach any application.

**Sabotage.** With `PROCTOR_TAKEOVER_INPUT` unset the tap is never created, `blocked` is false,
`swallowed` is zero, and the helper's event reaches the session — which the observer's own tap
records, so the negative is a measurement rather than an absence.

### A6 — REQ-002, an action landing in another process

The agent performs an accessibility-plane action on a window belonging to a different process,
with a different pid, while a third process reads `CGWindowListCopyWindowInfo` and
`NSWorkspace.frontmostApplication` either side of it. The window server records the target
window's change; the frontmost application is the same before and after.

The recorder is the window server's list. The count is target windows whose state the window
server reports as changed.

**Sabotage.** With the target process gone the action is refused, the count is zero, and the
refusal carries a reason rather than a false negative.

### A7 — REQ-012, notifications from another process

A settle over another process's window reports `axNotificationsSeen` greater than zero and lists
`ax` among the signals that were actually available. Those notifications are delivered by the
target's accessibility server; nothing in Proctor generates them.

The recorder is the AX notification stream. The count is notifications seen.

**Sabotage.** A settle over a window whose process has been quit reports zero and does not list
`ax` among its available signals, which is the distinction `SettleReport.signals` exists for.

### A8 — REQ-014, the tri-observer across a boundary

`proctor_assert` with `kind: agree` against another process's window reads the AX tree from that
process and a ScreenCaptureKit frame of the same window id, and reports its findings and their
severities. Two channels, neither of which is the other, and neither of which is Proctor's own
memory.

The recorder is the pair. The count is the number of AX nodes the target's accessibility server
returned across the boundary, corroborated by the frame's own `frameStatus`.

**The ceiling, and it is recorded rather than argued around.** The kernel bar for an ipc witness
is a traced mach message. SIP is on and this lane has no root, so `dtrace` on the accessibility
transport is not available. What this case stands on is the portable floor from
`references/effect-boundary.md`: a real other process, identified by a pid the window server
agrees with, answering reads that only it could answer, and a sabotage that takes the answers to
zero. If the count cannot be established from what the product reports, the case resolves
`inconclusive:` naming the instrument, and REQ-014 stays unwitnessed. It is never marked `n/a`,
and its effect class is never reclassed to `none`.

## Failure modes this spec is written against

**A witness whose recorder is the driver.** A8's ceiling note and A4's two-way sabotage both
exist for this. Where the code under test is the only thing reporting the effect, the case says so.

**A count that reads as a measurement and is a subtraction.** Every count is read out of a
recorder's own output and quoted in the case note with the field it came from.

**A capture standing in for two cases.** Every published picture goes through
`capture-lineage.py`, which refuses one sha256 under two subjects. New captures are taken with
their manifest; no existing case row is rewritten to carry a witness it did not take.

**A green that hides a lane.** Nothing here runs headless. The report names the split between
witnessed and structurally limited rather than reporting a single count.

**Asserting a value the test itself wrote.** DEF-019 was exactly this shape and was found here
once. Every count in this item is read back from a process other than the one that produced it,
or, where that is impossible, the case records the limitation.

## Acceptance clauses

1. `.build/Proctor.app` is built with the Developer ID identity, its signature reads
   `Authority=Developer ID Application: Luke Rhodes (H4HGFL52W7)` and
   `TeamIdentifier=H4HGFL52W7`, and an agent from that bundle is running on a private socket with
   `/Applications/Proctor.app` untouched. Evidence: `codesign -dv` output and the agent's own
   `proctor_doctor` reply naming its socket and its grants.
2. Eight cases exist in `docs/test-campaign/cases.json`, one per requirement, each on lane
   `macos-glass`, each appended rather than overwriting a row this item did not create.
3. Every case that passes carries `oracle: effect-witness`, a recorder, an effect class matching
   its requirement's declared class, and a count greater than zero.
4. Every case that passes names at least one evidence artifact that exists on disk and holds what
   the note says it holds.
5. Every case carries its sabotage, recorded as its own artifact, showing the count at zero with
   the reason.
6. Any requirement whose witness cannot be built resolves to `inconclusive:` with the instrument
   named. No requirement in this set is marked `n/a`, and no effect class is changed to `none`.
7. `python3 campaign.py check docs/test-campaign` reports `witnessed` greater than zero and lists
   none of these eight under "External-effect claims with no witness" except those recorded
   `inconclusive`.
8. `python3 capture-lineage.py docs/test-campaign --gate` exits 0, with every new capture carrying
   a manifest row and no sha256 shared between two subjects.
9. `./scripts/test.sh` exits 0. It owns the verdict; a bare `swift test` exits 1 while reporting
   every test passing, because the pipe eats the exit code.
10. `campaign.json` and `inventory.json` are appended to only. No row this item did not create is
    reformatted, re-sorted or rewritten, and `docs/feature-specs/LEDGER.md` is not touched.

## Open questions

**Whether REQ-014's count can be sourced from something other than Proctor's own walk.** The
answer decides between a pass and an `inconclusive`, and it is settled by measurement in the work
stage rather than by argument here. The spec commits to the honest outcome either way.

**Whether the harness's own Accessibility trust is a confound for the observer process.** The
observer inherits its grant from this harness's responsible process rather than from Proctor, which
is what makes a listen-only tap available at all. It is recorded as a property of the lane, because
the same probe on a machine without that grant would report zero and the zero would mean something
else entirely.

## Out-of-family spec review

`grok-4.6`, read-only. The first call at `xhigh` with the whole spec inlined returned reasoning
preamble and no verdict inside its 300-second alarm; that is a lane failure, so the call was
re-run at `high` with the eight recorders compacted to one line each and returned a verdict in
1,423 bytes. Both the failure and the retry are recorded because an unlogged fallback is
indistinguishable from a skipped gate.

It classed A2, A3 and A6 independent, and A1, A4, A5, A7 and A8 self-reporting: *"both the AX walk
and the ScreenCaptureKit frame are reads the agent performs; two self-reads are not a third
party."* Its named weakest case is A8, and its proposed fix is to give the count to a helper that
reads the target's AX tree itself, so the agent's reply is checked against the helper rather than
standing as the witness.

Four of the five are accepted and change the instruments:

**A1.** A helper captures the same CG window id through `CGWindowListCreateImage`, a channel
Proctor does not write, in the same second. The recorder becomes `SCFrameStatus` corroborated by an
independent capture of the same window, and the two are compared on dimensions and content.

**A5.** The helper's own tap is tail-appended while the agent's is head-inserted, so an event the
block swallows never reaches the helper. The helper posts N and observes how many survive: zero
while the block is armed, N while it is not. That is a third party watching the events be
destroyed in flight, rather than the agent counting itself.

**A7.** The helper installs its own `AXObserver` on the same target element and counts the
notifications it receives. Two independent observers receiving the target's notifications
establishes that the target is emitting them across a process boundary.

**A8.** Accepted as proposed. The helper walks the target's AX tree itself and reports its own node
count; the agent's `agree` reply is checked against it.

**A4 is accepted as a partial.** The yield decision is Proctor's own and no external recorder can
observe it. What the helper establishes independently is that the triggering event came from
another process and was destroyed before reaching any application. The case therefore records the
yield as the product's report and the event's provenance as the witness, and names the half that
stays self-reported rather than implying both were third-party.

### The same reviewer on the finished evidence

The eight measurements went back to grok-4.6 once they existed, compacted to what each recorder
actually saw. That call returned inside its alarm at `--effort high`; a first attempt from a
directory the model could read spent its whole 300-second budget opening files instead of
answering, so the re-check was run from an empty directory with the text supplied inline. The
verdict was SOUND for A2, A3, A4, A5, A6, A7 and A8, and **UNSOUND for A1**: *"SCFrameStatus=complete
and the PNG are the agent's own capture path; the probe only matched window size, and the
independent raster was refused."*

The reviewer was right, and the pixels were worse than the objection. The A1 capture had been taken
of a window Proctor's own UI process owns, and reading the PNG rather than trusting its filename
showed all 2,942,720 pixels at RGBA(0,0,0,0) while the reply read `status: complete`,
`trustworthy: true`. Proctor excludes its own windows from its own captures, so the empty frame is
that exclusion working; the reply not saying so is DEF-025.

A1 was retaken against Calculator, a process Proctor does not control, and the subject is now
proved by text rather than by geometry. A probe process walks the target's accessibility tree with
its own AX client and reads a `Last Expression` element carrying `1,861.20-690` and an edit field
carrying `1,171.2`; those are the two numbers painted in the delivered frame. The re-check returned
SOUND, with one residual the case records as its ceiling: `SCFrameStatus=complete` is still relayed
by the code under test, because a second raster channel needs a Screen Recording grant the probe's
responsible process does not hold.

The reviewer's closing note on A8 — that a third process reading the target's AX tree is not
independent evidence of the tri-observer *agreement* — is taken as a scope narrowing rather than a
defect. CASE-0071 now states that what is witnessed is the accessibility plane crossing a process
boundary, and that the agreement between the three observers sits beside that claim at its own
rung rather than under it.

**The empty frame is the finding worth carrying out of this item.** A capture channel reported a
complete, trustworthy frame containing nothing, and every gate in the campaign would have accepted
it. What caught it was reading the picture.
