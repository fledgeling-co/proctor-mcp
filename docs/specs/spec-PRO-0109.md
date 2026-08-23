# PRO-0109: Thirty-five captures reconciled with their cases

**ID:** PRO-0109
**Status:** Ready for Plan
**Created:** 2026-08-23
**Last updated:** 2026-08-23
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
- CASE-0008, 0010, 0011, 0028, 0029 and 0100 cite published captures with valid targets.
- `capture-lineage.py --gate` exits 0 with a raised published count.
- `shot_disposition.py` verifies all 43 files with no misnamed or empty frames.

## Defects

DEF-218, DEF-219, DEF-220, DEF-221, DEF-222, DEF-223, DEF-224, DEF-225.
