---
sources: [REQ-028, REQ-061, REQ-062, DEF-025, DEF-028]
status: retired
---
# The capture path reports a frame it did not get, and a window it does not know about

**Wave 13, brief 1 of 6.** DEF-025 and DEF-028. Sequence it first: every visual claim this project
makes rests on the path these two defects sit in.

## DEF-025 — a fully transparent frame reported as complete and trustworthy

PRO-0078 captured a Proctor-owned window and `proctor_capture` returned
`status: complete, trustworthy: true` over a PNG whose **2,942,720 pixels were all
`RGBA(0,0,0,0)`**. Proctor excludes its own windows from its own captures, so the exclusion worked
exactly as designed — and the capture path did not notice that exclusion was all it got.

The two facts are the same mechanism from two sides, which is why this is not "the exclusion is
broken". `SCFrameStatus complete` means ScreenCaptureKit delivered a frame, not that the frame
depicts anything. Nothing between that status and the returned verdict asks whether the frame has
content.

**No gate in the campaign would have caught it.** It was found because a human-directed check
opened the image. That is the fourth failure mode this campaign documents — the ungated part being
the part people look at — reaching the one path every `raster-visual` case depends on.

## DEF-028 — a third window at layer 0 reporting `sharingState 1`

CASE-0032 records all three Proctor overlays at `sharingState 0`, which is what keeps them out of
other applications' captures. Sampling `CGWindowListCopyWindowInfo` from a **separate probe
process** against agent pid 86732 found the run HUD panel (window 121489, layer 25) and the takeover
statement (window 121490, layer 24) both at 0 as recorded — and alongside them **window 121491 at
layer 0, 1710×1073, reporting `sharingState 1`**.

A full-screen agent-owned window that is *not* excluded from capture is either a window the case
does not know about or an overlay that lost its exclusion. Either way CASE-0032's claim — *all
three* — is measured against a population of three when the process owns four.

`sharingType = .none` on the HUD and takeover overlay is correct and is not what this brief
changes. Evidence must not change because somebody was watching.

## What to build

**A capture that came back empty is not a pass.** The verdict needs a content check between
`SCFrameStatus` and `trustworthy: true` — not a judgement about whether the image is *right*, which
is `be-my-witness`'s job, but whether a frame arrived with anything in it at all. A fully
transparent frame, or a single-colour frame the size of the target, is `inconclusive` with a reason,
never `complete` and `trustworthy`.

Be careful about the honest edge: a legitimately blank window exists, and calling it a defect would
be its own false positive. The distinguishing fact available here is that the target was
Proctor-owned and therefore excluded by design — so the path can say *"this window is excluded from
capture, so nothing was going to be in it"* rather than guessing from pixels alone.

**Identify window 121491 before deciding anything about it.** Name what it is, whether it is
supposed to exist, and whether `sharingState 1` is correct for it. If it is a window CASE-0032
should have counted, the case's denominator is wrong and the case gets corrected. If it is an
overlay that lost its exclusion, that is a leak and it gets fixed. Do not assume which.

**Re-derive CASE-0032's population with `len()`.** The case says "all three". Count what the agent
process actually owns rather than asserting the number the case was written with.

## The conversion contract

- A test driving a genuinely empty capture through the production path and asserting the verdict is
  not `complete`+`trustworthy`, with its sabotage showing a real frame still passing.
- Window 121491 named, and CASE-0032 either corrected or confirmed against a counted population.
- `./scripts/test.sh` green with the suite count before and after.

## What this brief does not do

It does not change what `be-my-witness` judges, and it does not make Proctor's overlays appear in
Proctor's own captures.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-028, REQ-061, REQ-062
- surface: SURF-004, SURF-005, SURF-006
- cases: CASE-0004, CASE-0005, CASE-0006, CASE-0008, CASE-0009, CASE-0010
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: StreamCapture in ProctorAgent/Capture/StreamCapture.swift
