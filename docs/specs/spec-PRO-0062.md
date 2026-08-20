# PRO-0062: The overlay says which machine

**ID:** PRO-0062
**Status:** Merged
**Created:** 2026-08-17
**Last updated:** 2026-08-17
**Branch:** `ai/pro-0062`

Last item of the guest-target wave. See `docs/features-to-triage/57-vm-targets.md`.
Depends on PRO-0056 and PRO-0061.

## The problem

The overlay's takeover statement, input block and contention yield are all
claims about *this* Mac. When the steps land in a guest they are false, and
a panel that still says "the app must stay in front" is lying about the
machine the person is sitting at.

## What was built

`RunHUDModel.target` sits beside the existing `exception` line. Nil on the
host, so a host run encodes exactly as it did before guests existed.

`RunHUDEvent.runBegan` carries the session's `Machine`. On a guest the
exception line is replaced with `On <guest>. This Mac is free.` A synthetic
step on that run does not swap back to the host-takeover sentence.

The host-takeover claims are suppressed at the source, not just relabelled:

- `takeoverShow` is a no-op on a guest session.
- Contention is not armed for a guest batch, including a late fallback onto
  the event stream.
- The statement therefore never goes up, the block never arms, and the
  yield never watches this Mac for a person taking it back.

## Evidence

`guestRunNamesTheGuest` / `hostRunIsUnchanged` in `RunHUDTests`: a guest
run names the guest and keeps that sentence through a synthetic step; a
host run still has no target and still announces a click.

`aGuestRunLeavesThisMacAlone` in `TakeoverWiringTests`: a click batch on a
guest session raises no statement, arms no block and watches no contention.

Gate: confirm on `scripts/test.sh`.

## Changelog

This is the wave's one user-facing change. The Unreleased entry is written
through create-luke-content in the same change.
