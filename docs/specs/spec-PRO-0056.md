# PRO-0056: A run says which machine it is on

**ID:** PRO-0056
**Status:** Merged
**Created:** 2026-08-16
**Last updated:** 2026-08-16
**Branch:** `ai/pro-0056` (worktree `.worktrees/PRO-0056`)

First item of the guest-target wave. See `docs/features-to-triage/57-vm-targets.md`
for the wave's direction.

## Why this is first

Proctor has always had exactly one answer to "which machine did this run on", and
has therefore never said it. Guests change that, and the change is not cosmetic: a
result from a guest is about a different OS build, a different display
arrangement, a different set of installed applications and none of the person's
own data. A reader who assumes the host is reading a true statement about the
wrong computer.

The wave's routing item auto-routes a batch into a guest when one is configured.
PRO-0051 rejected automatic fallback because it "hands back a verdict that looks
fine and measures the plumbing", and routing is that move wearing better clothes.
It is honest only if every surface a reader consults already names the machine, so
the disclosure is built first and nothing routes yet.

## What was built

`Machine` in `Sources/ProctorCore/Wire.swift`, beside `ActuationBackendID`: a kind
(`host` / `guest`), the guest's own name as its provider knows it, the provider,
and a `MachinePlatform`. `Session.machine` defaults to `.host`, so nothing that
existed before this behaves differently.

Carried on four surfaces, which is the whole of the item:

| Surface | Field | Rule |
|---|---|---|
| `ActResult` | `machine` | Always set, including on a run where every step refused |
| `StabilityReport` | `machine` | One value per report; a session's machine cannot change under it |
| Audit trail | `mach` | `host` or `guest:<name>`, written on every row |
| `DoctorReport` | `machine` | Scopes every other answer in the report |

Two representations rather than one, deliberately. `line` is for the panel and
prose and degrades by dropping clauses (`sequoia-seed · macos · lume`, then
`win11`), never printing an absence. `auditToken` is one stable token per machine
(`guest:sequoia-seed`), because the trail is grepped and diffed and must not gain
or lose clauses with whatever happened to be known when a row was written.

## The optionality, and why the trail differs from the report

`machine` is optional in the type and always set on the wire, for the two separate
reasons `backend` already documents: optional so a record written before this
existed still decodes, always set because `SessionAct` passes the session's
machine unconditionally. There is no default, because a default would let a
construction site that forgot to say encode `host` under a guest run.

The trail writes `host` explicitly rather than omitting the field. Absence would
in fact be unambiguous today, since every row written before guests existed was a
host row. It is written anyway so that a later build which forgets to set it for a
guest is distinguishable from an older honest one, rather than reading as the
host. This trail is what attribution is argued from, so a wrong-and-silent value
costs more than a redundant one.

## Evidence

`MachineDisclosureWiringTests`, 11 tests: the default is still the host; the act
result, a fully-refused run, the trail, and the doctor each carry it; a host run
writes `host` rather than nothing; both string forms are pinned; and an older
record with no `machine` still decodes.

Gate: **1437 tests in 159 suites pass in 5.7s** (1426 before).

## Not in scope

Anything that sets `machine` to a guest in production. Nothing constructs a guest
yet, and nothing routes to one. Those are PRO-0058 through PRO-0061.

## Changelog

Deferred to the end of the wave, deliberately and recorded here so it cannot
drift: this item adds a field to results but no capability a reader can use, and
the user-facing change is "Proctor can test in a VM", which is not true until
PRO-0062. `ORCHESTRATOR.md` carries the obligation.
