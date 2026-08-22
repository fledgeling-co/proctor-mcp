# PRO-0107: Thirty-five pictures the gate cannot see

**ID:** PRO-0107
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/100-a-screenshot-gallery-the-gate-cannot-see.md`
**Defects:** DEF-209, DEF-218..DEF-225

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
| DEF-224 | Case evidence and the lineage manifest disagree about the same five files (recorded) | open |
| DEF-225 | A passing case cites a shots file that does not exist, and no gate looks (recorded) | open |

## Gates

| Gate | Exit |
|---|---|
| `capture-lineage.py docs/test-campaign --gate` | **0** — 43 files, 8 published, `COUNTED APART (35)`, judged 6 of 8, ratchet 6 held (was **2** with 35 hard failures) |
| `defect_gate.py claims docs/specs/spec-PRO-0107.md docs/test-campaign` | **0** — claims DEF-209, 8 recorded and not checked |
| `defect_gate.py dropped docs/test-campaign` | **0** — 2 files, 120 merges, 55,908 pairs |
| `test_instruments.py` | **0** — 62 passed |
| `spec_citation_measure.py` | **0** — 15/15, unclaimed briefs 0, specs 104 |
| `shot_disposition.py` (this item's own) | **0** — 43 disposed, 4 byte-identical groups |
| `campaign.py check docs/test-campaign` | 1 on head and on merge base, **blocker sets identical**, naming none of this item's ids |
| `./scripts/test.sh` | **0** — `Test run with 2074 tests in 252 suites passed after 18.008 seconds`, the `main` baseline exactly. A control: no Swift changed |

The suite took five attempts to be admitted, and what blocked it was berth accounting rather than
capacity: `available 0`, `in_use 12`, `ceiling 12`, twelve berths held at weight 6 by two other
projects with every claimant alive, while `load_per_core` read **0.63** and pressure read `healthy`.
Admitted on the fifth at `available 6`. Another reading in the direction this file already records:
`available` is authoritative as an admission predicate and worthless as a load proxy, and this time the
machine was idle while nothing could be granted.

## Out-of-family review — 2026-08-23

`gemini-3.7-flash-high` via `agy --new-project` from `/tmp`, answering about PRO-0107 by name and
citing this worktree's own paths, so the lane was on subject. It agreed with all four calls — the
declaration is the only disposition consistent with the instrument's rules, refusing to publish was
right, the ratchet earned no raise, and none of the six findings is overclaimed — and on the fifth
question it found something this item had produced and not recorded.

**Its finding, confirmed against `cases.json` rather than taken on its word.** `capture-lineage` reads
only the `shot` field on subjects; `cases.json` cites shots directly in `evidence`, and the two
registries now disagree about five files. CASE-0008, CASE-0010 and CASE-0011 are **raster-visual passes
citing captures this item declares unpublished** — `surf-004-run-hud.png`,
`surf-005-takeover-shield.png`, `surf-008-tools.png`. The review's phrasing needs one correction:
each of those three does carry a case-level `capture.method`, so the channel is named and what is
missing is the shutter-recorded target. CASE-0028 and CASE-0029 cite frames DEF-222 and DEF-221 show
misnamed or byte-duplicated, and both verdicts rest on their sweep JSON rather than on the frames.
DEF-224.

Confirming it turned up one more. **CASE-0100 cites `evidence/shots/a3-walkthrough-permissions-disabled.png`
and no such file exists.** Both instruments pass over it: `campaign.py` resolves an evidence path only
on the raster rungs and CASE-0100 stands at effect-witness, and `capture-lineage` never reads
`cases.json`. DEF-225.

## Registry

REQ-111, REQ-112, REQ-113 · CASE-0472 to CASE-0480 · SURF-027 · DEF-218 to DEF-225.

## Verification — 2026-08-23, `Needs More Work` on one claim, then corrected

Every gate reads as claimed and the disposition work is sound. The verdict turned on the item's
**mechanism** finding, which was false in the direction that matters, and it is corrected above.

`capture-lineage.py --gate` **0** on head against **2** at merge base, same 43 files / 8 published /
judged 6 of 8 / ratchet 6. `shot_disposition.py` **0** over 43 images with 4 byte-identical groups.
`defect_gate.py` claims **0** and dropped **0** (120 merges, 55,908 pairs), **2** bare.
`test_instruments.py` **0**. `spec_citation_measure.py` **0**. `campaign.py check` **1** on head and
base with identical blocker sets, the diff five count lines. `./scripts/test.sh` **0** at 2,074 tests in
252 suites — the baseline exactly. `capture-lineage.py` is md5-identical across test-campaign 0.9.6 and
0.9.9, so no further tool movement is pending on this gate. Five mutations re-applied, each confirmed
landed before its verdict was read, each restored.

### The mechanism was dead code, and that is worse than no row

`build_test_campaign.py` **will not do it again.** Line 26 is a module-level `sys.exit()`, and lines
282-296 sit inside a retired-original raw string; an AST parse finds no `src_assets` assignment and no
loop over one. This spec, DEF-218's note and `ORCHESTRATOR.md` all stated the mechanism in the present
tense and named removal of the copy list as the repair — **directing future work at dead code**, so
somebody would have deleted a retired docstring and recorded a fix.

The live falsehood is one line up, in that retirement docstring: *"Every one of those files has been
replaced by the output of a real tool call."* Nine were not. That sentence is what a check could read,
and it is why the mechanism looked live: the file says the problem was already fixed.

### Two judgements upheld

**Publishing nothing was right.** `target` is a claim about what the capture channel was pointed at,
not a caption. Inspection settles the *subject* and cannot settle the *target* —
`overlay-capture-lifted.json` records bounds, layer 25, `sharingState 1`, 704x460 and 2,517 colours,
and no window id. So even for `surf-004-run-hud.png`, confirmed by eye to be the Run HUD, a target
written now would be invention. The accepted cost is that raster coverage reads lower than the disk
supports, and the proper route (`capture_with_manifest.py`) is named and rowed.

**No verdict is void.** The concern was that `raster-visual` passes were standing on pictures of the
wrong thing. They are not: the three cited pictures each depict their named subject on inspection, and
each carries `capture.method` and `frameStatus: complete`. CASE-0028 and CASE-0029 are `outcome` cases
resting on sweep JSON that exists, with CASE-0028's Ready frame as its own control; CASE-0100 is
`effect-witness` on two JSONs that exist. Every case's oracle rung is intact — **the faults are
citations, and citation repair is not a status change.** DEF-224 and DEF-225 were the right disposition.

### A control the item lacked, which strengthens DEF-221

`sweepK-theme-before` against `-restored` — the same appearance, re-taken — differ in **1,046 pixels**.
So this pipeline does not emit byte-identical re-takes, and three identical frames across two unrelated
sweeps is **reuse rather than determinism**. That closes the one benign reading the finding had.

### The lane failed, so this item has no out-of-family verdict

Gemini refused twice — from `/tmp` with a fresh project and from an empty directory — with
`user denied permission` on its own `git branch -a` and `find` probes, returning 0 bytes. grok is at
402; codex is off. The fallback to `claude-fable-5` is same-family and, worse, **it read the merge base
rather than the branch**, describing `captures.json` as 405 lines with no `unpublishedReason`, which is
exactly the base — so its verdict was off-tree and discarded. Two tree-independent readings in it were
worth keeping: it overturned the verifier's own first reading of the retirement, and its
translucent-shield rebuttal was wrong, conflating the empty frames with the real shield.

**So this item is verified in-family only, and that is a logged downgrade rather than a pass.** It is a
direct consequence of leaving the lane's permissions flag unsettled, which is the reader's call and is
recorded rather than worked around.

### Four smaller findings, routed

- **DEF-226**, opened here: `shot_disposition.py --write` adopts any new content as the baseline. A flat
  magenta frame written over `surf-007-zoom.png` took the check to 1, and `--write` returned it to 0
  with the row keeping `publishedAs: SURF-007` and recording `distinctRGBA: 1` — a single-colour frame
  among the six judged. DEF-207's shape one level on.
- **DEF-225's repair is one line** and the row now says so:
  `step-a3-walkthrough-primary-disabled.png` exists and is published.
- The eight published files carry `depicts: null`; the read-by-eye record covers only the 35, and the
  eight are exactly what the ratchet pins.
- `sweepL-halfopen.json` cites a `statusShot` under `/tmp/campaign-run/` with no counterpart in
  `evidence/`, which no gate reads. CASE-0479 and CASE-0480 carry `armed: false` without the in-note
  declaration the other unarmed new cases have.
