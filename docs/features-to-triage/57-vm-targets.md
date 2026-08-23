---
sources: [REQ-017, REQ-018]
---
# VM targets: test in a guest, and say which machine

**Wave 8.** Seven items, PRO-0056 through PRO-0062. The approved plan is at
`~/.claude/plans/groovy-napping-parrot.md`; this file is the repo's copy of its
direction, so a fresh session can pick the wave up from the tree alone.

## The problem

Proctor's synthetic-event steps enter the single system event stream, which means
they take the machine away from whoever is using it. PRO-0018, PRO-0026 and
PRO-0033 are all damage control for that: a full-screen takeover statement, an
input block, a contention yield, a click-to-Stop panel. None of it is needed if
the application under test is in a guest.

So: run those steps in a guest, leave the host's user alone, and make the overlay
say plainly which machine a run is on.

## Two constraints settled before the wave started

**Cua for actuation, Proctor for observation.** Cua's screenshots carry no
frame-status metadata and Apple makes checking `SCFrameStatus` a precondition of
trusting a frame, so Proctor cannot be a pure consumer of another tool's surface.

**No provisioning layer.** Every macOS guest on Apple silicon runs through
Virtualization.framework, Parallels included, so writing our own wrapper avoids no
bugs and takes on a lot of undifferentiated work. `lume` and `prlctl` are CLI
adapters; Proctor owns no VM lifecycle code. Both readings were re-confirmed by
two out-of-family reviewers with the options presented in opposite orders.

## What TCC actually costs, since it is the real work

Cua does not work around it either. Their own guide: *"SIP does not grant
Accessibility, Screen Recording, Automation, or direct-capture consent."* A person
grants once in the guest's GUI session, then `lume clone` reproduces it. Two
constraints make that unavoidable rather than lazy: agent and daemon tool calls
cannot raise macOS permission UI, and SSH is not the foreground Aqua session that
owns the visible desktop.

The signature rule is one this repo already knows. Cua's troubleshooting says *"A
source build with an ad-hoc or changing signature gets a different TCC identity"*,
which is exactly what `CLAUDE.md` says about Developer ID versus ad-hoc.

## Known upstream risk

trycua/cua issues #870 and #912, open since January 2026: macOS **Tahoe** guests
render no application windows at all (`kCGWindowMemoryUsage: 2368` bytes against
~1.2 MB expected, `kCGWindowSharingState: 0`). A signed, notarised app with both
grants at `auth_value=2` still reports Not Granted and crashes during window
layout. Apple Feedback FB21748086 is filed; a maintainer says it may not be
fixable until Apple acts. This is Apple's framework, so no choice of wrapper
avoids it. **Verify against a Sequoia guest.**

It is also this repo's own pinned lesson in someone else's tree: window metadata
reporting `onscreen` and `alpha=1.0` is not proof anything rendered. A
frame-status check reports that capture as untrustworthy instead of returning a
plausible screenshot of nothing, which is worth a test of its own.

## Decisions taken by the user

- **Auto-route, always disclosed.** Safe only because PRO-0056 lands the
  disclosure first.
- **All three platforms in this wave**, at two witness tiers.

## The items

| ID | What | Depends on |
|---|---|---|
| PRO-0056 | A run says which machine it is on | — |
| PRO-0057 | The witness tier, and what it refuses | 0056 |
| PRO-0058 | Guest providers: lume and prlctl | — |
| PRO-0059 | `proctor_guest`, the lifecycle tool | 0058 |
| PRO-0060 | Reaching a guest's Proctor over SSH | 0056 |
| PRO-0061 | Auto-routing, and the disclosure that makes it honest | 0056, 0059, 0060 |
| PRO-0062 | The overlay says which machine | 0056, 0061 |

## Witness tiers

| Tier | Substrate | What works |
|---|---|---|
| `native` | macOS guest or remote Mac running a full Proctor | Everything: `SCFrameStatus`, AX tree, tri-observer `agree`, fidelity, determinism |
| `delegated` | Linux/Windows guest via Cua | Actuation and screenshots only |

Tier 2 does not silently degrade. It reuses the skill's existing rule: an
assertion that could not be evaluated is not an assertion that passed, so those
assertions report **skipped with a reason**.

## The wave's changelog obligation

`CHANGELOG.md` gets **one** entry, at the end, written through
`/create-luke-content` at format `marketing`. Recorded here rather than left
implicit because the per-item convention is to log in the same change: these items
add fields and seams but no capability a reader can use until PRO-0062, and seven
entries for one feature would be noise. `ORCHESTRATOR.md` carries the obligation
so it cannot drift.
