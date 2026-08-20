# PRO-0067: The walkthrough becomes the mock

**ID:** PRO-0067 · **Status:** Merged · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/61-walkthrough-to-the-mock.md`
**Branch:** `ai/pro-0067` off `ai/wave-9` · **Depends on:** PRO-0064, PRO-0065
**Mock:** `#mac/walkthrough/intro`, `…/permissions`, `…/granted`, `…/connect`

## The problem

`Walkthrough.swift` has three steps and one path. The mock has four states, and the extra one
is **the moment a grant lands**, played back on its row before the step advances. A person who
clicked Grant, saw a macOS dialog and came back to a window that simply moved on has no
evidence their click did anything — and the grant they just gave is the hardest thing in this
app to give again.

Second, smaller: the primary button says "Continue" three times. A label that predicts nothing
is what a screen reader lists out of context.

## Acceptance criteria

1. **A1** — the advance rule is a pure function of `(introSeen, accessibility, screenRecording)`
   tested at all eight combinations; auto-advance fires only where `introSeen` is true and both
   grants are granted, so it can never skip the step that says what Proctor is.
2. **A2** — no primary button carries a label that does not name its outcome; each is asserted
   against the Core constant, and the constants are the mock's.
3. **A3** — the disabled next button is present in the tree in every state where it is
   disabled. A control that disappears makes the layout jump and teaches the user the step does
   not exist.
4. **A4** — skipping and completing reach the same terminal state with `walkthroughCompleted`
   set, and both paths are covered.
5. **A5** — the Screen Recording row states the restart requirement whether or not the restart
   is offered, because the fact is true either way and the offer is gated on evidence that may
   not arrive.

## Decisions taken at triage

- **Skipping is completing.** The campaign observed `walkthroughCompleted` set by Skip setup;
  that is correct rather than accidental, and gets an explicit test. The alternative is a
  window that reappears every launch for somebody who has decided against it.
- **macOS caches the Screen Recording answer per process** through `SCShareableContent` for
  that process's life (PRO-0028, PRO-0041). No button in this flow can clear a stale denial,
  and none claims to.

## Out of scope

The "Already allowed? Open System Settings" line is still-open child work from PRO-0041. It
asks a different question — what to do when macOS says denied and the person disagrees — and
folding it in would make this a grant-diagnosis item.

## Verification

`WalkthroughFlowTests` is 8 tests; suite 1,555 in 180 suites.

- **A1** — the step is a pure function of `(introSeen, accessibility, screenRecording)` and all
  eight combinations are written out rather than looped, so a wrong answer names its case. The
  one that matters: a machine already holding both grants still opens on `intro`, so nobody is
  dropped into `connect` without learning what they installed. Auto-advance is asserted to fire
  from `granted` only, and never on a partial grant.
- **A2** — a vague-label set (`continue`, `next`, `ok`, `go`, `submit`, `proceed`) is asserted
  absent from every step's primary action. The flow said "Continue" three times; it now says
  "Set up permissions", "Connect a model" and "Done".
- **A4** — both exits complete. Skipping *is* completing, deliberately: the alternative is a
  window that reappears at every launch for somebody who has decided against it.
- **A5** — `screenRecording.needsRestart` is true and `accessibility` false, and the note says
  so, because macOS caches the answer per process for that process's life.

**A3 is not verified.** The disabled-next-button clause needs the rendered view, and this repo
has no `ProctorUI` test target. The identifier is defined and set; whether the control is
present-and-disabled rather than absent is a fidelity-harness question and is carried to the
campaign lane rather than claimed here.

### The view keeps its own enum, on purpose

`Walkthrough.Step` stays `Int`-backed because the slide direction is computed from the
ordering, and maps to `WalkthroughFlow.Step` for every decision and every string. Aliasing the
two was tried first and broke the animation, which is the honest reason rather than a
preference: one source for the flow, one for the animation, and no second answer to which step
is showing.

## Measured later, by the 0.8.0 campaign

The clause this spec carried has a measurement now rather than a carry. `be-my-witness` judged
a capture of the built surface against its design pane, both dark, both at the pane's own size,
and refuted it. The divergences are enumerated in `docs/test-campaign/witness-verdicts.json`
and recorded as defects in the campaign inventory; they are styling rather than content, and
they are left open as a gap-fix work order rather than changed in passing.

One content divergence found alongside them was fixed: the permissions list named a third
grant the design did not, and omitted the one the design draws. See PRO-0075.
