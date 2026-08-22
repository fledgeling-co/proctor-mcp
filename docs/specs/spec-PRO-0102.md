# PRO-0102: The reckoning tool mis-read this registry

**ID:** PRO-0102
**Status:** Developer Review
**Created:** 2026-08-22
**Last updated:** 2026-08-22
**Brief:** `docs/features-to-triage/93-the-reckoning-tool-mis-read-this-registry.md`

## Feature description

# The reckoning tool mis-read this registry three ways

- origin: running the reckoning against proctor-mcp for the first time · 2026-08-22
- audience: every project on this machine that will run a reckoning after this one
- platforms: n/a — shared tooling, outside this repository
- research: none; each fault was measured against this repo's own registry

## What and why

The first reckoning run against this project produced a headline of "218 pieces of work remain — 183
product". That number is wrong, and the way it is wrong matters more than the number: it
over-reported, which is the opposite of the failure the tool exists to prevent, so nothing about its
own design would have caught it.

Three faults, each found by reading the rows rather than the summary. It crashed outright on a field
whose shape it did not expect — this registry carries evidence as a list of paths where the tool
assumes a string. It classed every defect record as broken without reading status, when 88 of 96 are
fixed. And it classed 75 briefs as unbuilt because they failed to join, when every one of them names
an item that shipped.

The second and third share a root worth naming: **an entity absent from the evidence is treated as an
entity that failed**, and those are different things. That is the same confusion the tool was built
to fix, arriving from the other direction.

This is shared tooling. The faults will reach whoever runs it next, and the crash means they will not
get a report at all.

## Acceptance sketch

- A reckoning run against a registry whose fields vary in shape produces a report rather than a
  traceback.
- A defect that has been fixed is not counted as remaining work.
- A brief whose item shipped is not counted as unbuilt, whether or not the join found it.
- A run whose join is weak says which items it therefore cannot class, rather than assigning them a
  class the join does not support.
- The headline figure is one somebody can act on without re-deriving it from the rows.

## Assumptions made writing this

- Assuming the fix belongs in the shared tool rather than in a per-repo adapter, because the next
  project to hit it will not know to write one.
- Assuming "unjoined" needs to be its own visible outcome rather than folded into unbuilt, since the
  two carry opposite conclusions and the reckoning's own report has to distinguish them.
- Assuming the crash is worth fixing even though a local patch already exists here, because a local
  patch is invisible to every other repository.

---

<!-- Triage, plan link, and progress sections are appended below. -->

## Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions, with one restatement carried below: **one
of the three faults has already been repaired since this proposal was written, and the repair
has not reached anybody who runs the tool.** Acting on the brief as written would repair it
twice and still leave it unshipped, so the item's shape changes rather than its intent.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** **nothing customer-facing changes.** The change is to the shared
  "what is left" report used by every project on this machine *(internal — an existing tool)*.
- **What users will see:** the report finishes instead of stopping partway on a project whose
  records vary in shape; a problem somebody already fixed is not counted as still broken; a
  proposal whose feature shipped is not counted as never built; and where the report cannot
  tell, it says it cannot tell rather than picking the worse answer.
- **Behaviour changes:** a new visible outcome for "could not match this up", separate from
  "never built", because the two lead to opposite conclusions. The headline number becomes one
  somebody can act on without re-deriving it from the rows.

**Assumptions**
- `[Operations]` The repair belongs in the shared tool, not a per-project workaround. *(the next project will not know to write one.)*
- `[Operations]` "Could not match up" becomes its own visible outcome, not folded into "never built". *(opposite conclusions.)*
- `[Operations]` The already-shipped crash repair is verified and released rather than rewritten. *(it is correct; it is simply not reaching anyone.)*
- `[Data & scope]` The item raises the shared tool's published version so the repairs reach installed copies. *(a repair only in the source is the same invisibility the proposal objects to.)*
- `[Operations]` The other two faults are repaired in the same release as the first. *(one release, one thing to verify.)*
- `[Operations]` A problem's own recorded state decides whether it counts as remaining. *(the record already carries it; nothing new is inferred.)*
- `[Data & scope]` The shared change touches only this one tool, committed by explicit path. *(that repository is shared with other work.)*
- `[Operations]` Dropping the guess-by-number fallback is done once across this item and the brief-citation item, whichever builds first; the second verifies rather than re-edits. *(both name it.)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0102` before the planner picks this up.*

---

### Pipeline record — PRO-0102 *(machine trailer; not part of the review above)*

Measured 2026-08-22 against both copies of `skills/reckon/scripts/reckon.py`:

| Fault | Source (`~/Dev/fledgeling-plugins`, `a15febf`) | Installed (`~/.claude/plugins/cache/.../reckon/1.0.0`) |
|---|---|---|
| Crash on a list-shaped `evidence` | **fixed** — `flatten_text()` added in `81ad488`, 2026-08-22 | **still present** — `tokens()` is `(text or "").lower()` at `:245` |
| Every defect classed `broken` without reading `status` | open — unconditional `"class": "broken"` | open — same, at `:465` |
| An unjoined brief classed `unbuilt` | open — `best_cls = "unbuilt"` in `build_join`; `CLASSES` has no `unjoined` member | open |

- Both `plugins/reckon/.claude-plugin/plugin.json` and the marketplace entry still read
  `"version": "1.0.0"`, which is why `81ad488` has not reached the installed copy. The version
  bump is the delivery mechanism, not incidental tidying.
- The brief's third assumption ("a local patch already exists here") is stale in this repo's
  direction too: no patched copy of `reckon.py` exists under `proctor-mcp`.
- This project's own numbers, for the acceptance check: `docs/test-campaign/inventory.json`
  carries 110 defect rows, **10** non-fixed. The reckoning's "108 defect records, 88 fixed,
  eight open" is a snapshot from `2bd01be` and has since moved; the plan should re-read the
  registry rather than reuse those figures.
- Discipline: touch only the `reckon` plugin, commit with an explicit path, never `-a` and
  never `.`, stop and report if files appear entangled. Shared repo measured clean at
  `a15febf` while this triage ran.
- Out-of-family spec review: see the shared record at the foot of `spec-PRO-0103.md`.

---

## Implementation plan — 2026-08-22

Implementation plan: `docs/plans/plan-PRO-0102.md` (tier: Small). The shared work lands in
`~/Dev/fledgeling-plugins/plugins/reckon`; this repository carries the plan, this trailer and the
campaign registry rows only.

## Progress — PRO-0102

**Defects:** DEF-210..DEF-214
**Requirements:** REQ-097..REQ-099
**Cases:** CASE-0410..CASE-0429

Built in `~/Dev/fledgeling-plugins` at `224a696`, shipped as `reckon` **1.1.0**. This repository
carries the spec, the plan, the campaign rows and the evidence only; no Swift changed, so
`CHANGELOG.md` gains nothing — the user-facing change belongs to the other repository's plugin.

### Validation

| Gate | Family | Outcome |
|---|---|---|
| Design review, before the plan | gemini (`agy --model gemini-3.7-flash-high`) | Both classification calls upheld. Raised DEF-213, which nothing in the code review would have found because it is latent until DEF-210 is fixed. |
| Completeness critic, on the diff | gemini | 11 findings. 10 taken — 5 in the tool, 3 weak assertions, 2 whole checks that did not exist. 1 dispositioned with a reason in the plan. |
| Same-family validation, fresh context | `claude-fable-5`, `--effort high` | Re-derived all five acceptance criteria independently and found each satisfied, citing `file:line`. Two findings taken: one negative assertion strengthened, and this file's case range reconciled against the plan's table. |

Codex is OFF for this repo and grok returns `402 — balance exhausted`, so gemini substitutes on
both out-of-family gates under the egress rule amended in ORCHESTRATOR.md on 2026-08-22. Named
here as a downgrade rather than passed over.

### Defects

| ID | Title | Status |
|---|---|---|
| DEF-210 | The reckoning classed every defect record broken without reading its status | fixed |
| DEF-211 | The reckoning classed a brief it could not join as unbuilt | fixed |
| DEF-212 | A correct repair never reached any installed copy, because the version never moved | fixed |
| DEF-213 | A brief joined only to a repaired defect would still have read broken | fixed |
| DEF-214 | The reverse-citation scan turned a brief's file number into a confidence-1.0 citation | fixed |

### Gap-fix — 2026-08-22

One gate had not been run: `campaign.py check`. Run here it named three of this item's own cases,
six findings, and closing them is the whole of this stage.

`CASE-0426`, `CASE-0427` and `CASE-0428` stand on `source-analysis` and carried no `source` block, so
the guard at `campaign.py:772-781` had nothing to read. Each now carries the analyzer and the
denominator, both off a live run rather than off the prose already in the record — `CASE-0139`'s own
history is a case whose copied count had gone stale by a merge, and the count is the claim.

| Case | Analyzer | Population judged | Finding |
|---|---|---|---|
| CASE-0426 | `selftest.py` check 13, *every class is produced by a real fixture* | 9 classes in `reckon.CLASSES` | 0 unreachable |
| CASE-0427 | `selftest.py` check 14, first assertion | 2 version declarations reckon publishes | 0 disagreements |
| CASE-0428 | `selftest.py` check 14, second assertion | 1 published version string | 0 below the 1.1.0 floor |

The denominator is what was judged rather than what was opened. For CASE-0427 that means 2 rather
than the 46 plugin entries `marketplace.json` holds, because the check reads one of them. For
CASE-0428 it means 1, which is thin and is the honest count: that assertion reads a single value, and
CASE-0427 is the row that judges the pair. Probe and its output at
`evidence/PRO-0102/source-denominators.py` and `source-denominators.txt`.

All three stay `source-analysis`. Nothing here runs the product or witnesses an effect; relabelling
one to clear the guard would be the label over the evidence.

**The surface prose was stale in 28 places, not 23**, and one of them was structural. `SURF-023`
was minted at `c1132ea` and all twenty cases moved onto it, but 20 case notes and 8 inventory notes
still read "Filed under SURF-022" and "no SURF id was allocated to PRO-0102", and `REQ-097`,
`REQ-098` and `REQ-099` still carried `surfaces: ["SURF-022"]` — the same stale claim in a field the
tooling reads. All 28 strings and all three arrays now name `SURF-023`, with each note's own
reasoning kept and `SURF-022`'s route recorded as why it was the wrong home.

| Gate | Verbatim exit | Result |
|---|---|---|
| `campaign.py check docs/test-campaign` (0.9.9) | `EXIT=1` | Blocker set identical to the merge base's: CASE-0318, CASE-0333, CASE-0334, CASE-0335, REQ-007, REQ-024, REQ-086. Nothing in CASE-0410..0429, REQ-097..099 or DEF-210..214. source-analysis findings 12 → 6. |
| `campaign.py check`, merge base `9f99a0f` | `EXIT=1` | The control. Same seven ids, same six other categories. |
| `selftest.py` (reckon 1.1.0 at `fc86fe7`) | `EXIT=0` | 46 checks, all green. |
| `defect_gate.py claims spec-PRO-0102.md docs/test-campaign` | `exit=0` | 5 claimed defects, every one reads `fixed`. |
| `defect_gate.py dropped docs/test-campaign` | `exit=0` | 108 merges, 39,060 id/field pairs, no discarded value still missing. |
| `./scripts/test.sh` through `governor-run --weight 6`, run 1 | `EXIT=1` | `Test run with 2061 tests in 251 suites failed after 130.721 seconds with 1 issue.` One issue, and see below. |
| `./scripts/test.sh --filter planeFollowsTheWindowList` | `EXIT=0` | `Test run with 1 test in 1 suite passed after 0.071 seconds.` |
| `./scripts/test.sh` through `governor-run --weight 6`, run 2 | `EXIT=0` | `Test run with 2061 tests in 251 suites passed after 13.491 seconds.` |

Exit 1 on `campaign.py check` is the campaign's standing state on this history and is not this
item's failure. The diff is at `evidence/PRO-0102/check-blocker-diff.txt`, with both runs beside it.

**The Swift suite went red once, and it is not this branch's.** Run 1 lost
`planeFollowsTheWindowList` at `BackgroundRouteTests.swift:163`. `Session.cursorPlane`
(`SessionCursor.swift:87`) asks the live window server whether any on-screen window's number equals
the handle's `cgWindowID`; the fake claims id 7 and the test's premise is a comment asserting no such
window is on this machine's screen. That is a fact about the host at the moment of the run rather than
a fixture. The test passes in isolation, passes in run 2, and has passed in every run recorded in
`evidence/PRO-0088` and `evidence/PRO-0093`. Nothing outside `docs/` changed on this branch and no
Swift test reads any of the four changed files, so the code under it is byte-identical to the merge
base. Left alone: giving that path an injectable window list is a change to product test seams and is
not this item's work. Both runs are at `evidence/PRO-0102/swift-suite.txt`.

**One rung judgement, reported and not acted on.** `CASE-0426` sits on `source-analysis` while its
sixteen `outcome` siblings in the same range assert on the output of the same suite, and check 13
does *run* `reckon.classify()` on two fixtures rather than only reading source. By the vocabulary in
`campaign.py`'s own summary — *source-analysis: reads source, runs nothing, buys no effect credit* —
that reads like an under-claim, and `outcome` would be the closer rung. It stays where it is for two
reasons. Moving it would remove the denominator obligation that this stage exists to satisfy, which is
the label over the evidence. And under-claiming is the safe direction: `source-analysis` buys less
credit than `outcome`, so nothing rests on a rung it has not earned. `CASE-0427` and `CASE-0428` read
two JSON files and compare strings, which is `source-analysis` exactly.
