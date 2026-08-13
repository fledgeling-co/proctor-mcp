#!/usr/bin/env python3
"""build_icon.py — Proctor macOS app icon, Engine A (hand-authored layered SVG master).

Direction: Tahoe gel-glass, warm-paper register — a re-materialised brand mark.
Signature move: "the actuation edge" — one graphite window whose right edge
dissolves into drifting terracotta gel pixels (a machine writing the screen).

Geometry and material live here as named constants so fidelity rounds are
parameter edits, not path surgery. Layer groups map 1:1 onto the #10 plan:
bg (paper cushion) / mid (ghost back-window) / fg (window + pixels) /
highlight (rim + top-face speculars). Decorative icon: the squircle mask,
material and soft shadow are BAKED into the art.

    python3 build_icon.py            # writes icon-proctor.svg
"""
from __future__ import annotations
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
SQUIRCLE = (HERE / "squircle-path.txt").read_text().strip()

# ---------------------------------------------------------------- palette
# Warm paper ground (brand anchor) — sampled off the live mark.
PAPER_TOP   = "#F7F1E6"   # brightest, top-centre
PAPER_MID   = "#F1E9D9"
PAPER_EDGE  = "#E7DDC9"   # warm greige at the corners (gentle)
PAPER_RIM   = "#FFFEFA"   # inner rim light
VIGNETTE    = "#C9BA9E"   # corner darkening

# Deep graphite screen (charcoal DNA #3A3A42 family), given a real dark mass.
GRAPHITE_TOP = "#3E3E48"
GRAPHITE_BOT = "#2A2A31"
GRAPHITE_KEY = "#202026"   # keyline / outline against paper
TITLEBAR_TOP = "#474751"
TITLEBAR_BOT = "#3C3C45"
DIVIDER      = "#242429"
RIM_LIGHT    = "#6E6E7B"   # soft top rim on the window
CONTENT_BAR  = "#54545F"   # value-separated screen content
DOT_DARK     = "#50505B"
DOT_DARK_RIM = "#6A6A76"

# Terracotta accent (brand #F1552A), ramped as a translucent gel.
TERRA_HI   = "#FF8352"   # top-left lit face
TERRA_PURE = "#F1552A"   # brand value
TERRA_MID  = "#E14E23"
TERRA_LOW  = "#C63D17"   # shadowed lower-right face
TERRA_DOT  = "#F1552A"
BLOOM      = "#F1552A"   # warm emission onto paper

SHADOW     = "#B7A488"   # warm-neutral contact shadow on paper

# ---------------------------------------------------------------- geometry
CX = 512
# Window body (graphite screen). Right edge is where it converts to pixels.
WIN_L, WIN_R = 168, 596
WIN_T, WIN_B = 286, 742
WIN_RAD = 50
TITLE_H = 78
DIV_Y = WIN_T + TITLE_H

# Traffic-light dots (top-left of titlebar); leftmost = terracotta (active).
DOT_CY = WIN_T + TITLE_H / 2
DOT_R = 16
DOT_CX = [216, 270, 324]

# Screen content bars (fade out by 16px; garnish at mid sizes).
BAR_X, BAR_W, BAR_H, BAR_R = 226, 236, 24, 12
BAR_Y = [470, 552]

# Pixel-dissolve grid. col0 sits over the graphite; the edge erodes into pixels.
M = 46                     # module
GX0, GY0 = 572, 316        # centre of cell (row0,col0)
# state grid: '#' dense attached · 'o' mid · '.' faint drifting · ' ' empty
GRID = [
    "o#. .  ",
    "##o. . ",
    "##oo.  ",
    "o##o. .",
    "###oo. ",
    "##oo.. ",
    "o##o. .",
    "##oo.  ",
    "##o. . ",
    "o#. .  ",
]
PIX = {  # per-state: half-size, corner radius, body opacity
    "#": (20.5, 6, 1.00),
    "o": (17.0, 6, 0.94),
    ".": (12.0, 5, 0.72),
}

# ---------------------------------------------------------------- svg helpers
def g(*parts):
    return "\n".join(parts)

def gel_pixel(cx, cy, state):
    half, rad, op = PIX[state]
    x, y = cx - half, cy - half
    w = h = half * 2
    # body gel (diagonal ramp lit top-left → shadow bottom-right)
    body = (f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
            f'rx="{rad}" fill="url(#pixGel)" opacity="{op:.2f}"/>')
    # inner warm glow for the solid ones (emissive core)
    glow = ""
    if state in "#o":
        glow = (f'<rect x="{x+3:.1f}" y="{y+3:.1f}" width="{w-6:.1f}" height="{h-6:.1f}" '
                f'rx="{max(2,rad-2)}" fill="url(#pixGlow)" opacity="0.62"/>')
    # top-left specular face — a clean soft light, not a notch
    hop = {"#": 0.42, "o": 0.32, ".": 0.18}[state]
    hi = (f'<rect x="{x+3:.1f}" y="{y+3:.1f}" width="{w*0.46:.1f}" height="{h*0.40:.1f}" '
          f'rx="{max(2,rad-3)}" fill="#FFD8C2" opacity="{hop:.2f}"/>')
    return body + glow + hi

def build():
    W = 1024
    out = []
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" '
               f'viewBox="0 0 {W} {W}">')

    # -------------------------------------------------- defs
    out.append('<defs>')
    # paper cushion: radial, brightest top-centre
    out.append(f'''<radialGradient id="paper" cx="0.5" cy="0.36" r="0.85">
      <stop offset="0" stop-color="{PAPER_TOP}"/>
      <stop offset="0.55" stop-color="{PAPER_MID}"/>
      <stop offset="1" stop-color="{PAPER_EDGE}"/>
    </radialGradient>''')
    out.append(f'''<radialGradient id="vignette" cx="0.5" cy="0.5" r="0.80">
      <stop offset="0.72" stop-color="{VIGNETTE}" stop-opacity="0"/>
      <stop offset="1" stop-color="{VIGNETTE}" stop-opacity="0.20"/>
    </radialGradient>''')
    # warm bloom onto paper beside the pixels
    out.append(f'''<radialGradient id="bloom" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{BLOOM}" stop-opacity="0.42"/>
      <stop offset="0.5" stop-color="{BLOOM}" stop-opacity="0.14"/>
      <stop offset="1" stop-color="{BLOOM}" stop-opacity="0"/>
    </radialGradient>''')
    # graphite screen
    out.append(f'''<linearGradient id="graphite" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{GRAPHITE_TOP}"/>
      <stop offset="1" stop-color="{GRAPHITE_BOT}"/>
    </linearGradient>''')
    out.append(f'''<linearGradient id="titlebar" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{TITLEBAR_TOP}"/>
      <stop offset="1" stop-color="{TITLEBAR_BOT}"/>
    </linearGradient>''')
    # emissive terracotta bounce on the screen's inner-right
    out.append(f'''<linearGradient id="bounce" x1="1" y1="0.5" x2="0" y2="0.5">
      <stop offset="0" stop-color="{TERRA_PURE}" stop-opacity="0.72"/>
      <stop offset="0.30" stop-color="{TERRA_PURE}" stop-opacity="0.20"/>
      <stop offset="1" stop-color="{TERRA_PURE}" stop-opacity="0"/>
    </linearGradient>''')
    # soft graphite screen sheen (one top light)
    out.append(f'''<radialGradient id="sheen" cx="0.44" cy="0.14" r="0.72">
      <stop offset="0" stop-color="#5A5A66" stop-opacity="0.55"/>
      <stop offset="0.55" stop-color="#5A5A66" stop-opacity="0.12"/>
      <stop offset="1" stop-color="#5A5A66" stop-opacity="0"/>
    </radialGradient>''')
    # pixel gel body + glow
    out.append(f'''<linearGradient id="pixGel" x1="0.12" y1="0.08" x2="0.9" y2="0.95">
      <stop offset="0" stop-color="{TERRA_HI}"/>
      <stop offset="0.45" stop-color="{TERRA_PURE}"/>
      <stop offset="0.78" stop-color="{TERRA_MID}"/>
      <stop offset="1" stop-color="{TERRA_LOW}"/>
    </linearGradient>''')
    out.append(f'''<radialGradient id="pixGlow" cx="0.42" cy="0.4" r="0.6">
      <stop offset="0" stop-color="#FFB183" stop-opacity="0.9"/>
      <stop offset="1" stop-color="#FFB183" stop-opacity="0"/>
    </radialGradient>''')
    # window top rim light
    out.append(f'''<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{RIM_LIGHT}" stop-opacity="0.9"/>
      <stop offset="1" stop-color="{RIM_LIGHT}" stop-opacity="0"/>
    </linearGradient>''')
    out.append('<filter id="soft" x="-40%" y="-40%" width="180%" height="180%">'
               '<feGaussianBlur stdDeviation="14"/></filter>')
    out.append('<filter id="softer" x="-60%" y="-60%" width="220%" height="220%">'
               '<feGaussianBlur stdDeviation="30"/></filter>')
    out.append('<filter id="tiny" x="-40%" y="-40%" width="180%" height="180%">'
               '<feGaussianBlur stdDeviation="3"/></filter>')
    out.append(f'<clipPath id="tile"><path d="{SQUIRCLE}"/></clipPath>')
    out.append('</defs>')

    # everything clipped to the squircle tile (baked mask, decorative icon)
    out.append('<g clip-path="url(#tile)">')

    # -------------------------------------------------- bg
    out.append('<g id="bg">')
    out.append(f'<path d="{SQUIRCLE}" fill="url(#paper)"/>')
    out.append(f'<path d="{SQUIRCLE}" fill="url(#vignette)"/>')
    # warm bloom on the paper to the right, behind the drifting pixels
    out.append(f'<ellipse cx="712" cy="514" rx="250" ry="262" fill="url(#bloom)" filter="url(#softer)"/>')
    # inner rim light on the tile perimeter
    out.append(f'<path d="{SQUIRCLE}" fill="none" stroke="{PAPER_RIM}" stroke-width="3" opacity="0.6"/>')
    out.append('</g>')

    # -------------------------------------------------- mid : ghost back-window
    out.append('<g id="mid">')
    gx, gy = WIN_L - 30, WIN_T - 36   # offset up-left (stacked-windows DNA)
    out.append(f'<rect x="{gx}" y="{gy}" width="{WIN_R-WIN_L}" height="{WIN_B-WIN_T}" '
               f'rx="{WIN_RAD}" fill="#EBE2D0" opacity="0.7"/>')
    out.append(f'<rect x="{gx}" y="{gy}" width="{WIN_R-WIN_L}" height="{WIN_B-WIN_T}" '
               f'rx="{WIN_RAD}" fill="none" stroke="{GRAPHITE_KEY}" stroke-width="2.5" opacity="0.07"/>')
    out.append('</g>')

    # -------------------------------------------------- fg : window + pixels
    out.append('<g id="fg">')
    # contact shadow under the window (soft, warm, offset down)
    out.append(f'<ellipse cx="{(WIN_L+WIN_R)/2:.0f}" cy="{WIN_B+16}" rx="{(WIN_R-WIN_L)/2+6:.0f}" '
               f'ry="46" fill="{SHADOW}" opacity="0.5" filter="url(#soft)"/>')

    winW, winH = WIN_R - WIN_L, WIN_B - WIN_T
    # graphite body
    out.append(f'<rect x="{WIN_L}" y="{WIN_T}" width="{winW}" height="{winH}" '
               f'rx="{WIN_RAD}" fill="url(#graphite)"/>')
    # titlebar (clipped to the window's rounded top)
    out.append(f'<clipPath id="winclip"><rect x="{WIN_L}" y="{WIN_T}" width="{winW}" '
               f'height="{winH}" rx="{WIN_RAD}"/></clipPath>')
    out.append(f'<g clip-path="url(#winclip)">')
    out.append(f'<rect x="{WIN_L}" y="{WIN_T}" width="{winW}" height="{TITLE_H}" fill="url(#titlebar)"/>')
    # soft screen sheen (top light)
    out.append(f'<rect x="{WIN_L}" y="{DIV_Y}" width="{winW}" height="{WIN_B-DIV_Y}" fill="url(#sheen)"/>')
    out.append(f'<rect x="{WIN_L}" y="{DIV_Y-2}" width="{winW}" height="2.5" fill="{DIVIDER}" opacity="0.8"/>')
    # emissive terracotta bounce on the inner-right of the screen
    out.append(f'<rect x="{WIN_R-200}" y="{WIN_T}" width="200" height="{winH}" fill="url(#bounce)"/>')
    out.append('</g>')
    # window keyline (defines it against paper)
    out.append(f'<rect x="{WIN_L}" y="{WIN_T}" width="{winW}" height="{winH}" '
               f'rx="{WIN_RAD}" fill="none" stroke="{GRAPHITE_KEY}" stroke-width="2.5"/>')
    # traffic-light dots
    for i, cx in enumerate(DOT_CX):
        if i == 0:
            out.append(f'<circle cx="{cx}" cy="{DOT_CY:.0f}" r="{DOT_R+1}" fill="{TERRA_DOT}" '
                       f'opacity="0.28" filter="url(#tiny)"/>')  # active-dot halo
            out.append(f'<circle cx="{cx}" cy="{DOT_CY:.0f}" r="{DOT_R}" fill="{TERRA_DOT}"/>')
            out.append(f'<circle cx="{cx-3}" cy="{DOT_CY-3:.0f}" r="{DOT_R*0.4:.0f}" fill="#FFB48F" opacity="0.8"/>')
        else:
            out.append(f'<circle cx="{cx}" cy="{DOT_CY:.0f}" r="{DOT_R}" fill="{DOT_DARK}"/>')
            out.append(f'<circle cx="{cx}" cy="{DOT_CY:.0f}" r="{DOT_R}" fill="none" '
                       f'stroke="{DOT_DARK_RIM}" stroke-width="1.5" opacity="0.6"/>')
    # content bars
    for by in BAR_Y:
        out.append(f'<rect x="{BAR_X}" y="{by}" width="{BAR_W}" height="{BAR_H}" '
                   f'rx="{BAR_R}" fill="{CONTENT_BAR}" opacity="0.85"/>')

    # pixel dissolve — draw far→near so nearer pixels occlude farther ones
    cells = []
    for r, row in enumerate(GRID):
        for c, ch in enumerate(row):
            if ch in PIX:
                cx = GX0 + c * M
                cy = GY0 + r * M
                cells.append((c, r, cx, cy, ch))
    for c, r, cx, cy, ch in sorted(cells, key=lambda t: -t[0]):
        out.append(gel_pixel(cx, cy, ch))
    out.append('</g>')

    # -------------------------------------------------- highlight
    out.append('<g id="highlight">')
    # window top-edge rim light
    out.append(f'<rect x="{WIN_L+10}" y="{WIN_T+1}" width="{winW-20}" height="16" '
               f'rx="8" fill="url(#rim)" opacity="0.7"/>')
    # faint overall top sheen on the tile
    out.append(f'<rect x="0" y="0" width="1024" height="360" fill="#FFFFFF" opacity="0.05"/>')
    out.append('</g>')

    out.append('</g>')  # /tile clip
    out.append('</svg>')
    return "\n".join(out)


if __name__ == "__main__":
    svg = build()
    dst = HERE / "icon-proctor.svg"
    dst.write_text(svg)
    print(f"wrote {dst} ({len(svg)} bytes)")
