# Plan — PRO-0017: HUD character sprite assets

**Spec:** `docs/specs/spec-PRO-0017.md` · **Design:** `docs/design/run-hud-character.md`
· **Reference:** `mocks/run-hud.html` (settled, binding)
**Branch:** `ai/pro-0017` · **Worktree:** `.worktrees/PRO-0017`
**Size tier:** Standard. Two halves — asset production, and the binding to the
panel PRO-0015 ships with an empty 38pt bay.

The character is chosen. Nothing here re-opens it.

## Half one — the assets

### Source
One regenerated sheet, as the design record requires: seven separate calls did
not hold the character's identity, so the whole grid is drawn at once.
`design/character/sprite-frames-sheet-d03536.png`, GPT Image 2 (`style: "openai"`
— the model that honours exclusions), 4×4, flat solid charcoal, the existing
`sprite-states-sheet-42b853.png` passed as a reference image so the character
carries over. Transparency is never named in the prompt; naming it is what
summoned a painted checkerboard in all four earlier concepts.

Row 1 idle ×4, row 2 travelling ×4, row 3 acting ×4, row 4 the four still states.

### Slicing — `design/character/build-sprites.py`, committed and reproducible
The design record says regenerate the whole grid rather than one cell, so the
step that turns a grid into shipping frames has to be a script, not a hand pass.
Four decisions in it, each answering a measured problem:

| Step | Why not the obvious thing |
|---|---|
| Segment by ink projection | The model does not respect cell boundaries — measured, the bottom row overruns the nominal 4×4 pitch by tens of pixels. |
| Cut the charcoal by flood-filling from the border | The character's own outline is `(5,5,5)` against a `(20,20,20)` field. A colour-distance cut eats the outline. What makes background background is that it touches the frame. |
| Anchor on the feet's baseline and the case's own centre | The mock's slices were hand-estimated and drift. The case centre is read from the largest opaque body's middle band, so a raised arm or a trail of speed lines cannot pull the character sideways. |
| Quantise by taking the most common palette colour, never the average | Averaging a white/black edge yields grey, and grey is load-bearing: the paused screen is the only grey one, which is what makes paused readable without colour. A mode filter cannot invent it. |

Output `Sources/ProctorAgent/Resources/character/<frame>.png` plus `@2x`/`@3x`,
integer-scaled from one 38px master so all three densities are the same art.
38pt bay, one art pixel per point, so the pixel grid stays visible.

### Frames
- **idle** — two frames: the drawing, and the drawing lifted one pixel. The
  record's own slow bob. The model's four idle cells are four attempts at the
  same still; cycling them boils rather than bobs, which is worse than the
  simpler loop. Recorded here rather than left to be rediscovered.
- **travelling** — four drawn frames; the vermilion speed lines grow and reset.
- **acting** — four drawn frames; the arm extends and returns.
- **blocked / paused / finished / error** — one frame each. They hold still.

## Half two — the binding

### `Sources/ProctorCore/RunHUDCharacter.swift` (new, pure)
The frame table and the reduce-motion rule as values, so both are checkable
without a window — the same split that keeps `RunHUDState` testable.

- `RunHUDCharacter.Frame` (asset name + duration), `frames(for: RunHUDPhase)`,
  `assets` (the manifest a loader and a test both read).
- `RunHUDMotion.sprite(for:reduceMotion:)` — returns one frame when motion is
  reduced. Every state stays readable from its screen alone, which is the design
  rule that makes stopping the loop safe.
- `RunHUDMotion.railGlow(for:reduceMotion:)` — the reference's `glow` on the
  progress rail, `travelling` and `acting` only, nil when motion is reduced.

### `Sources/ProctorAgent/Overlay/RunHUDCharacterView.swift` (new)
A layer-backed subview in the bay. Frames become one
`CAKeyframeAnimation(keyPath: "contents")`, discrete, infinite, added once per
state change and committed. The cursor overlay's header carries the argument:
this process is busy settling and walking trees, so an overlay that needed
servicing would stutter exactly when it was most worth watching. Nearest-
neighbour filtering both ways — soft pixels are not pixel art.

A missing or unreadable asset leaves the bay empty and the run carries on,
matching the panel's own rule that a drawing failure never stops a run.

### `RunHUDContentView` changes
- Two subviews, positioned in `layout()`: the character in the bay, and the
  rail's filled portion over the track the view still draws. Subviews rather
  than raw sublayers because a subview's frame is unambiguously in the view's
  own flipped coordinates.
- `hitTest` is already fully overridden and ignores subviews, so neither can
  take a click. No change to what is clickable.
- Rail width is set with actions disabled: the reference transitions it, and a
  width that never animates cannot violate reduced motion. Recorded as a
  deliberate simplification.

### `RunHUDPanel` changes
- Push phase/tone/progress into the accessories alongside the model.
- Observe `accessibilityDisplayOptionsDidChangeNotification` and re-apply, so
  turning Reduce Motion on mid-run stops the loop rather than waiting for a
  restart. The panel's existing fade already reads the setting; the sprite and
  the rail glow are the first things here that need more than a fade.

### Packaging
`resources: [.copy("Resources/character")]` on the `ProctorAgent` target, and
`scripts/build-app.sh` copies the generated resource bundle into
`Contents/Resources` before signing, so the signature covers it. `install.sh`
dittos the whole app and needs no change.

## Acceptance clauses → evidence

| Clause | Test |
|---|---|
| Seven states, none added or dropped | `frames(for:)` is total over `RunHUDPhase`; asset manifest matches |
| One common footprint, no jump between states | Decode every shipped frame; the opaque bounding box's baseline is identical across all of them and the top varies by at most a pixel |
| Real alpha | Every frame has fully transparent pixels and no charcoal ground |
| Standard and double density ship (triple produced) | Every asset resolves at 1x/2x/3x at 38/76/114px |
| Idle, travelling, acting move; the other four hold | The moving set is exactly those three; the rest are single-frame |
| Motion reduced ⇒ nothing moves, every state still readable | `sprite(for:reduceMotion: true)` is one frame for every phase; `railGlow` is nil |
| Nothing is fetched during a run | Assets resolve from the bundle; no network in the path |
| A missing picture leaves the bay empty and the run carries on | Loader returns nil and the view hides |

Not machine-witnessable here: the sprite actually drawn in the bay, the loop
playing, the rail glowing, and light/dark. `swift test` has no window server and
obscura is web-only. Those are code-complete against the reference and need a
human glance.
