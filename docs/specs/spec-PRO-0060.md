# PRO-0060: Reaching a guest's Proctor over SSH

**ID:** PRO-0060
**Status:** In Review
**Created:** 2026-08-17
**Last updated:** 2026-08-17
**Branch:** `ai/pro-0060`

Fifth item of the guest-target wave. See `docs/features-to-triage/57-vm-targets.md`.
Depends on PRO-0056 (the machine is already named) and sits beside PRO-0059.

## The problem

A macOS guest running a full Proctor is a native witness, but the host-side
shim still talks to the host agent's socket. There is no new network
transport to write: `PROCTOR_SOCKET` already overrides the path, and the
loopback HTTP listener already tells you to use an SSH tunnel. What was
missing is a way to *describe* that tunnel for one guest, and a refusal
when the guest has no socket to forward onto.

## What was built

`GuestReach` in `Sources/ProctorCore/GuestInventory.swift`. Pure. Input is
a `Machine`, a host, and optional socket overrides; output is either a
recipe or a reason it cannot be asked.

The recipe is structured: `kind: streamLocal`, `localSocket`, `remoteSocket`,
`host`, `user`, `socketOverride`. **Never a shell line.** A tool result that
carried `ssh -L` would be an instruction a model with a shell would run,
which is the same defect `ToolAbsence` already refuses for install commands.
The person at the keyboard types the tunnel; this only says what it has to
bind. `PROCTOR_SOCKET` is then pointed at `localSocket`.

`cannotReach` is a list of what survives. A Linux guest, a Windows guest, a
macOS guest marked `delegated`, and the host itself are all refused with a
named reason. Delegated guests go through Cua. The same recipe reaches a
remote Mac over Tailscale: the host is that Mac's name and there is no
guest in between.

`proctor_guest` action `reach` is the surface. It resolves the guest the
same way `status` does, then hands the machine to `GuestReach.decide`.
Nothing opens a tunnel. Nothing starts ssh.

## Evidence

`GuestReachTests` (Core, 5): a native macOS guest produces a StreamLocal
recipe; Linux, Windows and a delegated macOS guest are refused; the host
is refused; an empty host is refused and a supplied socket is honoured;
the encoded recipe never carries a shell command.

`GuestToolTests` (Agent, 2 new): `reach` against an injected lume guest
returns the recipe and no `ssh`; `reach` against a Windows guest is
`notImplemented` and names Cua.

Gate: **1501 tests in 172 suites** (expected; confirm on `scripts/test.sh`).

## Not in scope

Auto-routing (PRO-0061), the overlay badge (PRO-0062). Nothing in
production attaches a session to the forwarded socket yet. Changelog
deferred to the end of the wave.
