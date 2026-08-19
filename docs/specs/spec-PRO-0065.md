# PRO-0065: The fidelity harness — Proctor measures Proctor

**ID:** PRO-0065
**Status:** Ready for Plan
**Created:** 2026-08-20
**Brief:** `docs/features-to-triage/67-the-fidelity-harness-proctor-on-proctor.md`
**Direction:** `docs/features-to-triage/58-swiftui-conversion-direction.md`
**Branch:** `ai/pro-0065` (worktree `.worktrees/PRO-0065`), off `ai/wave-9`
**Depends on:** PRO-0064
**Blocks:** the fidelity record of every surface item (PRO-0066 … PRO-0072)

Second in build order, and the item most likely to be skipped. It is the instrument.

## The problem

There is no way today to answer "does the built app match the mock" with a measurement.

The obvious tool does not work, and not because it is deficient: `mockup-fidelity` diffs
computed styles on a rendered DOM, SwiftUI has no DOM, and `docs/architecture.md` records the
underlying fact that **macOS has no cross-process computed-style API at all**. That is why
`proctor_inspect` returns `reflectorUnavailable` rather than approximating.

`ProctorReflector` is the answer this product already ships — a library embedded in an app you
own, behind `#if DEBUG`, returning resolved colours, fonts, radii, opacity, constraints and
both CALayer model and presentation values. Proctor.app is an app this team owns. It is
embedded in nothing.

## What it must do

Embed `ProctorReflector` in `ProctorUI` behind `#if DEBUG || PROCTOR_REFLECTOR`, and make the
mock-versus-build comparison return a verdict.

Three independent channels, which is the point: resolved styles from the build through
`proctor_inspect`; the mock's own measured values, already gated by `mock_check.py`; and
pixels through `proctor_capture` with frame status, so a claim about what is drawn rests on a
frame verified complete rather than on a screenshot that might be blank or stale. Where the
three disagree, that is `Disagreement` and the tri-observer check pointed at the app itself
for the first time.

## Acceptance criteria

1. **A1 — the instrument works.** `proctor_inspect` against a debug Proctor.app returns
   resolved styles rather than `reflectorUnavailable`. This single change is the item's core.
2. **A2 — `reflectorIdle` becomes reachable.** Settling on Proctor's own surfaces reports it —
   the strongest settle signal the product has, currently available on nothing.
3. **A3 — the anchor table is complete.** `SurfaceFidelity` in Core maps every mock anchor to
   the accessibility identifier of the surface converting it; an anchor with no counterpart in
   the built app fails, which is what stops a surface being quietly skipped.
4. **A4 — no reflector in a release build.** `scripts/build-app.sh` fails a release artifact
   that embeds it, in the shape it already fails a missing `__TEXT,__info_plist` section.
5. **A5 — an unmeasurable property is inconclusive, never agreement.** A property the
   instrument cannot read is reported with its reason. This is `mockup-fidelity`'s central
   discipline and it transfers intact even though its instrument does not.

## Decisions taken at triage

- **Debug-only, and the threat is stated in the source.** An embedded reflector is a socket
  inside a process holding Accessibility and Screen Recording; anything that can reach it can
  read that process's view tree. The code comment says so plainly rather than leaving it to be
  inferred from the `#if`.
- **The mock is the reference, the app is the target, and the burden of proof is inverted.** A
  difference is a defect until a citation proves it intentional. Where the app is deliberately
  ahead of the mock, the mock changes and re-passes its gates — the two never diverge with a
  comment explaining why.
- **The harness is not the oracle for everything.** It measures resolved style and geometry. It
  says nothing about whether the flow, the copy or the surface is right; those stay with
  `design-review`, `be-my-witness` and a person, and the fidelity record names which ran.

## Out of scope

- Not converting any surface — this item builds the instrument the conversions are measured
  with, and its own acceptance is the instrument working.

## Child work found

- The `proctor` skill in `vendor/fledgeling-plugins` should learn the dogfooding path once this
  lands. "Drive Proctor with Proctor to check a UI change" is the shortest demonstration of the
  product that exists and it is written down nowhere.
