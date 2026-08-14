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

- `design/character/sprite-states-sheet-42b853.png` — the first render, all seven
  states. Generating them as a single sheet is what kept the character identical
  across states; seven separate calls did not hold consistency in testing.
- `design/character/states/*.png` — sliced 260×260 cells, wired into
  `mocks/run-hud.html`. These are the mock's art and stay as they are.

**Shipped (PRO-0017, 2026-08-14.)** The four things owed are done, from a second
whole-grid render rather than by patching the first:

- `design/character/sprite-frames-sheet-d03536.png` — one 4×4 render carrying
  four idle cells, four travelling, four acting, and the four still states, drawn
  with the first sheet passed back as a reference image so the character carried
  over.
- `design/character/build-sprites.py` — the committed slicer. Real alpha (the
  charcoal is flood-filled from the border, because the character's own outline
  is `(5,5,5)` against a `(20,20,20)` ground and a colour-distance cut eats it),
  one common footprint (every frame anchored on the feet's baseline and the
  case's own centre), and @1x/@2x/@3x integer-scaled from a single 38px master.
  Downsampling takes the most common palette colour under each target pixel
  rather than the average, because averaging a white/black edge yields grey and
  grey belongs to paused alone.
- Frames: travelling and acting are four drawn frames each. Idle is the slow
  one-pixel bob this record already specifies, carried as two frames — the
  render's four idle cells are four attempts at the same still, so cycling them
  boils rather than bobs.
- The extras still go at small sizes, as this record says they should: measured,
  the error state's puff of smoke loses seven pixels to the bay's rounded corner
  and nothing else is clipped. No state loses any of its footing.

## Regenerating

`media-gen-pro`, `style: "openai"` — GPT Image 2 is the model that honours
exclusions, and the first attempt with Gemini painted a fake transparency
checkerboard into all four concepts instead of producing alpha. Ask for a **flat
solid charcoal background**, never a transparent one: naming transparency is
what summons the checkerboard.

The sheet prompt is in this repo's git history; regenerate the whole grid rather
than one cell, or the character will drift.
