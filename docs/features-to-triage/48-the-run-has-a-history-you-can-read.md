---
sources: [REQ-033]
status: retired
---
# The run has a history you can read

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

Proctor records a great deal and shows almost none of it. The audit trail is sealed and
signed and readable only by a tool. The HUD shows the step in flight and forgets it.
The queue bar shows what is waiting. When a run ends, a person who wants to know what
just happened to their machine has nowhere to look.

The reader asked for action logs and history alongside the overlay, and they are the
part that does not exist yet.

## What it should do

A readable record of what Proctor did, reachable from the menu bar and the status
window: the runs, their steps, what each step targeted, which plane it travelled, what
came back, and what it cost in time.

## The hard parts, named

- **This is a second reader of the audit trail, and the trail is sealed.** Decryption
  happens in the agent, which holds the key. A window that renders history is therefore
  asking the agent for plaintext it deliberately made unreadable at rest. Say what
  crosses that boundary and in what form, and keep the answer as narrow as the feature
  needs.
- **A history view is a place a person reads attacker-controlled text.** Step
  descriptions carry an application's own accessibility labels, which is why PRO-0014
  fences every object in quotes and sanitises both supplied and derived names. A list
  view renders far more of that text than a one-line HUD ever did, so the fencing has
  to hold at this size.
- **Retention is a decision, not a default.** An unbounded history of everything an
  agent did on somebody's Mac is a surveillance artifact sitting in their home
  directory. Say how much is kept, how it ages out, and how a person clears it.
- **Do not build a log viewer when a run summary is what people want.** The unit a
  person thinks in is "that thing it just did", not a line-per-event stream. Design for
  the run, and let a step list live inside it.

## Not in scope

Exporting history, or any second copy of the trail outside the sealed one. PRO-0013
chose no recovery path deliberately and this feature does not reopen it.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-033
- surface: SURF-017, SURF-036
- cases: CASE-0033, CASE-0034, CASE-0035, CASE-0036, CASE-0040, CASE-0041
- rungs reached: effect-witness, metamorphic, outcome
- provider: Darwin.bind/listen/accept in Sources/ProctorAgent/Server.swift; Darwin.connect in Sources/ProctorCore/Transport.swift
