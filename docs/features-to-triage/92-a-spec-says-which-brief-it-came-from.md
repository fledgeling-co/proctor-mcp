---
sources: [REQ-100, REQ-101]
---
# A spec says which brief it came from

- origin: the 2026-08-22 reckoning, which could not speak for 14% of the brief queue · 2026-08-22
- audience: whoever asks "what is left" and needs the answer to be trustworthy
- platforms: n/a — pipeline bookkeeping
- research: none; the measurement is in `docs/reckoning/2026-08-22/reckoning.md`

## What and why

A reckoning reconciles what the project said it would do against what anybody established. It ties
the two together by joining briefs to registry entities, and that join is the only inferential step
in an otherwise deterministic pipeline. Here it came out at 78 of 91.

The thirteen it missed are not lost work — every one names an item that is merged, checked
individually. They are missing because their spec never recorded which brief it came from. Sixty-six
specs do record it and every one of those joined perfectly, so the difference between a reckoning
that speaks for 86% of the queue and one that speaks for all of it is a single line written when the
id is allocated.

Without it the join has to fall back on guessing from the file number, and the numbering drifts:
brief 15 guesses PRO-0015, and PRO-0015 is a different feature entirely. A guess that lands on the
wrong item is worse than no join at all, because it reports a confident answer about the wrong thing.

Two halves, and they are separable. The backward half is the twenty-four existing specs that carry no
citation. The forward half is that the stage which mints a spec should write it, so this never
regrows — that stage lives outside this repository, and saying so is part of the work rather than a
reason to skip it.

## Acceptance sketch

- Somebody running a reckoning gets a join rate of 100%, with no brief excluded for want of a link.
- A spec written from a brief records which brief, without anyone remembering to do it.
- A spec written from something other than a brief says so, rather than being silently unjoinable.
- The join no longer falls back on the file number, so it cannot land on the wrong item.
- The reckoning's "cannot speak for" section shrinks to things genuinely unmeasured, rather than
  things merely unlinked.

## Assumptions made writing this

- Assuming the citation belongs in the spec rather than in a separate index, because a spec is
  already the artifact that survives and an index is a second source that drifts.
- Assuming the backward half is worth doing for all twenty-four rather than only for unmerged items,
  because a reckoning reads the whole history and a merged item is exactly what should be retirable.
- Assuming the forward half is a change to the shared pipeline stage rather than a convention in this
  repo's own docs, since a convention nobody enforces is what produced the twenty-four.
