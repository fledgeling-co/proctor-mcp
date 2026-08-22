# PRO-0101: A spec says which brief it came from

**ID:** PRO-0101
**Status:** In Review
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

## A citation has to resolve, and this repo has already proved that is a separate claim (added 2026-08-22, orchestrator)

Measured at `9f99a0f`, across all 99 specs: **75 cite a brief path, 24 cite none, and of the 75, four
cited paths did not exist.** The four were this wave's own — PRO-0100 through PRO-0103 — deleted by
`400808d`, the triage commit that wrote their specs, in a message that describes everything else it
did and never mentions the deletion. The other 71 keep their briefs, so consuming a brief at triage
is not this pipeline's convention; those four were an exception nobody recorded.

The four briefs are restored on `main`, so the count now reads 71 of 75 resolving and 0 dangling.
What the episode establishes is that the join rate this item optimises and the usefulness of a
citation are two different measurements. The join reads a path mention, so a spec citing a deleted
brief joins at 100% while the reference resolves for nobody, and a scheme that only guarantees
presence would have shipped 99 citations of which any number could be dead.

So this item owes one more acceptance clause: **a cited brief path resolves in the working tree, and
whatever check proves a spec carries a citation proves the citation resolves in the same pass.**
Where a brief is deliberately consumed, the citation records the commit that holds it rather than a
path that does not — a recoverable reference rather than a dangling one.

Scope note: this widens the item by one clause and one check. It is not a licence to change how
triage handles briefs; the four restored files match the majority convention, and any deliberate move
to consuming them is a separate decision with its own record.

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

---

## Progress — 2026-08-22 (`ai/pro-0101`)

**Ids allocated:** REQ-100, REQ-101 · CASE-0430..0438 · DEF-215 · SURF-024. Started at
CASE-0430 / REQ-100 / DEF-215 / SURF-024 because `ai/pro-0100` reserved DEF-200..209 and
CASE-0401..0409 unused and `ai/pro-0102` reaches CASE-0429 / REQ-099 / DEF-214 / SURF-023.

**Backward half.** The 24 uncited specs now carry a citation. Twenty name a brief; four say they
never had one and name what they had instead — PRO-0063 the screenshot-encoding research as a
follow-on to PRO-0006, PRO-0075 the campaign's own report, PRO-0076 a direct request against PRD
§9 and §10, and PRO-0096, which already carried the form. Every citation was established by
reading the brief against the spec. The seven where brief number and id disagree say so on the
line, because they are the counterexample to the fallback this item removes: PRO-0014 through
PRO-0017 sit one behind briefs 15 to 18, and PRO-0034 is brief 35, whose own retirement banner
names PRO-0034 while the number points at PRO-0035, a different feature.

**The reverse direction** needed somewhere to put a brief that is accounted for and still
uncitable, so `docs/feature-specs/UNCLAIMED-BRIEFS.md` records four with their reasons. Two of
them are DEF-215: briefs 23 and 40 belong to PRO-0022 and PRO-0039, ledger rows with no spec file,
so there is no artifact to carry a citation. That defect is recorded rather than fixed — writing
retrospective specs for two retired items and one merged one is a separate decision.

**Forward half**, in `~/Dev/fledgeling-plugins` at `364c785`, committed by explicit path over two
files under `plugins/shipyard/skills/triage/`. The spec scaffold gains a `**Brief:**` line, the
id-allocation step is told to fill it, `references/spec-format.md` documents the three forms, and
SKILL.md step 1 tells triage to write the citation. Nothing there changes whether triage consumes
a brief; the consumed case is handled by the citation form instead.

**The added clause.** `scripts/campaign/spec_citation_measure.py` proves presence and resolution in
one pass: a path-form citation must resolve in the brief queue, and a consumed-brief citation
`path @ sha` must resolve at the commit it names. No spec uses the commit form yet, so CASE-0432 is
the only thing exercising that path and it is armed both ways on immutable shas — `@ 3fb7681` PASS
because that commit holds the brief, `@ 400808d` FAIL because that is the commit which deleted it.

**The number fallback was already gone**, removed by PRO-0102 at `224a696`, so this item verifies
rather than re-edits, which is what this spec's own assumption asked of whichever item reached it
second. CASE-0436 executes `project_id_in` rather than reading it, and is armed in both directions.

**Gates.** `./scripts/test.sh` 2,061 tests in 251 suites, exit 0, twice — the baseline unchanged,
and no Swift was touched. `spec_citation_measure.py` 14/14, exit 0. `spec_citation_arm.py` 18/18
mutations pinned, 14/14 checks watched to fail, exit 0. `test_instruments.py` 62/62 exit 0.
`operator_path_gate.py` exit 0. `defect_gate.py dropped` exit 0.

## Out-of-family review — gemini-3.7-flash-high, 2026-08-22

`Needs More Work`, and three of its five points were taken. Full reply at
`docs/test-campaign/evidence/PRO-0101/gemini-review.md`; the lane verified its own subject before
answering.

**Taken.** A consumed-brief citation took its sha from `git rev-parse --short HEAD`, which names a
commit on the branch doing the triage: squash-merge or rebase that branch and the citation points
at an object no clone has. It now reads `git log -1 --format=%h -- <path>`, the commit that filed
the brief, and says what to do when that commit is on the same unmerged branch. `git cat-file -e`
is satisfied by a tree entry and by a zero-byte blob, so the check now reads the object's type and
size — armed against a purpose-built git fixture, because the real history holds no commit where a
cited brief path is either shape. And a `none.` reason has to name an artifact rather than reach a
character count, since "none. not applicable here" clears twenty characters and names nothing.

**Taken in a different form.** The review was right that a brief claimed only in prose sits outside
the uniqueness check. Its remedy — normalise all 24 prose citations to the header form — was
measured against this tree and rejected: brief 55 would then be claimed by two headers and brief 57
by seven, because those are direction documents several items were cut from at once. The four
many-to-one briefs are enumerated in the register with their counts instead, and the count is what
CASE-0439 watches, so a designed exception is recorded rather than silent.

**Not taken.** Moving a consumed brief to an archive directory instead of deleting it changes how
triage handles briefs, which this spec's own scope note rules out as a separate decision with its
own record.

## Defects

| ID | Title | Disposition |
|----|-------|-------------|
| DEF-215 | Four ledger rows have no spec file, so two briefs have no artifact that could cite them | (recorded) — accounted for in `docs/feature-specs/UNCLAIMED-BRIEFS.md`; the fix is a separate decision about whether a retired item earns a spec |
