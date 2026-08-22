# PRO-0105: A version string is not the artifact

**ID:** PRO-0105
**Status:** Ready for Plan
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/98-a-version-string-is-not-the-artifact.md`

## Feature description

`reckon` was repaired, `plugin.json` moved to 1.1.0, the marketplace entry followed, and both were
verified. Neither is the artifact that runs: the installed cache is still `reckon/1.0.0/`, its
`reckon.py` has **0** occurrences of `unjoined` against the source's **14**, and its `tokens()` raises
`AttributeError: 'list' object has no attribute 'lower'` where the source returns three tokens.
That is DEF-216. DEF-204 is the same error inside the repair for it: `compare` refuses a tool that is
not the one which took the current reading, keyed on a declared version string — so genuinely altered
1.1.0 code was accepted at exit 0 and published −163 tool / +79 project against a true −88 / +4.

## What and why

> **When a version string is what goes wrong, a version string cannot be the test.**

`run.json` already records `tool.source_commit` and `compare` never reads it, so half the repair is
reading a field the instrument already writes.

## Acceptance sketch

- The plugin cache runs the repaired classifier, and the check that proves it reads **content** —
  `grep -c unjoined` on the file that will actually run, 14 for the repair and 0 for the old one.
- `compare` identifies a tool by content or by `source_commit`, not by its manifest version, and
  refuses altered code at a matching version.
- Anywhere else a tool's identity gates a decision, it is identified by content.

## Assumptions made writing this

- Assuming the exposure statement is **per row**: a project is loud if at least one row is list-valued
  and silent only if none is, so a reproduction asserting at project granularity passes on a project
  that is half broken.
- Assuming refreshing the plugin cache is the reader's action rather than this item's, since it is
  another session's installed state.

## Defects

DEF-204, DEF-216.
