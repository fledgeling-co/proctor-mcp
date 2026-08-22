# PRO-0107: Thirty-five pictures the gate cannot see

**ID:** PRO-0107
**Status:** Ready for Plan
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/100-a-screenshot-gallery-the-gate-cannot-see.md`

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

## Defects

DEF-209.
