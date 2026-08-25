---
sources: [REQ-010, REQ-049]
status: retired
---
# The walkthrough becomes the mock

**Wave 9, brief 3 of 11.** Reads `58` and `59`. Mock anchors:
`#mac/walkthrough/intro`, `…/permissions`, `…/granted`, `…/connect`.

## The problem

`Walkthrough.swift` has three steps and one path through them. The mock has four states, and
the difference is the third: **the moment a grant lands**, played back on its own row before
the step advances. The shipped version advances; it does not confirm. A person who clicked
Grant, watched macOS put up a dialog, and came back to a window that simply moved on has no
evidence their click did anything, and the grant they just gave is the one thing in this app
that is hard to give again.

There is a second, smaller problem the mock caught: the primary button says **Continue**,
three times. A label that predicts nothing is a label a screen reader lists out of context as
nothing, and the mock replaced them with the outcome — "Set up permissions", "Connect a
model".

## What it should do

Four states, and the transition rules between them as a value rather than as view state.

- **Intro** — what Proctor is. Auto-advance is armed only after this step, so it cannot skip
  the step that explains the app.
- **Permissions** — the two grants as one sheet, each asking macOS for the real consent
  dialog rather than linking to Settings. The next button is disabled and visible.
- **Granted** — each grant plays back on its row as it lands; once both are in, the step
  advances itself.
- **Connect** — the snippet, a copy button, and where Proctor lives from here.

## The conversion contract

- `WalkthroughFlow` in `ProctorCore`: the step enumeration, the per-step copy, the
  advance rule (which is a function of the two grant states plus whether the intro has been
  passed), and the identifiers.
- The view holds the animation and nothing else.

## Acceptance

1. The advance rule is a pure function of `(introSeen, accessibility, screenRecording)` and
   is tested at all eight combinations. Auto-advance fires only where `introSeen` is true and
   both grants are granted.
2. No step's primary button is labelled with a word that does not name its outcome; the test
   asserts each label against the Core constant, and the constants are the mock's.
3. The disabled next button exists in the tree in every state where it is disabled — a test
   that it is never absent, because a control that disappears makes the layout jump and
   teaches the user the step does not exist.
4. Skipping setup reaches the same terminal state as completing it, with `walkthroughCompleted`
   set either way, and the test covers both paths.

## The hard parts, named

**Screen Recording needs a restart before it takes effect, and the walkthrough has to say so
without turning it into an error.** macOS caches the answer per process through
`SCShareableContent` for the life of that process — PRO-0028 and PRO-0041 both hit this. The
mock states the fact on the row whether or not the restart is offered. Keep that: the fact is
true either way, and the offer is gated on evidence that may not arrive.

**`walkthroughCompleted` is currently a single boolean and the campaign found it set to 1 by
"Skip setup".** That is correct behaviour and worth an explicit test rather than an
accident: skipping is completing, because the alternative is a window that reappears every
launch for somebody who has decided they do not want it.

## Out of scope

- The "Already allowed? Open System Settings" line is still-open child work from PRO-0041 and
  is not resolved here. It is a different question — what to do when macOS says denied and the
  person believes otherwise — and folding it in would make this brief a grant-diagnosis brief.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-010, REQ-049
- surface: SURF-009
- cases: CASE-0012, CASE-0100, CASE-0101, CASE-0106, CASE-0251, CASE-0252
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: none
