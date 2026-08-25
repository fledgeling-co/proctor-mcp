---
sources: [REQ-015, REQ-016]
status: retired
---
# A delegated call is still gated and recorded

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

PRO-0005 built a fail-closed policy gate. PRO-0013 sealed the audit trail at rest.
PRO-0032 signed it and recorded the browser lane recommendation. All three assume the
process writing the record is the process performing the action.

Move actuation into `cua-driver` and that stops being true. Unless this is designed,
Proctor's trail quietly becomes a record of **what Proctor asked for**, which is a
weaker claim than **what happened to the machine**, written in the same words.

## What it should do

Keep the gate in front of every delegated call, keep the trail describing reality, and
say precisely what the trail now attests to.

## The hard parts, named

- **Intent and outcome are now two facts, and the trail should carry both.** Cua
  returns an effect for an action (confirmed, unverifiable, suspected no-op). A trail
  recording only the request is the hole described above; a trail recording the
  request and the reported effect is stronger than what Proctor has today, because
  today's record has no independent confirmation at all.
- **A subprocess can fail in ways an in-process call cannot.** It can die mid-step,
  answer late, or be a different build than the one whose grants were checked. Each is
  an audit event, not just an error return.
- **Do not widen what is recorded about the target.** PRO-0032 decided a URL in an
  audit entry is a person's browsing history in a file Proctor keeps, and defaulted to
  less. Delegation is not a reason to revisit that.
- **The gate must not be bypassable by talking to Cua directly.** If `cua-driver` is
  installed and running on the machine, a model with a shell can call it without
  passing through Proctor at all. Proctor cannot prevent that and should not pretend
  to; say so plainly in the spec so nobody mistakes the gate for a sandbox.

## Worth knowing

The interlock that stops `swift test` writing to the operator's real trail
(`PolicyStore.isTestProcess`) has already been inert once. Verify it fires before
running any suite that appends.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-015, REQ-016
- surface: SURF-001, SURF-008, SURF-012
- cases: CASE-0001, CASE-0011, CASE-0017, CASE-0018, CASE-0027, CASE-0028
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: data.write(to:options:.atomic) in Sources/ProctorAgent/Session/PolicyStore.swift; key material in Sources/ProctorAgent/Session/AuditKeyStore.swift
