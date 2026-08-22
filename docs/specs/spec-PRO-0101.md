# PRO-0101: A spec says which brief it came from

**ID:** PRO-0101
**Status:** Ready for Plan
**Created:** 2026-08-22
**Last updated:** 2026-08-22
**Brief:** `docs/features-to-triage/92-a-spec-says-which-brief-it-came-from.md`

## Feature description

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

---

<!-- Triage, plan link, and progress sections are appended below. -->

## Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions. Bookkeeping with no product surface, and
the measurement behind it holds: twenty-four of the ninety-five recorded features name no
brief anywhere, which is exactly the population the reckoning could not speak for.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** **nothing customer-facing changes.** The change is to the written
  record of what this project decided to do, and to the shared step that creates that record
  for every project on this machine *(internal — an existing step that gains one line)*.
- **What users will see:** nothing in the app. Somebody running the "what is left" report gets
  an answer that covers the whole queue instead of 86% of it, and stops seeing a section of
  items it could not speak for that were merely unlinked.
- **Behaviour changes:** a feature record created from a written proposal names that proposal;
  a record created from something else says so, so it is never silently unaccountable.

**Assumptions**
- `[Operations]` The link lives in the feature record itself, not in a separate index. *(one artifact that survives; an index drifts.)*
- `[Operations]` All twenty-four unlinked records get a link, merged ones included. *(the report reads the whole history.)*
- `[Operations]` A record with no written proposal behind it says so explicitly. *(silence and "unlinked" must not look alike.)*
- `[Data & scope]` The forward half changes the shared creation step, not a note in this project's own documents. *(a convention nobody enforces is what produced the twenty-four.)*
- `[Data & scope]` The shared change touches only the step that creates the record, committed by explicit path. *(that repository is shared with other work.)*
- `[Operations]` Dropping the guess-by-number fallback is done once across this item and the report-tool repairs, whichever builds first; the second verifies rather than re-edits. *(both name it; two edits to one place is how it regrows.)*
- `[Operations]` Existing links keep the form the sixty-six working ones already use. *(they join perfectly; a new form would need its own reader.)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0101` before the planner picks this up.*

---

### Pipeline record — PRO-0101 *(machine trailer; not part of the review above)*

- Measured on HEAD `3fb7681`: 95 files in `docs/specs/`; **71** mention a
  `docs/features-to-triage/` path anywhere, **24** mention none — PRO-0001..0017 (all),
  PRO-0034, PRO-0045, PRO-0047, PRO-0063, PRO-0075, PRO-0076, PRO-0096. That 24 matches the
  brief's figure exactly. Only 48 carry the structured `**Brief:**` header line, so the
  reckoning's join reads any path mention, not the header.
- The thirteen unjoined briefs and their merged items are already enumerated in
  `docs/reckoning/2026-08-22/reckoning.md`; the backward half has its mapping and does not
  need to re-derive it.
- Forward half lands in `~/Dev/fledgeling-plugins/plugins/shipyard/skills/triage` — the id
  allocation step in `references/spec-format.md` and the scaffold it defines. Shared repo
  measured clean at `a15febf` while this triage ran. Discipline: touch only the `shipyard`
  plugin, commit with an explicit path, never `-a` and never `.`, stop and report if files
  appear entangled.
- Note for the planner: this repo's specs already write `**Brief:**` on line 7 of the header,
  and PRO-0100/0101/0102/0103 were minted with it. The forward half is making that automatic,
  not inventing it.
- Out-of-family spec review: see the shared record at the foot of `spec-PRO-0103.md`.
