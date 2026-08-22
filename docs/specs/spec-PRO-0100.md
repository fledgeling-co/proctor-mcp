# PRO-0100: Six repairs whose diagnosis is done

**ID:** PRO-0100
**Status:** Ready for AI
**Created:** 2026-08-22
**Last updated:** 2026-08-22
**Brief:** `docs/features-to-triage/95-six-named-repairs.md`

## Feature description

# Six repairs whose diagnosis is already done

- origin: the open-defect sweep after wave 15, and today's clarify pass · 2026-08-22
- audience: whoever runs the suite next, and whoever reads the walkthrough
- platforms: mac
- research: none; each has a measurement or a decision already on record

## What and why

Six of the eleven open defects need no investigation. Each carries either a measured diagnosis or a
decision already taken, and each is small. They are grouped because they are one sitting, not
because they are one subject.

**Two are the walkthrough disagreeing with its design of record, and they resolve in opposite
directions.** The design draws no Skip on the permissions pane; the build draws one. The build is
right — Skip is a tested escape hatch that postdates the design page, and removing it was measured
to strand a person with no way out while the whole suite stayed green. So the design changes. But
the disabled primary is the other way round: the build draws it accent-filled with only the label
dimmed, which reads as tappable-but-broken, and the design's plain treatment is the correct disabled
affordance. So the build changes. A referral split these two apart; taken together they would have
had one wrong answer.

**Two are tests that read the machine rather than the product.** One asserts a doctor verdict is
invariant while reading live grant state, so it fails on whichever machine happens to disagree. The
other reads a scheduler's ticket before the hold has reached it — a stronger timing claim than the
requirement makes, and the second known flake in a suite that gates every item.

**One is the force-unwrap class, finished.** A previous item converted every site matching its own
grep. Two shapes cannot match that pattern and abort the runner identically, which is the failure
where the suite reports no verdict at all rather than one red test.

**One is a stale count in a shared instruction file**, the fifth of its kind, in a document live for
every project on this machine.

## Acceptance sketch

- The walkthrough's permissions pane and its design of record agree on what is drawn, in both
  directions, with the reason recorded where they were made to differ.
- A disabled primary action reads as refusing rather than as broken.
- No test's verdict depends on the grant state or the timing of the machine it runs on.
- No force-unwrap shape remains that can end a run with no verdict line.
- The shared skill states one tool count and it matches the catalogue.

## Assumptions made writing this

- Assuming the design of record is the artifact that yields on Skip, because the build's behaviour
  was tested and the design page was not revised after that test existed.
- Assuming the scheduler race is fixed by polling rather than by relaxing the assertion, since the
  assertion is what the requirement actually promises.
- Assuming the two force-unwrap shapes are converted rather than exempted, because the hazard is
  identical and only the grep differed.

---

<!-- Triage, plan link, and progress sections are appended below. -->

## Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions. Six repairs, each already diagnosed,
grouped as one sitting rather than one subject. Two of the six change what a person sees;
the other four change only whether a test run can be believed.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** the setup walkthrough's permissions step *(customer-facing — an
  existing surface, one control redrawn)*. The other four repairs are **behind the scenes —
  nothing visible changes**, and one of them lands in a shared instruction file used by every
  project on this machine rather than in Proctor itself.
- **What users will see — per surface:**
  - Setup walkthrough, permissions step: the continue action, while it is refusing, is drawn
    plain instead of filled in the accent colour, so it reads as refusing rather than as
    broken. Its wording, its position and the reason line above it are unchanged.
- **Behaviour changes:** none. The way out of setup stays exactly where it is; what changes is
  that the design record now draws it too, so the two agree.
- **Design reference:** the surfaces page under `design/surfaces` is the record being brought
  into agreement, and it is the artifact that changes on the way-out question.

**Assumptions**
- `[Layout]` The design record gains the way out of setup; the app is unchanged there. *(behaviour tested; record never revised after.)*
- `[Layout]` The refusing continue action changes in the app; the design record already has it right. *(accent fill reads tappable-but-broken.)*
- `[Operations]` The timing check waits for the record rather than loosening what it claims. *(the claim is what was promised.)*
- `[Operations]` The permission check supplies fixed answers for every input it reads, not one. *(a verdict must not move with this Mac's mood.)*
- `[Operations]` Both remaining unsafe shapes are converted, not exempted. *(same hazard; only the search pattern differed.)*
- `[Data & scope]` The stale count is corrected in the shared repository it lives in, one file, committed by explicit path. *(that file is live for every project here.)*
- `[Operations]` The other open defects stay open and unclaimed by this item. *(each still needs investigation this one does not do.)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0100` before the planner picks this up.*

---

### Pipeline record — PRO-0100 *(machine trailer; not part of the review above)*

- Grounded against `docs/test-campaign/inventory.json`: the six are DEF-162, DEF-163, DEF-165,
  DEF-175, DEF-140, DEF-193. The registry currently carries **ten** non-fixed defect rows, not
  the eleven the brief names; the remaining four (DEF-033, DEF-141, DEF-151, DEF-180) are the
  ones the brief says still need investigation.
- DEF-162 confirmed by reading both records: `design/surfaces/proctor-surfaces.html:1000-1004`
  draws dots, spacer, `Back`, and a disabled `Connect a model` with no `Skip setup`;
  `Sources/ProctorUI/Walkthrough.swift:100-105` draws `Skip setup` under
  `WalkthroughFlow.showsSkip`. DEF-163 confirmed at `Walkthrough.swift:115`
  (`.borderedProminent` unconditional) against `proctor-surfaces.html:1004` (`class="btn"
  disabled`). Both are *(measured: source read on HEAD 3fb7681)*, not re-captured.
- **The brief's premise that this item is entirely inside this repository does not hold.**
  DEF-193's target is `~/Dev/fledgeling-plugins/plugins/proctor/skills/proctor/gemini.md:21`.
  The shared-repo discipline from PRO-0101/PRO-0102 applies to it: touch only the `proctor`
  plugin, commit with an explicit path, never `-a` and never `.`, and stop and report if files
  appear entangled. Shared repo measured clean at `a15febf` while this triage ran.
- Out-of-family spec review: see the shared record at the foot of `spec-PRO-0103.md`.

---

## Implementation plan

Implementation plan: `docs/plans/plan-PRO-0100.md` (committed: `6982317`, tier: Standard).

Plan review gate: mechanical path check clean; out-of-family review by **gemini**
(`agy --model gemini-3.7-flash-high`) — a named substitution, because codex is OFF for this
repository and grok returns `402 — usage balance exhausted`. Four material findings, all four
accepted. Full verdict in the plan's gate note and in
`docs/test-campaign/evidence/PRO-0100/plan-review-gemini.md`.

**One narrowing surfaced by that review, and the plan keeps it deliberately.** Triage assumption 5
reads *"Both remaining unsafe shapes are converted, not exempted."* Three of the fourteen bare
force-unwraps are total over a closed input space and are kept with the reason beside them, on
PRO-0098's own recorded classification method. The assumption is read as being about the two
shapes as classes rather than about every individual site. If that reading is wrong, the three
sites convert in about ten lines — say so and they will.

---

## Defects

| Defect | Was | Now | Cases |
|---|---|---|---|
| DEF-140 | open | fixed | CASE-0395, CASE-0396 |
| DEF-162 | open | fixed | CASE-0390 |
| DEF-163 | open | fixed | CASE-0391, CASE-0392 |
| DEF-165 | open | fixed | CASE-0393 |
| DEF-175 | open | fixed | CASE-0394 |
| DEF-193 | open | fixed | CASE-0397, CASE-0398, CASE-0399 |

**Defects:** DEF-140, DEF-162, DEF-163, DEF-165, DEF-175, DEF-193

**Requirements:** REQ-094, REQ-095, REQ-096

**Cases:** CASE-0390 through CASE-0400

**Unused from this item's allocation:** DEF-200..209 in full, and CASE-0401..0409. Nothing new was
opened, so the defect range is reported unused rather than filled. Eleven cases were needed rather
than twenty.

## Progress — 2026-08-22

Built on `ai/pro-0100`, stopped before verify. Gate **2,064 tests in 251 suites, exit 0**, twice.

**The two walkthrough repairs resolved in opposite directions, as triaged.** The design of record
gained the way out; the build stopped drawing a refusing control in the accent fill. The build's
shape was chosen the long way round, through a `ViewModifier` rather than the obvious two-branch
`if/else`, because the obvious shape duplicates the single `.disabled(` modifier that
`skipIsNeverClosed` counts. All three existing walkthrough source guards pass **unedited**, which
was the constraint that picked the shape.

**Arming found a blind pass in this item's own first test, and it is the finding worth carrying.**
CASE-0390's footer slice ended on a marker that matched 2,218 characters later, inside the following
pane, so the slice carried the pane's caption — and the caption names "Skip setup" in prose, which
satisfied a claim about a control. Removing the button left the case green on that clause. The slice
is now bounded to the footer's own eight-space close (304 characters, measured) with two guards of
its own, and the clause asserts the button element rather than the words. Found by arming, not by
reading, which is this campaign's own repeated lesson arriving from the inside.

**A second self-inflicted fault, and it is DEF-140's failure mode:** the first version of DEF-163's
test wrote `#expect(!source.contains(…))`, so swift-testing captured the whole 14 KB of
`Walkthrough.swift` into its failure message and the run produced **no verdict line at all**. Every
source-reading clause in the new tests now computes a Bool into a local first. A test written to
close the no-verdict class had reopened it.

**One clause was rewritten because its arming showed it recognised only the defect's formatting.**
DEF-163's first clause matched the pre-fix arrangement of modifier lines, so re-ordering them while
keeping the unconditional fill survived it. It now reads "no `.borderedProminent` anywhere before
the branch", and is armed twice: once with the exact pre-fix shape and once with the re-ordering
that beat the old version.

**Eight of eleven cases are `armed: true`, each watched failing with its `armedBy` naming the
mutation, the failure text and the exit code.** The three that are not say why, in the row, rather
than claiming an arming that did not happen. DEF-140's arming is the class's own contrast rather
than an exit code: the unsafe form gave signal 5, `Executed 0 tests, with 0 failures`, and zero
verdict lines, while the converted form gave one verdict line and a named failing test. Reading exit
codes alone would have called those two runs identical.

**DEF-193's repair widened its own denominator.** The one-word fix is committed in
`~/Dev/fledgeling-plugins` at `82ebe7d`, one explicit path, tree measured clean before and after.
`skill_doc_measure.py` now reads every `*.md` under the skill rather than the two it was pointed at,
on both stated counts and named tools, and it immediately found two files no check had ever opened.
27 of 27 checks armed.

**Out-of-family lanes:** codex is OFF for this repository and grok returns
`402 — usage balance exhausted`, so **gemini** (`agy --model gemini-3.7-flash-high`) took the plan
review gate, named as a substitution under ORCHESTRATOR.md's rule as amended today. Four material
findings, all four accepted; one of them corrected a reason this item had given for keeping a force
unwrap, by opening the file and finding the reason was true of the neighbouring site and not of that
one.

**Stopped before verify and before merge.** Nothing pushed.

### Gates, with their real exit codes

| Gate | Exit | Reading |
|---|---|---|
| `./scripts/test.sh` | **0**, twice | 2,064 tests in 251 suites, verdict line present in both. Baseline before this item: 2,061 in 251. The three new tests are CASE-0390's, CASE-0391's and CASE-0392's. |
| `scripts/campaign/defect_gate.py claims` | **0** | All six claimed defects read `fixed`. |
| `scripts/campaign/defect_gate.py dropped` | **0** | 2 files, 108 merges, 39,060 id/field pairs examined; no dropped value. |
| `scripts/campaign/test_instruments.py` | **0** | 62 passed, 0 failed. |
| `scripts/campaign/operator_path_gate.py` (`census`, `seams`) | **0**, **0** | 13 operator-path sites, 15 entries classed. |
| `scripts/campaign/skill_doc_measure.py` | **0** | 27 of 27 checks pass. Exited **1** against the unfixed `gemini.md`, which is the arming. |
| `scripts/campaign/skill_doc_arm.py` | **0** | 27 of 27 checks armed, each watched failing under its own mutation on a scratch copy. |
| `campaign.py check` (test-campaign 0.9.9) | **1** | **Pre-existing, and measured as such.** The same gate run against this branch's base registries at `9f99a0f` also exits 1, with a blocker set that `diff` reports **identical** to this one: REQ-086 checked by nothing, REQ-024 vacuous, CASE-0318's three missing capture files and its unstated pixel origin, and six source-analysis findings against CASE-0333, CASE-0334 and CASE-0335. All belong to PRO-0086 and PRO-0099 rather than to this item. Baseline and current output are both kept, at `campaign-check-baseline.txt` and `campaign-check.txt`. |

**This item's own cases add zero findings to that gate**, and doing so needed a correction: the
eight source-analysis cases first carried no `source` block, so `campaign.py check` reported 22
findings where the baseline had 6. Every one now names its analyzer and a **measured** denominator,
which is the whole point of the guard: a grep pointed at the wrong file and a grep that found
nothing read the same without the count.

**Left open deliberately, and not this item's to take:** CASE-0333..0335's missing `source` blocks
are PRO-0099's rows. They are a small fix, and correcting another item's registry rows is exactly
where the orchestrator's merge has dropped values three times, so they are reported rather than
edited. REQ-086 and CASE-0318 are the same call.

## Verification — 2026-08-22, `Done`

Verified fresh-context on `a33ac1c` by an agent that did not build the work. Every gate re-run:
`./scripts/test.sh` `EXITCODE=0` at *Test run with 2064 tests in 251 suites passed after 68.588
seconds*; `defect_gate.py` `claims` 0 and `dropped` 0 over 108 merges and 39,060 id/field pairs;
`test_instruments.py` 0 with 62 passed; `operator_path_gate.py` 0/0/0 over 13 sites and 15 classed
entries; `skill_doc_measure.py` 0 at 27/27 and `skill_doc_arm.py` 0 at 27/27 armed. `campaign.py
check` exits 1 on a blocker set of REQ-007, REQ-024, REQ-086, CASE-0318 and CASE-0333–0335 — none of
CASE-0390–0400, none of REQ-094/095/096.

**Every recorded arming was re-applied and every one bit.** CASE-0395 reproduced the contrast the
whole of DEF-140 rests on: the bare unwrap fed a nil printed `Fatal error: Unexpectedly found nil`,
`Executed 0 tests, with 0 failures`, **zero verdict lines** and `FAIL: no swift-testing verdict line`,
while the same nil through `try #require` produced one verdict line naming the failing test at 30:30.
CASE-0394's no-op ticket raised four issues, one per ending, over 256 seconds — the wait does not
report success regardless.

### The three kept unwraps stand, and the reason is narrower than "they are safe"

All three stated input spaces were verified true in source: `box.value!` where both the `do` and
`catch` arms `set` before `resume`; `frame.baseAddress!` with four prefix bytes appended two lines
above; and the second `baseAddress!` in `FrameCodec.encode`, where `Transport.swift:17-20` prepends
four bytes unconditionally. What settles it is that the acceptance clause is *no force-unwrap shape
that can end a run with no verdict line*, and a total unwrap cannot. Converting sites 2 and 3 would
mean handing a pointer out of `withUnsafeBytes`, trading a proven-total unwrap for a pointer-lifetime
hazard, and would leave DEF-136's four surviving group-1 sites inconsistent with them. So no
zero-exemption sweep is owed. The gemini plan review had read the exemptions as narrowing triage
assumption 5; on the source they narrow nothing.

### Two things the verification produced that are not acceptance clauses

Both were routed by the fleet's non-AC findings gate, which PRO-0100 is the first item through.

- **DEF-200, opened before this merge.** CASE-0392 records `armed: false` on the grounds that arming
  it would mean breaking the design of record; the verifier broke it on a scratch basis anyway and the
  check reds at line 397. The case is armable and the record understates its own strength. The flag is
  not flipped here, because the probe left no evidence file and no artifact means no verdict.
- **A limit of the prominence guards, recorded on REQ-094.** The three guards partition
  `Walkthrough.swift` so no unbranched `.borderedProminent` can hide, and they read that one spelling.
  An accent fill through `.tint` or a `.background` would satisfy all three. Nothing draws one today,
  which is what makes it a limit rather than a defect.

### One lane artifact worth naming, because it manufactured a finding

Gemini marked the first unwrap site `UNPROVEN` while accepting the other two. The cause was the
packet rather than the code: the excerpt handed to it began one line below the `do`/`catch` that makes
the site total. An out-of-family reviewer reading an excerpt can only be as right as its boundaries,
and an excerpt boundary is invisible in the reply. It answered about PRO-0100 throughout — citing
`WalkthroughFlowTests`, `PrimaryProminence` and `Transport.swift:10-22` — so the lane itself held:
`OVERALL: ACCEPT`, with A2, A3 and A6 met and the exemptions defensible.
