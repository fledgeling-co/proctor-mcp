---
sources: [REQ-155, REQ-156, REQ-157, DEF-280, DEF-281]
status: retired
validated-by: REQ-155, REQ-156, REQ-157 via CASE-0620, CASE-0621, CASE-0622, CASE-0623, CASE-0624, CASE-0625
validated-rungs: outcome
validated-provider: none
---
# What 1.1.0 still groups, and what it still lets a citation grade

**Wave 16, brief 6.** Two findings a peer session measured against `reckon` 1.1.0 *after* PRO-0102
built it. Neither is a regression in PRO-0102's work; both are things the fixed tool still does, so
they are either this item's remaining scope or an explicit decline with a reason.

## Where they came from, and why the source is worth naming

`graft` ran this repository's registry through both versions of the tool in the same session:

| Run | product | evidence | decision |
|---|---|---|---|
| installed cache, `1.0.0` | 48 | 21 | 0 |
| shared source, `224a696` | **0** | 21 | **48** |

Ratchet clean between runs, gate clean. And on the axis where the fix could have been worse than the
bug it replaced: the 19 requirements marked `observed` while sourced to the brief that states them
stay `unmeasured` under both versions, remedy unchanged. **`unjoined` did not absorb the
fabrication.** That is the measurement that makes 1.1.0 safe to rely on, and it is worth recording
because the obvious failure mode of adding a class is that the new class swallows a finding the old
one surfaced.

## Finding 1 — the split is still manual

The fixed tool still groups all four unmeasured cells into a single `BLOCK-0001` at 16.7%. A reader
who wants to know *which* cell is unmeasured still has to take the block apart by hand, which is the
work the class was supposed to remove. One block standing for four distinct remedies is a denominator
problem wearing a percentage.

## Finding 2 — `source` is read to join and is still allowed to grade

This is the sharper one, and the two findings compose rather than compete:

> **Read `source` to JOIN, refuse to let it GRADE.**

A `source` field inside the brief queue is doing two jobs at once. It is the citation that ties a
brief to a registry entity, which is exactly what the join needs and what PRO-0102 taught the tool to
read. It is also the circular case that must never promote a requirement to `observed` — a
requirement whose only evidence is the document that asserts it has not been measured, it has been
restated. `224a696` does neither: it does not use `source` to join, and it does not stop `source`
from grading.

So the repair is one predicate with two exits rather than two features. The same field, read for
identity and refused for evidence.

## What this brief is asking for

1. Split `BLOCK-0001` so each unmeasured cell carries its own remedy, or record why one block is the
   honest grouping.
2. Make `source` joinable and non-grading in one pass, with a fixture proving each half: a brief that
   joins *only* through `source`, and a requirement whose only evidence is its own `source` staying
   `unmeasured`.
3. Decline either explicitly if it is out of scope, in the spec, with the reason — an unrecorded
   decline is indistinguishable from an oversight the next time somebody reckons.

Upstream briefs holding the detail: `docs/upstream-briefs/` in the `graft` project, committed
`d441560`.

## What this is not

Not a claim that 1.1.0 is wrong. The version bump was the delivery half of PRO-0102 and it reached
nine projects; the two findings here are about what the tool still does, measured on a tree that
already carries the fix.


## Correction — 2026-08-22: both measurements were right, and the disagreement was a denominator

PRO-0103 measured finding 1 against this repository and reported that it did not reproduce: four
blockers with one case each contributing +0.3 points, and the 16.7% being the *briefs joined*
percentage rather than a block's weight. I passed that on as a correction to the finding. It was not
one.

The finding does reproduce on the ledger it was taken from:
`cases=[CASE-0020, CASE-0021, CASE-0022, CASE-0024] unblocks=4 coverage_gain_pct=16.7`, with a join
percentage of 2.0%. Four of twenty-four cases **is** 16.7%. Two correct measurements of two different
registries produced the same number for two different reasons, and the coincidence is what made each
look like a refutation of the other.

**So finding 1 stands for the registry it was measured on, and does not describe this one.** The
practice that would have prevented the whole exchange is cheap: **print the denominator beside every
percentage.** Two right numbers that disagree cost more to reconcile than either cost to produce.
