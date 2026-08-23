---
sources: [REQ-109, REQ-110, DEF-018, DEF-033]
---
# Nineteen of twenty-two ProctorAgent mutants survived

**Wave 13, brief 5 of 6.** DEF-033. The single largest statement anyone has made about how much this
suite actually knows.

## The measurement

PRO-0080 took the first mutation sample ever run against `ProctorAgent`: 24 mutants over a pool of
**3,189 sites across all 84 files**. Nineteen survived, five scored killed, none unbuildable.

Two of the five kills are timeout-scored at exactly 600.0s under a load average that reached 271,
and the runner scores a timeout as a kill. Those two are not trustworthy — a survivor is trustworthy
in both directions, a kill under starvation is not. **The honest figure is 3 kills of 22 scored: a
survival rate of 86.4%.**

For contrast, DEF-018 recorded half of `ProctorCore`'s sampled mutants surviving and that was
treated as serious enough to fix. `ProctorAgent` is the package holding the session, the queue, the
overlay, the actuation backend and every guest adapter — the half of the product that touches the
machine — and it is markedly weaker.

PRO-0080 dispositioned all nineteen: **5 killed by new tests** (CASE-0075..0079), **1 equivalent**,
**6 uncovered-by-lane**, **7 "no seam"**. That third and fourth label are where this brief lives.

## What "no seam" means and why it is the real finding

Seven survivors carry a label the acceptance clause did not enumerate. PRO-0080's report defines it
openly as the weaker, more honest claim: headless-testable in principle, but **no fake exists
today** to test it through. Its verifier accepted the deviation precisely because it refuses to
conflate a coverage hole with a mathematical impossibility, which is what calling them `equivalent`
would have done.

So the disposition is honest and the work it names is untouched. Seven places in the code that
touches the machine have no seam through which a test could observe them, and six more are reachable
only on a lane the suite does not run headless.

**That is thirteen of nineteen survivors that no amount of test-writing closes without changing the
product's testability.** Building those seams is this item.

## What to build

**Sample more before building more.** 24 mutants over 3,189 sites is 0.75%, one seed. The
disposition of the next 24 will tell you whether "no seam" is a property of the seven files sampled
or of the package. Sample first, then build seams where the density is, rather than building seams
for the seven already named and re-measuring nothing.

**Build seams the way this repo already does.** `GuestProvider`'s
`init(executable:timeoutMs:run:)` beside a convenience initialiser binding `Self.liveRun`, and
`SignatureVerdictCache`'s `init(identify:verify:)`, are both the pattern: production supplies the
live implementation, tests supply a fake, and the seam is a parameter rather than a global.

**Every seam earns a killing test, or the survivor is recorded with its reason.** A seam built and
not used moves a survivor from "no seam" to "uncovered", which is a worse answer than before because
it looks like progress.

**Run under low load and say what it was.** The two untrustworthy kills exist because the run
finished under a load average of 271. Record load at both ends, and treat any 600.0s kill as a
survivor unless the load says otherwise.

## The conversion contract

- A second `ProctorAgent` mutation sample with a stated denominator, a stated seed, load at both
  ends, and its unrun count.
- Every survivor across both samples dispositioned, with `equivalent` reserved for arguments checked
  against source rather than asserted.
- Seams built where the sampling says they are worth building, each with a test that kills a real
  mutant.
- The number **not** copied into `.warrant/suite-health.json`; `mutation_measured: false` there is
  correct and means warrant's own assay has not run.

## What this brief does not do

It does not chase equivalent mutants — `RunHUDGate.onSegment`'s `<=` boundary is already recorded as
one, and a suite contorted to kill an unkillable mutant is worse than the survivor. It does not aim
at a survival-rate target: the number is a measurement, and moving it by choosing easier mutants
would be the finish line moving.
