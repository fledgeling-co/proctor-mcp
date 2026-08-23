---
sources: [REQ-057, REQ-058, DEF-030, DEF-032, DEF-040]
---
# The campaign's own instruments, and what each of them could not see

**Wave 13, brief 4 of 6.** DEF-030, DEF-032, DEF-040, DEF-041, DEF-055, DEF-057, DEF-058. Seven
findings about the tools that measure this project rather than about the project.

They are one brief because they share a failure mode: **an instrument that reports a number nobody
can act on, or reports a clean result over a population it never examined.** Every one was found by
somebody checking the instrument rather than reading its output.

## The two that make a green mean less than it looks

**DEF-041 — a capped list read as a population.** `campaign.py check` prints at most twelve
unwitnessed requirements. The real external set is twenty-two. Reading the printed list as the
population under-scoped a whole wave by ten items, and it is still printing twelve today while the
set behind it is eighteen. The fix is not to raise the cap: it is to print the **denominator**
beside the list, so a truncated display can never be mistaken for a count.

**DEF-030 — a control that exercises one of the two passes it arms.** `--seed-strengthen` passed in
both directions, and decomposing what the seeded mutation actually fires showed it hits only the
`uncensused` predicate. So `unclassed examined=47 findings=0` survived the control that exists to
arm it, and remains an unwatched zero. A control that arms half a gate leaves the other half
indistinguishable from a predicate that cannot fire.

## The two about the mutation runner

**DEF-032 — an operator that spends a slot on an edit the compiler must reject.**
`mutate_swift.py`'s integer-literal increment matched the `0` in a closure shorthand parameter.
Mutant 24 rewrote `{ bind(fd, $0, size) }` to `bind(fd, $1, size)`, which cannot compile because the
closure takes one parameter. `$0` and `$1` are not integer literals. The operator table's stated
contract is that every operator keeps the types the same so the file still compiles — an
unbuildable mutant is a wasted sample, and with 24 slots against 3,189 sites the samples are the
scarce thing.

**DEF-055 — a note that contradicts its own evidence.** CASE-0074 records the mutation run's
starting load as 11.20; `evidence/mutation-agent.txt` records 22.92. One substring. It matters
because the load figure is what makes a timeout-scored kill trustworthy or not.

## The two about classification

**DEF-057 — an oracle rung that is not on the ladder.** `CASE-0102..0105` record
`oracle: "static-analysis"`, which is not in the rung set, so `campaign.py` files all four under
`unrated` and its own comment says unrated counts *never as adequate*. REQ-048's coverage rests on
four cases the ladder does not recognise.

The rung may be honest rather than wrong: the ladder describes checks against a **running** product,
and a grep over source runs none of it. So the decision is real — either the ladder gains a
source-analysis rung with a stated position below `outcome`, or those four cases are re-expressed as
checks against the built product. Reclassifying them to `structural` without changing what they
check would be the second option's label over the first option's evidence, and that is the one route
that must not be taken.

**DEF-040 — a declared effect class naming a boundary the code never crosses.** REQ-024's effect and
provider name the browser-routing path as `subprocess`, and the path does not cross that boundary.
This is the census's own target condition — a guarantee true because nothing does the thing — found
in the census's own data. Reclass the requirement honestly, or record it `vacuous`, which is the
status that exists for exactly this.

## The one about a hand merge

**DEF-058 — an orchestrator merge dropped a flow.** Reconciling `inventory.json` at the PRO-0081
merge, only `defect` and `requirement` were merged and ours was taken as the base document, so
PRO-0081's addition to `flow` was lost with it. The capture stayed on disk and its verdict stayed in
`witness-verdicts.json`; only the subject left the published set, and judged fell 6 to 5 against a
ratchet of 6. `capture-lineage --gate` exited 2 and named it.

Already repaired. It is here because the remedy is mechanical rather than a resolution to be
careful: **a registry merge sweeps every key with a uniqueness assertion per key**, and that belongs
in a script rather than in an instruction. Write it.

## The conversion contract

- `campaign.py check` prints the denominator beside every capped list.
- The census control arms both passes, proved by watching each go red.
- The mutation runner's integer operator no longer matches closure shorthand, with a test over a
  fixture containing `$0`.
- CASE-0074's load figure corrected.
- DEF-057 decided and recorded, whichever way.
- REQ-024 reclassed or recorded `vacuous`.
- A registry-merge script that sweeps every key, with a test that a dropped key is caught.

## What this brief does not do

It does not raise any ratchet, and it does not change a case's status to clear a gate.
