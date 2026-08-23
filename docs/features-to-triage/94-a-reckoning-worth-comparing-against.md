---
sources: [REQ-102, REQ-103, REQ-104, REQ-105, REQ-106, REQ-107]
---
# A reckoning worth comparing against

- origin: proposed while running the first reckoning · 2026-08-22
- audience: whoever wants to know whether the not-knowing is shrinking
- platforms: n/a — pipeline bookkeeping
- proposed-by-ai: true

## What and why

The reckoning that ran today is a snapshot, and a snapshot answers the smaller question. It says how
much is unmeasured now. It cannot say whether that figure is falling, and it cannot catch the failure
it most needs to: an item quietly reclassified from unmeasured to something else across runs, until
nothing remembers it was never checked.

The tool already carries the mechanism — a ratchet that compares two ledgers and enforces that an
item may leave unmeasured only by being measured. It has nothing to compare against, because this was
the first run. A second run is what turns the ratchet on, and after that the interesting number stops
being the total and becomes the delta.

The honest reason to propose this rather than assume it: a reckoning is only worth repeating if
somebody reads it. One run produced three tool defects and a structural fix worth taking, which is a
decent return, but that is one data point about a tool's first contact with a new repository, not
evidence that the tenth run will earn its keep. So the question this brief really asks is what
cadence makes it useful without making it wallpaper — after a wave closes, before a release, or on a
clock.

## Acceptance sketch

- A second reckoning exists to compare the first against, and the comparison runs rather than being
  described.
- An item that leaves the unmeasured class does so because somebody measured it, and a run that
  cannot show that fails rather than reporting a smaller number.
- The report leads with what changed since the last one, not with the totals.
- Somebody who reads two consecutive reckonings can say whether coverage is improving without
  recomputing anything.
- A cadence is chosen and written down, so the second run is not simply whenever somebody remembers.

## Assumptions made writing this

- Assuming the cadence question is genuinely open rather than obviously "every wave", because the
  cost of a reckoning nobody reads is that the next one gets skipped.
- Assuming the ratchet is worth turning on before the join is perfect, since the delta is meaningful
  even over a partial denominator as long as the denominator is stated.
- Assuming this is proposed rather than asked-for, so deleting this file is the way to say no.
