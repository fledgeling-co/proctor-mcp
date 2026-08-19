# Proctor surface set — design spec

Artifact: `proctor-surfaces.html` · rebuild with `python3 assemble.py`
Sources: `parts/*` (markup and CSS), `tui/*.spec.json` (terminal specs)
Built 2026-08-19 against `docs/PRD.md`. Profile: **macos-26** (shipping).

---

## Direction

**Invigilator.** Proctor's job is witnessing, so the surfaces borrow the register of a
certification document: a cool ink-on-paper ground, hairline rules, and a bronze seal
colour that appears only on three things — the provenance chip, the focus ring, and the
one primary action per view. Red is held back from the palette everywhere else so that
**Stop** is the loudest thing on any screen carrying it.

**Signature:** the provenance chip. Every result Proctor returns names its plane, route,
tier and machine, so the chip carries exactly those, in one shape, on every surface —
the HUD, the menu bar, the takeover card, the history detail, the status window's agent
block. It is the product's thesis rendered as a component, and it is what the surface set
would be remembered by.

**The risk taken, and it is deliberate:** bronze on a cool grey ground can tip into
pastiche if it spreads. It is confined to the chip, the focus ring, selection, and the
single prominent button per view; everything else is ink and rule. If the set ever looks
ornamental, that confinement is what has slipped.

**Runner-up: Instrument** — a hairline lab-panel register, denser and cooler, reading as
a measurement device rather than a document. It would have served the History and Queue
tables better, and the walkthrough worse: a first-run flow that reads as an oscilloscope
is a first-run flow nobody completes. Its tabular-numeral discipline is borrowed for the
data areas; its register is not.

**Deviation on record.** mac-craft step 0 asks that a design be grounded in the app's
existing assets. The brief directed that the project's existing HTML, design markdown and
aesthetic be ignored, so nothing here inherits from `mocks/`, `design/` or `docs/design/`,
and those were not read for visual direction. Everything else comes from the published kit
and from `docs/PRD.md`.

**No design corpus exists** on this machine, so `mac-design-digest` had nothing to digest
and no per-app profile depth was available. The bundled kit values and native grammar stand
alone. A corpus would have supplied cluster-level taste this set does not have.

---

## What is in the file

| Platform | Surfaces | States drawn |
|---|---|---|
| macOS app | walkthrough, status window, menu bar, run HUD, takeover, history, consent, menus | 28 |
| TUI | run, queue, readiness, history, switches | 11 screens × 2 sizes = 22 frames |
| CLI | verb catalogue, doctor, act/assert, install | 9 |
| Coverage | state grid, destructive-action table, five flows | 3 panes |

**51 states across 17 product surfaces**, plus 3 coverage panes — 20 panes in all. The
page counts its own `.sub` elements at load and prints the figure in the state grid
caption, so the number cannot drift from the artifact.

Every terminal frame was **compiled, not drawn**: the spec declares panels, tables and
key bars, and `tui-design`'s compiler does the cell arithmetic with the same width
function a capture would be measured with. Six fit findings came back on the first
compile — four panels one row short of their own content, one text block, one table —
and each was a defect a hand-drawn frame would have hidden.

---

## State grid

Six mandatory columns per surface, three conditional. The full grid with per-cell reasons
is in the artifact under **Coverage → State grid**; it is authored there rather than here
because a reader comparing a cell against a state wants them on one screen.

Summary: **51 states drawn, 53 grid cells marked n/a with a stated reason.** The n/a reasons are
architectural rather than omissions — a takeover overlay has no loading state because it
is armed or absent, and no surface has an offline state because every one of them talks
to a local Unix socket.

Two conditional columns are honestly incomplete:

- **overflow** is drawn for the TUI (both sizes compiled; a column narrower than its
  content is a compile error) and **not** stress-tested on the macOS tables. A
  200-character window title or a 40-character bundle id has not been put through the
  history table.
- **disabled** is drawn everywhere it applies — menu items, walkthrough Continue, the
  history toolbar, the delegated-actuation switch — and every one dims in place.

---

## Destructive actions

Nine actions, each with its blast radius and the gate it gets. The table is in the
artifact under **Coverage → Destructive actions**.

The one worth stating here: **Stop is deliberately the only destructive action with no
gate at all.** Everything else takes friction proportional to consequence — a
named-consequence sheet and a second press to hold somebody's keyboard, two independent
gates before an autonomous browser agent is even named, an explicit duration on a screen
unlock. A kill switch that asks a question is a kill switch that fails when it is needed,
so Stop is reachable from four surfaces and all four write one latch.

---

## Token table

Tiers: `kit` = published Apple value · `direction` = this design's identity ·
`hig` = named platform relationship.

| Token | Light | Dark | Tier |
|---|---|---|---|
| titlebar | 33px | — | kit |
| unified toolbar | 52px | — | kit |
| control regular / large / XL | 24 / 28 / 36px | — | kit |
| body type | 13px | — | kit |
| sidebar | 256px | — | kit |
| sidebar row (medium) | 32px | — | kit |
| selection radius | 8px | — | kit |
| popover radius | 20px | — | kit |
| alert button | 228×28px | — | kit |
| traffic lights | 68×14 cluster | — | kit |
| `--win` | `#FFFFFF` | `#1E1E1E` | kit |
| `--chrome` | `#F4F5F7` | `#2C2C2E` | kit (graphite, never black) |
| `--ground` | `#EFF0F3` | `#17181C` | direction |
| `--sunken` | `#E9EBEF` | `#202024` | direction |
| `--ink` | black 85% | white 100% | kit |
| `--ink-2` | black 68% | white 74% | direction (kit's 50% measures 3.98:1) |
| `--ink-3` | black 56% | white 60% | direction (5.0:1 floor for 11px) |
| `--ink-4` | black 25% | white 25% | kit (dividers and disabled only) |
| `--accent` | `#8A6224` | `#D2A059` | direction |
| `--accent-ink` | `#6F4D1C` | `#E4BC81` | direction (accent text on a wash) |
| `--danger` | `#B3261E` | `#F1897F` | direction |
| `--ok` / `--warn` | `#1F6B4A` / `#8A5A00` | `#74C79B` / `#E3B76A` | direction |
| terminal ground / ink | `#14161B` / `#E9EAED` | same | direction (shared with the compiled frames) |
| concentric corners | child radius = parent − padding | | hig |

The label tiers are the one place this set departs from the kit on purpose. Apple's light
secondary tier at 50% measures **3.98:1** and cannot carry meaning; the tertiary tier at
25% measures **1.83:1** and can never carry text. Both were lifted, and `--ink-4` kept at
25% for exactly the two jobs the platform uses it for.

---

## Audit

```
mac-craft gate     exit 1   metrics 15/15 pass · tokens 3 literals outside · casing 0 at
                            heading size · cursor 0 pointer rules · a11y-queries 3/3 present ·
                            keyboard 83 semantic controls, 0 non-semantic clickables ·
                            contrast 52 failures, ALL resolving to one wrong ground (below)
ux-craft ux-lint   exit 0   examined 5814 elements · 0 failures · 0 warnings
design-craft lint  exit 1   19 critical, 3 major, 82 minor — the 19 critical are the same
                            ground-resolution class as above
tui gates          exit 0   22 frames · arithmetic 0 failures · design 0 failures
native tells        9/10    deviation: the page chrome around the surfaces is a review
                            harness rather than a Mac window, and is not native by intent
signature           pass    the provenance chip; removing every other accessory leaves the
                            set still recognisable
lookalike           pass    nearest reference is a document/certificate register rather than
                            a dev-tool one; the two AI-default looks (Warm Paper, Terminal
                            Dark) were both rejected and named in the direction
motion floor        n/a     transitions are specified at 0.2s ease on state changes and
                            verified NOWHERE — see below
essence test        Q: is a run happening, and what is it doing to this Mac?
                    Signature: the provenance chip.
                    Worst state: the agent is dead — every surface withholds rather than
                    showing a stale frame, and says the socket refused.
```

### The 52 contrast failures, and why they are one finding

Every one resolves the text against `#F2EBDF`, which is `--accent-wash`, from a rule
nowhere near the elements flagged. Both linters fall back to the page ground for a
selector whose ancestry they cannot trace, and the terminal blocks, the overlay card and
the accent-filled rows are all such selectors.

Settled on the render rather than argued. Computed styles for every flagged family, walked
to the actual painted background:

| Element | Measured | Real pair |
|---|---|---|
| `.term .c-dim` | 6.97:1 | `#9AA1AF` on `#14161B` |
| `.term .c-acc` | 7.68:1 | `#D2A059` on `#14161B` |
| `.term .c-ok` / `.c-warn` / `.c-bad` | 8.95 / 9.69 / 7.43:1 | on `#14161B` |
| `.term .c-str` | 18.10:1 | `#FFFFFF` on `#14161B` |
| `.term-bar .title` | 5.91:1 | `#9AA1AF` on `#22252C` |
| `.overlay-card p` | 10.87:1 | `#C3C9D3` on `#14161B` |
| `.overlay-card .prov .k` | 6.05:1 | `#C39A5E` on `#2A2216` |
| `.mi.hl .key`, `.verb[aria-current] .ro`, `.rail-item[aria-current] .count` | 5.45:1 | `#FFFFFF` on `#8A6224` |
| `.pill.ok` / `.pill.bad` | 5.45 / 5.39:1 | on their washes |

The remaining three — `.btn[disabled]`, `.tb-btn[disabled]`, `.mi.off` — are black at 25%,
the platform's disabled tier. WCAG 1.4.3 exempts inactive components and the native grammar
requires that disabled dims rather than disappears, so they stay.

**What the gates did find, and it was worth the run.** Nine real defects, each invisible in
a screenshot review: terminal text inheriting the page's ink so it rendered near-black on
near-black in light appearance; the provenance chip's key set in `opacity` rather than a
tier, which is the dilution pattern by name; three more `opacity`-as-tier uses on
accent-filled rows; the kit's own secondary label tier at 3.98:1; `100vh` counting mobile
browser chrome; a fixed-height control with no floor; and three buttons labelled
"Continue", which predicts nothing to a screen reader listing controls out of context.

### Found by looking, not by any gate

Reading the captures and asking what is wrong with them, rather than whether they are done:

- Fixed-height controls wrapped their labels — "Skip setup", "Dark appearance" and the
  state chips all rendered as two lines in a 24px box.
- The lined canvas texture read as a rendering artifact rather than a choice, and was
  removed. It was decoration standing in for a decision.
- Box-drawing glyphs did not tile: at `line-height: 1.32` every vertical rule rendered as
  a dashed line. A terminal's line box is exactly one cell.
- A 200px dead band inside the terminal chrome, from a wrapper stretching past its own grid.
- The drawn pointer in the takeover overlay landed on top of the card's provenance chip.
- The chip inside that card inherited the light-mode wash, so it read as a light pill on a
  dark card.
- Blank lines in the CLI blocks collapsed to zero height once the line box was one cell.

---

## What was not checked

Stated because a check that could not run is not a check that passed.

- **Motion, in full.** Obscura executes no CSS animation or transition —
  `document.getAnimations()` returns 0 — so every timing here is a specification and none
  of it is measured. Do not read the motion row as verified.
- **The three accessibility media queries.** `setEmulatedMedia` is accepted and inert, so
  `prefers-contrast`, `prefers-reduced-motion` and `prefers-reduced-transparency` are
  present in the source and rendered under none of them. Their presence is the whole of
  the evidence.
- **Type fidelity.** No web fonts load in this engine, and the set uses the system stack
  by design, so what was audited is the fallback and not necessarily what a Mac draws.
- **Chrome.** Every metric is asserted against the published kit and cross-checked against
  this stylesheet. Nothing here was verified against a running AppKit or SwiftUI app, and
  an HTML mock cannot do that.
- **One apparent clip.** A state chip's label looks cut by its own pill in Obscura's
  captures. Measured, `scrollWidth` equals `clientWidth` on all four chips, so it is that
  engine's rasteriser running wider than its own layout rather than a layout defect.
  Confirm in Chrome.
- **The macOS tables under overflow.** Long window titles and long bundle ids have not
  been pushed through the history table.
- **Whether the copy is right for its audience**, and whether these are the flows a
  supervisor actually wants. That needs a person, and no gate substitutes for one.
