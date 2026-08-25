# Trawl — the full campaign run and the reckoning, 2026-08-25

Sources: `docs/reckoning/2026-08-25-FULL2/reckoning.md`, `strict-check.py`,
`vacuity-check.py`, `capture-lineage.py`, `campaign.py check`, and warrant's
`rollup_classes.py`. Every idea below names the figure it came from.

## Kept

- **idea-01: a declared pass that silently did not run** → brief 151,
  `proposed-by-ai: false`. The blind pass reported NOT RUN for the life of this
  campaign because `testRoot` was absent, and every "vacuity 0 findings" line was
  true of two passes out of three. Nothing checks that a pass a config declares
  actually executed over a population.
- **idea-02: 38 of 40 surfaces declare no controls** → brief 152,
  `proposed-by-ai: false`. `Controls: 4 of 34` is a fraction of the two surfaces
  that were enumerated, not of the product. This is the denominator
  `references/inert-ui.md` exists to demand, and it is currently 5% of the
  surface list.
- **idea-03: 41 cases only prove something rendered** → brief 153,
  `proposed-by-ai: false`. 438 of 500 CHECKED. The 41 stand at `source-analysis`,
  which reads a fact off the source and witnesses no effect, and 16 more were
  never watched to fail.
- **idea-04: 7 durable boundaries uncut across 10 journeys** → brief 154,
  `proposed-by-ai: false`. Four journeys are not `critical` because their cuts do
  not exist, and a journey uncut at a boundary proves the happy path and says
  nothing about partial completion.
- **idea-05: five warrant classes still short after the figure-sourcing merged**
  → brief 155, `proposed-by-ai: false`. PRO-0129, 0130, 0134 and 0135 all merged
  and `rollup_classes.py` still reports capture-trust 95.7%, evidence-integrity
  91.1%, operator-state 94.5%, registry-drift 97.0%, surface-conformance 84.0%.
  The work that was supposed to close them did not.
- **idea-06: an evidence page nobody judged** → brief 156, `proposed-by-ai: true`.
  6 of 8 judgeable captures judged, ratchet 6. Small, and it is the one number in
  the lineage plane that ratchets rather than blocks — which is exactly where a
  figure stops being looked at.

## Dropped, with the reason

- **A brief for DEF-340** (106 cases with no lane). Refused by the intake rule
  that a `broken` row already has a defect. The defect carries the measurement
  and the reason it was not closed by inference; a brief beside it would be a
  second copy that drifts.
- **A brief for the two `unmeasured` requirements.** REQ-025 is deferred against
  an upstream Apple bug and REQ-072 is a recorded ceiling. Both are correctly
  unmeasured, and a brief asking somebody to measure them would be asking for the
  re-label the ratchet exists to refuse.
- **A lane-proof shape that fits an ephemeral artifact.** `campaign.py lane`
  refused the ios-sim proof because a CoreSimulator device is not a file on disk.
  Real, and it is the instrument's shape rather than this project's work — it
  belongs upstream, and filing it here would put a fix in the repository that
  cannot apply it.
- **Raising the blind ratchet's population by tuning the vocabulary.** Refused in
  `campaign.json` with its numbers, and refused again by an out-of-family
  reviewer. Adding readers moves the count and not the measurement.
- **A dashboard for the campaign's denominators.** They are printed by four
  instruments that already run on every gate. A second surface for them is a
  place for them to drift.
