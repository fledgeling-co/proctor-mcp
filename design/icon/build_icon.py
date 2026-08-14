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
# Warm paper ground (brand anchor) — sampled off the live mark, then deepened
# at the corners to the reference's measured vignette (TL/BR corner L≈0.66,
# top-centre L≈0.95). A strong cushion falloff is most of the reference's read.
PAPER_TOP   = "#F8F2E4"   # brightest, top-centre (ref 0.955)
PAPER_MID   = "#EFE4CD"
PAPER_EDGE  = "#C9B590"   # warm greige at the corners (ref corner #BFA583)
PAPER_RIM   = "#FFFEFA"   # inner rim light
VIGNETTE    = "#A8926C"   # corner darkening (deeper, warmer)

# Deep graphite screen — reference falls titlebar L0.35 → base L0.11, a much
# deeper vertical ramp than a flat charcoal. Neutral-warm, never blue.
GRAPHITE_TOP = "#3F3D40"   # warm-neutral (ref titlebar/screen read warm, not blue)
GRAPHITE_BOT = "#1A1917"   # ref base #1C1C1D
GRAPHITE_KEY = "#141418"   # keyline / outline against paper
TITLEBAR_TOP = "#54504E"   # warm-neutral (ref titlebar #605654)
TITLEBAR_BOT = "#3A3A42"
DIVIDER      = "#1C1C20"
RIM_LIGHT    = "#6E6E7B"   # soft top rim on the window
DOT_DARK     = "#37373A"   # recessed dark dots (ref #3B3B3C, darker than titlebar)
DOT_DARK_RIM = "#4A4A50"
AMBER        = "#FB7E31"   # glowing traffic-light dot (ref #FB7E31, amber not brand-terra)
AMBER_HALO   = "#F1552A"   # warm bloom around the amber dot

# Terracotta accent (brand #F1552A), ramped as a translucent gel.
TERRA_HI   = "#FF8352"   # top-left lit face
TERRA_PURE = "#F1552A"   # brand value
TERRA_MID  = "#E14E23"
TERRA_LOW  = "#C63D17"   # shadowed lower-right face
TERRA_DOT  = "#F1552A"
BLOOM      = "#F1552A"   # warm emission onto paper

# Contact shadow on the paper — a tight dark AO band at the base + a soft
# ambient falloff. Ref reads #9D7D59 (L0.51) at the edge to #725639 (L0.35) core.
SHADOW_CORE = "#4E3A24"   # tight contact band, hugging the base
SHADOW_SOFT = "#7A5E3C"   # wide ambient falloff

# ---------------------------------------------------------------- geometry
CX = 512
# Window body (graphite screen). Right edge is where it converts to pixels.
# Taller, rounder "tablet" to match the reference proportion (ref body
# x178-665 y234-804, corner r≈80).
WIN_L, WIN_R = 168, 596
WIN_T, WIN_B = 270, 786
WIN_RAD = 82
TITLE_H = 78
DIV_Y = WIN_T + TITLE_H

# Traffic-light dots (top-left of titlebar); leftmost = amber (active/glowing).
DOT_CY = WIN_T + TITLE_H / 2
DOT_R = 16
DOT_CX = [216, 270, 324]

# Pixel-dissolve grid. col0 sits over the graphite; the edge erodes into pixels.
# Ref cubes are ~40px with a loose ~56-81px pitch (dense near the window, sparse
# drifting out), and the drifting ones stay large rather than shrinking away.
M = 56                     # module pitch (looser, matches the ref scatter)
GX0, GY0 = 574, 306        # centre of cell (row0,col0), just off the window edge
# state grid: '#' dense attached · 'o' mid · '.' faint drifting · ' ' empty.
# Denser on the left, an irregular loose scatter on the right.
GRID = [
    "o#.  . ",
    "##o .  ",
    "##oo. .",
    "o##o.  ",
    "###o. .",
    "##oo. .",
    "o##o.  ",
    "##oo. .",
    "##o.  .",
    "o#.  . ",
]
PIX = {  # per-state: half-size, corner radius, body opacity
    "#": (21.0, 7, 1.00),
    "o": (18.0, 6, 0.94),
    ".": (15.0, 6, 0.72),
}
# Deterministic sub-grid jitter so the drift reads organic, not gridded.
def jitter(r, c, state):
    h = (r * 73856093) ^ (c * 19349663) ^ (ord(state) * 83492791)
    jx = ((h >> 3) % 15) - 7          # -7..7
    jy = ((h >> 11) % 15) - 7
    scale = {"#": 0.15, "o": 0.55, ".": 1.0}[state]  # attached cubes barely move
    return jx * scale, jy * scale

# ---------------------------------------------------------------- svg helpers
def g(*parts):
    return "\n".join(parts)

def gel_pixel(cx, cy, state):
    half, rad, op = PIX[state]
    x, y = cx - half, cy - half
    w = h = half * 2
    parts = []
    # translucent glass body — drifting cubes carry less opacity, so the warm
    # bloom reads THROUGH them (glass, not an opaque chip)
    bop = {"#": 0.94, "o": 0.82, ".": 0.60}[state]
    parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
                 f'rx="{rad}" fill="url(#pixGel)" opacity="{bop:.2f}"/>')
    # emissive interior — hot core, lights the gel from within
    gop = {"#": 0.90, "o": 0.78, ".": 0.58}[state]
    parts.append(f'<rect x="{x+2:.1f}" y="{y+2:.1f}" width="{w-4:.1f}" height="{h-4:.1f}" '
                 f'rx="{max(2,rad-2)}" fill="url(#pixGlow)" opacity="{gop:.2f}"/>')
    # bright rim-lit glass edge — a warm stroke that catches on the top and upper
    # sides and dies out toward the base (the glass tell)
    parts.append(f'<rect x="{x+1.4:.1f}" y="{y+1.4:.1f}" width="{w-2.8:.1f}" height="{h-2.8:.1f}" '
                 f'rx="{max(2,rad-1)}" fill="none" stroke="url(#pixRim)" '
                 f'stroke-width="2.3" opacity="{0.85*op:.2f}"/>')
    # soft warm specular near the top-left corner (not a hard white dot)
    sr = max(1.7, half * 0.15)
    parts.append(f'<circle cx="{x+half*0.5:.1f}" cy="{y+half*0.46:.1f}" r="{sr:.1f}" '
                 f'fill="#FFEBD6" opacity="{0.62*op:.2f}"/>')
    return "".join(parts)

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
    out.append(f'''<radialGradient id="vignette" cx="0.5" cy="0.42" r="0.86">
      <stop offset="0.42" stop-color="{VIGNETTE}" stop-opacity="0"/>
      <stop offset="1" stop-color="{VIGNETTE}" stop-opacity="0.50"/>
    </radialGradient>''')
    # warm bloom onto paper beside the pixels — two layers (splice bloom recipe):
    # a hot core near the dense cubes + a broad creamy wash. Ref paper bloom runs
    # #F4A26A (L0.69) near the cubes out to #F9C597 (L0.81), not pure terracotta.
    out.append(f'''<radialGradient id="bloomHot" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FF7A33" stop-opacity="0.55"/>
      <stop offset="0.45" stop-color="#F97C39" stop-opacity="0.22"/>
      <stop offset="1" stop-color="#F97C39" stop-opacity="0"/>
    </radialGradient>''')
    out.append(f'''<radialGradient id="bloomWarm" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#F9C48E" stop-opacity="0.55"/>
      <stop offset="0.6" stop-color="#F6B478" stop-opacity="0.18"/>
      <stop offset="1" stop-color="#F6B478" stop-opacity="0"/>
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
    # pixel gel body — a glassy diagonal ramp: bright lit top-left face down to a
    # deep saturated shadow base (ref lit face L~0.72, shadow base #C14419 L0.36).
    # A wide luminance range is what reads as glass rather than a matte chip.
    out.append(f'''<linearGradient id="pixGel" x1="0.14" y1="0.04" x2="0.86" y2="0.98">
      <stop offset="0" stop-color="#FFC98F"/>
      <stop offset="0.28" stop-color="#FB8C44"/>
      <stop offset="0.62" stop-color="#EE5A24"/>
      <stop offset="1" stop-color="#B4380F"/>
    </linearGradient>''')
    # emissive interior — a hot core that lights the gel from within (ref #F96D26)
    out.append(f'''<radialGradient id="pixGlow" cx="0.5" cy="0.56" r="0.62">
      <stop offset="0" stop-color="#FF8C3E" stop-opacity="0.95"/>
      <stop offset="0.55" stop-color="#F96D26" stop-opacity="0.42"/>
      <stop offset="1" stop-color="#F96D26" stop-opacity="0"/>
    </radialGradient>''')
    # glass rim — a bright warm edge catch, strong on the top, fading down the
    # sides to nothing at the base. This edge wrap is what reads as glass rather
    # than a glossy face dot (ref cubes glow at their rim, translucent in body).
    out.append(f'''<linearGradient id="pixRim" x1="0" y1="0" x2="0.22" y2="1">
      <stop offset="0" stop-color="#FFEAD0" stop-opacity="0.95"/>
      <stop offset="0.38" stop-color="#FFC79A" stop-opacity="0.42"/>
      <stop offset="1" stop-color="#FFC79A" stop-opacity="0"/>
    </linearGradient>''')
    # window top rim light
    out.append(f'''<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{RIM_LIGHT}" stop-opacity="0.9"/>
      <stop offset="1" stop-color="{RIM_LIGHT}" stop-opacity="0"/>
    </linearGradient>''')
    # window bottom-edge rim (warm bounce off the paper, grounds the base)
    out.append(f'''<linearGradient id="rimBot" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#8A8078" stop-opacity="0"/>
      <stop offset="1" stop-color="#9E9186" stop-opacity="0.85"/>
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
    # warm bloom on the paper behind the drifting pixels — hot core + creamy wash
    out.append(f'<ellipse cx="748" cy="512" rx="340" ry="350" fill="url(#bloomWarm)" filter="url(#softer)"/>')
    out.append(f'<ellipse cx="700" cy="512" rx="238" ry="262" fill="url(#bloomHot)" filter="url(#softer)"/>')
    # inner rim light on the tile perimeter
    out.append(f'<path d="{SQUIRCLE}" fill="none" stroke="{PAPER_RIM}" stroke-width="3" opacity="0.6"/>')
    out.append('</g>')

    # -------------------------------------------------- mid : (reserved)
    # The ghost back-window was dropped — the reference carries none, and at the
    # 16px squint the second outline muddied the single-window read. Group kept
    # (layer plan) but empty.
    out.append('<g id="mid"></g>')

    # -------------------------------------------------- fg : window + pixels
    out.append('<g id="fg">')
    # contact shadow on the paper — two layers: a soft ambient falloff, then a
    # tight dark AO band hugging the base, both offset down-right (top-left key)
    winCX = (WIN_L + WIN_R) / 2
    out.append(f'<ellipse cx="{winCX+16:.0f}" cy="{WIN_B+34}" rx="{(WIN_R-WIN_L)/2+26:.0f}" '
               f'ry="60" fill="{SHADOW_SOFT}" opacity="0.42" filter="url(#softer)"/>')
    out.append(f'<ellipse cx="{winCX+12:.0f}" cy="{WIN_B+10}" rx="{(WIN_R-WIN_L)/2-8:.0f}" '
               f'ry="26" fill="{SHADOW_CORE}" opacity="0.55" filter="url(#soft)"/>')

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
    # traffic-light dots — one glowing amber (active), two recessed dark
    for i, cx in enumerate(DOT_CX):
        if i == 0:
            out.append(f'<circle cx="{cx}" cy="{DOT_CY:.0f}" r="{DOT_R*2.0:.0f}" '
                       f'fill="{AMBER_HALO}" opacity="0.30" filter="url(#soft)"/>')  # warm bloom
            out.append(f'<circle cx="{cx}" cy="{DOT_CY:.0f}" r="{DOT_R}" fill="{AMBER}"/>')
            out.append(f'<circle cx="{cx-4}" cy="{DOT_CY-5:.0f}" r="5" fill="#FFE2CC" opacity="0.85"/>')
        else:
            out.append(f'<circle cx="{cx}" cy="{DOT_CY:.0f}" r="{DOT_R}" fill="{DOT_DARK}"/>')
            out.append(f'<circle cx="{cx}" cy="{DOT_CY-2:.0f}" r="{DOT_R-1}" fill="none" '
                       f'stroke="#2B2B2E" stroke-width="1.8" opacity="0.6"/>')  # recessed rim

    # (screen intentionally empty — reference has no content bars; helps 16px squint)

    # pixel dissolve — draw far→near so nearer pixels occlude farther ones
    cells = []
    for r, row in enumerate(GRID):
        for c, ch in enumerate(row):
            if ch in PIX:
                jx, jy = jitter(r, c, ch)
                cx = GX0 + c * M + jx
                cy = GY0 + r * M + jy
                cells.append((c, r, cx, cy, ch))
    for c, r, cx, cy, ch in sorted(cells, key=lambda t: -t[0]):
        out.append(gel_pixel(cx, cy, ch))
    out.append('</g>')

    # -------------------------------------------------- highlight
    out.append('<g id="highlight">')
    # window top-edge rim light — clipped to the window so its ends follow the
    # rounded top corners rather than poking out over the paper
    out.append(f'<g clip-path="url(#winclip)">')
    out.append(f'<rect x="{WIN_L}" y="{WIN_T+1}" width="{winW}" height="14" '
               f'fill="url(#rim)" opacity="0.55"/>')
    # bottom-edge catch — grounds the window on the paper
    out.append(f'<rect x="{WIN_L}" y="{WIN_B-14}" width="{winW}" height="13" '
               f'fill="url(#rimBot)" opacity="0.28"/>')
    out.append('</g>')
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
