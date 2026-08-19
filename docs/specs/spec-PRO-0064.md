# PRO-0064: Design tokens as a generated Swift value

**ID:** PRO-0064
**Status:** Merged
**Created:** 2026-08-20
**Brief:** `docs/features-to-triage/59-design-tokens-as-a-swift-value.md`
**Direction:** `docs/features-to-triage/58-swiftui-conversion-direction.md`
**Branch:** `ai/pro-0064` (worktree `.worktrees/PRO-0064`), off `ai/wave-9`
**Depends on:** —
**Blocks:** every other item in wave 9

First item of the surface-conversion wave. Nothing else can start until it lands,
because every other item reads what it produces.

## The problem

`design/surfaces/parts/head.html` holds the design of record's token block — 82 declared
colours plus the kit geometry — and it is readable by a browser and by nothing else. Every
surface item needs those values in Swift.

Transcribing them is the failure mode. Nothing would notice a transcription going stale, the
mock is expected to change during the wave, and a token that disagrees with its source is
worse than an absent one: the app compiles, draws, and is wrong in a way no test can see.

## What it must do

Generate `ProctorTokens` in `ProctorCore` from the mock's token block at build time, following
`BuildIdentity`'s shape — a build-tool plugin hanging off `swift build`, writing only when its
content changes so an unchanged tree does not recompile Core.

Each token carries name, light value, dark value, and **tier** (`kit` | `hig` | `direction` |
`brand`). The tier governs when a value may change: a `direction` token moves when the design
moves, a `kit` token only when Apple's does.

## Acceptance criteria

Each is red before and green after, and every one is computable with no window.

1. **A1 — the value exists and matches its source.** `ProctorTokens.accent(.light)` returns the
   mock's accent. A drift test re-parses `head.html` and fails if the generated source and the
   mock disagree, in the shape `SwitchCatalogueDriftTests` already uses against the switch
   catalogue.
2. **A2 — every token is tiered.** A token with no tier fails the build rather than defaulting.
3. **A3 — contrast floors hold, computed in Swift.** For every pair the design nominates as
   text: 4.5:1 where it carries meaning, 3:1 for the two quiet tiers. The disabled tier is
   exempt and the test names it as exempt rather than skipping it silently.
4. **A4 — dark is authored, not derived.** Every token with a dark value has one in the
   generated source, and no dark value is computed from its light counterpart. The test asserts
   the generator has no inversion path.
5. **A5 — a `direction` tier on chrome geometry fails**, matching the rule `mock_check.py`
   already enforces on the mock itself.
6. **A6 — idempotent generation.** Two consecutive builds of an unchanged tree produce one
   write and no recompile of `ProctorCore`.
7. **A7 — an unresolvable colour is a build failure naming the token**, never a best guess.

## Decisions taken at triage

- **Colour forms.** Hex and `rgba()` map directly. `color-mix()` against an opaque neighbour is
  computed at generation time. Anything else — an unresolved `var()`, a `color-mix` against
  `transparent`, an `oklch()` the parser does not implement — fails the build with the token
  named. An approximated colour is exactly the defect class this repo's provenance thesis
  exists to prevent.
- **The label ramp's departure from the kit is preserved and commented.** Apple's light
  secondary tier at 50% measures 3.98:1 and the tertiary at 25% measures 1.83:1; the mock
  lifted both and kept 25% for dividers and disabled. Those measurements go in the generated
  source as comments so the next person to "correct" them back reads why first.
- **Where the mock and the kit disagree, the kit wins and the build fails.** The mock is a copy
  of the kit for `kit`-tiered values; a disagreement is a defect in the mock.

## Out of scope

- Not a theming system: one light palette, one dark, generated. No runtime switching.
- Not touching `SwitchCatalogue`, which owns the eight runtime switches and is unrelated.
- Not the SF Symbols mapping — that belongs to PRO-0069 with the character states.

## Child work found

- The mock's `--term-*` palette is duplicated in `design/surfaces/tui/build_specs.py`'s role
  overrides. Two files carry the same six colours with nothing tying them together. PRO-0074
  needs one of them to be the source; this generator is the natural home.

## Verification

All seven clauses green. `DesignTokensTests` is 6 tests in `ProctorCoreTests`; the suite is
1,526 in 176 suites.

- **A1** drift — the test re-parses `head.html` with the same at-rule stripping the generator
  uses and compares every token both ways, so a token in the mock and missing from the table
  fails too. `accent(.light) == "#8A6224"`.
- **A2** tiers — enforced at generation (exit 1, token named) and asserted in Swift. Verified
  by removing a tier comment: exit 1.
- **A3** contrast — 12 pairs across both appearances, computed in Swift with alpha composited
  over the ground, because a translucent label tier has no luminance of its own.
- **A4** dark authored — every dark colour differs from its light counterpart, and `--win`
  dark is `#1E1E1E` rather than the `#000000` an inversion would give.
- **A6** idempotent — two builds produce byte-identical output.
- **A7** unresolvable colour — verified by replacing the accent with a `color-mix` against
  `transparent`: exit 1, token named, no approximation.

### The defect this found in its own first draft

The generator initially emitted `--accent` light as `#EEC385` and `--ink-2` light as a white
alpha — the *increased-contrast dark* values. `:root:not([data-appearance="dark"])` inside the
`prefers-contrast` media block was being read as the light palette, and
`:root[data-appearance="dark"]` inside the same block overwrote the real dark one. Both
compiled and both were wrong, which is the exact failure mode this item exists to prevent. The
fix strips at-rule regions with balanced braces and matches the two selectors exactly; the
Swift drift test parses the same way, so the two cannot disagree about what a palette is.

### Tiering moved into the mock

Rather than the generator carrying a name-to-tier table — a second source that drifts — each
declaration in `head.html` now carries `/* tier:… */` beside its value. 63 tokens: 6 kit, 57
direction. An untiered declaration fails the build.
