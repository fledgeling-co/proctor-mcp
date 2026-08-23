---
sources: [REQ-030]
---
# The design tokens are a Swift value, generated from the mock

**Wave 9, brief 1 of 11.** Read `58-swiftui-conversion-direction.md` first. Nothing else in
the wave can start until this lands, because every other brief reads what this one produces.

## The problem

The mock set's token block is 82 declared colours plus the kit geometry, and it is currently
readable by a browser and by nothing else. Every other brief in this wave needs those values
in Swift, and there are exactly two ways to get them there.

Transcribing them is the way that fails. There is no mechanism that would notice a
transcription going stale, the mock is expected to change during the wave, and a token that
disagrees with its source is worse than an absent one because the disagreement is invisible:
the app compiles, draws, and is wrong in a way no test can see.

The repo has already solved this shape once. `BuildIdentity` is a build-tool plugin hanging
off `swift build`, generating a Swift source before every build, writing only when its
content changes so an unchanged tree does not recompile Core. `Sources/ProctorCore/BuildInfo.swift`
consumes it. That is the pattern.

## What it should do

Generate `ProctorTokens` in `ProctorCore` from `design/surfaces/parts/head.html`, at build
time, and make the mock's token block the single source for every colour, radius, control
height and type size the app draws.

The generated value carries, per token: its name, its light value, its dark value, and **the
tier it came from** — `kit`, `hig`, `direction` or `brand`. The tier is not decoration. A
later reader has to be able to tell a published Apple constant from a choice this design
made, because the two have different rules about when they may be changed: a `direction`
token moves when the design moves, and a `kit` token moves only when Apple's does.

The mock's metric block already carries the tier per row, and `mock_check.py` already fails
a `direction` tag on a chrome metric. This generator reads the same tags.

## The hard parts, named

**A CSS custom property is not a Swift colour, and the gap is where a generator quietly
lies.** The token block holds `#8A6224`, `rgba(0,0,0,0.68)`, `color-mix(in srgb, …)` and
`oklch()`-shaped values. Decide per form what the generator does, and refuse rather than
approximate: a hex and an `rgba` map cleanly, a `color-mix` against an opaque neighbour is
computable, and anything the generator cannot resolve exactly is a build failure naming the
token — not a best guess. An approximated colour is precisely the class of defect the whole
repo's provenance thesis exists to prevent, and it would be embarrassing to ship one here.

**The label tiers are the one place the design departs from the kit on purpose, and the
generator must not silently re-align them.** Apple's light secondary tier at 50% measures
3.98:1 and cannot carry meaning; the tertiary tier at 25% measures 1.83:1 and can never
carry text. The mock lifted both, and kept `--ink-4` at 25% for dividers and disabled only.
Those three facts belong in the generated source as comments carrying their measurements, so
the next person to "fix" them back to the kit values reads why first.

**Light and dark are authored independently and neither is derived from the other.** The
generator emits both and has no inversion path. A dark scheme computed from a light one is
how graphite becomes pure black, which the native grammar names as a tell.

**The mock is not always the only source.** Where a value came from the Apple kit, the kit
is the authority and the mock is a copy of it. If the two disagree, that is a defect in the
mock, and the generator should fail rather than encode the disagreement — `mac-craft`'s
`references/native-foundation.md` carries the kit values with their provenance marks and is
the tiebreaker.

## Acceptance

Red before, green after, and every clause is computable with no window:

1. `ProctorTokens.accent(.light)` returns the mock's accent, and the test fails if
   `head.html` and the generated source disagree — the same drift test
   `SwitchCatalogueDriftTests` runs against the switch catalogue.
2. Every token carries a tier from the closed set, and a token with no tier fails the build.
3. Every foreground/background pair the design nominates as text clears its floor, computed
   in Swift from the generated values: 4.5:1 for anything that carries meaning, 3:1 for the
   two quiet tiers, and the disabled tier exempt and named as such.
4. The dark palette is present for every token that has one, and no dark value is computed
   from its light counterpart.
5. A `direction` tier on a chrome metric fails, matching the rule `mock_check.py` already
   enforces on the mock.
6. The generator writes only when content changes: two consecutive builds of an unchanged
   tree produce one write and no recompile of Core.

## Out of scope

- **Not a theming system.** One light palette, one dark, generated. No user-selectable
  accent, no runtime palette switching, nothing reading a preference.
- **Not touching the switches.** `SwitchCatalogue` already owns the eight runtime switches
  and is unrelated to drawing.
- **Not the SF Symbols question.** The mock draws its glyphs as inline SVG because a
  self-contained HTML file cannot bundle SF Symbols; the SwiftUI side uses real symbols. The
  mapping from the mock's seven character states and its interface glyphs to symbol names is
  brief 63's problem, not this one.

## Child work found

- The mock's terminal palette (`--term-*`) is shared with the compiled TUI frames' role
  overrides in `design/surfaces/tui/build_specs.py`. Two files carry the same six colours
  and nothing ties them together. Brief 69 needs one of them to be the source; recorded here
  because this generator is the natural place for it to live.
