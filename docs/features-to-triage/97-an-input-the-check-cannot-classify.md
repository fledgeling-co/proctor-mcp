---
sources: [REQ-120, REQ-121, REQ-122, REQ-123, DEF-201, DEF-202, DEF-203]
status: retired
validated-by: REQ-098, REQ-100, REQ-120, REQ-121, REQ-122, REQ-123 via CASE-0416, CASE-0417, CASE-0418, CASE-0421, CASE-0422, CASE-0423
validated-rungs: outcome
validated-provider: none
validated-through-defect: REQ-098 via DEF-201; REQ-100 via DEF-203
---
# An input the check cannot classify, and the two directions it can be wrong

**Wave 17, brief 1.** DEF-201, DEF-202, DEF-203. Three defects found in one evening across two
repositories and three instruments, and they are one shape rather than three bugs.

## The shape

Each of the three instruments meets an input it has no rule for, and each **guesses instead of
saying so**.

- **DEF-201** — `reckon`'s `ID_RE` scans a brief's whole body for id-shaped tokens with no code-fence
  and no placeholder exclusion, so a quoted example id becomes a citation at confidence 1.0. A brief
  whose only id-shaped token sat in a fenced example command — **a quotation of a probe, not a
  citation of this registry**; the id does not exist and cites nothing — classed `unbuilt`. The planted
  token, now in a fence so the scanner that blanks fenced blocks can exclude it:

```
A brief whose only id-shaped token was CASE-9999 inside an example command classed unbuilt
```

  reasoning that the registry holds none of the ids it cites.
- **DEF-203** — `scripts/campaign/spec_citation_measure.py`'s legacy fallback accepts a brief path from a fenced block,
  an HTML comment or a struck-through line; its `none.` floor accepts an unresolvable reference and
  any backtick pair padded to twenty characters; and reverse totality is satisfied by an incidental
  mention in an unrelated spec.
- **DEF-202** — `reckon` classifies a defect as remaining work on any status word other than `fixed`,
  so eight words that mean *not* remaining work count as work.

The first two are the same sentence twice: **a scanner that reads a whole document for a token, with
no exclusion for fences, comments or struck-through text, cannot tell a citation from a mention of
one.** Two tools written independently grew that blind spot within a day of each other, which makes
it a shape to check for rather than a mistake either author made.

## The direction that makes it dangerous

DEF-202 is where the class earns a brief rather than three fixes, because it fails **both ways and
only one way is visible.**

`reckon` over-reports on an unknown word: annoying, self-announcing, somebody looks. A sibling
project checked its own reproduction gate for the same shape and found the opposite: it selected its
population with a single status string, `open`, so a register growing a word meaning *still broken* —
`regressed`, `reopened` — would have dropped those rows **out of the obligation entirely** while the
gate went on printing a clean count over a quietly smaller population.

> **A clean green is a worse failure than an inflated backlog, because nothing about it asks to be
> checked.**

Widening that gate to classify every status explicitly surfaced five real defects there and took
owing from 19 to 24.

## What this asks for

**Not a longer list, and not a longer floor.** Both are the same mistake one iteration on: they
extend the set of inputs the instrument guesses correctly about, and leave it guessing.

1. Classify every input as one thing or the other, explicitly.
2. Make an input the instrument **cannot** classify a **finding that names it and its count**, rather
   than a default in either direction.
3. For the two scanners: exclude fenced blocks, HTML comments and struck-through text before
   matching, and prove the exclusion with a fixture per kind rather than in aggregate.

## One caveat that is itself a finding

DEF-201 records "0 occurrences across 91 real briefs" here. **That is a fact about this repository's
idiom, not about the risk.** All 24 legacy citations here sit in real prose at fence depth 0. A
repository whose briefs cite by convention — *the brief names the defects it closes* — has the
opposite prior, and one does: there, a brief discussing a neighbouring defect is textually identical
to one that owns it. A count of zero taken on the wrong population invites the next reader to treat
the defect as theoretical.
