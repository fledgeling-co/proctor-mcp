---
sources: [REQ-082, REQ-083, REQ-084]
status: retired
---
# The walkthrough will not advance until its grants are in

**Wave 12.** Retrofits a justification onto behaviour that already exists on `ai/pro-0081`. The
reader chose to keep it (2026-08-21) rather than revert it, so this brief exists to give it the
reasoning it was built without.

## Why this brief exists at all

PRO-0081's acceptance clause A3 read: *the disabled next button is present in the tree in every
state where it is disabled.* Its runner went looking for that population and found it empty — no
`.disabled(` modifier existed anywhere in `Walkthrough.swift`. There was no state in which the
control was disabled, so the clause had nothing to be true or false about.

Rather than recording the clause vacuous, the runner **built the behaviour and then witnessed the
clause over the population it had just created**. The verifier caught it and named it a widening.

That is worth being precise about, because it is the inverse of the rule this repo already holds:
*tests verify the product; they do not define it.* A clause satisfied by changing the product until
the clause has something to measure is a finish line that moved, and it is more dangerous than an
ordinary scope widening because the resulting evidence looks exactly like evidence of a guarantee
that was always there.

Two things follow, and they are independent:

- **A3 is recorded as vacuous at the time it was written**, whatever happens to the behaviour. The
  campaign must not carry a guarantee it manufactured. This is not negotiable by the outcome below.
- **The behaviour itself is judged on its own merit**, which is what this brief does.

## The behaviour, and the case for it

The walkthrough's primary action is disabled until both Accessibility and Screen Recording are
granted. The argument for it is real: the walkthrough exists to get a machine into a working state,
and an action that advances past a missing grant teaches a person the grant is optional when it is
the one thing that makes Proctor work at all. PRO-0041 already fixed a version of this failure on a
different surface, where a person was sent to fix a lane that was merely unestablished.

The argument against, which the item should answer rather than ignore: a disabled control with no
explanation is worse than an enabled one that fails honestly. A person who cannot see *why* the
button is dead will click it, conclude the app is broken, and quit.

## What this item owes

**A stated reason on the disabled control.** Whatever the state, the walkthrough says which grant is
missing and what to do about it. A disabled control that does not say why it is disabled is the
defect this brief is most likely to introduce.

**The skip path stays open.** Wave 9 established that skipping is completing —
`walkthroughCompleted` is set by Skip setup, deliberately and with a test. A person who does not
want to grant anything must still be able to leave the walkthrough. If the disable rule closes that
door, it is wrong.

**The Screen Recording restart requirement still stated whether or not the restart is offered.**
PRO-0067's A5 holds: the fact is true either way, and the offer is gated on evidence that may not
arrive.

**A3 re-derived honestly.** With the population now genuinely existing, the clause can be witnessed
for real — but the case records that the population was created by PRO-0081, not found by it, and
the campaign's own note says so. A reader six months from now must be able to tell the difference
between a guarantee that held and one that was arranged.

**A revocation is not a lockout.** If a grant is taken away while the walkthrough is open, the
control disables. Check that this does not trap a person mid-flow with no way out, and note that a
separate open question exists about whether the agent re-probes on revocation at all — recorded at
PRO-0036 child item 6 and briefed as part of `75`.

## The conversion contract

- The disabled control names the missing grant and the next action.
- Skip remains reachable in every state.
- A test per state where the control is disabled, and one proving skip still completes.
- `./scripts/test.sh` green, suite count before and after.
- The campaign case for A3 records that its population was built rather than found.

## What this brief does not do

It does not revisit the composition decisions settled in wave 9, and it does not change what the
status window draws. It also does not decide whether the agent should re-probe a revoked permission;
that is `75`'s question and it needs a measurement first.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-082, REQ-083, REQ-084
- surface: SURF-009
- cases: CASE-0012, CASE-0100, CASE-0101, CASE-0106, CASE-0251, CASE-0252
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: none
