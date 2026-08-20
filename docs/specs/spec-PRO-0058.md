# PRO-0058: Guest providers: lume and prlctl

**ID:** PRO-0058
**Status:** Merged
**Created:** 2026-08-17
**Last updated:** 2026-08-17
**Branch:** `ai/pro-0058`

Third item of the guest-target wave. See `docs/features-to-triage/57-vm-targets.md`.

## The problem

A guest is reached through someone else's CLI. Proctor owns no VM lifecycle: every
macOS guest on Apple silicon runs through Virtualization.framework, Parallels
included, so a wrapper of our own avoids no bugs. What this item has to do is
make `lume` and `prlctl` look like one seam, and make their presence visible
the same way every other tool already is.

## What was built

`GuestProvider` in `Sources/ProctorAgent/Guest/GuestProvider.swift`, modelled
on `ActuationBackend`: `list` / `status` / `start` / `stop` / `clone`. Two
adapters, both injectable. Production is the only construction that creates a
process; tests plant a runner.

The deciding half is pure and lives in `Sources/ProctorCore/GuestInventory.swift`:

- `GuestRecord` is one VM as its provider listed it. The provider's own word
  for the power state travels through; `running` is the one derived boolean.
- `GuestPlatform.infer` returns nil rather than a guess. A wrong platform
  becomes a wrong witness tier.
- `GuestRecord.machine` is `native` only when the platform is macOS. Anything
  else, including a listing that did not name one, is `delegated`.
- `LumeInventory` and `PrlctlInventory` decode the two CLIs' JSON. The
  Parallels fixture is the listing measured on this machine against Desktop
  26.4.0. lume has no binary here, so its parser accepts an array, a wrapper
  object, a single object, and a text table.

Detection is a filesystem read, never an execution, matching
`ToolProbe.maestroOnDisk()` / `cuaDriverOnDisk()`. Both binaries join
`Toolchain.entries` on a new `guest` lane. Either provider is enough; both
missing is unavailable. Presence settles usability: a health check does not
list guests.

The guest-lane note carries the grant-once-then-clone recipe and the Tahoe
upstream risk (trycua/cua #870, Apple FB21748086). Nothing provisions.

## Evidence

`GuestInventoryTests` (Core, 14): platform and power inference; lume JSON,
wrapper, table and empty; the measured prlctl short listing and the info
listing; the guest lane's either-provider rule.

`GuestProviderTests` (Agent, 7): lume prefers `ls --json` and falls back to
`list --json`; start / stop / clone argv; a missing guest is refused by name;
prlctl `list -a -j` and `clone --name`; truncated output is refused; a doctor
report with prlctl present shows the guest lane ready.

Existing toolchain and doctor suites updated for two new rows and a fifth lane.
`ready` is still untouched by their absence.

## Not in scope

`proctor_guest` (PRO-0059), SSH reach (PRO-0060), auto-routing (PRO-0061), the
overlay badge (PRO-0062). Nothing in production constructs a guest `Machine`
yet. Changelog deferred to the end of the wave.
