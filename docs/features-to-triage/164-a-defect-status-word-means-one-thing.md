---
generated-by: tailings
tailings-sources: [site-read]
reckon-sources: [REQ-046, REQ-130]
status: triaged
---
# A defect's status word means one thing, and matches its own note

- origin: tailings pass 2026-08-26 · 2026-08-26
- audience: anyone reading the defect registry to decide what is left
- platforms: n/a
- proposed-by-ai: false

## What and why
DEF-221 was recorded `fixed` while its own note closed with "RECORDED rather than fixed" for
the second of the two arms in its title, and the two captures that arm names are still one
image. The registry already carries `partially-fixed` and uses it for DEF-339, so the word
existed and the row did not use it. `reckon` reads these words directly: a `fixed` row leaves
the owing set and a `partially-fixed` one stays in it, so the wrong word removes a piece of
work from the only report that counts them.

The vocabulary is also open. Four words are in use — `fixed` (166), `open` (3),
`partially-fixed` (2) and `closed` (1) — and nothing defines them or refuses a fifth. `closed`
is used once, for DEF-033, and means what `fixed` means.

## Acceptance sketch
- The status words are enumerated in one place with what each means for the owing set
- A check refuses a status word that is not in that list
- A check refuses a `fixed` defect whose note declares an unfixed remainder, and the phrases it
  matches come from rows somebody read rather than from a list somebody imagined
- DEF-033 is either given the word it means or the vocabulary keeps `closed` and defines it
- Both checks are armed in both directions on a fixture, so a check that cannot fire is
  distinguishable from one that found nothing

## Assumptions made writing this
- Assuming the remainder check matches phrases rather than parsing intent, and that its
  denominator is printed — a matcher tuned until it finds nothing is the failure this repository
  refuses elsewhere
- Assuming the vocabulary stays closed rather than free text, because `reckon` maps each word to
  a class and an unmapped word is placed by its fail-closed default rather than by the registry
