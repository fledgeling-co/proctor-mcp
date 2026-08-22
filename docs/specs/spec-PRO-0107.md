# PRO-0107: Thirty-five pictures the gate cannot see

**ID:** PRO-0107
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/100-a-screenshot-gallery-the-gate-cannot-see.md`
**Defects:** DEF-209, DEF-218..DEF-223

## Feature description

`capture-lineage.py --gate` exits 2 on `main`: 43 files in the shots directory against 8 published
captures, so 35 images are unaccounted — nothing publishes them and no manifest entry names them.

## What and why

The gate's own reasoning is that every finding it makes is derived from published captures, so a file
nobody publishes is a capture it cannot see; it cites a campaign that read `published captures: 0 ·
files in shots dir: 11` and exited 0. Thirty-five unpublished images are pictures a reader takes as
evidence and the instrument cannot speak for.

This is **tool movement, not a regression**, established by holding the tool constant across three
trees: identical reading at `dd1a443`, `eed148f` and `3d6fb15`, the last predating this session. The
ratchet holds at 6.

## Acceptance sketch

- Every one of the 35 files has a disposition: published into the manifest with the subject it shows,
  or an `unpublishedReason` on its `captures.json` entry.
- `capture-lineage.py --gate` exits 0 **because the population is accounted for**, not because it
  shrank — the published count rises or each exclusion carries a reason.
- The ratchet is raised only by what the change actually earns.

## Assumptions made writing this

- Assuming deletion is not the default remedy, though the tool offers it: discarding evidence to clear
  a gate is the move this campaign refuses, and a surface capture nobody published is evidence
  somebody meant to keep.
- Assuming the surface-shaped names (`surf-001` … `surf-016`) mean these are real captures from earlier
  waves rather than debris, which makes the recoverable disposition the likely one.


## What was delivered

Every one of the 35 was opened and looked at. The disposition for all 35 is an `unpublishedReason` on
its `captures.json` entry, and nothing was published, because publishing needs a target recorded at
the shutter and none of the 35 has one — writing that target now is a manifest written after the fact,
which is the pass this gate exists to refuse. Nine of them have no subject to be published under at
all.

| | Before | After |
|---|---|---|
| Published captures | 8 | 8 |
| Files in the shots directory | 43 | 43 |
| UNACCOUNTED | 35 | 0 |
| Declared unpublished with a reason | 0 | 35 |
| Files deleted | — | 0 |
| `capture-lineage.py --gate` | exit 2 | **exit 0** |
| Judged / judgeable | 6 of 8 | 6 of 8 |
| Ratchet | 6 | **6, not raised** |

**The ratchet was not raised, and that is what the change earned.** A ratchet pins judged captures.
No capture became judgeable here and none was judged, so a raise would record a bar that nothing new
passed under. The two unjudged captures are still SURF-006 and SURF-007, which `pairs.json` records as
structurally unjudgeable capture engines.

**Nothing was deleted, and both tests that would have licensed it were applied.** No file is zero
bytes — the smallest is 10,680. No byte-identical group contains a published file, so no member is an
exact duplicate of something already shown. Three of the four groups are themselves the evidence for
DEF-221 and DEF-222, so deleting a member would have deleted the finding.

## The finding the disposition produced

The brief assumed the surface-shaped names meant real captures from earlier waves. That was wrong for
nine of them, and the assumption is the reason nobody had looked.

- **Nine files named for nine engine surfaces are app-icon renders.** `surf-001-mcp-stdio`,
  `surf-002-tool-catalogue`, `surf-003-process-directed`, `surf-011-stability`, `surf-012-audit-policy`,
  `surf-013-guest-provider`, `surf-014-ios-maestro`, `surf-015-reflector` and `surf-016-install-notarize`
  every one show the Proctor icon's dark window dissolving into orange squares at exactly 1024x1024.
  The mechanism is a copy statement rather than a misfiling: `scripts/build_test_campaign.py:282-296`
  copies `design/icon/audit-renders/*` and `design/icon/runs/*/candidate-1024.png` into the shots
  directory under surface-shaped destination names, and `surf-016-install-notarize.png` is byte-identical
  to `design/icon/icon-proctor-1024.png`. DEF-218.
- **`sweepL-status-agent-down.png` depicts a Ready window.** Green Ready pill, both grants Granted,
  "Ready. Every permission Proctor needs is granted." The frames that do show `Agent down` are the
  `-t0.6` and `-t3.5` files beside it, and those two are byte-identical to each other. DEF-222.
- **One image carries three captions across two unrelated sweeps.** `sweepK-theme-before.png`,
  `sweepL-wedged-t1.png` and `sweepL-wedged-recovered.png` are one file. A recovery the sweep records as
  true is shown by the same bytes as the frame before it. `sweepL-wedged-t7` and `-t14` are likewise one
  picture. DEF-221.
- **Three files named for the takeover shield contain no image**: 0 non-transparent pixels of
  14,745,600, 7,720,704 and 677,888, one distinct RGBA each. Their own record already calls them
  `framesThatWereNotEvidence`; nothing in the gallery said so. DEF-219.
- **`sweepK-scaling.json` lists two frames its own mode table has no capture of**: both are 900x833
  against measured sizes 970x773, 820x654, 970x773 and 781x961, and no file in the directory is
  781x961. DEF-220.
- **Two files' surface prefixes name a surface the picture does not show**: `surf-004-drawn-pointer.png`
  is the pointer glyph alone with no Run HUD in it, and `surf-008-about.png` is the About panel rather
  than the status window. DEF-223.

## How it is kept honest

`scripts/campaign/shot_disposition.py` holds the 35 dispositions and splits each in two: `depicts`,
read by opening the file, and the measurements — dimensions, bytes, sha256, opaque-pixel count,
distinct-RGBA count — which it re-derives. Run with no flags it fails on an image with no disposition,
a disposition whose file is gone, and a file whose bytes moved under a disposition written for the old
ones. `--write` regenerates `evidence/PRO-0107/shot-audit.json`; `--manifest` emits the
`captures.json` entries so the manifest, the registry and this spec quote one sentence rather than
three paraphrases.

Both new checks were watched to fail, and each mutation was confirmed landed before its verdict was
read. Removing one `unpublishedReason` returned the gate to exit 2 naming that file; replacing one
sha256 in the audit returned `shot_disposition.py` to exit 1 naming that file. Both restored, both
reproducing the passing reading.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-209 | Thirty-five images in the shots directory that nothing publishes and no manifest names | fixed |
| DEF-218 | Nine files named for nine engine surfaces are app-icon renders (recorded) | open |
| DEF-219 | Three files named for the takeover shield contain no image at all (recorded) | open |
| DEF-220 | sweepK-scaling.json lists two frames its own mode table has no capture of (recorded) | open |
| DEF-221 | One image carries three captions across two unrelated sweeps (recorded) | open |
| DEF-222 | sweepL-status-agent-down.png depicts a Ready window (recorded) | open |
| DEF-223 | A file's surface prefix binds it to a surface the picture does not show (recorded) | open |

## Registry

REQ-111, REQ-112, REQ-113 · CASE-0472 to CASE-0478 · SURF-027 · DEF-218 to DEF-223.
