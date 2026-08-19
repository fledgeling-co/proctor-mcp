# PRO-0070: The takeover overlay, and what it does not claim

**ID:** PRO-0070 · **Status:** Ready for Plan · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/64-takeover-overlay-and-the-drawn-pointer.md`
**Branch:** `ai/pro-0070` off `ai/wave-9` · **Depends on:** PRO-0064, PRO-0065
**Mock:** `#mac/takeover/armed`, `#mac/takeover/guest`

## The problem

`TakeoverOverlay` draws a veil and a label. The mock adds the provenance chip and the
**guest-route refusal** — the state where a guest is configured, the batch would have taken the
host, and Proctor refuses rather than running. `GuestRoute` already computes that decision and
names the configured guest; it is drawn nowhere, so a person watching sees nothing happen and
cannot tell why.

## Acceptance criteria

1. **A1** — the refusal names the configured guest and the variable that set it, read from
   `GuestRoute` rather than from a string in the view.
2. **A2** — the overlay and the drawn pointer set `sharingType = .none`. A capture of an app
   under test taken while the overlay is up is byte-identical to one taken while it is down;
   the campaign proved this with three identical frame hashes and it stays true.
3. **A3** — Stop is reachable from the overlay in both states.
4. **A4** — the overlay never survives its process.

## Decisions taken at triage

- **The overlay signals mechanism, not consequence, and the copy must not imply otherwise.**
  PRO-0026 finding 10 recorded this as an open question the reader carried rather than specced:
  an all-accessibility run can delete a file through `AXPress` with this overlay never
  appearing, because nothing entered the event stream. The honest claim is "Proctor holds the
  event stream", not "Proctor is doing something significant". The mock's caption states the
  limitation out loud and the conversion keeps it.
- **The card carries a fixed palette.** It sits on a dark scene in both appearances, so it does
  not swap with the scheme.

## Out of scope

`PROCTOR_TAKEOVER_INPUT` — the event tap that swallows a person's input — is gated by
PRO-0072's consent sheet and the switch catalogue. This item draws the notice; it does not
acquire the capability.
