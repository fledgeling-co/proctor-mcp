# Reckoning — proctor-mcp, 2026-08-22

Campaign read: `docs/test-campaign` on `ai/wave-9` at `2bd01be`. Briefs: `docs/features-to-triage`,
91 files. Three items were mid-flight in their own worktrees while this ran and are excluded from
every count below: PRO-0082, PRO-0085 and PRO-0099.

## What this reckoning cannot speak for

**Thirteen of 91 briefs could not be joined to anything**, so nothing here says whether their
subjects are built, broken or abandoned. They are listed at the end. That is 14% of the brief queue
standing outside the partition, and it is the honest ceiling on every claim below.

The generated ledger's own headline — *"218 pieces of work remain — 183 product"* — **is wrong for
this repository and is not reproduced here.** Two mechanical faults produced it, both found by
reading the rows rather than the summary:

- It classed **all 108 defect records as `broken`** without reading `status`. Eighty-eight are
  `fixed`; eight are open.
- It classed **75 briefs as `unbuilt`** because they did not join. Every one of them names a merged
  item. `BRIEF-01-cua-schema-facade` is PRO-0001, merged in wave 1.

A third fault stopped the tool outright: `tokens()` assumes `evidence` is a string, and this
registry carries it as a list of paths. Patched in a local copy, not in the shared plugin.

## The axes, each with its own denominator

No blended percentage. These numbers disagree with each other, and the disagreement is the point.

| Axis | Measured | Denominator |
|---|---|---|
| Briefs joined to an item | 78 | 91 |
| Joined briefs whose item is merged | 78 | 78 |
| Defects open | 8 | 96 |
| Cases passing | 227 | 231 |
| Cases inconclusive | 4 | 231 |
| Passing cases armed | 227 | 227 |
| External effects witnessed | 27 | 29 |
| Requirements in the registry | 76 | — |

**The join is 66 by spec citation plus 12 by number confirmed against the ledger title.** The number
alone is not evidence: the brief numbering and the PRO numbering drift apart from brief 15 onward, so
`15-step-descriptions` guesses PRO-0015 and PRO-0015 is "Run HUD panel". Twelve joins survived
because the title also matched; thirteen did not and are excluded rather than guessed.

**Every denominator here is a floor.** The requirement count is what the documents describe, and
this campaign has repeatedly found surfaces no document named — the external-effect census went from
22 requirements to 29 as the work proceeded.

## What remains

**Eight open defects**, each recorded with its reason: DEF-033 (the ProctorAgent mutant survival
rate, a measurement that closes when the number moves rather than when an item lands), DEF-099,
DEF-140, DEF-141 (REQ-055's three named gaps), DEF-151 (nothing in the suite can post at pid 0),
DEF-162, DEF-163, DEF-165.

**Four inconclusive cases**, each against a ceiling checked in source rather than asserted — REQ-007's
`isAPerson` requiring `sourcePid == 0` among them.

**Two external effects unwitnessed** of 29.

**Thirteen unjoined briefs**, which is the largest single piece of not-knowing in this report:

`01-cua-schema-facade` · `15-step-descriptions` · `16-run-hud-panel` · `17-multi-session-queue` ·
`18-hud-character-assets` · `23-drawing-fault-must-not-kill-the-agent` · `40-page-scoped-refusal` ·
`46-a-delegated-call-is-still-gated-and-recorded` · `48-the-run-has-a-history-you-can-read` ·
`75-what-the-status-window-still-owes` · `78-the-skill-and-the-guest-lane` ·
`85-proctoragents-mutants-mostly-survive` · `91-eight-more-operator-paths-with-no-seam`

The last four are in-flight items whose specs exist but do not cite their brief. The first nine are
old enough that the citation convention did not exist when they were written.

## The cheapest thing that would make the next reckoning better

Have `shipyard:triage` write the brief path into the spec it mints. Sixty-six specs already do it and
those join perfectly; the thirteen that do not are exactly the ones this report cannot speak for. It
is one line at the point where the id is allocated, and it converts the weakest step in this pipeline
into a deterministic one.
