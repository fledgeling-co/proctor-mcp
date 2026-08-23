---
sources: [REQ-032, REQ-088, REQ-089, REQ-090]
---
# What the status window still owes, and one permission that may lie

**Wave 11, brief 6 of 6.** Independent of `70`-`74`. Sequence the last item first: it is the only
one here that can mislead a person about whether their machine is safe.

## Where these came from

`docs/specs/spec-PRO-0036.md` closed with a "Child work found" list of six items. All six were
deliberately out of scope for that item and none has been picked up since. They are grouped here
because five of them are the same surface and the sixth was raised by that item's own
out-of-family review.

## The sharp one — a revoked permission that stays reported as granted

Recorded at PRO-0036 as child item 6:

> A revoked Screen Recording permission is frozen the same way a denial is, so the agent can
> report a permission granted after a person has taken it away, until it restarts.

If that holds, a person who revokes Screen Recording in System Settings is told by Proctor that
Proctor still has it, for as long as the agent keeps running. That is the wrong direction for a
permission to be wrong in: the product's whole posture is that a person can take the machine back,
and a stale grant reading tells them they did not.

**It has not been reproduced, and the brief says so rather than asserting it.** The claim came
from a reviewer reading the code, not from a measurement. `Sources/ProctorCore/AgentRecovery.swift`
records a *different* and adjacent accepted cost, in the window process rather than the agent:

> The cost of that gate, accepted knowingly: if `CGPreflightScreenCaptureAccess` caches per
> process the way its ScreenCaptureKit neighbour does, a window that was running before the grant
> will agree with the agent and the offer will never appear.

That is the same caching mechanism pointed the other way — a grant that arrives late is missed,
rather than a revocation that arrives late being missed. Whether the agent's own probe has the
symmetric problem is the question, and it is answerable on this machine in about ten minutes.

**First step is a measurement, not a fix.** Start the agent with Screen Recording granted, confirm
`proctor doctor --json` reports it granted, revoke it in System Settings without restarting
anything, and read `doctor` again. Record what it says. If it still reports granted, that is a
defect with a number and a surgical fix; if it re-probes correctly, the child-work item was wrong
and gets closed as such. Either outcome is worth the ten minutes, and asserting the defect without
running it would be the failure this repo has already been bitten by twice.

If it does hold, the decision attached is whether the agent re-probes on a revocation signal or
the window papers over it. PRO-0036 declined to decide that, correctly, because it changes what
the agent does rather than what a window draws.

## The five that are the status window's own shape

1. **The health report calls the Shortcuts CLI a permission.** It is appended to the report's
   permissions list, and only when it is missing. PRO-0036 corrected the window; every other
   reader of that report still sees a tool in the permissions list. The fix belongs with the
   report's shape rather than with each reader, and the CLI and the TUI are both readers.

2. **The per-lane readiness block is on the wire and nothing renders it.** The agent already sends
   it. This is the natural next question the window can answer, and it costs a section rather than
   a protocol change.

3. **The policy posture block is on the wire and nothing renders it.** Same shape. PRO-0050
   recorded its own child work about the policy tool answering freely, which bears on how much a
   window should show — read that before deciding the section's contents, because "render
   everything on the wire" and "render what a person needs" are different answers here.

4. **The first-run walkthrough's "Already allowed? Open System Settings" line** carries the
   misdirection PRO-0041 fixed on the grant row. The row was corrected; the walkthrough was not.
   Same wording, different surface, and a person meets the walkthrough first.

5. **The window mock has drifted.** It shows the window before the toolchain report existed and
   still carries a menu row that was deleted. The choice is binary and should be made rather than
   left: either the mock is maintained against the build, or it is marked as a record of a past
   state. A mock that is neither is a design of record that quietly disagrees with the product.

## The conversion contract

- Item 6 measured first, with the `doctor --json` output before and after revocation pasted
  verbatim. A defect record only if the measurement produces one.
- Items 1 and 4 are corrections with a test each: the report's permissions list contains only
  permissions, and the walkthrough's line matches the grant row's corrected wording.
- Items 2 and 3 are new sections, each reading its strings from `StatusSurface.Copy` — which is
  `74`'s A2 clause, so sequence them after `74` or write them to it directly rather than adding
  two more sections of literals.
- Item 5 is a decision recorded in the mock itself, either as a maintained artifact or as a dated
  record of a past state.
- `./scripts/test.sh` green, with the suite count before and after.

## What this brief does not do

It does not add a warning about a revoked permission before the measurement says one is needed,
and it does not change what the agent does on a revocation signal without that decision being
made deliberately. PRO-0036 declined to decide it; this brief surfaces it rather than deciding it
by default.
