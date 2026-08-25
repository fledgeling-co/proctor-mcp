---
sources: [REQ-094, REQ-095, REQ-096]
status: retired
---
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

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-094, REQ-095, REQ-096
- surface: SURF-002, SURF-009, SURF-022
- cases: CASE-0002, CASE-0012, CASE-0063, CASE-0072, CASE-0073, CASE-0074
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: none
