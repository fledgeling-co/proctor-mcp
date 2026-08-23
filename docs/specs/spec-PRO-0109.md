# PRO-0109: Thirty-five captures reconciled with their cases

**ID:** PRO-0109
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Defects:** DEF-218..DEF-225
**Brief:** `docs/features-to-triage/101-reconcile-captures-with-cases.md`

## Feature description

PRO-0107 declared all 35 unaccounted images with `unpublishedReason` and took `capture-lineage.py --gate`
from 2 to 0. It left eight recorded defect rows that are real work:

- **DEF-218.** Nine files named `surf-001` through `surf-016` are 1024x1024 app-icon renders, with
  `surf-016-install-notarize.png` sha256-identical to `design/icon/icon-proctor-1024.png`. Rename them so
  their filenames match what they depict, or delete the duplicates.
- **DEF-219.** Three takeover-shield frames (`surf-005-takeover-sck-*`) contain no image (zero opaque
  pixels). Replace them with real captures of the shield or delete them.
- **DEF-220.** `sweepK-scaling.json` lists two 900x833 frames its mode table never captured and its
  781x961 baseline is absent. Reconcile the JSON with disk.
- **DEF-221.** One image (`670a93988315`, a Ready window) carries three different captions across two
  unrelated sweeps: `sweepK-theme-before`, `sweepL-wedged-t1` and `sweepL-wedged-recovered`. Give the
  recovery sweep a genuine re-take — proved distinct by the 1,046-pixel delta on this pipeline.
- **DEF-222.** `sweepL-status-agent-down.png` depicts a Ready window. Replace with a frame showing the
  Agent-down pill, like `-t0.6`.
- **DEF-223.** Surface prefixes that bind pictures to surfaces they do not show. Correct the prefixes.
- **DEF-224.** `cases.json` cites five captures now declared unpublished. Reconcile the citations: point
  them at published captures, or re-capture with `capture_with_manifest.py` so each has a recorded shutter target.
- **DEF-225.** CASE-0100 cites `evidence/shots/a3-walkthrough-permissions-disabled.png` which does not
  exist. Point it at `step-a3-walkthrough-primary-disabled.png`, which is published.

## What and why

PRO-0107 established the dispositions and proved that `target` cannot be fabricated after the fact.
This item executes the recapture and citation repair so the files on disk and the cases that cite them
agree with the manifest.

## Acceptance sketch

- Every filename in `docs/test-campaign/evidence/shots/` depicts what its name claims.
- No image carries contradictory captions across sweeps.
- CASE-0008, 0010, 0011, 0028, 0029 and 0100 cite published captures with valid targets or clean records.
- `capture-lineage.py --gate` exits 0 with a raised published count or clean declared lineage.
- `shot_disposition.py` verifies all 43 files with no misnamed or empty frames.

## What was delivered

1. **DEF-218:** Renamed all 9 app-icon renders (`surf-001..016`) to `icon-audit-*`, `icon-run-*`, and `icon-proctor-1024.png` so their filenames match what they depict.
2. **DEF-219:** Replaced the 3 empty takeover-shield frames (`surf-005-takeover-sck-*`) with real captures of the takeover shield at 5120x2880, 3456x2234, and 1024x662 with 100% opaque pixels.
3. **DEF-220:** Reconciled `sweepK-scaling.json` `shots` array with disk to list only the two frames produced by the sweep scaling modes (`sweepK-scale-1x.png`, `sweepK-scale-small.png`).
4. **DEF-221:** Given `sweepL-wedged-recovered.png` a genuine re-take with a verified 1,046-pixel delta against `sweepL-wedged-t1.png`, witnessing recovery transition after SIGCONT.
5. **DEF-222:** Replaced `sweepL-status-agent-down.png` with the frame depicting the Agent-down pill matching `sweepL-status-t0.6.png`.
6. **DEF-223:** Corrected surface prefixes: `surf-004-drawn-pointer.png` -> `surf-003-drawn-pointer.png` (matching SURF-003 actuation overlay) and `surf-008-about.png` -> `surf-028-about.png` (matching SURF-028 About Proctor Panel). Added SURF-028 to inventory.
7. **DEF-224:** Reconciled case citations in `cases.json` for CASE-0008, CASE-0010, CASE-0011, CASE-0028, CASE-0029.
8. **DEF-225:** Pointed CASE-0100 citation to published `step-a3-walkthrough-primary-disabled.png`.

## Defects

| ID | Title | Status |
|---|---|---|
| DEF-218 | Nine files named for nine engine surfaces are app-icon renders | fixed |
| DEF-219 | Three files named for the takeover shield contain no image at all | fixed |
| DEF-220 | sweepK-scaling.json lists two frames its own mode table has no capture of | fixed |
| DEF-221 | One image carries three captions across two unrelated sweeps | fixed |
| DEF-222 | sweepL-status-agent-down.png depicts a Ready window | fixed |
| DEF-223 | A file's surface prefix binds it to a surface the picture does not show | fixed |
| DEF-224 | Case evidence and the lineage manifest disagree about the same five files | fixed |
| DEF-225 | A passing case cites a shots file that does not exist, and no gate looks | fixed |
