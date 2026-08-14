# Run HUD character — the compact-Mac sprite

The HUD's companion. It sits in a 38pt inset bay at the left of the live line
and changes with run state. It carries tone, never information the text doesn't
also carry — but it is the fastest thing on the panel to read.

**Chosen after four concepts were generated and looked at**
(`design/character/concept-*.jpg`). A glass-gel orb, a Luxo-style desk lamp and
an illustrated owl were rejected: the orb had no personality, the lamp's arms
and joints vanished below about 60pt, and the owl read as sticker art on a
native panel. The sprite won on the test the others failed — pixel art is the
only one of the four that *gains* legibility as it shrinks.

## What it is

A small classic compact Macintosh with a face on its screen, on a coarse visible
pixel grid, in white, black and vermilion `#FF6A3D` only. Hard edges, no
anti-aliasing, no gradients.

The screen is the expression. Arms and lean are secondary and are expected to
disappear at small sizes — verified at 38px, where all seven states stay
distinguishable on the screen glyph alone. That division is the design: **any
new state must be readable from its screen alone.**

## The seven states

| State | Screen | Body |
|---|---|---|
| **Idle** | Two dot eyes, calm | Standing, slow 1px bob |
| **Travelling** | Eyes looking ahead | Leaning forward, orange speed lines trailing |
| **Acting** | Filled vermilion, eyes forward | Leaning in, one arm extended pressing |
| **Blocked** | Bold `!` on vermilion | Both arms raised in a stop gesture |
| **Paused** | Two grey pause bars | Standing, dimmed |
| **Finished** | Vermilion checkmark | Arms up, sparkles |
| **Error** | Vermilion `X` | Tilted off balance, puff of smoke |

Paused is the only grey screen, so it is distinguishable from every other state
without relying on colour.

## Current assets, and what is still owed

- `design/character/sprite-states-sheet-42b853.png` — all seven states in one
  render. Generating them as a single sheet is what kept the character identical
  across states; seven separate calls did not hold consistency in testing.
- `design/character/states/*.png` — sliced 260×260 cells, wired into
  `mocks/run-hud.html`.

Still owed before this ships:

1. **Real alpha.** Every render carries a charcoal background. The mock hides
   this by seating the character in a dark inset bay — which is also what keeps
   the white body legible on the light panel, so the bay stays either way — but
   the shipping assets need cutting out.
2. **Even footprints.** The slices are hand-estimated and the character's size
   drifts slightly between cells. Redraw or re-crop to a common baseline so it
   doesn't jump as the state changes.
3. **Animation frames.** Idle, travelling and acting want 4–6 frame loops rather
   than the CSS transform stand-ins currently in the mock.
4. **@2x and @3x.**

## Regenerating

`media-gen-pro`, `style: "openai"` — GPT Image 2 is the model that honours
exclusions, and the first attempt with Gemini painted a fake transparency
checkerboard into all four concepts instead of producing alpha. Ask for a **flat
solid charcoal background**, never a transparent one: naming transparency is
what summons the checkerboard.

The sheet prompt is in this repo's git history; regenerate the whole grid rather
than one cell, or the character will drift.
