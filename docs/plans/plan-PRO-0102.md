# PRO-0102 — implementation plan

**Spec:** `docs/specs/spec-PRO-0102.md` · **Brief:** `docs/features-to-triage/93-the-reckoning-tool-mis-read-this-registry.md` (on `ai/wave-9`)
**Tier:** Small — one Python module, one self-test, two version strings, four doc paragraphs. No new units of architecture.
**Lands in:** `~/Dev/fledgeling-plugins/plugins/reckon` — nothing in this repository changes except this plan, the spec trailer and the campaign registry rows.
**Design stage:** skipped. Nothing renders; the surface is a CLI and a markdown report.

## The shape, corrected

The brief says three faults. It is two faults plus a delivery problem, and the plan is written to
that. Measured 2026-08-22 against the shared source at `31697a9` and this repo's own registry:

| | State at the base commit | Where |
|---|---|---|
| Crash on a list-shaped `evidence` | **already repaired** — `flatten_text()` at `reckon.py:244` | source only |
| The repair reaching an installed copy | **open** — `plugin.json` and the marketplace entry both read `1.0.0` | delivery |
| 110 defect rows classed `broken` without reading `status` | **open** — `reckon.py:493` | classification |
| 75 briefs classed `unbuilt` because the join found nothing | **open** — `best_cls = "unbuilt"` at `reckon.py:535` | classification |

Baseline run, kept at `docs/test-campaign/evidence/PRO-0102/baseline/`:

```
proctor-mcp · 569 rows · 232 piece(s) of work remain — 197 product, 31 evidence, 4 decision
warning: only 17.6% of briefs could be joined to the registry at all.
```

197 product-work items = 110 defects (100 of them `status: fixed`) + 75 unjoinable briefs + 12
briefs classed `broken` through a defect. The true product figure is on the order of twenty.

## What gets built

**1 — A defect's own recorded status decides its class.** `classify()`'s defect loop reads
`d.get("status")` through the existing `state_of()` splitter and maps it:

| Defect status | Class | Why |
|---|---|---|
| `fixed`, `resolved`, `closed`, `done`, `verified` | `verified-done` | symmetry with a case whose status is `pass`, which already retires with no further corroboration. The registry is an observation log here, not the project's account of itself. |
| `open`, `new`, `confirmed`, `reopened`, `regressed` | `broken` | unchanged: the measured negative |
| `wontfix`, `won't fix`, `deferred`, `declined`, `duplicate`, `n/a` | `waived` | a decision, and it stays visible |
| anything else, or absent | `broken` | fail-closed. Today's behaviour, so a registry that does not track defect status is unaffected. |

Rejected: `unmeasured` unless a passing case cites the defect. It moves 100 rows from false
product-work to false evidence-work — the same over-report in a new coat — and it fails the spec's
"a defect that has been fixed is not counted as remaining work".

**2 — A brief that joined only to a fixed defect is no longer `broken`.** `hit_defect` at
`reckon.py:544` fires on any `DEF-` target. Once (1) lands, a brief citing a repaired defect would
still read `broken`, which is the same fault one hop out. `hit_defect` narrows to defects whose
class came out `broken`. Found by the out-of-family lane, not by me.

**3 — `unjoined` becomes the ninth class.** `CLASSES`, `KIND_OF` (`decision-work`), the render
blurb, the SKILL.md table and `references/partition.md`'s precedence list all gain it.

- brief with **no edges at all** → `unjoined`. The join is a labelled guess; it found nothing, so
  the brief's state is unknown rather than absent. `is_work_item: True`, kind `decision-work`, so
  it leaves the product-work headline.
- brief with **cited** edges whose target ids are **absent from the registry** → `unbuilt`.
  Somebody wrote down what should exist and the registry does not hold it: positive evidence of
  absence, and the only thing that keeps `unbuilt` a live predicate rather than a dead one.
- brief with resolvable edges → classed as today.

An overlap edge below `--join-threshold` is never created, so a weak match already falls to
`unjoined` by construction; the lane asked for that and the code already has it.

**4 — An `unjoined` row carries its nearest candidate.** `build_join()` already computes `best`
and `best_score` and throws them away below threshold. Return them as `near_misses` so the row
reads `nearest REQ-041 (0.11)` instead of sending a reader to grep. This is what makes the class
actionable rather than a second kind of silence.

**5 — The gate learns the defect legality.** `LEGAL_CLASS` is case-only today. Add
`DEFECT_LEGAL_CLASS` and a placement check in `gate()`, so a defect row whose class contradicts its
status is a violation rather than a preference — the same protection cases already have.

**6 — The headline names what it cannot class.** Appended when non-zero: `N brief(s) could not be
tied to the registry at all and are listed as unjoined rather than assumed unbuilt.` The
product/evidence/decision split stays.

**7 — Delivery.** `plugins/reckon/.claude-plugin/plugin.json` and the `reckon` entry in
`.claude-plugin/marketplace.json` go to **1.1.0** together. This is the mechanism, not tidying: it
is why `81ad488` never reached anybody.

**Out of scope, deliberately.** Teaching reckon to read a repo's spec ledger to confirm a brief
shipped — the `unjoined` class answers the spec's criterion without it. Gemini's other two
"evidence of absence" sources (a registered surface with zero cases; a requirement whose status is
explicitly `not_implemented`) — neither vocabulary exists in this registry, so both would be
unarmable predicates. No triage assumption covers either; nothing is narrowed.

## Test strategy

**Seam:** `plugins/reckon/skills/reckon/scripts/selftest.py` — existing, and the highest seam
available (the repo has no CI workflow and no other runner). Its established pattern is followed
exactly: restate the pre-fix expression verbatim, assert it produces the wrong answer on the
fixture *first*, then assert the new code produces the right one. Without that first half every
row below is green on any registry whose defects happen to be open.

Verdict is `python3 selftest.py`, exit read into a file.

| Case | What it arms | Falsifiable at base by |
|---|---|---|
| CASE-0410 | defect `fixed` → `verified-done`, not a work item | base classes it `broken`, work item |
| CASE-0411 | defect `open` → `broken`, work item | passes at base; the control that stops (1) blanket-retiring |
| CASE-0412 | unrecognised defect status → `broken` | passes at base; proves the fail-closed direction is chosen, not inherited |
| CASE-0413 | absent defect status → `broken` | as above |
| CASE-0414 | `wontfix` → `waived` with its reason recorded | base says `broken` |
| CASE-0415 | brief with no edges → `unjoined`, kind `decision-work` | base says `unbuilt`, kind `product-work` |
| CASE-0416 | brief citing ids absent from the registry → `unbuilt` | base says `unmeasured` (the cited edge exists, the target does not resolve) |
| CASE-0417 | an `unjoined` row carries `near_misses` with a score | base has no such field |
| CASE-0418 | brief joined only to a fixed defect → not `broken` | base says `broken` |
| CASE-0419 | gate: defect class contradicting its status is a placement violation | base gate returns clean on that fixture |
| CASE-0420 | gate: `unjoined` passes the partition check | base gate says "not one of the partition" |
| CASE-0421 | headline excludes `unjoined` from product-work and names it | base headline says 197 product |
| CASE-0422 | `render()` emits the `unjoined` table row and section | absent at base |
| CASE-0423 | every class reachable, computed from real `classify()` runs rather than a hand-written set | base's section 7 unions a literal; `unjoined` would be reported reachable while never produced |
| CASE-0424 | end-to-end against this repo's registry: product-work drops to the true figure | the baseline capture is the red |
| CASE-0425 | `plugin.json` and the marketplace entry agree and exceed 1.0.0 | equal at 1.0.0 at base |

CASE-0423 is the one that matters most for the ratchet: a partition check that unions a literal
list will call a class reachable that nothing can produce, which is the eleventh dead predicate
this campaign has found. It is rewritten to collect the classes actual `classify()` calls emit.

**Registry rows** (this repo, from the allocated ranges): `REQ-097` a defect's recorded status
decides whether it is remaining work · `REQ-098` a brief the join cannot tie to the registry is
classed `unjoined`, visibly and as decision-work · `REQ-099` the shared tool's published version
rises with the repair. `DEF-210` defects classed broken without reading status · `DEF-211` an
unjoined brief classed unbuilt · `DEF-212` the `81ad488` repair unshipped behind a static version ·
`DEF-213` a brief joined only to a fixed defect classed broken. No other id is touched.

**Not covered, and named rather than left implicit.** Nothing here proves the installed copy at
`~/.claude/plugins/cache/.../reckon/` actually updates — that is the plugin host's job and this
item cannot run it. CASE-0425 proves the two version strings that gate it, which is the part this
item owns.

## Gates

- Out-of-family design review: **gemini** (`agy --model gemini-3.7-flash-high`), 2026-08-22.
  Codex is OFF for this repo and grok returns `402 — balance exhausted`; the substitution is the
  amended egress rule in ORCHESTRATOR.md, recorded here as required. Verdict: both calls upheld;
  three additions, one taken as work item 2 above, one already satisfied by construction, one taken
  as work item 4. Transcript at `docs/test-campaign/evidence/PRO-0102/lane-gemini-design.md`.
- `scripts/campaign/defect_gate.py` in both `claims` and `dropped` modes before reporting.
- `./scripts/test.sh` through the governor — this item changes no Swift, so it is a regression
  control rather than a proof of the work.

## Adjustments during the build, disclosed

Four changes the plan above did not name. Each is recorded here rather than left to be found in
the diff.

**8 — The reverse-citation scan requires a project-id shape.** Triage assumption A8 ("dropping the
guess-by-number fallback is done once across this item and the brief-citation item, whichever
builds first") turned out to name something the plan had not located. It is not a separate
fallback: it is `build_join`'s reverse-citation scan taking the first two hyphen-separated fields
of a brief's filename. On `SCR-0075-dead-credential.md` that is the project id the mechanism was
built for; on this repo's `NN-slug` queue it produces `03-menu` — a position in a directory
listing, matched against free prose and labelled `method: "cited"` at confidence 1.0, which is the
only edge kind allowed to retire stated intent. Measured before the change: the scan contributed
**0 of 92** cited edges here, so requiring letters-then-digits costs nothing. PRO-0102 built
first, so PRO-0101 verifies rather than re-edits. Recorded as `DEF-214`.

**A defect row's note falls back through `evidence` → `note` → `fix`.** Pre-fix it read `evidence`
only, and a repaired or waived defect frequently has none. One line, and it is why a waived defect
reaches the gate with a reason.

**Five findings from the out-of-family critic, applied.** The gate could not fire on a defect whose
status it did not recognise; a dangling citation was classed `unbuilt` even in a run with no
campaign at all (contradicting `references/no-campaign.md`, which this item had just rewritten); a
dangling citation discarded a usable overlap edge; a registry row with no id could be inserted as a
reverse citation and suppress the overlap search; and three assertions were weak — one tautological
on its own fixture, one asserting `!= "broken"` rather than a class, one agreeing with the pre-fix
code. Two whole checks were missing: `cmd_build` was never executed by the suite, and the weak-join
degrade had no behavioural test. All applied; the critic's remaining finding is dispositioned below.

**One critic finding not taken.** It reported that a waived defect bypasses the gate's
"a waiver names a reason" rule because `status` is truthy. That rule has always accepted a case's
`n/a` status as its own reason, and a defect's `wontfix` is the same shape — the decision word *is*
the record. Changing it would fire on every waived case in every existing ledger, which is a
separate item rather than this one.

## Gate results

| Gate | Result |
|---|---|
| `selftest.py` (the tool's own suite) | 46 checks, exit 0. 26 before this item. |
| Arming, whole suite vs `31697a9` | 17 red — `evidence/PRO-0102/arming/arming-D-full-prefix.txt` |
| Arming, the two controls, by mutation | 2 red — `arming-E-controls.txt` |
| Arming, the delivery pair, both directions | 2 red — `arming-B-delivery.txt` |
| End to end vs this registry | 232 work items → 132; product 197 → 13; 569 rows conserved |
| Out-of-family design review | gemini, both calls upheld, one finding taken as work item 2 |
| Out-of-family completeness critic | gemini, 11 findings, 10 taken, 1 dispositioned above |

**The case allocation grew from 16 to 20 during the build**, so the sixteen rows in the test
strategy table above are not the final mapping. The suite ended at 24 assertions and the registry
groups them into the twenty ids allocated, CASE-0410..CASE-0429; the reconciliation is the `Cases`
table in `docs/specs/spec-PRO-0102.md`. Four of the extra rows are the critic's and the
validation's findings, which did not exist when the table was written.

**One more assertion strengthened after the same-family validation.** `CASE-0423` asserted
`class not in ("unbuilt", "unjoined")`, which goes green under one of the two regressions it
exists to catch. It now names the class, and both reverts red it —
`evidence/PRO-0102/arming/arming-F-dprime.txt`, landed at `fc86fe7`.
