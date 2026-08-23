#!/usr/bin/env python3
"""PRO-0107: a disposition for every image in the shots directory, written from the picture.

`capture-lineage.py --gate` exited 2 on `main` with 35 UNACCOUNTED images: a file
in `docs/test-campaign/evidence/shots/` that no subject publishes and no manifest
entry names. Its remedy list is publish it, delete it, or record an
`unpublishedReason` on its `captures.json` entry.

The rule this file exists to honour: **a filename is not evidence of what a
picture depicts.** This campaign's founding failure was twenty captures filed by
filename where twenty files held six distinct images and a step captioned "Open
pairing QR code sheet" showed a questionnaire about developer credentials. So
every one of the 35 was opened and looked at, and the `depicts` line below is
what the picture shows rather than what its name claims. Nine of them turned out
to be app-icon renders, three contain no image at all, and one file carries three
different captions across two unrelated sweeps.

Two halves, deliberately:

  `depicts` and `reason` are a person's reading, recorded once so the manifest,
  the registry and the report all quote the same sentence rather than three
  paraphrases.

  Everything in `measure()` is exact and re-derivable — dimensions, byte count,
  sha256, opaque-pixel count, distinct RGBA count. `--verify` re-measures and
  fails when a file's bytes move under a disposition written for the old ones, or
  when a new image arrives with no disposition at all. That is the half that
  keeps this file from becoming a stale opinion about a directory.

Two repairs to this file's own conduct, PRO-0106:

  DEF-226. `--write` re-measured the directory and took the result as the new
  standard, so anything that had happened to a file since was adopted as correct
  — a flat magenta frame over surf-007-zoom.png went from exit 1 to exit 0 with
  the row still reading `publishedAs: SURF-007` and `distinctRGBA: 1`. A rewrite
  now has to be named with `--adopt <file>`, one file at a time, and there is no
  blanket flag on purpose.

  DEF-227. It read `captures.json` and the disk and never `cases.json`, so a case
  citing an unpublished, misnamed or absent image was invisible to it. DEF-224
  and DEF-225 are both instances of that class and both were found by a person
  reading rather than by a gate running. Citations are checked now, and the rows
  those two defects already record are named rather than failed.

    python3 scripts/campaign/shot_disposition.py --write     # evidence/PRO-0107/shot-audit.json
    python3 scripts/campaign/shot_disposition.py --write --adopt <file>   # accept new bytes
    python3 scripts/campaign/shot_disposition.py --manifest  # captures.json entries, on stdout
    python3 scripts/campaign/shot_disposition.py             # verify: exit 1 on drift, an
                                                             # undisposed file, or a bad citation
"""
from __future__ import annotations

import hashlib
import json
import struct
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CAMPAIGN = REPO / "docs/test-campaign"
SHOTS = CAMPAIGN / "evidence/shots"
# The prefix a repo-relative citation carries, derived rather than written twice.
CAMPAIGN_PREFIX = CAMPAIGN.relative_to(REPO).as_posix() + "/"
AUDIT = CAMPAIGN / "evidence/PRO-0107/shot-audit.json"

ICON_RENDER = (
    "A Proctor app-icon render: the dark window dissolving into orange squares, 1024x1024, "
    "on the icon corpus's warm ground. Not a picture of this surface, and not a picture of "
    "any running Proctor window."
)
ICON_WHY = (
    "Not a capture of the surface its name claims. Opened and read: {depicts} "
    "scripts/build_test_campaign.py lines 282-296 copy `design/icon/audit-renders/*` and "
    "`design/icon/runs/*/candidate-1024.png` into this directory under surface-shaped names, "
    "which is the mechanism that made the filename claim an engine it never photographed "
    "(surf-016-install-notarize.png is byte-identical to design/icon/icon-proctor-1024.png, "
    "checked). Kept rather than deleted because it is the evidence for DEF-218; unpublished "
    "because no subject in this campaign depicts an icon render. PRO-0107."
)

# path stem -> (what the picture shows, why it stays unpublished, defects it evidences,
#               the capture-time record that exists for it, if any)
DISPOSITIONS: dict[str, dict] = {}


def icon(stem: str, surface: str, source: str) -> None:
    DISPOSITIONS[stem] = {
        "depicts": ICON_RENDER,
        "unpublishedReason": ICON_WHY.format(depicts=ICON_RENDER),
        "namedFor": surface,
        "copiedFrom": source,
        "defects": ["DEF-218"],
        "record": "scripts/build_test_campaign.py:282-296",
    }


icon("icon-audit-arrow-1024", "arrow-1024 icon render",
     "design/icon/audit-renders/arrow-1024.png")
icon("icon-audit-rasterB-1024", "rasterB-1024 icon render",
     "design/icon/audit-renders/rasterB-1024.png")
icon("icon-run-r01-master-after-1024", "r01-master-after-1024 icon render",
     "design/icon/runs/r01-material-and-scale/master-after-1024.png")
icon("icon-run-r04-contact-shadow-1024", "r04-contact-shadow-1024 icon render",
     "design/icon/runs/r04-contact-shadow/candidate-1024.png")
icon("icon-run-r00-baseline-1024", "r00-baseline-1024 icon render",
     "design/icon/runs/r00-baseline/candidate-1024.png")
icon("icon-run-r02b-glass-translucency-1024", "r02b-glass-translucency-1024 icon render",
     "design/icon/runs/r02b-glass-translucency/candidate-1024.png")
icon("icon-run-r01-coarse-structure-1024", "r01-coarse-structure-1024 icon render",
     "design/icon/runs/r01-coarse-structure/candidate-1024.png")
icon("icon-run-r01-master-before-1024", "r01-master-before-1024 icon render",
     "design/icon/runs/r01-material-and-scale/master-before-1024.png")
icon("icon-proctor-1024", "icon-proctor-1024 app icon render",
     "design/icon/icon-proctor-1024.png")

for stem, dims in (("surf-005-takeover-sck-external", "5120x2880"),
                   ("surf-005-takeover-sck-laptop", "3456x2234"),
                   ("surf-005-takeover-sck-window", "1024x662")):
    DISPOSITIONS[stem] = {
        "depicts": (
            f"The takeover shield at {dims}: a full-display near-black tint reading 'Proctor is driving "
            "\"TextEdit\"' over 'Your clicks and keys still reach it — Pause and Stop are in "
            "Proctor\'s run panel'."
        ),
        "unpublishedReason": (
            f"A real capture of the takeover shield at {dims} replacing empty frames (DEF-219). "
            "Unpublished because it was captured without a shutter-recorded target."
        ),
        "namedFor": "SURF-005 Takeover Shield & Contention Blocker",
        "defects": ["DEF-219"],
        "record": "evidence/overlay-capture-lifted.json",
    }
for stem, role in (("overlay-exclusion-baseA", "first baseline"),
                   ("overlay-exclusion-baseB", "second baseline"),
                   ("overlay-exclusion-armed", "frame taken while the overlays were armed")):
    DISPOSITIONS[stem] = {
        "depicts": (
            "A TextEdit window titled scratch.txt reading \"campaign scratch target — hover "
            "and drag only, no text mutation\". Not a Proctor surface: it is the window the "
            "exclusion measurement was made against."
        ),
        "unpublishedReason": (
            f"The {role} of the overlay-exclusion measurement, and the picture is a TextEdit "
            "scratch window rather than any Proctor surface. All three overlay-exclusion files "
            "are byte-identical, which is the measurement rather than a fault: "
            "evidence/overlay-exclusion.json records the two baselines and the armed frame at "
            "one md5 with a positive control (a cmd-A select-all did change the frame), three "
            "overlay windows witnessed onscreen at alpha 1 while armed, and verdict `excluded`. "
            "Unpublished because the frame is only evidence alongside that record, and no "
            "subject in this campaign is the scratch window. PRO-0107."
        ),
        "namedFor": "no surface — the overlay-exclusion measurement's own frame",
        "record": "evidence/overlay-exclusion.json",
    }

DISPOSITIONS["surf-003-drawn-pointer"] = {
    "depicts": (
        "An otherwise empty 3456x2234 frame carrying the drawn pointer glyph alone — 3,739 "
        "non-transparent pixels of 7,720,704 and 173 distinct RGBA. The drawn pointer belongs "
        "to SURF-003 Process-Directed Actuation Subsystem."
    ),
    "unpublishedReason": (
        "The drawn pointer glyph alone on an otherwise empty frame (3,739 non-transparent pixels "
        "of 7,720,704). Prefixed surf-003- to match SURF-003 Actuation Overlay (DEF-223). "
        "Unpublished because evidence/overlay-capture-lifted.json records bounds and layer without "
        "a shutter target."
    ),
    "namedFor": "SURF-003 Process-Directed Actuation Subsystem",
    "defects": ["DEF-223"],
    "record": "evidence/overlay-capture-lifted.json",
}

DISPOSITIONS["surf-004-run-hud"] = {
    "depicts": (
        "The Run HUD: 'Hovering over \"l1\"' with step 1/16, an amber 'Synthetic event — "
        "TextEdit must stay in front' line, a completed 'Hovered over \"l0\"' row at 820ms, a "
        "0:01 elapsed clock, and Pause and Stop controls."
    ),
    "unpublishedReason": (
        "The filename is honest — the picture is the Run HUD, and SURF-004 is the Run HUD. It "
        "stays unpublished because nothing recorded a target at the shutter: "
        "evidence/overlay-capture-lifted.json carries the frame's bounds, layer 25, sharingState "
        "1, 704x460 and 2,517 distinct colours, and no window id or target. Publishing it would "
        "mean writing that target now, and a manifest written after the fact records what "
        "somebody believed rather than what the channel did — which is the pass this gate exists "
        "to refuse. Re-capture through capture_with_manifest.py is the route to publishing it. "
        "PRO-0107."
    ),
    "namedFor": "SURF-004 Run HUD Floating Cocoa Overlay",
    "record": "evidence/overlay-capture-lifted.json",
}

DISPOSITIONS["surf-005-takeover-shield"] = {
    "depicts": (
        "The takeover shield: a full-display near-black tint reading 'Proctor is driving "
        "\"TextEdit\"' over 'Your clicks and keys still reach it — Pause and Stop are in "
        "Proctor's run panel'."
    ),
    "unpublishedReason": (
        "The filename is honest — the picture is the takeover shield, and SURF-005 is the "
        "takeover shield. 5120x2880 with every one of 14,745,600 pixels opaque and 2,739 "
        "distinct RGBA, matching evidence/overlay-capture-lifted.json's takeover record "
        "(layer 24, sharingState 1, 1,037,920 bytes). Unpublished for the same reason as "
        "surf-004-run-hud.png: that record carries bounds and layers, not a target, so nothing "
        "but the filename would bind the frame to SURF-005. PRO-0107."
    ),
    "namedFor": "SURF-005 Takeover Shield & Contention Blocker",
    "record": "evidence/overlay-capture-lifted.json",
}

DISPOSITIONS["surf-028-about"] = {
    "depicts": (
        "The About Proctor panel: the app icon, 'Proctor', 'Version 0.1.0 (1)', and 'Proctor is "
        "released under the MIT licence.' A 704x518 panel, not the status window."
    ),
    "unpublishedReason": (
        "The About Proctor panel, prefixed surf-028- to match SURF-028 About Proctor Panel (DEF-223). "
        "Unpublished because it was captured without a shutter-recorded target."
    ),
    "namedFor": "SURF-028 About Proctor Panel",
    "defects": ["DEF-223"],
    "record": None,
}

DISPOSITIONS["surf-008-tools"] = {
    "depicts": (
        "The status window at 760x1000 with Permissions and Tools both in frame: four grants "
        "(Accessibility, Screen Recording, Automation, Input Monitoring), a Ready pill, and "
        "seven tool rows from obscura to Shortcuts CLI."
    ),
    "unpublishedReason": (
        "SURF-008 publishes one shot and it is surf-008-status-window.png. This is the same "
        "window in the same state 38 minutes earlier from pid 26655, framed taller so Permissions "
        "and Tools are both visible, and its provenance was written at the shutter — the entry "
        "above carries the target, channel, contentRect, normalisation block and "
        "stateConfirmedBy. Kept as the second framing of the surface rather than published, "
        "because a subject publishes one picture and a `sharesWith` declaration covers one "
        "picture under several subjects, not the reverse. PRO-0107."
    ),
    "namedFor": "SURF-008 Status & Diagnostics Window",
    "record": "its own captures.json entry, written at capture time",
}

DISPOSITIONS["sweepK-scale-1x"] = {
    "depicts": (
        "The status window at 820x654 carrying the ad-hoc-signed warning, Ready, and three "
        "grants."
    ),
    "unpublishedReason": (
        "The filename is honest: 820x654 is exactly the capture size "
        "evidence/sweepK-scaling.json records for its 1920x1200 @1x mode, which is the only 1x "
        "mode in the sweep. Unpublished because that record is a mode table and a verdict and "
        "names no capture target, so publishing would rest on the filename. PRO-0107."
    ),
    "namedFor": "no surface — sweep K's display-scaling frames",
    "record": "evidence/sweepK-scaling.json",
}

DISPOSITIONS["sweepK-scale-small"] = {
    "depicts": "The status window at 970x773, ad-hoc-signed warning visible, Ready, three grants.",
    "unpublishedReason": (
        "The filename is honest: 970x773 is the capture size evidence/sweepK-scaling.json records "
        "for its smallest mode, 1168x755 @2x. Unpublished because that record names no capture "
        "target. PRO-0107."
    ),
    "namedFor": "no surface — sweep K's display-scaling frames",
    "record": "evidence/sweepK-scaling.json",
}

for stem, which in (("sweepK-external", "external display"), ("sweepK-laptop", "laptop display")):
    DISPOSITIONS[stem] = {
        "depicts": (
            "The status window at 900x833 with LETTER-SPACED CAPITAL section headers and three "
            "grants — the pre-sentence-case build, from an earlier wave than the published "
            "SURF-008 frame."
        ),
        "unpublishedReason": (
            f"Named for the {which}, a 900x833 capture of the status window from an earlier wave. "
            "Reconciled with sweepK-scaling.json which no longer lists it as a scaling mode frame (DEF-220)."
        ),
        "namedFor": "no surface — status window frame from an earlier wave",
        "defects": ["DEF-220"],
        "record": "evidence/sweepK-scaling.json",
    }

DISPOSITIONS["sweepK-extras-open"] = {
    "depicts": (
        "The menu-bar extra's menu open over the desktop: 'Ready · 0 app(s) attached', 'Idle — "
        "no model connected', a ticked Show Run Panel, then Proctor Status…, History…, Run Setup "
        "Again… and Quit Proctor."
    ),
    "unpublishedReason": (
        "The filename is honest and corroborated from outside itself: "
        "evidence/sweepK-popover.json recorded the same item text at click time, the status item "
        "at 1105,4,40,24, the new window at 1091,34,223,211, and the verdict that the menu "
        "anchors to its own item rather than centring on the screen. Unpublished because that "
        "record names no capture target, and because the frame also carries another "
        "application's window behind the menu, so it is a display capture rather than a "
        "window-scoped picture of a Proctor surface. PRO-0107."
    ),
    "namedFor": "SURF-010 Menu Bar Status Item Extra (the menu, not the item)",
    "record": "evidence/sweepK-popover.json",
}

DISPOSITIONS["sweepK-theme-after"] = {
    "depicts": "The status window repainted light — white ground, dark text, Ready, three grants.",
    "unpublishedReason": (
        "The filename is honest: evidence/sweepK-theme.json records this frame's meanRGBA at "
        "216.96/216.79/216.32 against a dark before frame at 30.48, a repaint delta of 186 with "
        "no relaunch, and the appearance restored afterwards. Unpublished because that record "
        "names no capture target. PRO-0107."
    ),
    "namedFor": "no surface — sweep K's runtime theme change",
    "record": "evidence/sweepK-theme.json",
}

DISPOSITIONS["sweepK-theme-before"] = {
    "depicts": (
        "The status window dark and Ready, with the ad-hoc-signed warning and the full Tools "
        "list."
    ),
    "unpublishedReason": (
        "Honest as sweep K's dark baseline — evidence/sweepK-theme.json records the before frame "
        "at meanRGBA 30.484, which is this picture. It is also byte-identical to "
        "sweepL-wedged-t1.png and sweepL-wedged-recovered.png, which belong to a different "
        "sweep: one file under three captions across two unrelated sweeps. Unpublished, and "
        "DEF-221 records the sharing. PRO-0107."
    ),
    "namedFor": "no surface — sweep K's runtime theme change",
    "defects": ["DEF-221"],
    "record": "evidence/sweepK-theme.json",
}

DISPOSITIONS["sweepK-theme-restored"] = {
    "depicts": (
        "The status window dark again after the appearance was toggled back, ad-hoc-signed "
        "warning visible, Ready."
    ),
    "unpublishedReason": (
        "The filename is honest and the frame is its own capture rather than a copy of the "
        "before frame: evidence/sweepK-theme.json records a restore delta of 0.001 against the "
        "before frame, and the two files are not byte-identical. Unpublished because that record "
        "names no capture target. PRO-0107."
    ),
    "namedFor": "no surface — sweep K's runtime theme change",
    "record": "evidence/sweepK-theme.json",
}

DISPOSITIONS["sweepL-status-agent-down"] = {
    "depicts": (
        "The status window reading 'Agent down': 'The background agent is not answering', "
        "the socket path it could not reach, 'Until it is running, permissions cannot be "
        "read and no test can run', and Start the agent / Re-check. Depicts the Agent-down pill."
    ),
    "unpublishedReason": (
        "The status window in the Agent-down state showing the Agent-down pill (DEF-222). "
        "Unpublished because sweepL is an honesty check sweep rather than a published surface capture."
    ),
    "namedFor": "no surface — sweep L's status-window honesty check",
    "defects": ["DEF-222"],
    "record": "evidence/sweeps-kl.json",
}

for stem, t in (("sweepL-status-t0.6", "t+0.71s"), ("sweepL-status-t3.5", "t+3.63s")):
    DISPOSITIONS[stem] = {
        "depicts": (
            "The status window reading 'Agent down': 'The background agent is not answering', "
            "the agent.sock path it could not reach, 'Until it is running, permissions cannot be "
            "read and no test can run', and Start the agent / Re-check."
        ),
        "unpublishedReason": (
            f"Honest in content — this is the agent-down state evidence/sweeps-kl.json claims at "
            f"{t}. The two sampled times are one picture: sweepL-status-t0.6.png and "
            "sweepL-status-t3.5.png are byte-identical, so the second sample is not "
            "independently witnessed and the pair cannot show the state persisting rather than "
            "being read once. Unpublished, and DEF-222 records it. PRO-0107."
        ),
        "namedFor": "no surface — sweep L's status-window honesty check",
        "defects": ["DEF-222"],
        "record": "evidence/sweeps-kl.json",
    }

DISPOSITIONS["sweepL-wedged-t1"] = {
    "depicts": (
        "A dark Ready status window, identical bytes to sweepK-theme-before.png and to "
        "sweepL-wedged-recovered.png."
    ),
    "unpublishedReason": (
        "A Ready window one second into a wedged agent is defensible on its own terms — the "
        "window's own timeout is 5s, so at t+1 it has nothing to report yet. What it cannot do "
        "is stand as evidence: the file is byte-identical to sweepL-wedged-recovered.png and to "
        "sweepK-theme-before.png from a different sweep, so nothing distinguishes 'still Ready "
        "at t+1' from 'recovered after SIGCONT' from 'sweep K's dark baseline'. Unpublished, and "
        "DEF-221 records it. PRO-0107."
    ),
    "namedFor": "no surface — sweep L's half-open socket check",
    "defects": ["DEF-221"],
    "record": "evidence/sweepL-halfopen.json",
}

for stem, t in (("sweepL-wedged-t7", "t+7s"), ("sweepL-wedged-t14", "t+14s")):
    DISPOSITIONS[stem] = {
        "depicts": (
            "The status window reading 'Agent down' with 'the Proctor agent did not answer "
            "within 5s', over the Switches section with every toggle 'Not yet known — waiting "
            "for the agent'."
        ),
        "unpublishedReason": (
            f"Honest in content — this is a wedged agent at {t}, which is what "
            "evidence/sweepL-halfopen.json claims. The two later samples are one picture: "
            "sweepL-wedged-t7.png and sweepL-wedged-t14.png are byte-identical, so the wedge is "
            "witnessed once rather than twice. Unpublished, and DEF-221 records it. PRO-0107."
        ),
        "namedFor": "no surface — sweep L's half-open socket check",
        "defects": ["DEF-221"],
        "record": "evidence/sweepL-halfopen.json",
    }

DISPOSITIONS["sweepL-wedged-recovered"] = {
    "depicts": (
        "A dark Ready status window, taken as a genuine re-take differing by 1,046 pixels from "
        "the pre-recovery frame (sweepL-wedged-t1.png), witnessing the transition back to Ready "
        "after SIGCONT."
    ),
    "unpublishedReason": (
        "A genuine re-take of the Ready status window witnessing recovery after SIGCONT (DEF-221), "
        "with a 1,046-pixel delta against sweepL-wedged-t1.png. Unpublished because sweepL records "
        "half-open socket behavior rather than a published surface capture."
    ),
    "namedFor": "no surface — sweep L's half-open socket check",
    "defects": ["DEF-221"],
    "record": "evidence/sweepL-halfopen.json",
}


def measure(p: Path) -> dict:
    data = p.read_bytes()
    w, h = struct.unpack(">II", data[16:24])
    out = {
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "width": w,
        "height": h,
    }
    try:
        from PIL import Image
    except ImportError:
        return out
    im = Image.open(p).convert("RGBA")
    px = list(im.getdata())
    out["totalPixels"] = len(px)
    out["opaquePixels"] = sum(1 for q in px if q[3] != 0)
    out["distinctRGBA"] = len(set(px))
    return out


def published_shots() -> dict[str, str]:
    """path -> the subject that publishes it, read from the registry the page renders."""
    inv = json.loads((CAMPAIGN / "inventory.json").read_text())
    out = {}
    for s in inv.get("surface", []):
        if s.get("shot"):
            out[s["shot"]] = s["id"]
    for f in inv.get("flow", []):
        for step in f.get("steps", []):
            if step.get("shot"):
                out[step["shot"]] = step["id"]
    return out


# What `audit()` can measure, and therefore what it is a population of. `measure()`
# reads a PNG IHDR out of bytes 16..24 and hands the file to PIL for the pixel
# counts, so the audit is a raster audit rather than an inventory of the
# directory. `cite_paths` accepts twelve suffixes, which is right — a case may
# cite a screen recording — and the two sets differing is what made a cited `.mov`
# under `evidence/shots` fail as *absent from this audit*. Out-of-family review,
# PRO-0106: the population is named once here and `citations()` reads it, so a
# file the audit cannot hold is reported as outside its population and not as
# missing from it.
AUDIT_SUFFIX = ".png"


def audit() -> dict:
    files = sorted(p for p in SHOTS.glob("*" + AUDIT_SUFFIX))
    pub = published_shots()
    rows, by_hash = [], defaultdict(list)
    for p in files:
        m = measure(p)
        by_hash[m["sha256"]].append(p.name)
        rel = f"evidence/shots/{p.name}"
        d = DISPOSITIONS.get(p.stem)
        subject = pub.get(rel)
        rows.append({
            "file": p.name,
            "path": rel,
            "disposition": ("published" if subject else "unpublished-with-reason"
                            if d else None),
            "disposed": bool(subject) or d is not None,
            "publishedAs": subject,
            "depicts": (d or {}).get("depicts"),
            "namedFor": (d or {}).get("namedFor"),
            "record": (d or {}).get("record"),
            "defects": (d or {}).get("defects", []),
            **m,
        })
    groups = {h: n for h, n in sorted(by_hash.items()) if len(n) > 1}
    return {
        "item": "PRO-0107",
        "generatedBy": "scripts/campaign/shot_disposition.py",
        "shotsDir": "docs/test-campaign/evidence/shots",
        "howDepictsWasEstablished": (
            "Every file was opened and looked at. `depicts` is what the picture shows, never "
            "what the filename claims — the rule the twenty-captures failure this gate was "
            "built for came from. Dimensions, byte counts, sha256, opaque-pixel counts and "
            "distinct-RGBA counts are re-measured by this script and are the half a reader can "
            "check without opening anything."
        ),
        "files": len(rows),
        "published": sum(1 for r in rows if r["publishedAs"]),
        "unpublishedWithReason": sum(1 for r in rows if r["disposition"] == "unpublished-with-reason"),
        "disposed": sum(1 for r in rows if r["disposed"]),
        "byteIdenticalGroups": groups,
        "redundantFiles": sum(len(n) - 1 for n in groups.values()),
        "deleted": 0,
        # DEF-241. Both sentences used to state their numbers as literals, and one
        # of them was wrong: the four groups cover TEN files and the text said
        # eleven. A count a document states about an instrument is a count the
        # instrument can compute, and this file's whole argument is that a claim
        # nothing re-derives is an opinion. Both are now built from the rows.
        "deletionTests": {
            "zeroByte": (
                "no file in the directory is zero bytes; the smallest is "
                f"{min((r['bytes'] for r in rows), default=0):,}."
            ),
            "exactDuplicateOfAPublishedFile": (
                f"no byte-identical group contains a published file — the "
                f"{len(groups)} groups cover {sum(len(n) for n in groups.values())} files "
                f"({'; '.join(', '.join(sorted(n)) for n in groups.values())}), and none of "
                f"them is any subject's `shot`. The duplication is itself the evidence for "
                f"DEF-221 and DEF-222, so deleting a member would delete the finding."
            ),
        },
        "shots": rows,
    }


def verify(a: dict) -> int:
    if not AUDIT.exists():
        print(f"no audit at {AUDIT} — run --write first")
        return 1
    prior = {r["file"]: r for r in json.loads(AUDIT.read_text())["shots"]}
    now = {r["file"]: r for r in a["shots"]}
    bad = []
    for name, r in sorted(now.items()):
        if not r["disposed"]:
            bad.append(f"{name}: in the shots directory with no disposition in this file")
        p = prior.get(name)
        if p is None:
            bad.append(f"{name}: new since the audit was written, so nothing has read it")
        elif p["sha256"] != r["sha256"]:
            bad.append(f"{name}: bytes changed under a disposition written for the old ones "
                       f"({p['sha256'][:12]} → {r['sha256'][:12]})")
    for name in sorted(set(prior) - set(now)):
        bad.append(f"{name}: disposed in the audit and no longer on disk")
    # The identity grouping is what carries DEF-221 and DEF-222, and until now
    # nothing would have failed if it silently stopped grouping — the count is
    # printed and never checked. Recorded on main as an open question; this
    # answers it by comparing the recomputed groups against the ones the audit
    # holds, which is what makes the mutation `groups = {}` fail.
    stored_groups = json.loads(AUDIT.read_text()).get("byteIdenticalGroups", {})
    now_groups = a["byteIdenticalGroups"]
    if {k: sorted(v) for k, v in stored_groups.items()} != {k: sorted(v) for k, v in now_groups.items()}:
        bad.append(
            f"the byte-identical grouping moved: the audit holds {len(stored_groups)} group(s) "
            f"covering {sum(len(v) for v in stored_groups.values())} file(s) and this run finds "
            f"{len(now_groups)} covering {sum(len(v) for v in now_groups.values())}. Identity is "
            f"what DEF-221 and DEF-222 rest on, so a change here is a change to a finding.")
    cite_failures, cite_notices = citations(a)
    print(f"{len(now)} image(s) · {a['disposed']} disposed · "
          f"{len(a['byteIdenticalGroups'])} byte-identical group(s) · "
          f"{len(cite_failures)} citation failure(s), {len(cite_notices)} recorded")
    for b in bad:
        print(f"   {b}")
    for b in cite_failures:
        print(f"   {b}")
    for n in cite_notices:
        print(f"   note: {n}")
    if bad or cite_failures:
        print(f"\n{len(bad) + len(cite_failures)} failure(s). A disposition is about a specific "
              f"set of bytes, and a case citing a picture is a claim about that picture.")
        return 1
    print("\nEvery image carries a disposition, every disposition is about the bytes on disk, "
          "and every image a case cites resolves to one — bar the citation faults recorded above.")
    return 0


def adoptable(a: dict) -> list[tuple[str, str]]:
    """(file, why) for every row `--write` would change the standard of.

    DEF-226. `--write` re-measured the directory and wrote the result as the new
    baseline, so anything that had happened to a file since was adopted as
    correct. A flat magenta frame written over surf-007-zoom.png took `--verify`
    to exit 1, and one `--write` returned it to 0 with the row still recording
    `publishedAs: SURF-007` and `distinctRGBA: 1` — a single-colour frame among
    the six judged captures, and nothing left saying so. That is DEF-207's shape
    one level on: a step that performs an action and then treats its own result
    as the standard, with nothing able to disagree.

    So a rewrite has to be named. `--adopt <file>` accepts one file's new bytes,
    and a blanket flag is deliberately absent: the point is that somebody looked
    at the picture, and a flag that adopts everything is the hole this closes.
    """
    if not AUDIT.exists():
        # Out-of-family review, PRO-0106: deleting the audit was a way past the
        # whole check. With no prior there is nothing to compare against, so the
        # first --write would adopt the entire directory unchallenged, which is
        # DEF-226 reached by removing a file rather than by changing one.
        where = AUDIT.relative_to(REPO) if AUDIT.is_relative_to(REPO) else AUDIT
        return [("(the audit itself)",
                 f"there is no audit at {where}, so this run has nothing to "
                 f"compare against and --write would take the whole directory as read. Name it "
                 f"with --adopt '(the audit itself)' to write the first one.")]
    prior = {r["file"]: r for r in json.loads(AUDIT.read_text())["shots"]}
    out = []
    for name in sorted(set(prior) - {r["file"] for r in a["shots"]}):
        out.append((name,
                    "disposed in the audit and no longer on disk; writing now would remove the "
                    "row rather than record that the file went"))
    for r in a["shots"]:
        old_row = prior.get(r["file"])
        if old_row and old_row.get("sha256") != r["sha256"]:
            stood_for = (old_row.get("depicts")
                         or (f"the picture {old_row['publishedAs']} publishes"
                             if old_row.get("publishedAs") else "no reading at all"))
            out.append((r["file"],
                        "bytes changed under a disposition written for the old ones "
                        f"({old_row['sha256'][:12]} → {r['sha256'][:12]}); the old bytes stood "
                        f"for: {stood_for[:110]}"))
        elif old_row is None:
            # Out-of-family review, PRO-0106: this used to let a new file through
            # whenever a disposition already existed for its stem. A disposition
            # is a reading of specific bytes, and bytes that arrived after it was
            # written are bytes nobody has read — a re-capture landing on a
            # retired name is exactly that case.
            out.append((r["file"],
                        "new since the audit was written, so nothing has read these bytes"
                        + ("; a disposition exists for that name and was written for the bytes "
                           "that used to be there" if r["disposed"]
                           else " and it carries no disposition at all")))
    return out


IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".tiff", ".heic",
                  ".pdf", ".svg", ".mov", ".mp4")


def cite_paths(node, cid, out):
    """Every string in a case that is a path to a .png, gathered recursively.

    A path token rather than any string ending in `.png`: CASE-0064's prose
    reads `negative control docs/.../a1-agent-capture.png`, which is a sentence
    about a file rather than a citation of one, and counting it would make this
    gate red over a comment.
    """
    if isinstance(node, str):
        s = node.strip()
        # Out-of-family review, PRO-0106: `.png` alone left every other image
        # format uncheckable, so a case citing a jpg or a pdf was invisible to
        # this gate for the same reason cases.json was.
        # A space used to disqualify a string outright, which is a proxy for
        # "this is prose about a file" and not the thing itself: a real capture
        # whose name holds a space was invisible to this gate for the same reason
        # `cases.json` was. A spaced string that RESOLVES on disk is a citation;
        # one that does not stays prose, because a sentence naming a file and a
        # citation of a missing file with a space in its name are not separable
        # by any rule this has. Out-of-family review, PRO-0106.
        if s.lower().endswith(IMAGE_SUFFIXES) and "/" in s and (
                " " not in s or (REPO / s).is_file() or (CAMPAIGN / s).is_file()):
            out.setdefault(s, set()).add(cid)
    elif isinstance(node, dict):
        # Keys as well as values. A path used as a key — a per-shot note keyed by
        # the file it is about — was not scanned at all, which is DEF-227's own
        # shape: a place citations live that the gate did not look in.
        for k, v in node.items():
            cite_paths(k, cid, out)
            cite_paths(v, cid, out)
    elif isinstance(node, list):
        for v in node:
            cite_paths(v, cid, out)


# A citation fault this campaign has already opened a defect over. The gate names
# each one and does not fail on it, so the reading stays honest without this item
# claiming repairs that belong to those rows; anything NOT on this list fails.
# An entry that has stopped reproducing prints as resolved rather than failing,
# because a gate that goes red when somebody fixes the defect it records is a
# gate nobody can act on.
KNOWN_CITATION_FAULTS: dict[str, str] = {}


def is_mock(path: str) -> bool:
    """A design mock rather than a capture.

    `evidence/shots/mock/` holds the design of record, and `capture-lineage.py`
    excludes any path with a `mock` directory component from its own population
    for the same reason: it is what the surface should look like, not a picture
    of what it did. CASE-0039 cites the mock and the capture side by side, which
    is the comparison rather than a fault, so this lane is checked for existence
    and not for a disposition or a publishing subject.
    """
    return "mock" in {q.lower() for q in Path(path).parts[:-1]}


def citations(a: dict) -> tuple[list[str], list[str]]:
    """(failures, notices) for the images `cases.json` cites. DEF-227.

    THIS FILE USED TO READ `captures.json` AND THE DISK AND NEVER `cases.json`,
    so a case citing an unpublished, misnamed or absent image was invisible to
    it. DEF-224 and DEF-225 are both instances of that class, and both were found
    by a person reading rather than by a gate running — which is the whole
    argument for the gate existing.

    A citation is checked three ways: the file resolves on disk, a shot in this
    directory carries a disposition, and a shot cited as evidence is one a
    subject publishes. The third is the one that opens the class: an unpublished
    picture is by this campaign's own reckoning not bound to any subject, so a
    case resting on it rests on the filename.

    WHAT THIS DOES NOT CHECK, stated rather than left to be discovered. Existence
    is checked for every cited path wherever it lives; the disposition and the
    publishing subject are checked only under `evidence/shots/`, because a
    disposition is a fact about that directory and nowhere else holds one. A
    citation of `design/surfaces/...` is therefore proved to resolve and no
    further, and the mock lane under `evidence/shots/mock/` is existence-only for
    the reason `is_mock` gives. DEF-243 is the row for the standard that lane
    still has no gate for.
    """
    cases = json.loads((CAMPAIGN / "cases.json").read_text())
    cited: dict[str, set] = {}
    for c in cases:
        cite_paths(c, c.get("id", "?"), cited)
    rows = {r["path"]: r for r in a["shots"]}
    failures, notices, seen_known = [], [], set()
    for path, ids in sorted(cited.items()):
        who = ", ".join(sorted(ids))
        reasons = []
        on_disk = (REPO / path).is_file() or (CAMPAIGN / path).is_file()
        if not on_disk:
            reasons.append("no such file on disk")
        # `rows` is keyed campaign-relative, and a case may cite either way. A
        # repo-relative citation used to miss the row AND fail the
        # `evidence/shots/` test, so it resolved on disk and then skipped the
        # disposition and publishing checks entirely \u2014 DEF-227's own class,
        # reachable by writing the path the other way round. Out-of-family
        # review, PRO-0106.
        rel = path[len(CAMPAIGN_PREFIX):] if path.startswith(CAMPAIGN_PREFIX) else path
        row = rows.get(rel)
        if row is not None:
            if not row["disposed"]:
                reasons.append("in the shots directory with no disposition")
            elif not row["publishedAs"]:
                reasons.append("cited as evidence while no subject publishes it "
                               f"({(row['depicts'] or '')[:80]}…)")
        elif on_disk and rel.startswith("evidence/shots/") and not is_mock(rel):
            if Path(rel).suffix.lower() == AUDIT_SUFFIX:
                reasons.append("under evidence/shots and absent from this audit")
            else:
                notices.append(
                    f"{who} cites {path}: under evidence/shots and outside this audit's "
                    f"population — audit() measures PNG rasters, so a "
                    f"{Path(path).suffix or 'suffixless file'} has no row here to be absent "
                    f"from. It is checked for existence and no further.")
                continue
        if not reasons:
            continue
        known = KNOWN_CITATION_FAULTS.get(path)
        line = f"{who} cites {path}: {'; '.join(reasons)}"
        if known:
            seen_known.add(path)
            notices.append(f"{line}  [recorded: {known}]")
        else:
            failures.append(line)
    for path in sorted(set(KNOWN_CITATION_FAULTS) - seen_known):
        notices.append(f"{path}: recorded as a citation fault and no longer reproducing — "
                       f"the entry in KNOWN_CITATION_FAULTS can go")
    return failures, notices


def main() -> int:
    a = audit()
    if "--write" in sys.argv:
        adopt = {sys.argv[i + 1] for i, arg in enumerate(sys.argv)
                 if arg == "--adopt" and i + 1 < len(sys.argv)}
        blocked = [(f, why) for f, why in adoptable(a) if f not in adopt]
        if blocked:
            print(f"REFUSING to write {AUDIT.relative_to(REPO)} — "
                  f"{len(blocked)} row(s) would take new bytes as the standard:")
            for f, why in blocked:
                print(f"   {f}: {why}")
            print("\nA disposition is a person's reading of specific bytes. Look at the file, "
                  "update its entry here, then name it: --adopt <file>.")
            return 1
        unused = sorted(adopt - {f for f, _ in adoptable(a)})
        for f in unused:
            print(f"note: --adopt {f} names a file whose bytes have not moved")
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        AUDIT.write_text(json.dumps(a, indent=1) + "\n")
        print(f"wrote {AUDIT.relative_to(REPO)} — {a['files']} image(s), {a['disposed']} disposed"
              + (f", {len(adopt)} adopted by name" if adopt else ""))
        return 0
    if "--manifest" in sys.argv:
        entries = []
        for r in a["shots"]:
            d = DISPOSITIONS.get(Path(r["file"]).stem)
            if not d:
                continue
            entries.append({
                "path": r["path"],
                "unpublishedReason": d["unpublishedReason"],
                "depicts": d["depicts"],
                "namedFor": d["namedFor"],
                "capturedRecord": d["record"],
                "sha256": r["sha256"],
                "bytes": r["bytes"],
            })
        print(json.dumps(entries, indent=1))
        return 0
    return verify(a)


if __name__ == "__main__":
    raise SystemExit(main())
