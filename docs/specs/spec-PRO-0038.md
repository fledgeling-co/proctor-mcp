# PRO-0038: Stability knows when it is scoring a page

**ID:** PRO-0038
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/39-stability-knows-when-it-is-scoring-a-page.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` — wins over any earlier spec
**Evidence:** `docs/research/2026-08-15-dossier-proctor-vs-cua.md`
**Builds on:** PRO-0020 / PRO-0024 (the browser boundary and its routing), PRO-0044 (the actuation
seam, merged `d65dc1e`), PRO-0045 (the indeterminate outcome, merged `1bff5c2`), PRO-0051 (a verdict
names its actuation path, merged `0f76c56`)
**Coordinates with:** PRO-0049 (the same question for a Maestro flow, in flight — vocabulary shared,
no shared code)
**Branch:** `ai/pro-0038` (worktree `.worktrees/PRO-0038`)

## Feature description

<!-- Verbatim from docs/features-to-triage/39-stability-knows-when-it-is-scoring-a-page.md -->

> **REVISED for wave 7, 2026-08-15.** Still wanted and more central than when it was written: determinism scoring is the capability this repo is pivoting towards, and nothing else on this platform packages it. Its browser half changes, because a page driven by Cua over CDP is executed rather than handed off. Brief 50 raises the same question for a Maestro flow, and the two should share an answer about what a score means when Proctor did not run the steps itself.

# Stability knows when it is scoring a page

## The problem

`proctor_stability` replays a flow several times and scores how deterministic it
was. PRO-0020 logged what happens when that flow runs over browser content: the
score measures the page's own render-tree churn as much as the application's, and
the stability report has no idea. PRO-0024 made it larger, because a flow whose
steps were recommended to a lane Proctor does not execute produces a score that
measures nothing it claims to.

A determinism number is exactly the kind of output somebody trusts without
checking, which is what makes a silently meaningless one worth fixing.

## What it should do

Have the stability report disclose when the thing it scored was page content, and
say what that does to the number.

## The hard parts, named

- **`proctor_act` already discloses this and the report does not**, which is the
  whole shape of the item: the detection exists, and the two surfaces are not
  joined. Reuse PRO-0020's browser detection rather than adding a second one.
- **Disclosure is not the same as refusal**, and the spec should say which this
  is. A page-content flow that scores 1.0 across five runs has told you something
  real. One that scores 0.4 has told you almost nothing about the application.
  Reporting the churn alongside the score is more useful than withholding the
  score, and it is also more work.
- **Per-step, not per-run.** A flow that touches native chrome and then a web
  area has steps of both kinds, and a single flag on the report would mark the
  whole thing suspect when one step is. The per-step instability data already
  exists in the report; that is where this belongs.
- **The handed-off case is different from the page-content case.** A step whose
  target was recommended to Obscura was never executed by Proctor at all. That is
  not churn, it is an absence, and it should not be scored as if it were a step
  that ran.

---

## The decision

**Disclosure, per step, measured at the moment the step ran — and one behavioural
change, because one of the three cases is not a disclosure problem at all.**

A determinism score has two separate defects here and the brief runs them together.
One is a **labelling** defect: the number is real but nobody is told what it was
taken over. The other is a **sampling** defect: a hash that is not evidence about
the step is folded in as though it were. The first is fixed by saying more; the
second cannot be, and is fixed by taking the hash out of the fold.

## What the score is taken over, and why the report never said

`Canonical.hash` walks the accessibility tree of the window. Inside a browser's
web area that tree is the page's render tree; outside it, it is the application's
own view hierarchy. `BrowserTarget.evidence` already states the consequence in one
sentence, and `proctor_act` already emits it:

> A step into page content still travels the accessibility plane like any other, but its state hash
> is taken over a browser's render tree rather than an app's view hierarchy, so a determinism score
> across page content measures the page's own churn as much as the app's.

**The sentence and the detection both already exist. `StabilityReport` is the one
surface they never reached** — which is the brief's first hard part, and it is
exactly right. Nothing new is detected here and no second boundary rule is written:
`BrowserCatalogue.identify` decides whether a window is a browser's,
`AXEngineImpl.webContent` reads the web areas, and `WebContentProbe.contains`
decides which side of the boundary a rect falls on. All three are PRO-0020's, all
three are already tested, and this item consumes them.

## Disclosure, never refusal

The brief asks which this is and the answer is disclosure, with no case in which a
score is withheld for being page content.

The reasoning is the brief's own and it is right: **a page-content flow scoring 1.0
across five repeats has proved something real** — the page rendered identically five
times and the application drove it identically five times. Withholding that would
destroy a true result to avoid a reader misreading a different one. A score of 0.4
has told you almost nothing about the application, and the fix for that is to say so
beside the number rather than to delete the number.

This also matches the established shape of the boundary. PRO-0020 made the browser
handoff advisory and never a refusal; PRO-0024 kept it advisory; `proctor_act`'s own
comment records that "nothing here refuses anything and no step's plane changes."
A stability report that refused where `act` discloses would put two different answers
on one boundary.

## Per-step, and measured while the step ran

The brief's third hard part settles the shape — a flow that touches native chrome
and then a web area has steps of both kinds — and the report already has the right
place for it, `stepInstability`, one entry per step.

**What the first draft got wrong was *when* to measure it, and the out-of-family
gate killed that draft.** The draft resolved every step's target rect once, before
the first repeat, and marked the ones inside a web area. The objection:

> Step *k*'s target usually does not exist until steps `1..k-1` have run (the click that opens the
> webview). Unresolved → not marked […] means a flow that only hits a page mid-run ships **no**
> advisory and still scores render-tree churn. That is the Fact 1 bug with a count attached.

That is decisive. A flow that opens a browser and then drives a page is the ordinary
case for this feature, and a pre-scan misses precisely it. The same objection notes a
pre-scan can also false-positive, resolving a coordinate against whatever happens to
be under it before the flow starts.

**So the classification happens during the run, at the step, where the target has
just been resolved and the window is in the state the step actually met.** That is
`runSteps`, the one code path `act`, `flowReplay` and `stability` all share, so the
answer is produced once and every surface reads the same one.

Cost is bounded by the rule `browserHandoff` already follows: the catalogue lookup
runs first, so a window no browser renders costs one dictionary lookup and no
accessibility traffic. Only a browser window pays for a web-content read.

## The three per-step cases, which are not the three the brief named

The brief names *ran*, *handed off* and — via PRO-0045 — *indeterminate*. Measured
against this build, one of those does not exist and a different one does.

### 1. Page content — a real score over the wrong subject

The step ran, Proctor performed it, and its hash is over a render tree. **Scored,
disclosed, and the number stands.**

### 2. Unvouched — a hash that is not evidence about the step

This is the sampling defect, and it is present in this build rather than
hypothetical. When a delegated backend dies mid-step, PRO-0045 records the step
`indeterminate`: Proctor cannot say whether the action happened. `SessionAct` then
takes a post-state walk anyway and stores it as that step's `stateHash` — correctly,
because it is the only evidence left about what the machine did, and PRO-0045's own
comment says it is "evidence and not proof".

`SessionFlow`'s sweep loop then appends that hash into the fold column, where it is
scored exactly like a step that ran. **A hash taken after an action nobody can vouch
happened is not a sample of that step's post-state**, and folding it in either masks
a real divergence or invents one.

This is the brief's fourth hard part — "it should not be scored as if it were a step
that ran" — reached by a different route than the brief expected. So the hash is
**withheld from the fold**, matching PRO-0049's treatment of a repeat that never
reached the app: not a sample of the application's behaviour, therefore not folded.
It stays on the `StepResult` as evidence, which is PRO-0049's other rule — evidence
is reported beside the score, never fed into it.

### 3. Handed off — a premise this build contradicts

**There is no step in this build that is recommended to another lane and not
executed.** The browser handoff is advisory; every step still runs on the
accessibility plane, and `Sources/ProctorAgent/Actuation/` holds no browser or CDP
execution lane. Under the wave 7 direction a page driven by Cua over CDP is executed
rather than handed off, which removes the case rather than creating it.

Following the advice does produce something real, but it is invisible from here: the
operator drives the page in Obscura, and the flow they record simply has no step for
it. **Proctor cannot label a step it was never asked to run.** No state is invented
for this, and the honest statement is that a recording is evidence about what Proctor
did, never a claim that nothing else happened.

Stated plainly rather than papered over, following PRO-0051's handling of its own
brief's false premise about the test suite.

## What the gate found that the design still has to answer

Three residual failure modes, all adopted.

**A label frozen on one repeat.** Because classification now happens per step *per
repeat*, the repeats can disagree — step 3 was browser chrome in one and page content
in another. That is not noise to be collapsed; it means the flow itself took a
different path, which the hash may not show. **Every distinct subject the repeats
produced is reported**, so a disagreement is visible rather than averaged away.

**"Unmarked" meaning two different things.** A step with no classification could be a
native window's step or a browser window's step whose target never resolved. Those are
different facts. **The classification is emitted for every step of a browser window,
with `unclassified` as its own value**, and is absent only when no browser renders the
window at all — so absence means one thing.

**A zero computed on one sample.** `Canonical.instability` returns `0` for a column of
one hash, which reads as "perfectly stable" for a step measured once. Withholding an
unvouched hash makes that more reachable, so **the per-step sample count goes on the
wire** beside the score rather than only into `notes` as prose. A reader can no longer
take a `0.0` at face value without seeing what it was computed over.

## What the disclosure claims, and what it does not

The second out-of-family gate pressed on this and it is worth stating rather than
leaving implied: **naming the measurand does not change it.** A page-content step's
number is a measurement of the page, and a report that labels it correctly is still
reporting a measurement of the page. The disclosure makes a reader able to see what
they are holding; it does not convert a page measurement into an application one, and
no clause here should be read as claiming it does.

That is the whole reason the label is per step and carries the browser's name: the
useful question after reading it is "which of these steps am I entitled to draw a
conclusion about", and that question is answerable only when the boundary is drawn at
the step.

### The label marks where a step acted; it does not partition the hash

The completeness critic found the sharpest limit in the design and it is stated here
rather than discovered later. **A state hash is a walk of the whole window**, rooted at
the window and not at a subtree — `Session.walk(window:)` passes `root: nil` in the step
loop and `Canonical.hash` takes the resulting tree. In a browser window the page's render
tree is *inside* that walk.

So the page's churn is in every step's hash for that window, `browserChrome` steps
included. A step labelled `browserChrome` is a step whose **target** was outside the web
area; it is not a step whose number is unaffected by the page.

The label is therefore a statement about where Proctor acted, and about where churn in
that window most likely originates — not a partition of the score into a page half and an
application half. Reading it as a partition would be a subtler version of the same
over-trust this item exists to remove, so it is written down in the field's own
documentation as well as here.

Scoping the hash to a subtree would change what a determinism score means for every
window Proctor measures, browser or not, and is a much larger question than this item.
Recorded as child work.

## What this does not change, and one thing it does — measured, not assumed

Page content does **not** suppress `deterministic`. That is the disclosure decision
applied to the verdict: a page-content flow that agreed across every repeat did agree.

**The unvouched hash is a different matter, and the first draft of this spec was wrong
about it.** That draft claimed the withholding only moved which step `firstDivergence`
points at, on the reasoning that a repeat ending at an indeterminate step leaves a short
hash column, which makes `complete` false and withholds the verdict anyway.

Measured on this build by removing the withholding and running the sweep, that is false.
A two-repeat sweep whose second repeat died indeterminate at the only step reported:

```
stepInstability: [0.0], firstDivergence: nil, deterministic: true
```

The unvouched hash **fills** the column rather than shortening it — the step is the last
one in its repeat, so a hash stored for it makes that repeat's column exactly as long as
a clean one. `complete` is then true, and when the post-state happens to match the good
repeat's, every other condition passes too.

So the defect is not a misplaced divergence index. **It is a `deterministic: true` on a
sweep in which half the evidence came from an action nobody can say happened** — which is
precisely the silently meaningless number the brief exists to remove, produced by the code
as it stands. Withholding the hash turns that verdict to `false`, which is the correct
answer.

## Acceptance clauses

**A1 — One detection, not a second one.** The page boundary is decided by
`BrowserCatalogue.identify`, `AXEngineImpl.webContent` and `WebContentProbe.contains`
— PRO-0020's — with no new boundary rule, no new web-area role constant and no second
catalogue. A window no browser renders costs a dictionary lookup and no accessibility
traffic.

**A2 — A step is classified at the moment it ran, not before the sweep.** A flow whose
web area only exists after an earlier step still classifies the later step as page
content. This is the clause the out-of-family gate added and it is the one that makes
the feature work rather than appear to.

**A3 — Per step, not per run.** A flow whose steps touch native chrome and then a web
area reports both, against the step indices they belong to. No report-level flag marks
a whole sweep suspect because one step was.

**A4 — The score is still there, with the churn beside it.** A page-content sweep
returns `stepInstability`, `firstDivergence` and `deterministic` exactly as it does
today, plus the disclosure. Nothing is withheld for being page content, and
`deterministic` is not suppressed by it.

**A5 — The report says what the number was taken over, in one sentence, once.** The
sweep names the browser and carries `BrowserTarget.evidence` verbatim rather than a
second wording of the same fact.

**A6 — An unvouched hash is not folded.** A repeat whose step ended `indeterminate`
contributes no hash for that step to `stepInstability`, `divergenceDetail` or
`firstDivergence`. Proved red-to-green: with the withholding removed, the unvouched
hash changes the score.

**A7 — The withheld hash survives as evidence.** It stays on the `StepResult` and in
the audit row, so what Proctor observed after a step it cannot vouch for is still
readable. Excluded from the score, reported beside it.

**A8 — A score says how many samples it was computed over, and a score computed on
fewer than two is not published as a number.** Every step's entry carries the count of
repeats that contributed a hash. Where that count is below two its instability is
**absent from the entry** rather than reported as `0.0`, because `Canonical.instability`
returns `0.0` for a column of one hash and a step measured once would otherwise be
indistinguishable from five agreeing repeats. The legacy `stepInstability` array keeps
its shape and its `0.0` for wire compatibility; the entry is the surface that does not
lie, and the two are pinned to agree wherever both carry a number.

**A8b — A sweep holding an unscored step is never reported deterministic.** Stated because
A6 makes a short column reachable on a path that did not previously produce one — and
because measurement showed the existing guard did **not** already cover the unvouched
case: the withheld hash fills its column rather than shortening it, so without A6 the
verdict fires. Pinned by a test.

**A9 — The repeats' disagreement about the boundary is reported, not collapsed.** A step
classified page content in one repeat and browser chrome in another reports both. Such a
step will also score unstable, because the two hashes are over different trees; the
disclosure is what lets that instability be read as the flow taking two paths rather than
as the application misbehaving.

**A10 — Absence means one thing.** On a browser window every step carries a
classification, `unclassified` included. The field is absent only when no browser
renders the window.

**A11 — Older reports still decode, and a native sweep is unchanged.** The new fields are
**optional**, which is what makes `Codable` tolerate a missing key, and carry **no `init`
default**, which is a separate decision that forces every construction site to state the
value rather than silently inherit a wrong one. PRO-0051 established both; the plan gate
caught this spec running the two reasons together. A `StabilityReport` written before this
existed still decodes, and a sweep against a native window with nothing withheld encodes
exactly as it did before.

**A12 — The tool catalogue describes what the tool now returns.** `proctor_stability`'s
published description says a score can be taken over page content and that the report
says when it was, so a model reading the catalogue is not surprised by the field.

## Not in scope

- **Refusing, suppressing or discounting a page-content score.** Decided against
  above; the brief asks and this is the answer.
- **A browser or CDP execution lane.** The wave 7 direction puts actuation behind the
  Cua seam and its browser lane is upstream work, not this item's.
- **Changing `deterministic`'s definition** or adding a condition that suppresses it.
- **Anything in `Sources/ProctorUI/` or the iOS lane.** PRO-0029 and PRO-0049 are in
  flight there.
- **Treating an Electron app or a native `WKWebView` host as page content.** Raised by
  the clause gate and rejected above: PRO-0020 drew that boundary deliberately, and such
  an app's render tree is its own view hierarchy for the purpose of testing it.
- **A shared enum across the macOS and Maestro lanes.** The vocabulary is deliberately
  compatible with PRO-0049's — excluded-from-the-fold versus reported-beside-the-score
  — but PRO-0049 is unmerged and coupling to its code now would couple to something
  that may still change. Recorded as child work, as PRO-0049's own spec already does.

## Child work found

- **A state hash is a walk of the whole window, so a subtree cannot be scored on its
  own.** The consequence for this item is written up above: a `browserChrome` step's
  number still contains the page. Whether `proctor_stability` should be able to scope a
  hash to a region or a subtree is a real question about what a determinism score means
  for every window, and is much larger than this item. Found by the completeness critic.
- **A shared flake-attribution vocabulary.** PRO-0049 names this already. This item
  makes it two lanes rather than one: `unclassified`/withheld here and `driverFailed`
  there are the same idea. A third lane should force one enum.
- **Per-step page-content data on `proctor_act`'s own result.** Classifying at the step
  puts the fact on every `StepResult`, so `act`'s per-batch handoff could become
  per-step. Out of scope here, and a real improvement to the surface the brief says
  already discloses.
- **A step's classification is a fact worth asserting on.** `proctor_assert` has no way
  to require that a step stayed out of page content, which is what a suite pinning a
  native-chrome interaction would want.

## Triage — 2026-08-15 — Ready for Implementation Plan

**Sentinel verdict:** S2. The item changes one wire shape a determinism claim is read
from and changes which samples a published score is computed over. It touches no key
material and no gate logic; it does add a rule about what an audit-adjacent record is
allowed to feed. The weight is in the sampling change, not the diff.

No essential gaps. Every open question was resolvable from the direction file, PRO-0020
and PRO-0051's shipped decisions, PRO-0049's spec, or measurement against this repo.

### UI & logic preview

**Where it shows up:** nothing customer-facing changes. No panel, menu bar or status
window surface is touched. *(behind the scenes — nothing visible changes)*

**What users will see:** a repeatability report for a flow that touched a web page now
says which of its steps were measured over the page rather than the application, and
what that does to those numbers. Each step also says how many repeats its score was
computed from.

**Behaviour changes:**
- A score taken over page content is still reported, now with the caveat beside it.
- A step whose outcome could not be established no longer contributes to the score, so
  the reported point of first disagreement can move to an earlier step than before.
- A step measured on fewer repeats than the sweep asked for says so as a number.

### Assumptions

- `[Data & scope]` Disclosure, never refusal: a page-content score is always reported (*a flow scoring 1.0 across five repeats has proved something real, and deleting it to prevent a misreading of a different result costs more than it saves*).
- `[Data & scope]` Page content does not suppress the deterministic verdict (*the same decision applied to the verdict rather than a second, quieter refusal*).
- `[Data & scope]` A step is classified while it runs, not before the sweep (*a flow that opens a browser and then drives a page is the ordinary case, and a pre-scan misses exactly it*).
- `[Data & scope]` A hash taken after an action Proctor cannot vouch for is withheld from the score and kept as evidence (*it is not a sample of that step's post-state, and PRO-0049 settled the same question the same way*).
- `[Data & scope]` No step state is invented for the handed-off case (*this build has no step that is recommended elsewhere and not executed, and a recording cannot describe work Proctor never did*).
- `[Data & scope]` Every step of a browser window carries a classification, including one that could not be established (*absence must mean one thing, or unmarked silently mixes native with never-classified*).
- `[Data & scope]` Where repeats disagree about which side of the boundary a step fell on, every value is reported (*the disagreement is a finding about the flow, not noise to average away*).
- `[Data & scope]` The per-step sample count is published, and a score computed on fewer than two repeats is not published as a number at all (*instability returns zero for a column of one hash, so a step measured once would otherwise be indistinguishable from five agreeing repeats*).
- `[Data & scope]` New fields are optional with no default, so older reports decode and a native sweep is byte-identical (*measured on PRO-0051: an init default does not make Codable tolerate a missing key*).
- `[Operations]` The vocabulary is made compatible with the Maestro lane's but shares no code with it (*that lane is unmerged, and coupling to it now couples to something that may still change*).

*If any of these are wrong, edit the answer inline (or correct an assumption) in this file and re-run `/triage PRO-0038` before the planner picks this up.*

### Out-of-family review — grok-4.6, xhigh, read-only

Run on **the decision itself**, before this spec was written, with the measured facts
inlined rather than by asking it to read files — the lane is documented to die on a long
prompt. Five proposed decisions were put up for attack. It agreed with three and broke
two, and both breaks are adopted:

1. **Classifying before the sweep is the wrong moment, and it defeats the feature.** A
   step's target usually does not exist until earlier steps have run, so a flow that only
   reaches a page mid-run would ship no disclosure at all and still score render-tree
   churn — "the bug with a count attached". It also warned a pre-scan can false-positive
   on whatever sits under a coordinate beforehand. The design moved to classifying at the
   step, inside the shared step loop. This is clause A2 and it is the most valuable thing
   the gate produced.
2. **Withholding one cell is not the sibling item's treatment, and the fold's behaviour on
   a thin column was unspecified.** It asked what `stepInstability`, `firstDivergence` and
   `deterministic` do with a column of one or zero samples, and about columns with unequal
   *n*. Checked against this repo: `Canonical.instability` returns `0` for a one-hash
   column, so a step measured once scores as perfectly stable. Clause A8 puts the sample
   count on the wire. Its related worry that later steps of the same repeat would stay in
   the score does not arise here — an indeterminate step sets `failedAt` and ends its
   repeat, so there are no later steps — and that fact was missing from the evidence given
   to it rather than wrong in its reasoning.

Three further open failure modes it named are answered by A9, A10 and A7: a subject frozen
on one repeat, "unmarked" collapsing native with never-classified, and hashes the fold was
told to ignore lingering elsewhere. The last is deliberate and now stated — the hash stays
as evidence on the step and in the trail, and only the score refuses it.

No key material, gate code or audit-trail code was sent; the review was scoped to design
prose and measured facts.

### Out-of-family review — the acceptance clauses as an artifact

A second gate ran on the twelve clauses, same lane, evidence inlined and file reading
forbidden. It was asked what could pass all twelve and still ship a misleading
determinism number. Four findings; two accepted, two rejected with reasons.

**Accepted — a thin column still scores `0.0`.** The sharpest finding, and it survives
A6 rather than being fixed by it. A step that ended indeterminate on four of five
repeats leaves a column of one hash, which `Canonical.instability` scores `0.0` — "the
step completed once and the backend died the other four times" published as perfect
stability. A8 as first written only required the count *beside* the number, which makes
the trap visible without removing it. A8 now withholds the number itself below two
samples, and A8b pins the report-level verdict that already protects against this so it
cannot regress. The gate's related claim that the verdict does not suppress was checked
and is **wrong for this build** — a short column makes `complete` false and
`deterministic` is already withheld — but the per-step number it named was genuinely
being published, and that is what changed.

**Accepted — a boundary disagreement reads as application instability.** Where repeats
disagree about which side of the boundary a step fell on, its hashes are over two
different trees, so it scores unstable and the instability is attributed to the
application. A9 now says the disclosure is what makes that readable as the flow taking
two paths.

**Rejected — "classification is a sidecar; the number is still the folded hashes."**
Correct as an observation and rejected as a change, because it argues for the refusal
this item deliberately declined, on the brief's own reasoning. A number labelled with
its measurand is not a false number. The observation was worth keeping, so it is stated
directly in "What the disclosure claims, and what it does not" rather than answered by a
clause.

**Rejected — "A1 fails open for an Electron app or a native `WKWebView`."** This is
PRO-0020's boundary working as designed, not a hole in it. That item's own note records
the reasoning: inferring "browser" from the presence of a web area "would sweep in every
Electron application and every native app hosting a `WKWebView`, which is exactly the
boundary this feature exists to draw." Slack and VS Code are Chromium rendering one
origin, and they are applications under test — their render tree *is* their view
hierarchy for the purpose of testing them, so churn in it is the application's churn and
the caveat would be wrong. Reversing that here would reverse a landed decision from a
different item, on a surface this one does not own. A1 keeps the catalogue.

## Plan — 2026-08-15

Implementation plan: `docs/plans/plan-PRO-0038.md` (Plan size: Small).

The plan's out-of-family gate changed the design twice and refuted two of its own compile
warnings on measurement. The substantive change: `stepInstability` and the new per-step
entry were two write paths for one number and would have drifted, so `StabilityScore.Fold`
now returns the per-step sample count alongside the instability and every consumer reads
that one computation — drift is impossible by construction rather than pinned by a test.
The second: a step classified page content in one repeat and browser chrome in another
left the disclosure undefined, and both obvious choices are wrong, so the disclosure is
defined as page content in at least one repeat with the mixed `subjects` list carrying the
fact that the number belongs to neither side.

## Progress — 2026-08-15

**Status:** In Review. Branch `ai/pro-0038`, worktree `.worktrees/PRO-0038`. Not merged;
finalization is the orchestrator's.

**Gate:** `swift build` green; `./scripts/test.sh` **1318 tests in 142 suites passed**,
against a **1293**-test / 140-suite baseline at the merge base — exactly the 25 tests and
2 suites added here.

### Acceptance clauses, and what proves each

| Clause | Proof | Result |
|---|---|---|
| A1 one detection, native pays nothing | `nonBrowserWindowReadsNoWebContent` — an unlisted bundle **with a web-content probe set** carries no subject, so the catalogue gate is what stops it rather than the absence of a page | pass |
| A2 classified at the step, not before | `aWebAreaThatAppearsMidFlowIsStillClassified` — recorded with no page in the window at all, swept with one; the subject can only have come from the sweep's own passes | pass |
| A3 per step | `aFlowTouchingChromeThenPageReportsBoth` | pass |
| A4 score still returned, verdict not suppressed | `pageContentStillScoresAndStillVerdicts` | pass |
| A5 the existing sentence, once | `theDisclosureReusesTheExistingSentence`, `aFlowTouchingChromeThenPageReportsBoth` | pass |
| A6 unvouched hash not folded | `anUnvouchedHashIsNotFolded` — **red-to-green** | pass |
| A7 the reading survives as evidence | `theWithheldHashStaysOnTheStep` | pass |
| A8 sample count published, thin column not scored | `anUnvouchedHashIsNotFolded`, `aThinColumnPublishesNoNumber`, `aSingleSampleScoresZero` | pass |
| A8b unscored sweep is not deterministic | `anUnvouchedHashIsNotFolded` | pass |
| A9 disagreement reported | `repeatsThatDisagreeAboutTheBoundaryReportBoth` (wiring), `disagreementCarriesBothSubjects` (wire) | pass |
| A10 absence means one thing | `everyStepOfABrowserWindowCarriesASubject`, `unclassifiedIsAValue`, `anAllChromeSweepCarriesNoPageDisclosure` | pass |
| A11 old records decode, native unchanged | `aReportWithoutTheNewFieldsStillDecodes`, `aStepWithoutASubjectStillDecodes`, `aNativeSweepEncodesNoNewKeys`, `aNativeStepEncodesNoSubject`, `recordsRoundTrip` | pass |
| A12 catalogue describes it | `theCatalogueDescribesPageContent` | pass |
| one fold, no drift | `theFoldReportsItsOwnSampleCount`, `entryInstabilityAgreesWithTheLegacyArray` | pass |

### Red-to-green, and what it actually showed

The withholding was removed and `anUnvouchedHashIsNotFolded` failed. The failure output is
the most valuable evidence this item produced, because it refuted this spec's own first
draft. With the unvouched hash folded, a two-repeat sweep whose second repeat died
indeterminate reported:

```
stepInstability: [0.0], firstDivergence: nil, deterministic: true
```

The draft had claimed the existing short-column guard already withheld that verdict. It
does not: an indeterminate step is the last step of its repeat, so a hash stored for it
leaves the column exactly as long as a clean one. The spec was corrected to say the
defect is a false `deterministic: true` rather than a misplaced divergence index.

### Out-of-family completeness critic — grok-4.6, xhigh, read-only

Run on the shipped behaviour with the change and the test list inlined, asked what the
tests do not cover that a reader would assume they do. Its sharpest finding is now the
spec's own limitation section:

**A state hash is a walk of the whole window.** So the page's render tree is inside every
step's hash in a browser window, `browserChrome` steps included, and the label marks where
a step acted rather than partitioning the score. Verified against
`Session.walk(window:)`, which passes `root: nil` on the step path. Written into the
spec, into `HashSubject`'s own documentation, and recorded as child work.

Three test gaps were accepted and closed: no wiring test drove two repeats to disagree
about the boundary (A9 had only a wire-shape test); a browser sweep that never touched the
page was not shown to omit the disclosure; and the mid-flow test proved less than it
looked, because the page was present at record time. All three now exist, and the mid-flow
test was rebuilt to record with no page at all so the subject can only come from the sweep.

Three findings were rejected on measurement: that an unlisted bundle holding a web area was
uncovered (`nonBrowserWindowReadsNoWebContent` sets the probe deliberately, for exactly that
reason); that the `break` could drop a later vouched step in the same repeat (an
indeterminate step ends its repeat, which is what `anIndeterminateStepIsTheLastResultInItsRepeat`
pins); and that a legacy recording could carry an unvouched hash as a normal sample
(`appendToFlow` records only successful steps, and such a step is not one).
