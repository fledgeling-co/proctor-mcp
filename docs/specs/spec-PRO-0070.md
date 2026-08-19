# PRO-0070: The takeover overlay, and what it does not claim

**ID:** PRO-0070 · **Status:** Merged · **Created:** 2026-08-20
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

## Verification

`TakeoverSurfaceTests` is 5 tests; suite 1,574 in 183 suites.

- **A1** — the refusal names the guest *and* the switch that clears it, both asserted. A
  refusal a person cannot act on is a bare denial. Three non-refusal cases are covered too: no
  guest, no foreground demand, and a session already on a guest.
- **A3** — Stop is offered whenever the veil is up, stated as a value. The veil covers the
  screen, so a person whose Stop is underneath it cannot halt a run holding their keyboard.
- **The copy claims mechanism and not consequence**, asserted against a list of forbidden
  phrases rather than left for a reviewer to notice.

**A2 and A4 are pre-existing.** Both overlays already set `sharingType = .none`
(`TakeoverOverlay.swift:602`, `RunHUDPanel.swift:368`) and neither survives its process. Re-run
rather than re-implemented, and recorded as such.

## The mock was wrong, and the build caught it

The surface set draws a second overlay state: a veil carrying the guest-route refusal. **That
state should not exist**, and the product's own logic says so — `refuseHostTakeoverIfRouted`
throws *before* any step runs, so a refused batch never takes the machine. A veil announcing
"Proctor is driving this Mac" over a batch that was refused would make the overlay mean two
incompatible things at once, which is exactly the ambiguity this item's brief warns against.

A refusal is a **notice**, not a takeover. `TakeoverSurface.Refusal` carries the copy for the
menu bar and the run line; the veil keeps the single state it honestly describes.

Per the wave direction, the mock was changed rather than left to disagree with the build: the
state is kept and its caption now records the correction, so the design error is visible rather
than deleted. The set's gates were re-run — ux-lint 0/0, and `mock_check.py`'s 52 contrast
failures are the same single ground-resolution artifact documented in the surface spec,
unchanged by this edit.
