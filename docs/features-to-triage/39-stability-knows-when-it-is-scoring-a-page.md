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
