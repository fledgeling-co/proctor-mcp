# PRO-0104: An input the check cannot classify

**ID:** PRO-0104
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Defects:** DEF-201, DEF-202, DEF-203
**Registry ranges:** CASE-0500..0526 · REQ-120..123 · DEF-230 (recorded)
**Brief:** `docs/features-to-triage/97-an-input-the-check-cannot-classify.md`

## Feature description

Three instruments across two repositories each meet an input they have no rule for and guess rather
than say so. DEF-201 and DEF-203 are the same sentence twice — a scanner that reads a whole document
for a token, with no exclusion for fences, comments or struck-through text, cannot tell a citation
from a mention of one. DEF-202 is the same failure in a status vocabulary, and it is the one that
shows why the class matters: it fails in **both** directions and only one is visible.

## What and why

An unrecognised input is currently resolved by a default. Over-reporting announces itself — an
inflated backlog makes somebody look. Under-reporting does not: a gate selecting its population by a
single status string drops rows meaning *still broken* out of the obligation entirely and prints a
clean count over a quietly smaller population. **A clean green is a worse failure than an inflated
backlog, because nothing about it asks to be checked.** Widening one such gate elsewhere surfaced
five real defects and took owing from 19 to 24.

## Acceptance sketch

- Every input the three instruments meet is classified explicitly as one thing or the other.
- An input that cannot be classified is a **finding naming the input and its count**, never a default
  in either direction and never a silent pass.
- The two scanners exclude fenced blocks, HTML comments and struck-through text before matching, with
  a fixture per kind rather than one in aggregate.
- `partially-fixed` stays in the owing set. It is not a member of the not-remaining-work words: a half
  still broken owes a reproduction for that half, and retiring it would make the tool under-report for
  the first time.

## Assumptions made writing this

- Assuming the repair is a predicate rather than a longer list or a longer floor, because both of those
  extend the set of inputs the instrument guesses correctly about and leave it guessing.
- Assuming DEF-201's "0 occurrences across 91 briefs" is a fact about this repository's idiom rather
  than about the risk, since a repository citing by convention has the opposite prior and one does.

## Acceptance

**A1 — every input is placed by a rule that is written down.** reckon's three registry
vocabularies are closed sets: `CASE_VOCABULARY`, `DEFECT_VOCABULARY` and `EVIDENCE_VOCABULARY`,
the last reached through the existing evidence tuples so it cannot drift from test-campaign's
own `REQ_EVIDENCE`. `spec_citation_measure.py` gains the same shape one level up: the header
relations that account for a brief are enumerated (`Brief`, `Supersedes`, `Direction`), and the
kinds a `none.` reference can take are enumerated (a path, a PRD section, a commit, a name).

**A2 — an input no rule covers is a finding naming the input and its count.** `unclassified_inputs`
returns one entry per unclassifiable input with the rows carrying it; `gate` raises a
`vocabulary` violation per entry, `verdict` returns 4, the report carries a table, and the
headline names the first four. The row is still placed, because the partition has to be total,
and the placement is disclosed as this tool's decision rather than the registry's.

**A3 — the two scanners exclude fenced blocks, HTML comments and struck-through text, with a
fixture per kind.** `citable_text` in reckon and `citable` in the citation measure blank all
three before anything is matched. Six fixtures prove the six halves separately: three
exclusions in reckon's selftest, each with its own two-way control, and three mutations in
`spec_citation_arm.py` against the citation of record plus three more against reverse totality.

**A4 — a brief is accounted for by a decision, never by an incidental mention.** Reverse
totality reads header accounts, citations of record and register rows. A brief whose only trace
is a prose mention, or a mention inside one of the three excluded regions, is unclaimed and named
with its count.

**A5 — a `none.` citation resolves rather than names.** A token holding a `/` or resolving
repo-relative is a path and must exist; a `§N` must be a heading in `docs/PRD.md`; a 7-to-40-hex
token must resolve in git. A bare name never satisfies the requirement.

**A6 — `partially-fixed` stays in the owing set.** `DEFECT_PARTIAL` classes `broken` with
`is_work_item` true, and `DEFECT_LEGAL_CLASS` refuses a row at that status classed
`verified-done`.

## What was built

Two repositories, and the reckon half is the shared one.

`~/Dev/fledgeling-plugins`, reckon 1.1.0 to 1.2.0 at `a2d4db1`: the vocabulary partition, the
scanner, `unclassified_inputs`, exit code 4, the report table, twenty-three new selftest checks,
and the two documentation files that carry the legality table. `DEFECT_NOT_OWING` classes
`waived` rather than `verified-done`, because those seven words rule on whether the row was ever
a defect rather than recording a repair, and a `cannot reproduce` is one reproduction away from
being work again.

This repository: `citable`, `header_segments`, `references` and four new checks in
`spec_citation_measure.py`, taking it from 15 to 19; eleven new mutations in
`spec_citation_arm.py`, 34 in total, with every one of the 19 checks watched failing.

One spec was reclassified by the change. `spec-PRO-0096.md`'s citation read *none. The three
findings on `campaign.py check` are the specification*, and `campaign.py` is not a file this
repository holds, so the reason named something without resolving to anything. It now names
`docs/test-campaign`, which is the directory the findings were reported over, and the three
findings are quoted under their own headings in that spec already.

## What it measures on this tree

reckon 1.1.0 and 1.2.0 over the identical inputs — 100 briefs, 335 cases, 129 defect rows, 105
requirements, 26 surfaces — recorded in
`docs/test-campaign/evidence/PRO-0104/vocabulary-delta.json`:

| Reading | 1.1.0 | 1.2.0 |
|---|---|---|
| class counts | unchanged | unchanged |
| work items | 147 | 147 |
| rows reclassified | — | 0 |
| cited edges | 110 | 109 |
| briefs joined | 21.0% | 21.0% |
| `build` exit | 0 | 4 |

The edge that went is `BRIEF-97 -> CASE-9999`, a placeholder inside an example command carried at
confidence 1.0. The exit that arrived carries two findings: that token, and `requirement evidence
'inconclusive'` on REQ-072.

The zero in the middle column is a fact about this repository's idiom rather than about the risk.
All 24 legacy citations here sit in real prose at fence depth 0, and a repository whose
convention is *the brief names the defects it closes* has the opposite prior.

`spec_citation_measure.py` holds at unclaimed 0 under the stricter rule, which was the risk in
tightening it. Brief 32 keeps its account through `spec-PRO-0050.md`'s `**Supersedes:**` line —
retired, not built, both halves absorbed there — which is why the account grammar carries three
relations rather than one. The three were derived from the corpus rather than guessed: across 104
specs the only header segments naming a brief path are `Brief` at 76, `Direction` at 12 and
`Supersedes` at 1.

## Decisions taken here

**Exit 4 sits between a structural fault and a disclosure one.** A ledger whose placements rest
on a default this tool chose is not unsound the way a duplicated id is, and it is a stronger
objection than an absent denominator, because every count in the ledger is computed over rows it
placed by guessing. `CASE-0511` asserts the ordering, so a new code inserted at the top of
`verdict` would be caught rather than silently masking a conservation violation.

**A name is not a reference, and naming one does not fail a citation that also resolves
something.** Naming the tool a finding came off, beside an artifact a reader can open, is honest
description; what the check refuses is a name standing in for the artifact. The count of names is
printed in the summary rather than left invisible: `none-citations 4: 0 resolving nothing · 1
naming something this check cannot resolve (spec-PRO-0096.md `campaign.py`)`.

**DEF-230 is recorded rather than claimed, and the decision it needs is not this item's.**
REQ-072 carries `evidence: "inconclusive"`, which test-campaign's `REQ_EVIDENCE` does not permit
and `campaign.py check` does not re-validate. reckon had no rule for it either: the word fell
through to the self-reported branch, where the row was classed `unmeasured` — correct — and the
reader was told the reason was that `inconclusive` is the project's own account of itself. REQ-072
is a stated ceiling recorded deliberately by PRO-0084, and its own note says so. So the placement
was right by accident and the explanation was false. Fixing the row means choosing between
`vacuous`, `unknown` and a sixth word in `REQ_EVIDENCE`, and each says something different about a
requirement another item owns. Flipping it to silence a gate this item added would be the failure
the item is about.

**Token-overlap scoring still reads fenced text.** `build_join` computes its overlap tokens from
`brief["text"][:4000]` including fenced regions, so a brief carrying a long shell block can score
against a registry row on shell words. That is a guess already labelled a guess, and it cannot
retire a brief; it is recorded here rather than changed, because narrowing it would move the join
percentage on every project running this tool and this item measured nothing about that.

## Defects

| Defect | What it was | Where it landed |
|---|---|---|
| DEF-201 | `ID_RE` read a whole brief, so a quoted example id became a citation at confidence 1.0 | reckon `citable_text`, `scan_ids`, `PLACEHOLDER_ID_RE`; CASE-0500..0504, CASE-0514 |
| DEF-202 | A defect was remaining work on any word other than `fixed`, and an unknown word was a silent default in both directions | reckon `DEFECT_NOT_OWING`, `DEFECT_PARTIAL`, `unclassified_inputs`, exit 4; CASE-0505..0513, CASE-0515, CASE-0516 |
| DEF-203 | Three citation checks accepted inputs their names imply they reject | `spec_citation_measure.py` `citable`, `header_segments`, `references`, four new checks; CASE-0517..0526 |
| DEF-230 | REQ-072 carries an evidence word its own schema rejects, and the tool explained it as a self-report | (recorded) Named by the finding this item added; the row itself is a decision left open |
