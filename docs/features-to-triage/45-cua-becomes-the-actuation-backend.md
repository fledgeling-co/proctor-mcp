---
sources: [REQ-001, REQ-017]
status: retired
---
# Cua becomes the actuation backend

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

Proctor reimplements, for macOS only and with one maintainer, what Cua Driver does
across three platforms with a hundred contributors and 130+ commits a week. Every hour
spent on the actuation planes is spent losing ground.

## What it should do

Put Cua behind Proctor's existing actuation seam, so a `proctor_act` step is performed
by `cua-driver` while everything a caller sees stays the same.

## The hard parts, named

- **Choose the transport and defend it.** Cua ships one binary that runs as an MCP
  stdio server, a long-running daemon, or a one-shot CLI call. Proctor is Swift and
  already runs a long-lived agent. A daemon plus a client is the obvious fit and also
  the one that introduces a second process to supervise, restart and version-check.
  A one-shot call per step is simpler and pays process spawn on every click. Measure
  before choosing: a step budget that doubles is a determinism problem, not just a
  latency one.
- **The seam already exists and should be used rather than replaced.** Proctor has an
  actuator abstraction with fake implementations behind the test suite. Adding a Cua
  implementation beside the native one is the whole shape of this change; if it turns
  into a rewrite, stop and say why.
- **Version pinning.** Cua moves fast enough that "whatever is installed" is not a
  dependency, it is a variable. Decide the supported range, detect it, and refuse
  clearly rather than failing at the first call with a schema error.
- **Element addressing does not survive the boundary.** Cua's element handle is
  per-snapshot and returns a stale error once a newer snapshot supersedes it. Proctor's
  flows record the selector each step resolved through, which is what makes a replay
  meaningful. Say how a Proctor selector becomes a Cua target on each call, and what
  happens when the snapshot moved underneath.
- **Plane reporting is a wire contract.** Every step result says which plane it
  travelled and callers depend on it. Cua reports its own delivery mode. Map them
  honestly rather than flattening everything to one value.

## Not in scope

Deleting the native planes. That is its own item, deliberately, so this one can land
and be measured against the thing it replaces.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-001, REQ-017
- surface: SURF-001, SURF-002, SURF-013
- cases: CASE-0001, CASE-0002, CASE-0019, CASE-0020, CASE-0038, CASE-0059
- rungs reached: effect-witness, metamorphic, outcome
- provider: none
