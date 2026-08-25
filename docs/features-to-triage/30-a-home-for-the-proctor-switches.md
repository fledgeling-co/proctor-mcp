---
sources: [REQ-033, REQ-041]
status: retired
validated-by: REQ-033, REQ-041 via CASE-0041, CASE-0043, CASE-0051, CASE-0083, CASE-0715
validated-rungs: effect-witness, outcome
validated-provider: Darwin.bind/listen/accept in Sources/ProctorAgent/Server.swift; Darwin.connect in Sources/ProctorCore/Transport.swift
---
> **REVISED for wave 7, 2026-08-15.** Still wanted, and the switch list changes. The UI switches (`PROCTOR_CURSOR`, `PROCTOR_HUD`, `PROCTOR_YIELD`, `PROCTOR_YIELD_INPUT`, `PROCTOR_TAKEOVER_INPUT`) survive because the supervision surface survives. `PROCTOR_SECOND_LANE` may not, since brief 45 hands browser work to Cua. Read `00-WAVE-7-DIRECTION.md` and enumerate the switches that actually exist when this is built rather than trusting the list below.

# A home for the PROCTOR_* switches

## The problem

Proctor's behaviour is configured by environment variables read at agent start:
`PROCTOR_CURSOR`, `PROCTOR_HUD`, `PROCTOR_YIELD`, `PROCTOR_YIELD_INPUT`,
`PROCTOR_TAKEOVER_INPUT`, `PROCTOR_SECOND_LANE`. That is six switches with no
home. PRO-0026's review made the case plainly and it is true of all six rather
than of the one it was raised against: an environment variable leaks to every
child process the agent spawns, and it vanishes from a launchd plist the moment
somebody reinstalls, so a person who turned something on has no way to see that
it is on and no way to turn it off again except by editing a plist by hand.

PRO-0024 logged the same gap from the other end: a status-window control for
`PROCTOR_SECOND_LANE` was deliberately not built with the lane, because it needs
a preference store and a way to write the agent's launchd environment.

## What it should do

Give the switches one place to live that a person can see and change, and make
the agent read that place rather than only its inherited environment.

The status window is the surface: it already walks somebody through two
permission grants and now offers agent recovery, so it is where a person goes
when they want to know what Proctor is doing and change it.

## The hard parts, named

- **Two sources of truth, and a precedence rule.** An environment variable set
  by whoever launched the agent and a stored preference are both real inputs.
  Say which wins and why, and make the surface show the effective value together
  with where it came from, because a toggle that silently loses to an env var is
  worse than no toggle.
- **Changing a preference must reach a running agent.** The agent is long-lived
  and launchd-started. Writing a plist changes what the *next* launch sees. A
  switch that appears to take effect and does not until a relaunch is the same
  class of defect PRO-0028 deleted a button for. Either apply live, or say
  plainly that it applies on relaunch and offer the relaunch.
- **`PROCTOR_SECOND_LANE` is a security control, not a preference.** PRO-0024
  made it opt-in deliberately, on the reasoning that installing a CLI is not
  consent to have it named to a model with a shell. A UI toggle is the right
  place for that consent, and it is also a place somebody could flip without
  reading what it means. Whatever the surface says next to it has to carry that.
- **Writing a launchd environment from a GUI app** touches the agent's own
  installation. Say what it writes, where, and what happens on the next
  `install.sh`, which rewrites the plist.

## Not in scope

New switches. This gives the existing six a home; it does not add a seventh.
