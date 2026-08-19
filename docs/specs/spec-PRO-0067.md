# PRO-0067: The walkthrough becomes the mock

**ID:** PRO-0067 · **Status:** Ready for Plan · **Created:** 2026-08-20
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
