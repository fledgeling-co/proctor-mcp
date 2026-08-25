---
sources: [REQ-023]
status: retired
validated-by: REQ-023 via CASE-0025, CASE-0088
validated-rungs: effect-witness, outcome
validated-provider: ProctorReflector in ProctorReflector/ProctorReflector.swift
---
# The fidelity harness: Proctor measures Proctor

**Wave 9, brief 9 of 11.** Reads `58`. **Build this second, immediately after `59`** — the
number is allocation order, not build order. Every surface brief in the wave needs this
instrument to prove its conversion, and a wave that converts nine surfaces and then goes
looking for a way to check them has already drifted.

## The problem

There is no way, today, to answer "does the built app match the mock" with a measurement.

The obvious tool does not work. `mockup-fidelity` measures a rendered DOM and diffs computed
styles; SwiftUI has no DOM. And this is not a gap in that skill — `docs/architecture.md`
records the underlying fact: **there is no cross-process computed-style API on macOS.**
Nothing is equivalent to `getComputedStyle` across a process boundary, which is why
`proctor_inspect` returns `reflectorUnavailable` rather than approximating. For an app you do
not own, the ceiling is the accessibility tree plus pixels, and that is a real ceiling.

Proctor.app is an app this team owns, and `ProctorReflector` is a library built precisely for
this case — embedded behind `#if DEBUG`, it returns resolved colours and fonts, corner radii,
opacity, constraints, and both CALayer model and presentation values, with a monotonic render
revision. It has shipped as a SwiftPM product since the first wave and is embedded in nothing.

## What it should do

Embed `ProctorReflector` in `ProctorUI` behind `#if DEBUG || PROCTOR_REFLECTOR`, and make the
mock-versus-build comparison a command that returns a verdict.

Three channels, and the brief is worth doing because they are independent:

1. **Resolved styles from the build**, through `proctor_inspect` against the running
   Proctor.app — the SwiftUI equivalent of the computed styles the mock was measured with.
2. **Measured values from the mock**, through the surface set's own gates. `mock_check.py`
   already cross-checks the metric block against the published kit *and* against the
   stylesheet, and the mock passes it.
3. **Pixels**, through `proctor_capture` with frame status, so a claim about what is drawn
   rests on a frame that was verified complete rather than on a screenshot that might be
   blank or stale.

Where the three disagree, that is a finding — which is `Disagreement` and the tri-observer
check, already built, pointed at the app itself for the first time.

## The conversion contract

- Reflector embedded in `ProctorUI`, `#if DEBUG` only, and **absent from a release build**.
  `scripts/build-app.sh` fails the build if the reflector socket is reachable in a release
  artifact.
- A `SurfaceFidelity` value in Core mapping each mock anchor to the accessibility identifier
  of the SwiftUI surface it converts, so the comparison is driven by a table rather than by
  a hand-written script per surface.

## Acceptance

1. `proctor_inspect` against Proctor.app returns resolved styles rather than
   `reflectorUnavailable`. That single change is the brief's core, and it is a red-to-green
   test against a debug build.
2. Settling on Proctor's own surfaces reports `reflectorIdle` — the strongest settle signal
   the product has, currently reachable on nothing.
3. Every mock anchor in `SurfaceFidelity` resolves to an identifier that exists in the built
   app; an anchor with no counterpart fails, which is what stops a surface being quietly
   skipped.
4. A release build has no reflector: the build script's check fails a build that embeds it.
5. A property the instrument cannot measure is reported **inconclusive with its reason**, and
   never as agreement. This is `mockup-fidelity`'s central discipline and it transfers intact
   even though its instrument does not.

## The hard parts, named

**An embedded reflector is a socket inside the app that holds Accessibility and Screen
Recording.** It is debug-only for that reason, and the release check is not a nicety. State
the threat plainly in the code comment: anything that can reach that socket can read the view
tree of a process holding those grants.

**Do not let the harness become the oracle for everything.** It measures resolved style and
geometry. It says nothing about whether the flow is right, whether the copy is right, or
whether the surface is one a person can use. Those stay with `design-review`, `be-my-witness`
and a person, and the fidelity record says which of the three ran.

**The mock is the reference and the app is the target, and the burden of proof is inverted:**
a difference is a defect until a citation proves it intentional. Where the app is
deliberately ahead of the mock, the mock changes and re-passes its gates — the two do not
diverge with a comment explaining why.

## Child work found

- Once this lands, the `proctor` skill in `vendor/fledgeling-plugins` should learn the
  dogfooding path, because "drive Proctor with Proctor to check a UI change" is the shortest
  demonstration of the product that exists and it is currently written down nowhere.
