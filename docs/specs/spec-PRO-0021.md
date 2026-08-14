# PRO-0021: Menu bar switch for the panel, and the icon as the character

**ID:** PRO-0021
**Status:** In Review
**Created:** 2026-08-14
**Last updated:** 2026-08-14
**Plan:** `docs/plans/plan-PRO-0021.md`
**Brief:** `docs/features-to-triage/22-menu-bar-switch-and-character.md`

## Feature description

Two gaps that share a cause: the menu bar and the run HUD know nothing about each
other.

- **The panel cannot be turned off without an environment variable.** `PROCTOR_HUD=0`
  works, but it means editing a launchd plist and reloading the agent — the wrong
  shape for a thing somebody wants gone for the next ten minutes and back
  afterwards.
- **The menu bar icon says nothing.** Proctor is already in the menu bar, on every
  display, and it is currently a static SF Symbol — while a character built to make
  run state legible at 38px sits in a panel that may be on a display nobody is
  looking at.

What it should do: show and hide the panel from the menu bar, at once and for the
current run; and make the menu bar icon the same character in the same state.

Out of scope: choosing a different character, redesigning the panel. Both settled.

## Triage — 2026-08-14

**Ready for Implementation Plan.**

### The real design question: how the switch and the phase cross the process boundary

`ProctorUI` (menu bar) and `proctor-agent` are separate processes in one bundle.
The phase lives in `RunHUDPanel.shared`'s `RunHUDState`, on the agent's main actor.
The UI already opens short-lived socket connections and polls two internal verbs
(`proctor_doctor`, `proctor_recent_activity`), neither of which is in
`ToolCatalogue` — the shim gates `tools/call` on `ToolCatalogue.spec(named:)`, so an
MCP host cannot reach an internal verb as a tool. That is the settled precedent and
this feature uses it rather than inventing a channel.

- **Agent → UI (the phase).** The `RunHUDState` moves out of the panel and into
  `RunHUDFeed` — a lock-guarded holder in the agent, the shape `RunHUDAvailability`
  already uses — which owns the reduction and is readable from any thread.
  `RunHUDPanel` becomes a renderer of that model rather than the owner of it, and
  `proctor_recent_activity` gains a `hud` object the socket handler fills without
  hopping to the main actor. This is what "a second consumer reads the same phase
  rather than deriving its own" means concretely: one reducer, no second wording
  table, and a headless run (`PROCTOR_HUD=0`, no panel, no AppKit loop) still keeps a
  truthful phase because reduction never depended on the view.

  *(This is the shape the out-of-family spec review argued for, and it is right: an
  earlier draft left the reducer on the panel and reduced "even when not drawing",
  which covers hide-with-AppKit but not the launch that has no panel at all — and the
  main-actor hop per headless step was the tell that the source of truth was still
  in the view.)*
- **UI → agent (the switch and the controls).** One new internal verb, `proctor_hud`,
  taking `action` ∈ `show | hide | pause | resume | stop`, returning the resulting hud
  state so the menu updates without waiting for the next poll.

### The three forks the brief asked to be decided, not defaulted

**1. Does the menu bar animate when nothing is running? No.**
The panel's `idle` is a slow 1800ms one-pixel bob, which is fine on a panel that is
only on screen during a run. The menu bar is on screen forever, so a permanently
bobbing menu bar item is an irritation and a battery cost for no information. The
menu bar animates `travelling` and `acting` only; `idle` and every still state are
one frame. This is a menu-bar motion policy, so it lives beside `RunHUDMotion` in
Core where it is checkable without a display, not inside a view.

**2. Template image? No — full colour.**
Colour is load-bearing on this character: vermilion carries acting, blocked, finished
and error, and grey belongs to paused alone, which is what makes paused readable
without relying on colour at all. A template image discards every one of those and
keys the whole sprite off the alpha channel, which would also invert the case — the
case is white (`#FFFFFF`) with a `#111113` outline, so as a template the case would
become the tint and the screen would become a hole. Rendered on both a light
(`#F6F6F6`) and a dark (`#1E1E20`) ground at 22px, the full-colour sprite reads in
both: the outline carries it on light, the white case carries it on dark. So
`isTemplate = false`, and the trade accepted is that the icon does not adopt menu bar
tinting.

**3. Does hiding the panel hide the stop button? It would, so the menu keeps one.**
Hiding the panel removes Pause and Stop from the screen, and the panel is the kill
switch. So the menu bar gains the run's own two controls — **Pause/Resume** and
**Stop** — live whenever a run is in flight, whether or not the panel is drawn. They
are the run's words, never the queue's: Hold and Clear stay on the panel's queue bar
and are not added to the menu, so the two pairs are never adjacent and never share a
word. `proctor_doctor` continues to report the panel's absence, with a note that now
distinguishes hidden-from-the-menu-bar (a stop path exists) from switched-off-by-
`PROCTOR_HUD` (with the loop caveat below).

### The one thing `PROCTOR_HUD=0` still decides, and the menu cannot

`main.swift` runs `NSApplication.shared.run()` when the HUD is on and `CFRunLoopRun()`
when it is off, because a button can only receive a click under an AppKit loop. That
is a settled decision and this feature does not touch it. So an agent that *started*
with `PROCTOR_HUD=0` has no event loop that can deliver a click, and `present()`
already refuses in that case with a recorded reason. The menu's Show item is
therefore **unavailable, with that reason stated**, on an agent launched with the HUD
off; Hide is always available and reversible within the launch. The character in the
menu bar is unaffected either way, because the feed does not depend on drawing —
which is exactly the reach the brief is asking for.

### The menu bar rendition

A menu bar icon needs its own size. `design/character/build-sprites.py` is the
committed slicer and the design record's rule is regenerate the grid rather than a
cell — that rule is about art *generation* drift, and it is honoured because the
menu bar set is sliced from the same committed sheet
(`sprite-frames-sheet-d03536.png`), not drawn again. No image generation.

Size was chosen by rendering, not assumed. Measured on the shipped sheet:

| Canvas | Result |
|---|---|
| 16px, 18px | Fails. The screen glyph collapses: idle loses its dot eyes, and `blocked` and `acting` become the same solid vermilion block. |
| 22px, case 17 | Better; `blocked` still weak. |
| **22px, case 19, baseline 21** | **All seven read.** Two dot eyes on idle, a bold `!` on blocked, two grey bars on paused, a check on finished, a dark `X` on error, a plain vermilion screen on acting. |

So the menu bar set is 22pt at @1x/@2x/@3x, integer-scaled from one 22px master the
same way the 38px set is. 22pt is the standard menu bar thickness, so it draws 1:1;
the image is asked to scale with nearest-neighbour interpolation so that a bar that
is taller or shorter than 22pt degrades to hard pixels rather than to mush.

The art ships in **`ProctorCore`**'s resource bundle rather than in `ProctorUI`'s.
Core already owns the frame table and the motion rule, both targets can reach it, and
it is the one arrangement where a test can prove every asset is present at every
density without adding a test target for the UI.

### What the menu bar shows when Proctor cannot work

The current glyph encodes reachability and readiness (`checkmark.seal`,
`exclamationmark.triangle`, `bolt.horizontal.circle`, `circle.dashed`). Replacing it
outright would throw away the one signal a first-run user needs. So the character
replaces the glyph **only when the agent is reachable and every required grant is
present**; otherwise the existing symbol stays. A character reporting a calm idle
while Proctor is unreachable or missing Accessibility would be a lie, and the
readiness signal is worth more than the character at that moment.

## Acceptance clauses

1. **A1 — one reducer, two consumers.** The HUD phase the menu bar reads is the phase
   `RunHUDState` reduced; nothing derives a second one.
2. **A2 — the phase survives the panel being off.** Reduction happens in
   `RunHUDFeed`, off the main actor, and the feed is truthful with no panel built at
   all — including under `PROCTOR_HUD=0`, where none ever is.
3. **A3 — hide takes effect at once and for the current run.** Hiding orders the
   panel out immediately; showing brings it back mid-run without waiting for the next
   one.
4. **A4 — the switch agrees with `OverlaySwitch`.** `PROCTOR_HUD` sets the switch's
   initial value; the menu moves the same switch; nothing is written to disk, so the
   environment remains the default at the next launch.
5. **A5 — Show is refused, with its reason, on an agent with no AppKit loop.**
6. **A6 — hiding the panel leaves a stop path.** Pause/Resume and Stop are reachable
   from the menu bar whenever a run is live, and act on the same `RunControl` the
   panel's buttons do.
7. **A7 — the menu never carries the queue's words.** No Hold, no Clear.
8. **A8 — the menu bar is still when nothing is running.** `idle` and every still
   state are one frame; only `travelling` and `acting` animate, and neither does with
   Reduce Motion on.
9. **A9 — after a run ends, the menu bar returns to idle.** The ending is held for
   the linger and then the character rests.
10. **A10 — the sprite ships, at every density.** Every menu bar asset the frame table
    names is present at @1x/@2x/@3x, on one 22px footprint.
11. **A11 — colour, not a template.**
12. **A12 — readiness outranks the character.** Unreachable or a missing required
    grant keeps the status symbol.
13. **A13 — `proctor_doctor` tells the truth about the panel and the stop path** in
    each of the three states (drawn, hidden from the menu bar, switched off).
14. **A14 — the internal verb stays internal.** `proctor_hud` is not in
    `ToolCatalogue`, so the public tool count is unchanged and no MCP host can reach
    it.

## Assumptions recorded in place of questions

- `[Experience]` The menu bar character replaces the status symbol only when the agent
  is reachable and ready. *(A calm idle over a missing grant is a lie; readiness is
  the more useful signal at that moment.)*
- `[Experience]` The menu bar is still at idle; only travelling and acting move.
  *(A permanently animating menu bar item is an irritation and a battery cost.)*
- `[Experience]` The ending states (finished, blocked, paused, error) are held for the
  panel's own linger and then the menu bar rests at idle. *(One rule for how long an
  ending is shown, and it is already decided.)*
- `[Experience]` Hiding is a per-launch choice, not a preference on disk. *(The brief
  says "for the current run, not at the next relaunch", and a stored preference would
  compete with `PROCTOR_HUD` rather than agree with it.)*
- `[Experience]` The menu carries Pause/Resume and Stop and never Hold or Clear.
  *(Settled: the two pairs are never adjacent and never share a word.)*
- `[Layout]` The menu bar rendition is 22pt, sliced from the committed sheet at a new
  canvas size. *(Measured: 18pt collapses the state glyphs, 22pt keeps all seven.)*
- `[Layout]` Full colour, never a template. *(Colour carries four states and grey
  carries paused alone.)*
- `[Operations]` The phase reaches the menu bar by poll, not by push. The activity
  poll runs at 0.5s throughout and the doctor poll stays at 2s. *(A push channel means
  a new long-lived connection shape on a contended file. The activity verb is a pure
  in-memory projection over a local unix socket, so it is cheap enough to run at a
  fixed cadence — and gating the fast cadence on "a run is live" would have meant the
  menu learned that a run had **started** on the slow one, putting Pause and Stop up
  to two seconds late exactly when they exist to replace a hidden panel. That was the
  out-of-family review's second objection and it was right.)*
- `[Operations]` Reduction never touches the main actor, so a headless run pays no
  hop. The panel is told to redraw only when it is actually drawing.
- `[Operations]` Element lookups for the live line stay gated on the session feeding
  the HUD, not on the panel currently drawing. *(A person who hides the panel and
  brings it back mid-run would otherwise find a trail full of "a control" where the
  real object should be, and one AX lookup per step is cheap against a step.)*
- `[Data & scope]` `proctor_hud` is an internal verb on the same socket the UI already
  uses, reachable only by a local process of the same user, and never through the MCP
  surface. *(Same trust boundary and the same precedent as `proctor_recent_activity`.)*

## What a test cannot reach here

`swift test` has no window server. Not machine-witnessable in this repo: the menu bar
item rendering at all, the character's appearance in the bar, the animation playing,
the panel actually leaving and returning the screen, and a click landing on a menu
item. Those are code-complete and reasoned, and the report says so rather than
dressing a code reading up as verification. What *is* tested: the reducer, the feed,
the motion policy, the frame-at-elapsed arithmetic, the icon decision, the asset
manifest against the shipped bundle, the verb's wiring and refusals, and the doctor's
three notes.

## Progress — 2026-08-14

**Status: In Review.** Branch `ai/PRO-0021`, worktree
`.claude/worktrees/pro-0021`. `swift build` clean (no new warnings; three
pre-existing ones in `ProctorUIApp.swift:64` and `Walkthrough.swift:303` are
untouched). `swift test`: **425 tests in 55 suites pass**, up from 387 in 47.

Two out-of-family gates ran on grok (`grok-4.6`, effort xhigh) and both landed
changes rather than rubber-stamping:

- **Spec review** rejected leaving the reducer on the panel ("always reduce, even
  when not drawing" covers hide-with-AppKit but not the launch that builds no panel
  at all, and the main-actor hop per headless step was the tell). The state moved
  into `RunHUDFeed`. It also rejected gating the fast poll on "a run is live",
  because the menu would then learn a run had *started* on the slow one. Fixed poll
  at 0.5s.
- **Completeness critic** found that `RunHUDControl.needsRun` was defined and never
  enforced, so Pause, Resume and Stop would latch and reduce against no run at all.
  Now refused with a reason, with a test.

Files: `Sources/ProctorCore/RunHUDMenuBar.swift`,
`Sources/ProctorAgent/Overlay/RunHUDFeed.swift`,
`Sources/ProctorUI/MenuBarCharacter.swift`,
`Sources/ProctorCore/Resources/character-menubar/` (42 pictures), plus edits to
`RunHUDPanel`, `SessionHUD`, `Session`, `Dispatch`, `AgentModel`, `ProctorUIApp`,
`Package.swift`, `design/character/build-sprites.py`, the design record, the README
and the changelog. The panel's own 38px set is byte-identical after the slicer was
parameterised.

**Code-complete but not machine-witnessable here:** the menu bar item drawing at
all, the character's legibility in a real bar, the animation playing, a click
landing on a menu item, and the panel actually leaving and returning the screen.
The 22px art was checked by rendering it on light and dark grounds and looking at
it, which is evidence about the pictures, not about the menu bar.
