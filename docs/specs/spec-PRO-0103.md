# PRO-0103: A reckoning worth comparing against

**ID:** PRO-0103
**Status:** Needs More Info
**Created:** 2026-08-22
**Last updated:** 2026-08-22
**Brief:** `docs/features-to-triage/94-a-reckoning-worth-comparing-against.md`

## Feature description

# A reckoning worth comparing against

- origin: proposed while running the first reckoning · 2026-08-22
- audience: whoever wants to know whether the not-knowing is shrinking
- platforms: n/a — pipeline bookkeeping
- proposed-by-ai: true

## What and why

The reckoning that ran today is a snapshot, and a snapshot answers the smaller question. It says how
much is unmeasured now. It cannot say whether that figure is falling, and it cannot catch the failure
it most needs to: an item quietly reclassified from unmeasured to something else across runs, until
nothing remembers it was never checked.

The tool already carries the mechanism — a ratchet that compares two ledgers and enforces that an
item may leave unmeasured only by being measured. It has nothing to compare against, because this was
the first run. A second run is what turns the ratchet on, and after that the interesting number stops
being the total and becomes the delta.

The honest reason to propose this rather than assume it: a reckoning is only worth repeating if
somebody reads it. One run produced three tool defects and a structural fix worth taking, which is a
decent return, but that is one data point about a tool's first contact with a new repository, not
evidence that the tenth run will earn its keep. So the question this brief really asks is what
cadence makes it useful without making it wallpaper — after a wave closes, before a release, or on a
clock.

## Acceptance sketch

- A second reckoning exists to compare the first against, and the comparison runs rather than being
  described.
- An item that leaves the unmeasured class does so because somebody measured it, and a run that
  cannot show that fails rather than reporting a smaller number.
- The report leads with what changed since the last one, not with the totals.
- Somebody who reads two consecutive reckonings can say whether coverage is improving without
  recomputing anything.
- A cadence is chosen and written down, so the second run is not simply whenever somebody remembers.

## Assumptions made writing this

- Assuming the cadence question is genuinely open rather than obviously "every wave", because the
  cost of a reckoning nobody reads is that the next one gets skipped.
- Assuming the ratchet is worth turning on before the join is perfect, since the delta is meaningful
  even over a partial denominator as long as the denominator is stated.
- Assuming this is proposed rather than asked-for, so deleting this file is the way to say no.

---

<!-- Triage, plan link, and progress sections are appended below. -->

## Triage — 2026-08-22

**Sentinel review:** S1 — Block pending the essential question below. Everything except the
cadence is buildable today and is recorded as an assumption; the cadence is a judgement about
how much of your attention a recurring report is worth, and the proposal itself declines to
guess it. This item was proposed rather than requested, so "not at all" is a real answer and
is offered as one.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** **nothing customer-facing changes.** A second "what is left" report
  for this project, and a written note saying when the next one runs *(internal)*.
- **What users will see:** a report that opens with what changed since the last one instead of
  with totals, and refuses outright if something stopped being counted as unmeasured without
  anybody having measured it.
- **Behaviour changes:** the interesting number becomes the movement rather than the total.

**Assumptions**
- `[Operations]` The comparison is run, not described. *(a described comparison proves nothing.)*
- `[Operations]` The check is switched on before the matching-up is perfect, with the partial denominator stated. *(the movement is meaningful over a stated floor.)*
- `[Operations]` The second report is taken after the report tool's known misreadings are repaired. *(comparing against a run with three known faults measures the faults.)*
- `[Operations]` The first report stays as it is and is not re-run to make a tidier baseline. *(a baseline edited to suit is not a baseline.)*
- `[Operations]` A run that cannot show something was measured fails rather than reporting a smaller number. *(that failure is the whole point of the check.)*

**Essential Questions**
1. *[Operations]* How often should this report run — and should it run again at all? The
   proposal is honest that one run is one data point: it returned three tool faults and a
   structural fix, which is a decent first contact with a new project and no evidence about
   the tenth run. Whichever you pick becomes the written cadence, which is the fifth thing the
   proposal asks for.
   a) When a wave closes *(this is my lean, not a finding: the project already has a natural
      boundary there, and it ties the report to a moment when the answer would change
      something. I have not measured what a second run costs, so the lean is weak.)*
   b) Before a release only — rarer, tied to a moment somebody is already reading carefully.
   c) On a clock (weekly, monthly — say which).
   d) Not again. Retire this item; the first report was worth having and a second is not.
      *(The proposal named deleting its own file as the way to decline. Triage consumed that
      file into this record, so retiring this record is now what deletion meant.)*

*Easy reply — edit your answer under the question (or correct any assumption), then re-run
`/triage PRO-0103`:*
> `1. <a | b | c + interval | d>`

*Once that is answered I'll mark this Ready for Implementation Plan.*

---

### Pipeline record — PRO-0103 *(machine trailer; not part of the review above)*

- The comparison mechanism exists and was read rather than assumed: `ratchet(prev, cur)` at
  `reckon.py:725` in `~/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/`, exposed
  as the `ratchet` subcommand, exit code 3 on a violation. It needs two ledgers; only
  `docs/reckoning/2026-08-22/ledger.json` exists.
- Divergence test on the question: options (a), (b) and (c) produce the same build and differ
  only in one written line, which would normally make this an assumption. It survives as a
  question because option (d) exists — the item is `proposed-by-ai: true`, the proposal names
  deletion as the way to decline, and no default can choose deletion on the owner's behalf.
- Sequencing recorded rather than asked: this item depends on PRO-0102 landing first, per the
  third assumption.

---

### Out-of-family spec review — PRO-0100, PRO-0101, PRO-0102, PRO-0103

*(Shared record for all four items triaged 2026-08-22; the other three specs point here.)*

**Lane:** `agy --model gemini-3.7-flash-high`, read-only, grounded in this tree.
**Lane accounting:** the preferred lane, codex `gpt-5.6-sol`, is switched off for this
repository; the `grok` lane returned **402, balance exhausted** earlier today and was not
retried. Gemini is out-of-family, so this is a lane substitution, **not** an in-family
downgrade — no fully in-family fallback was needed.

**Verdicts:** AGREE on PRO-0100, PRO-0101, PRO-0102 with zero objections. DISAGREE on
PRO-0103, arguing it should be Ready with an assumed cadence. Three objections raised.

**Tally: 1 accepted, 2 rejected.**

- **Accepted** — that option (d) as first written treated deleting the proposal file as the
  live opt-out, when triage had already consumed that file. The option is reworded above to
  say what declining now means.
- **Rejected** — "options a, b and c produce the same build, so the cadence is an assumption."
  The divergence test was already run and recorded, and the same-build reading is why. It does
  not settle the question, because the written cadence is itself the fifth thing the proposal
  asks for: the deliverable is the decision, not a setting on one. How often a recurring report
  is worth reading is a judgement about the owner's attention, and the item's own reasoning is
  that the cost of a report nobody reads is the next one being skipped.
- **Rejected** — "no implementation blocker remains." Correct and not the bar. Triage blocks on
  what only the owner can settle, not on what the builder cannot start; option (d) is exactly
  that, and no default may choose retirement on the owner's behalf for an item nobody asked
  for.

No objection reached Critical or High, and none exposed an external dependency wearing a
default, so nothing escalated to a new Essential Question.

**Assumptions gate:** this run is unattended, so the recorded assumptions were checked against
"would this surprise the owner?" by the same out-of-family reviewer above, which reported none
in that class across the four items.


## The cadence, settled 2026-08-22

The reader chose **at wave close**, over retiring the item. Four options were put: at wave close,
before a release, on a clock, or retire it. Retirement was on the list because this item is
AI-proposed and triage had already consumed the brief that named deletion as its opt-out, so the
veto route the proposal relied on no longer existed and could not be left implicit.

What that fixes is the thing a single run cannot do. Today's reckoning is a snapshot: it says how
much is unmeasured now and cannot say whether that figure is falling. Running at wave close gives
the ratchet two ledgers to compare, and the ratchet is what refuses an item that leaves the
`unmeasured` class by any route other than being measured — the slow failure, where a row is quietly
reclassified across runs until nothing remembers it was never checked.

**A wave close is the trigger, not a date.** The clock option was available and was not taken, and
the difference matters: a clock fires whether or not anything changed, and a reckoning nobody reads
is one that gets skipped and then dropped. A wave close is the moment the delta is largest and the
context for reading it is still in somebody's head.

This item stays behind PRO-0102, because a second run against a tool that mis-reads this registry
would produce a second wrong headline and a delta between two wrong numbers.

---

## Progress — PRO-0103

**Defects:** DEF-216
**Requirements:** REQ-102..REQ-107
**Cases:** CASE-0441..CASE-0456
**Surfaces:** SURF-025

Built in this repository. No Swift changed, so the suite is a control rather than a claim and
`CHANGELOG.md` gains nothing: this is pipeline bookkeeping, not a user-facing change, and the two
wave-16 items before it were treated the same way.

### What was built

`scripts/reckoning/reckoning.py`, with three subcommands. `take` builds a reading and stamps it
with the commit it was taken on. `compare` differences two readings. `stamp` writes provenance for
a run that predates the script, which is how the 2026-08-22 baseline got a `run.json` without being
re-taken — a baseline edited to suit is not a baseline, so it was transcribed from its own report's
first line and marked `transcribed` rather than `measured`.

The design decision worth recording is the control rebuild. The two readings straddle PRO-0102's
repair of `reckon`, so differencing the published ledgers reports the tool's repair as the
project's progress. Where the two runs declare different tool versions, `compare` rebuilds the
earlier run's own inputs at the earlier run's own commit with the current tool and reports **tool
movement** and **project movement** in separate columns. That is only possible because the earlier
run names its commit, which is the argument for `run.json` and the reason the acceptance clause
about naming the tree is the one underneath all the others.

Five refusals, all fail-closed: a tool below the 1.1.0 floor or missing a class from the current
partition, a reading over uncommitted inputs, a run with no provenance, a ratchet that cannot run,
and a ratchet violation. `--allow-dirty` moves the refusal downstream rather than removing it — the
reading is marked unnamed and `compare` then declines it as a baseline.

`scripts/reckoning/reckoning_selftest.py` arms every one of them, 28 checks, exit 0. Each gate gets
a two-way control so a command that refuses everything is caught, and six get a removal mutation on
a scratch copy so the refusal is attributed to the line that made it. Arming the comparison found a
hole the design did not have: a control built by a third tool version belongs to neither side of
the delta, so `compare` now refuses when the tool on disk is not the one that took the current
reading.

### The reading

`docs/reckoning/2026-08-22-2bdc808`, taken at **2bdc808** on `ai/pro-0103` with `reckon` **1.1.0**.
620 rows, 134 work items, `reckon`'s own gate clean, and both ratchet pairs clean.

Differencing the two published reckonings says this project shed 84 pieces of work in a day.
Holding the tool constant says the tool accounts for **-88** of that and the project moved **+4**
the other way. Evidence work is flat at 36 and `unmeasured` is flat at 36 rows with nothing
entering and nothing leaving, which is the number the exercise exists to move and the one that did
not move. Requirements observed went 49/76 to 63/90, and briefs joined fell 17.6% to 16.7% because
the queue gained five briefs and the mechanical join gained none — the axis PRO-0101 exists to fix.

The reading was taken mid-wave rather than at wave 16's close, because PRO-0101 had not merged.
Its ids and this item's own campaign rows are absent from it and will appear as movement in the
next delta; both facts travel with the run in `run.json` as notes and are reprinted in every delta
computed from it.

### Claims stated as relations rather than counts

PRO-0102 recorded that ten defects were both `broken` and non-fixed, and PRO-0100's merge falsified
the sentence within the hour. The form that does not decay was re-measured here at a third tree:
**the classifier's `broken` defect rows are the registry's own non-fixed set**, at 118 defect rows
giving seven. The `broken` class total is ten, because it also carries three briefs joined to a
defect or a failing case, so the class count and the defect count are different questions.

### Validation

| Gate | Outcome |
|---|---|
| `./scripts/test.sh` under `governor-run --weight 6` | *Test run with 2064 tests in 251 suites passed*, exit 0 — a control, since no Swift changed |
| `reckoning_selftest.py` | 28 checks, 0 failed, exit 0 |
| `campaign.py check docs/test-campaign` | exit 1 on both head and merge base, blocker sets identical apart from witnessed 27/29 → 28/30, naming none of this item's ids |
| `defect_gate.py claims` | exit 0, DEF-216 recorded rather than claimed |
| `defect_gate.py dropped` | exit 0, 112 merges, 44,283 id/field pairs |
| Out-of-family review | `agy --model gemini-3.7-flash-high`, `--new-project` from a neutral cwd; verdict recorded below |

### What this item did not take

Brief 96's two findings are not this item's, and both are declined here explicitly rather than left
to look like oversights. The `source` field joining and being refused as evidence is `reckon`'s
work, in another repository. The block grouping is recorded with a correction: on this registry at
2bdc808 the tool produces four blockers, `BLOCK-0001` to `BLOCK-0004`, one case each at +0.3 points
of coverage, not one block at 16.7%. The 16.7% brief 96 quotes is the join percentage, which
`reckon` prints as a warning on the same run. Brief 96 was left unedited: it is another item's
input, and editing it would also have changed the inputs of the reading taken here.

DEF-201 and DEF-202 were confirmed rather than assumed harmless on this registry. DEF-202 does not
bite: 118 defect rows carry only `fixed` (111) and `open` (7), none of the six over-reporting
words. DEF-201 has no live instance: of 176 registry ids cited across 96 briefs, zero sit inside a
code fence.

No `docs/plans/plan-PRO-0103.md` was written. This runner went from the settled spec to the branch
without a separate plan stage, and a plan file written after the build would be an implementation
record wearing a plan's name; the design decisions are in this section instead.

## Defects

*(Two hashes because `defect_gate.py claims` reads `^## Defects` and a `###`
heading is invisible to it.)*

| ID | Title | Status |
|---|---|---|
| DEF-216 | The installed reckon plugin is still 1.0.0, and 1.0.0 crashes on this registry (recorded) | open |

## Out-of-family review — 2026-08-22

**Lane:** `agy --model gemini-3.7-flash-high`, `--new-project` from `/tmp`, handed the two scripts,
the cadence note, the published delta and its notes whole rather than as excerpts — PRO-0100's
reviewer called a total unwrap UNPROVEN off an excerpt that began one line too low. Codex is OFF
for this repository and `grok` returns `402 — balance exhausted`, so this is a lane substitution
and not an in-family downgrade.

The reply answered about PRO-0103: it names the item, the 1.0.0 to 1.1.0 repair, `repo_name()`,
`--allow-dirty` and the 28 checks, so it is a verdict rather than the cross-project contamination
this lane has produced before. **`OVERALL: ACCEPT`**, with the decomposition called sound, the
ratchet fully enforced with no path to a delta that skips it, the selftest non-vacuous, and the
report's ordering meeting the clause.

**One finding, Low, taken in part.** `DEFAULT_RECKON` falls back to an absolute path under
`~/Dev`, so on another machine the command refuses. Taken: the refusal now names both overrides
(`--reckon` and `RECKON_SCRIPT`) and says the default is this machine's checkout, because the harm
is a reader who is told a path is missing and not told how to fix it. Not taken: a discovery walk
over candidate locations. The nearest candidate on this machine is the installed plugin cache,
which holds 1.0.0 and is exactly what DEF-216 records as unsafe to fall back to, and the repository
already resolves cross-repo skill paths this way in `scripts/campaign/skill_doc_measure.py`.


## Verification — 2026-08-22, `Done`

Verified fresh-context on the branch with `main` merged in at `98db23f`. The branch did **not** merge
clean — `cases.json` and `inventory.json` conflicted, wave-16 rows appended at the same array
positions — and the verifier resolved it as an id-keyed union. Checked independently before it was
taken: 320 cases and 121 defect rows with **zero duplicates**, `defect_gate.py dropped` passing over
116 merges and 49,881 id/field pairs, and `main`'s newer DEF-201 and DEF-202 text preserved intact.

`./scripts/test.sh` 2,064 tests in 251 suites exit 0; `reckoning_selftest.py` 28 checks 0 failed exit
0; `defect_gate.py` claims and dropped both exit 0 and exit 2 when invoked bare; `test_instruments.py`
62 passed exit 0. `campaign.py check` exits 1 at head and at both bases, and the blocker sets differ
by exactly one line — *External-effect claims with no witness (27 of 29)* → *(28 of 30)*. The named
ids are identical; the **denominator** grew because REQ-102 declares `filesystem-write` and CASE-0456
witnesses it. This item's own new requirement, not a regression.

### The separation reproduces, including on a row moved by both causes

The rebuild of `2bdc808` from its named commit is byte-identical at sha256 `ca5f76ff27daf95d…5e` over
582,690 bytes, and an independent control rebuild at `2bd01be` gives work 130, product 11, evidence
36, decision 83 — the same **−88 tool, +4 project**. A second checkout of the same tool produced a
`delta.md` byte-identical to the published one.

The hard case was constructed rather than waited for: a row moved by *both* causes
(`BRIEF-00-WAVE-7-DIRECTION`, `unbuilt`→`unjoined` by the tool, then `unjoined`→`verified-done` by the
project) splits at the control pivot — the tool column unchanged, the project column moving +4 to +3,
and the row table showing the project's move only. No double count and no misattribution.

### Three findings outside the acceptance set, and one case corrected rather than routed

**CASE-0456 was recording evidence it did not have, so it is fixed here rather than filed.** Its note
claimed four files each carrying a byte count and sha256; `run.json` holds `count: 2`, two filenames
and no digests. The delta files are written *after* the sweep, so they were never in the after-set,
and `cmd_take` discards the digests `sweep()` computes, so they were never stored. `campaign.py`
counted the case witnessed without opening the artifact. The witness still stands at a count of 2,
which is non-zero and is what the recorder actually saw.

- **DEF-204.** `compare`'s new refusal is keyed on a declared version string rather than on the tool.
  The relabelled 1.0.0 cache is caught, but by the class-vocabulary check rather than the version — and
  the real 1.1.0 source with `classify()` altered to reclassify `unjoined` as `verified-done` was
  **accepted at exit 0**, publishing −163 tool / +79 project against a true −88 / +4. `run.json`
  already records `tool.source_commit`; `compare` never reads it. Same shape as DEF-216 one level up.
- **DEF-205.** `cmd_take` stores names and a count while `sweep()` computed digests, so the witness
  cannot say what was in the files and a file replaced between sweeps would be invisible. It is also
  what let CASE-0456 make an uncheckable claim.
- **DEF-206.** `git()` strips its output, so ` M docs/…` arrives as `M docs/…` and the `[3:]` slice
  removes the first character of the path: `docs/test-campaign/cases.json` is refused as
  `ocs/test-campaign/cases.json`. Untracked entries survive because `?? ` strips intact. It fires on
  the commonest case, and with `--allow-dirty` the mangled name is written permanently into
  `run.json.dirty_inputs`.
