You are reviewing a design decision in a Python tool called `reckon`. Answer concretely; do not restate the question.

## The tool
`reckon.py` reconciles a repo's feature-brief queue against a test-campaign registry (cases, requirements, surfaces, defects) and puts every entity into exactly one class of a total partition:

  unbuilt (named, nothing in the registry answers to it) · broken (measured, answer was no) ·
  unmeasured (nobody found out) · unnamed (registry found it, no document claims it) ·
  undecided (documents and evidence disagree; needs a person) · retirable (measured done at a
  rung that can carry the claim) · waived (somebody decided not to) · verified-done.

Its whole thesis is that "not done" and "not known" are different things and both look like absence. A gate enforces a table LEGAL_CLASS mapping each case status to the classes it may support (e.g. `blocked` may only be `unmeasured`, `pass` may be `verified-done` or `retirable`).

## The measured faults (real run, 91 briefs, 569 rows)
Headline said "232 pieces of work remain — 197 product". Two causes:

1. Every defect row is hardcoded `"class": "broken"` with no read of `status`. This registry has 110 defect rows: 100 `status: fixed`, 10 `status: open`.
2. A brief that the join could not tie to anything became `unbuilt`. 75 of 91 briefs (join rate 17.6%) landed there. Every one of the 75 names an item that has actually shipped; they simply failed to join, because the join is a token-overlap guess plus explicit id citations.

Both are "an entity absent from the evidence treated as an entity that failed" — the tool's own target failure, arriving from the opposite direction. It over-reported, so nothing in its design caught it.

## Decision A — what class does a defect with `status: fixed` take?
Candidate 1: `verified-done`, by symmetry with a case whose status is `pass`, which already maps straight to `verified-done` with no further corroboration. The registry's own recorded status is the measurement in this vocabulary.
Candidate 2: something more conservative — e.g. `unmeasured` unless a passing case cites the defect id, or unless the row carries a `fixedBy`/`resolution` field. Rationale: "fixed" is the project's own account of itself, which this tool elsewhere refuses to treat as observation (requirement evidence `reported`/`unknown` → `unmeasured`).

Note the cost of candidate 2 on this registry: 100 defects would move into `unmeasured`, i.e. 100 new "evidence-work" items — which is the same over-reporting fault in a new coat. Note also the acceptance criterion the item must meet: "A defect that has been fixed is not counted as remaining work."
Unrecognised or absent defect status: my proposal is to fall through to `broken` (today's behaviour), never-silently-done.

## Decision B — how to split `unbuilt` from a new class `unjoined`
The item requires `unjoined` to become its own visible outcome rather than being folded into `unbuilt`, because the two carry opposite conclusions. Straightforward reading: no join edge at all → `unjoined`. But that makes `unbuilt` unreachable in practice (it was only ever assigned when there was no support), and a dead class in a partition is a predicate that can never fire.

My proposal keeps both alive:
- brief has **cited** edges (it names REQ-/DEF-/CASE- ids explicitly) but **none of those ids exist in the registry** → `unbuilt`. Somebody wrote down what should exist and the registry does not have it: positive evidence of absence.
- brief has **no edges at all** → `unjoined`. The join is a guess and it found nothing; we cannot tell whether it shipped.
- brief has overlap-only or resolvable cited edges → classed as today (broken / undecided / unmeasured / retirable).

`unjoined` would get kind `decision-work` (a person reads the brief and rules), is_work_item true, and would be excluded from the `product-work` headline count.

## What I want from you
1. Decision A: which candidate, and if neither, what instead. Say what breaks under the one you reject.
2. Decision B: is the unbuilt/unjoined split coherent, or is there a better boundary? Is there a third source of "positive evidence of absence" I have missed that would keep `unbuilt` alive more honestly?
3. Anything else in this design that is wrong, or an approach better than either option listed.
Be terse and specific. Under 500 words.
