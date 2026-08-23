---
sources: [REQ-008, REQ-042, REQ-043]
---
# The takeover overlay, and what it does not claim

**Wave 9, brief 6 of 11.** Reads `58`, `59`. Mock anchors: `#mac/takeover/armed`,
`#mac/takeover/guest`.

## The problem

`TakeoverOverlay` draws a veil and a label. The mock adds two things: the provenance chip on
the card, and the **guest-route refusal** — the state where a guest is configured, the batch
would have taken the host, and Proctor refuses rather than running.

The refusal is currently a diagnostic returned on the wire and drawn nowhere. A person
watching the machine sees nothing happen and has no way to know why. `GuestRoute` already
computes the decision and names the configured guest; this brief puts it on screen.

## What it should do

Two states. **Armed**: the veil, the label, the chip, Pause and Stop, and the drawn pointer
in the target's own plane. **Refused**: why, which guest caused it, and the switch that
clears it.

## The conversion contract

- `Takeover` and `GuestRoute` in Core already hold the decisions. The overlay reads them.
- The card's palette is fixed rather than scheme-dependent: it sits on a dark scene in both
  appearances, and the mock records that.

## Acceptance

1. The refusal names the configured guest and the variable that set it, from `GuestRoute`
   rather than from a string in the view.
2. The overlay and the drawn pointer set `sharingType = .none` and are excluded from
   captures. A capture of an app under test taken while the overlay is up is byte-identical
   to one taken while it is down — the campaign proved this with three identical frame
   hashes and it must stay true.
3. Stop is reachable from the overlay in both states.
4. The overlay never survives its process.

## The hard parts, named

**The overlay signals mechanism, not consequence, and that is a known open question rather
than a defect this brief closes.** PRO-0026 finding 10 recorded it and the reader carried it
rather than speccing it: an all-accessibility run can delete a file through `AXPress` with
this overlay never appearing, because nothing was posted into the event stream. The mock's
caption states the limitation out loud. Do not let the copy imply the overlay means "Proctor
is doing something significant" — it means "Proctor holds the event stream", which is a
narrower and honest claim.

**`PROCTOR_TAKEOVER_INPUT` is a separate capability and is not this brief.** The event tap
that swallows a person's input is gated by brief 66's consent sheet and by the switch
catalogue. This brief draws the notice; it does not acquire the capability.
