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
