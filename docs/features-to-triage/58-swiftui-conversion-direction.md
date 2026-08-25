---
sources: [REQ-026, REQ-030]
status: retired
---
# Wave 9: the surface set becomes the app

**Direction for briefs 59–69.** The surfaces now exist as a measured, gated HTML set at
`design/surfaces/proctor-surfaces.html` with its spec beside it. This wave converts them to
SwiftUI without losing the fidelity, and the whole of the difficulty is that the usual way
of proving a conversion does not work here.

Read this before any brief in the wave. Every one of them inherits the method below.

## The problem

`Sources/ProctorUI` was built surface by surface across eight waves. It works, and it does
not read as one designed thing: the walkthrough, the status window, the menu bar and the
history window each arrived with their own spacing, their own label tiers and their own
idea of what a section header is. The mock set is the first time all sixteen surfaces have
been drawn to one system, and it carries decisions the app does not have — a signature
component, a corrected label ramp, seven character states, and the three states per surface
that only exist on paper today.

So the task is a conversion, and conversions drift. The question this direction answers is
not *how to write the SwiftUI* — that is ordinary work — but **how a runner proves the
SwiftUI matches the mock**, in a repo whose gate cannot see a window.

## Three constraints decide the method, and none of them is negotiable

### 1. `swift test` has no window server, and there is no `ProctorUI` test target

`Package.swift` declares test targets for `ProctorCore` and `ProctorAgent` and none for
`ProctorUI`. A rule written inside a `View` body is a rule this repo cannot prove, and a
wave that writes sixteen surfaces of unprovable rules is a wave that reports itself green
and drifts on the next edit.

The repo already solved this four times, and the pattern is the whole method:
`StatusChecks`, `SwitchCatalogue`, `WindowPresentation` and `RunHUDPlacement` are pure
values in `ProctorCore` carrying a decision, with a test each, and a view that only reads
them. `WindowPresentation` is the sharpest example — the rule "should a reopen present the
Status window" is three pure functions and a test file, and the `AppDelegate` does nothing
but call them.

**So: every design decision in the mock becomes a value in `ProctorCore` before it becomes
a view.** Tokens, geometry, copy, per-state content, the state machine, the character-state
mapping, the shortcut table. The SwiftUI file is then a projection, and what the gate
proves is the decision rather than the drawing.

The test for "is this the right shade of bronze" is not a screenshot. It is
`ProctorTokens.accent(.light) == "#8A6224"` plus a contrast assertion computed in Swift
over the same pair the mock was gated on.

### 2. mockup-fidelity cannot see a SwiftUI tree

The obvious verification skill measures a rendered DOM. SwiftUI has no DOM, no
`getComputedStyle`, and — as `docs/architecture.md` records — macOS has no cross-process
computed-style API at all. `proctor_inspect` returns `reflectorUnavailable` rather than
approximating, for exactly this reason.

But Proctor already ships the answer, and has since the first wave. **`ProctorReflector` is
a library you embed in an app you own, behind `#if DEBUG`, and it returns resolved colours,
fonts, corner radii, opacity, constraints and both CALayer model and presentation values.**
Proctor.app is an app this team owns. Nothing embeds the Reflector in it today.

So the fidelity channel for this wave is **Proctor driving Proctor**: embed
`ProctorReflector` in `ProctorUI` and measure through it, the accessibility tree, and pixels
carrying frame status.

**Corrected 2026-08-20, during PRO-0065.** An earlier version of this paragraph claimed the
Reflector returns the SwiftUI equivalent of computed styles. It does not, and its own README
says so: `NSHostingView` subtrees walk as ordinary `NSView`s, and there is no supported way to
read a resolved SwiftUI modifier value from outside the framework. What the harness settles
fully is identifiers, roles, geometry and pixels; layer-level style is settled only where
SwiftUI materialises it into a `CALayer`, and anything else is reported
`inconclusive(.notMaterialisedInLayer)` rather than as agreement. `spec-PRO-0065.md` carries
the full channel table. `reflectorIdle` is unaffected and is still worth the embedding on its
own.

It also settles a second thing worth naming: `reflectorIdle` becomes available on the app's
own surfaces, which is the strongest settle signal Proctor has and is currently reachable on
nothing.

### 3. A selector that does not survive a layout change is not a selector

The Cua research (`docs/research/2026-08-15-dossier-proctor-vs-cua.md`) found that Cua's
`element_token` is an "opaque per-snapshot element handle" whose staleness is a routine
error, and that its replay survives by re-clicking absolute positions — which is precisely
what a layout change breaks. Proctor's counter-claim is the durable selector.

The app cannot make that claim about other people's software while its own views expose
nothing to select on. **Every control, row and section in the converted surfaces sets an
`accessibilityIdentifier` from a constant owned by `ProctorCore`**, so:

- Proctor can drive its own UI, which is the acceptance path for the interactive states.
- The identifier is a value with a test, so a rename is a red build rather than a silently
  broken flow.
- The claim in the README about durable selectors becomes true of the app making it.

## The conversion contract, per surface

Every brief in this wave delivers the same four things, in this order:

1. **A pure value in `ProctorCore`** holding what the mock decided: tokens, geometry, the
   per-state copy, the state enumeration, the identifiers. Pure means no clock it was not
   handed, no filesystem, no AppKit.
2. **A test file** proving the decision, red before the value exists and green after. The
   contrast floors, the state coverage, the identifier uniqueness and the geometry
   relationships are all computable in Swift with no window.
3. **The SwiftUI view**, reading only from (1), setting the identifiers from (1), and
   holding no literal colour, size, radius or user-facing string of its own.
4. **A fidelity record** in the spec's Verification section: the mock anchor
   (`#mac/status/ready`), what was compared, what matched, and what could not be measured
   with the reason.

A brief that cannot express its rule as a testable value says so and explains why, rather
than writing it into a view body and calling it done.

## The token pipeline

`design/surfaces/parts/head.html` holds the token block, and it is the source. Brief 59
generates `ProctorTokens` from it rather than transcribing it, because a transcription
drifts on the first edit and nothing catches it. The generator runs the same way
`BuildIdentity` does — as a build plugin hanging off `swift build`, writing only when the
content changes.

Values that came from the published Apple kit stay marked as such, so a later reader can
tell a platform constant from a choice this design made. The mock's metric block already
carries that tier per row.

## What this wave is not

- **Not a redesign.** The mock is settled and gated. A brief that wants to change it
  changes the mock first, re-runs its gates, and records the change in the spec.
- **Not a rewrite of the agent.** Nothing here touches `ProctorAgent`, the wire, the
  planes or the queue. The HUD's *drawing* is in scope; what it draws is not.
- **Not a new capability.** Two of the briefs (68, 69) specify surfaces that do not exist —
  the operator CLI and the supervision TUI — and both are drawn in the mock set. They are
  in this wave because they are the same conversion problem, not because the wave is
  widening.

## The skills that help, and where they now live

`vendor/fledgeling-plugins` is a git submodule pinned to `main`. A runner in a fresh
worktree gets the skills without a marketplace install:

| Skill | Use in this wave |
|---|---|
| `mac-craft` | The kit ground truth, the native grammar, and `mock_check.py` — the gate the mock already passes. Re-run it when a mock changes. |
| `mac-design-digest` | No corpus exists on this machine, so it has nothing to digest. Named here so a runner does not go looking. |
| `mockup-fidelity` | Its method transfers; its instrument does not. Read `references/measurement-enforcement.md` for the artifact-forcing discipline, then measure through the Reflector instead of a DOM. |
| `design-review`, `be-my-witness` | The rendered-UI gates, once a surface draws. `be-my-witness` compares a capture against the mock. |
| `tui-craft` / `tui-design` | Brief 68. The frames are already compiled; the conversion target is a real program, so `tui-craft`'s capture loop applies from that point. |
| `ux-craft`, `design-craft` | The state grid and the destructive-action table are already filled in the mock's spec. Re-read before changing either. |
| `shipyard`, `ship-feature` | The delivery pipeline this repo runs on, unchanged. |
| `proctor` | The repo's own skill, which should learn the dogfooding path once brief 60 lands. |

**`macosify` is not in this submodule** — it lives in `diolog-plugins` and carries a bundled
37-file HIG library, a token-level `DESIGN.md` and an Apple macOS 27 kit token JSON. It is
a *refit* skill rather than a conversion one, so it is the right reference when a converted
surface reads iOS-derived or web-derived, and the wrong tool for the conversion itself. A
runner without that marketplace installed uses `mac-craft`'s `references/native-foundation.md`,
which carries the same kit values with their provenance marks.

## Order

**Build order is not brief order.** Numbers are allocation order; the sequence below is the
one to run.

1. **59** first and alone, because everything reads its output.
2. **67** second, and this is the one most likely to be skipped. It is the instrument —
   embedding the Reflector so `proctor_inspect` can measure the app's own view tree. A wave
   that converts nine surfaces and then goes looking for a way to check them has already
   drifted, and the fidelity records for briefs 60–66 are unwritable without it.
3. **60** and **61** in parallel — they share no files.
4. **62** after 61: the walkthrough's completion path sets what the menu bar shows on first run.
5. **63**, **64**, **65** — disjoint, any order.
6. **66** after 60, since the consent sheets are raised from the status window's switches.
7. **68** and **69** last and independent of the rest: they are new binaries rather than
   changes to an existing one, and 69 depends on 68 for the shared argument surface.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-026, REQ-030
- surface: SURF-008, SURF-010, SURF-017, SURF-036
- cases: CASE-0011, CASE-0013, CASE-0027, CASE-0028, CASE-0029, CASE-0033
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: none
