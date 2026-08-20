# PRO-0061: Auto-routing, and the disclosure that makes it honest

**ID:** PRO-0061
**Status:** Merged
**Created:** 2026-08-17
**Last updated:** 2026-08-17
**Branch:** `ai/pro-0061`

Sixth item of the guest-target wave. See `docs/features-to-triage/57-vm-targets.md`.
Depends on PRO-0056, PRO-0059 and PRO-0060.

## The problem

A batch whose steps would take this Mac should run in a guest when one is
configured. PRO-0051 rejected automatic fallback because it "hands back a
verdict that looks fine and measures the plumbing". Executing the steps on
the host while naming a guest would be that move.

This process cannot yet perform a step inside a guest. `reach` describes
the tunnel; it does not attach. So the honest auto-route is a gate, not a
proxy.

## What was built

`GuestRoute` / `GuestRouteConfig` in `Sources/ProctorCore/GuestRoute.swift`.
Pure. Three outcomes:

- `host` when nothing is configured, or the batch would not take the Mac.
- `alreadyOnGuest` when the session is already elsewhere. Not refused here.
- `refuseHost` when `PROCTOR_GUEST` names a guest and the batch would take
  this Mac. The refusal names the guest and says how to reach it.

`PROCTOR_GUEST` is routing config, like `PROCTOR_SOCKET`, not one of the
eight runtime switches. Unset is the host, unchanged.

The gate sits on `act`, flow replay, stability and the CUA façade, before
the queue. A click posts nothing. A press on the same session is not
refused, because it would not take the Mac.

## Evidence

`GuestRouteTests` (Core, 4): unset and a non-takeover batch stay on the
host; a takeover batch with a guest configured refuses and names it; a
session already on a guest is not refused; the configured name is trimmed.

`GuestRouteWiringTests` (Agent, 4): a click with `PROCTOR_GUEST` set is
refused and posts nothing; a press on the same session runs; unset, a
click takes the host; a session already on a guest is not refused.

Gate: confirm on `scripts/test.sh`.

## Not in scope

The overlay badge (PRO-0062). Actually attaching a session to a forwarded
socket and performing steps there. Changelog deferred to the end of the
wave.
