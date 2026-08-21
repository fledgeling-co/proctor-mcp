# A dead peer holds the queue, and a swallowed event says nothing

**Wave 13, brief 6 of 6.** DEF-026 and DEF-027. Both are run-lifecycle defects a person meets as
"Proctor has stopped working", with no way to tell why.

## DEF-026 — a run outlives the process driving it

When the shim process driving a run exits while a run is in flight, **the run stays in the agent's
queue holding the slot**. Every subsequent `proctor_act` returns `queueBusy` with *"another session
was driving this Mac … gave up without running any step"*, and the lane is unusable until the agent
is restarted.

Measured: `evidence/witness/a4-stranded-run-queue.json` reads `heldForSeconds 552` with reason
`frontmostChanged`. The 900-second pause backstop did not release it, because the backstop is about
a paused run rather than a dead peer.

The peer identity needed to detect this is already on the wire and already trusted for something
more sensitive: `SessionIdentity` derives the caller from `getsockopt(SOL_LOCAL, LOCAL_PEERPID)` and
`proc_pidpath`, and REQ-035's whole guarantee is that this cannot be forged. A slot held by a pid
that no longer exists is therefore answerable without inventing a heartbeat or a new wire field.

Be careful what "gone" means. A peer that has exited is gone; a peer that is slow, stopped at a
breakpoint, or blocked is not, and reclaiming its slot would cut off a live run. Reclaim on process
death, not on silence.

## DEF-027 — the block swallows input and reports neither

The takeover block's tap calls `onPersonInput` for every event it declines to deliver, and
`SessionTakeover.swift:137` wires that to `ContentionMonitor.noteUserInput`, which sets the field
`ContentionWatch` reads to decide the `userInput` condition.

Measured across three runs, with a helper process posting into the session while the run held the
foreground: the agent reported swallowing **6, 24 and 10 events** — and produced **no yield record
and no held reason** in any of the three.

A person pressing keys into a machine an agent is driving is exactly the event the yield exists for.
Forty swallowed events producing nothing means either the wiring does not carry, or the condition
requires something these events do not satisfy.

**Establish which before changing anything**, because the second reading is plausible and the fix
differs entirely: `PersonInput.isAPerson` requires `sourcePid == 0`, and REQ-007 is already recorded
`inconclusive` on exactly that ceiling — no second process can forge a hardware event. So a helper
process posting events may be **unable in principle** to trigger the yield, and the measurement
would then be evidence about the instrument rather than about the product.

That distinction is the whole item. If the helper cannot satisfy `isAPerson`, this is not a defect
in the yield and the honest outcome is to say so and record what instrument could settle it. If the
wiring genuinely does not carry, it is a real defect on the path that lets a person take their
machine back.

## The conversion contract

- DEF-027 settled as a defect or as an instrument limit, with the evidence naming which, before any
  behaviour changes.
- If it is a defect: a test driving the swallow path and asserting a yield record and a held reason,
  with a sabotage showing the absence.
- DEF-026: a slot held by a dead peer is released, proved by a test that spawns a real peer, has it
  exit mid-run, and asserts the next call is not `queueBusy` — with the recorder being the queue's
  own state rather than a value the test wrote.
- A live-but-silent peer keeps its slot, tested explicitly, so the fix cannot cut off a running
  session.
- `./scripts/test.sh` green, suite count before and after.

## What this brief does not do

It does not revisit REQ-007's `inconclusive` ceiling, which was checked in source twice. It does not
add a heartbeat or a new wire field; peer liveness is already derivable from the socket.
