# Briefs no spec claims

Every brief in `docs/features-to-triage/` is cited by exactly one spec in
`docs/specs/` (or accounted for as a shared parent in the table below), so that
a reckoning can trace what happened to it.

`scripts/campaign/spec_citation_measure.py` reads this file. A row whose reason is
empty is not a row: it fails the check the same way a missing row does.

| Brief | Where it went | Why no spec claims it |
|---|---|---|

## Briefs several specs share

One-to-one is the rule for the `**Brief:**` header, and these four briefs are why it is not the
rule for a brief path mentioned in a spec's prose. Each is a direction document that several items
were cut from at once, so no single spec owns it and uniqueness cannot apply. They are enumerated
here with their counts rather than left as a silent exemption: an out-of-family review of PRO-0101
was right that a brief claimed only in prose sits outside the uniqueness check, and a recorded
many-to-one is the difference between a designed exception and a hole.

The same review proposed normalising all 24 prose citations to the header form. Measured against
this tree that would break the invariant it was meant to strengthen: brief 55 would be claimed by
two headers and brief 57 by seven.

`spec_citation_measure.py` reads the counts below and fails when one moves.

| Brief | Specs | What it is |
|---|---|---|
| `00-WAVE-7-DIRECTION.md` | 13 specs | Wave 7's direction document — PRO-0029, 0031, 0036, 0038, 0039, 0040, 0044, 0046, 0048, 0049, 0050, 0051, 0052. |
| `55-three-tests-still-redden-the-gate.md` | 2 specs | Three failing tests split across PRO-0054 and PRO-0055. |
| `57-vm-targets.md` | 7 specs | Wave 8's VM-targets direction — PRO-0056 through PRO-0062. |
| `58-swiftui-conversion-direction.md` | 2 specs | The SwiftUI conversion direction, taken by PRO-0064 and PRO-0065. |

A brief one spec owns by header is not a shared parent, whatever else mentions it: brief 35 is
PRO-0034's, and PRO-0051 refers to its retirement without claiming it.
