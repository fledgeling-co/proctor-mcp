# PRO-0065: The fidelity harness — Proctor measures Proctor

**ID:** PRO-0065
**Status:** Merged
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

Three independent channels: the accessibility tree, layer geometry through
`proctor_inspect` where SwiftUI materialises it, and pixels through `proctor_capture` with
frame status — so a claim about what is drawn rests on a frame verified complete rather than
on a screenshot that might be blank or stale. Where the three disagree, that is `Disagreement`
and the tri-observer check pointed at the app itself for the first time. **What each channel
can and cannot settle is in the correction below, and it is narrower than this item was
originally specced on.**


## Correction taken during implementation, 2026-08-20

**The premise this item was specced on was wrong, and the source says so.**

The brief and the wave direction both claimed `ProctorReflector` returns "the SwiftUI
equivalent of the computed styles the mock was measured with". `Sources/ProctorReflector/README.md`
lines 74-76 and the type's own doc comment say the opposite, in terms:

> SwiftUI: `NSHostingView` subtrees walk as ordinary `NSView`s, so you see the hosting view
> and whatever AppKit backing views SwiftUI created. That is not SwiftUI introspection — there
> is no supported way to read resolved SwiftUI modifier values from outside the framework, and
> this package does not pretend otherwise.

So the harness cannot read a resolved SwiftUI modifier. Building on the original premise would
have produced an instrument that reports agreement it never measured, which is the precise
failure this item exists to prevent — and it would have been invisible, because a property the
walker never saw and a property that matched look identical in a passing report.

**What the three channels can actually settle**, which is what this item now delivers:

| Property class | Channel | Settles it? |
|---|---|---|
| Identifier, role, label, enabled, focused | accessibility tree | **Yes**, fully |
| Frame, bounds, hit size, alignment | accessibility tree | **Yes**, fully |
| Layer geometry — corner radius, opacity, layer background | Reflector, where SwiftUI materialises it into a `CALayer` | **Sometimes**, and the difference is not knowable from the mock side |
| Resolved font family, size, weight, text colour | Reflector, where the text is `NSText`-backed | **Sometimes**, same caveat |
| A SwiftUI modifier value that never reaches a layer | — | **No.** Reported `inconclusive(.notMaterialisedInLayer)` |
| Rendered appearance | `proctor_capture` with `SCFrameStatus` | **Yes**, as pixels, against a reference capture |

`reflectorIdle` is unaffected by any of this and stands: it is the app declaring its own busy
state, not a view introspection, so embedding the Reflector still buys the strongest settle
signal the product has.

**The consequence for the wave:** a surface item's fidelity record covers identifiers,
geometry, state coverage and pixels — which is most of the fidelity question — and reports
resolved style as inconclusive-with-reason wherever SwiftUI did not materialise it. A6 below
is therefore not a footnote but the load-bearing clause, and `FidelityChannel` exists so that
"what can this instrument measure" is a value with a test rather than a hope.

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
6. **A6 — the channel table is a value with a test.** `FidelityChannel.settling(_:)` answers
   which channel can settle a given property class, and a property no channel settles resolves
   to `inconclusive` by construction rather than by a caller remembering to check. A verdict of
   `matches` is unreachable for such a property, and the test proves it is unreachable.

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

## Verification

`SurfaceFidelityTests` is 9 tests in `ProctorCoreTests`; suite 1,535 in 177 suites.

- **A3** — 28 anchors, identifiers and anchors both unique and namespaced; per-item counts
  asserted, so a conversion that forgets a state fails rather than passing by omission.
- **A4** — verified in both directions rather than asserted. A debug binary carries the
  reflector socket string (2 matches), so the guard's premise holds; a `-c release` build of
  the same product carries 0, so the guard passes on a correct build instead of always firing.
- **A5** — three inconclusive reasons each tested, including the case that matters most: a
  value that *equals* the expected one, read through an absent reflector, is
  `inconclusive(.reflectorUnavailable)` and not a match.
- **A6** — a `swiftUIModifier` property returns `inconclusive(.noChannel)` for every
  measurement a caller can supply, including one equal to the expectation. Unreachable by
  construction: `compare` consults the channel before it looks at the measurement.
- **A1, A2** — **not verified here, and they cannot be.** Both need a running app with a live
  agent: `proctor_inspect` returning resolved styles, and a settle reporting `reflectorIdle`.
  The wiring is in place (`ProctorReflector.start()` from `applicationDidFinishLaunching`,
  debug-only) and the campaign lane is where they are exercised. Recorded as unverified rather
  than assumed, because a clause nobody checked and a clause that passed look identical in a
  spec.

### What the report deliberately does not compute

`Report.measured` is `matched + differed` and there is no percentage over the total. A rate
whose denominator includes what could not be measured reports coverage the run never had —
the same reason the campaign counts armed cases apart from passing ones.
