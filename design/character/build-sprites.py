#!/usr/bin/env python3
"""Cut the run-HUD character sheet into shipping sprite frames.

The source is one render, never seven or sixteen: generating the states
separately did not hold the character's identity, which is why the whole grid is
regenerated at once and sliced here. `docs/design/run-hud-character.md` carries
that finding and the prompt rules that go with it (flat charcoal, never a
"transparent" background — naming transparency is what summons a painted
checkerboard).

What this does, and why each step is here rather than done by hand:

  SEGMENT by ink projection rather than by a fixed 4x4 pitch. The model does not
  respect cell boundaries: measured on the shipped sheet, the bottom row's
  characters overrun the nominal grid by tens of pixels. Bands found from the
  ink itself are where the drawings actually are.

  CUT the charcoal by flood-filling the border, not by colour distance. The
  character's own outline is (5,5,5) against a (20,20,20) field — close enough
  that a threshold cut eats the outline. What makes the background the
  background is that it touches the frame, so that is what is tested.

  NORMALISE every cell onto one footprint. The slices in the mock were
  hand-estimated and the character drifts between them; here every frame is
  anchored on the same two things — the feet's baseline and the case's own
  centre, taken from the largest opaque body so a raised arm or a trail of speed
  lines cannot pull the character sideways.

  QUANTISE to a true pixel grid by taking the most common palette colour under
  each target pixel, never the average. Averaging an edge between white and
  black yields grey, and grey is load-bearing on this character: the paused
  screen is the only grey one, which is what makes paused readable without
  relying on colour. A mode filter cannot invent it.

Output is `Sources/ProctorAgent/Resources/character/<frame>@Nx.png` at 1x, 2x and
3x, integer-scaled from one 38px master so the three densities are the same art.
"""

from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SHEET = HERE / "sprite-frames-sheet-d03536.png"
OUT = REPO / "Sources" / "ProctorAgent" / "Resources" / "character"

# The bay is 38pt. One art pixel is one point, so @1x is 1:1 and the pixel grid
# stays visible — pixel art is the one concept of the four that gains legibility
# as it shrinks, and a fractional grid is how that gets thrown away.
CANVAS = 38
# The case, not the whole drawing. Extras (speed lines, sparkles, smoke) are
# allowed to run off the edges of the bay; the case never moves.
CASE_HEIGHT = 29
BASELINE = 35

# White, black, vermilion and one grey. `docs/design/run-hud-character.md` fixes
# the first three; the grey exists only so the paused screen can be told apart
# without colour.
PALETTE = np.array([
    [255, 255, 255],
    [17, 17, 19],
    [255, 106, 61],
    [150, 150, 156],
], dtype=int)
PALETTE_NAMES = ["white", "black", "vermilion", "grey"]

# Row-major, matching the prompt the sheet was drawn from.
LAYOUT = [
    ["idle-0", "idle-1-src", "idle-2-src", "idle-3-src"],
    ["travelling-0", "travelling-1", "travelling-2", "travelling-3"],
    ["acting-0", "acting-1", "acting-2", "acting-3"],
    ["blocked", "paused", "finished", "error"],
]
# Idle's motion is the design record's slow one-pixel bob, so its second frame is
# the first lifted a whole pixel rather than a second drawing. The model's four
# idle cells are four attempts at the same still: cycling them would boil rather
# than bob, which is worse than the simpler loop and is written down here rather
# than left to be rediscovered.
IDLE_LIFT = 1


def bands(mask: np.ndarray, gap: int = 12) -> list[tuple[int, int]]:
    """Contiguous runs of True, closing over gaps shorter than `gap`."""
    out: list[tuple[int, int]] = []
    start = None
    run = 0
    for i, v in enumerate(mask):
        if v:
            if start is None:
                start = i
            run = 0
        elif start is not None:
            run += 1
            if run >= gap:
                out.append((start, i - run))
                start = None
    if start is not None:
        out.append((start, len(mask) - 1))
    return out


def background_mask(rgb: np.ndarray) -> np.ndarray:
    """Pixels reachable from the border through near-charcoal. See the header."""
    corner = rgb[0, 0].astype(int)
    near = np.abs(rgb.astype(int) - corner).max(axis=2) <= 10
    h, w = near.shape
    seen = np.zeros_like(near)
    queue: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def largest_body(opaque: np.ndarray) -> np.ndarray:
    """The biggest connected run of opaque pixels — the case, its legs and any
    arm touching it. Detached extras are deliberately left out: a raised arm is
    part of the body, a trail of speed lines is not."""
    h, w = opaque.shape
    seen = np.zeros_like(opaque)
    best = np.zeros_like(opaque)
    best_size = 0
    for sy in range(h):
        for sx in range(w):
            if not opaque[sy, sx] or seen[sy, sx]:
                continue
            component = np.zeros_like(opaque)
            queue = deque([(sy, sx)])
            seen[sy, sx] = True
            size = 0
            while queue:
                y, x = queue.popleft()
                component[y, x] = True
                size += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
            if size > best_size:
                best_size, best = size, component
    return best


def case_centre(body: np.ndarray) -> float:
    """The case's own horizontal centre, read from the middle half of the body so
    legs and a raised arm cannot pull it sideways."""
    ys = np.where(body.any(axis=1))[0]
    lo, hi = ys.min(), ys.max()
    band = body[lo + (hi - lo) // 4: hi - (hi - lo) // 4 + 1]
    centres = []
    for row in band:
        xs = np.where(row)[0]
        if len(xs):
            centres.append((xs.min() + xs.max()) / 2)
    return float(np.median(centres)) if centres else float(body.shape[1] / 2)


def snap(rgb: np.ndarray) -> np.ndarray:
    """Index of the nearest palette colour, per pixel."""
    flat = rgb.reshape(-1, 1, 3).astype(int)
    return np.argmin(np.abs(flat - PALETTE[None, :, :]).sum(axis=2), axis=1).reshape(rgb.shape[:2])


def render(rgb: np.ndarray, opaque: np.ndarray, body: np.ndarray,
           scale: float) -> tuple[np.ndarray, dict[str, int]]:
    """Resample one cell onto the shared 38px canvas at the shared scale."""
    index = snap(rgb)
    centre_x = case_centre(body)
    baseline_y = float(np.where(body.any(axis=1))[0].max()) + 1

    out = np.zeros((CANVAS, CANVAS, 4), dtype=np.uint8)
    used: dict[str, int] = {}
    for ty in range(CANVAS):
        # Source window for this target pixel, placed so the feet land on
        # BASELINE and the case's centre lands on the canvas centre.
        sy0 = baseline_y + (ty - BASELINE) / scale
        sy1 = sy0 + 1 / scale
        for tx in range(CANVAS):
            sx0 = centre_x + (tx - CANVAS / 2) / scale
            sx1 = sx0 + 1 / scale
            y0, y1 = int(np.floor(sy0)), max(int(np.ceil(sy1)), int(np.floor(sy0)) + 1)
            x0, x1 = int(np.floor(sx0)), max(int(np.ceil(sx1)), int(np.floor(sx0)) + 1)
            y0, x0 = max(y0, 0), max(x0, 0)
            y1, x1 = min(y1, rgb.shape[0]), min(x1, rgb.shape[1])
            if y1 <= y0 or x1 <= x0:
                continue
            window = opaque[y0:y1, x0:x1]
            if window.mean() < 0.5:
                continue
            counts = np.bincount(index[y0:y1, x0:x1][window], minlength=len(PALETTE))
            pick = int(np.argmax(counts))
            out[ty, tx, :3] = PALETTE[pick]
            out[ty, tx, 3] = 255
            used[PALETTE_NAMES[pick]] = used.get(PALETTE_NAMES[pick], 0) + 1
    return out, used


def main() -> int:
    sheet = np.asarray(Image.open(SHEET).convert("RGB"))
    ink = ~background_mask(sheet)
    row_bands = bands(ink.any(axis=1))
    if len(row_bands) != 4:
        print(f"error: expected 4 rows of drawings, found {len(row_bands)}", file=sys.stderr)
        return 1

    cells = []
    for ri, (y0, y1) in enumerate(row_bands):
        col_bands = bands(ink[y0:y1 + 1].any(axis=0))
        if len(col_bands) != 4:
            print(f"error: row {ri} has {len(col_bands)} drawings, expected 4", file=sys.stderr)
            return 1
        for ci, (x0, x1) in enumerate(col_bands):
            pad = 6
            sy0, sy1 = max(y0 - pad, 0), min(y1 + 1 + pad, sheet.shape[0])
            sx0, sx1 = max(x0 - pad, 0), min(x1 + 1 + pad, sheet.shape[1])
            rgb = sheet[sy0:sy1, sx0:sx1]
            opaque = ink[sy0:sy1, sx0:sx1]
            body = largest_body(opaque)
            cells.append((LAYOUT[ri][ci], rgb, opaque, body))

    # One scale for every frame, taken from the upright idle cells: a per-cell
    # scale would make the character breathe as the state changed, which is the
    # drift this whole step exists to remove.
    uprights = [c for c in cells if c[0].startswith("idle")]
    heights = [int(np.ptp(np.where(c[3].any(axis=1))[0])) + 1 for c in uprights]
    scale = CASE_HEIGHT / float(np.median(heights))
    print(f"case heights {heights} -> scale {scale:.4f}")

    OUT.mkdir(parents=True, exist_ok=True)
    for name, rgb, opaque, body in cells:
        if name.endswith("-src"):
            continue
        art, used = render(rgb, opaque, body, scale)
        write(name, art)
        print(f"{name:14s} {used}")
        if name == "idle-0":
            lifted = np.zeros_like(art)
            lifted[:-IDLE_LIFT] = art[IDLE_LIFT:]
            write("idle-1", lifted)
            print("idle-1         (idle-0 lifted one pixel — the record's bob)")
    return 0


def write(name: str, art: np.ndarray) -> None:
    base = Image.fromarray(art, mode="RGBA")
    base.save(OUT / f"{name}.png")
    for factor in (2, 3):
        base.resize((CANVAS * factor, CANVAS * factor), Image.NEAREST).save(
            OUT / f"{name}@{factor}x.png")


if __name__ == "__main__":
    raise SystemExit(main())
