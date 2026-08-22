# A version string is not the artifact

**Wave 17, brief 2.** DEF-216, DEF-204. Two defects, one evening, and the second is the first with
the lesson not yet learned.

## What happened

PRO-0102 repaired `reckon`, moved `plugin.json` to 1.1.0 and brought the marketplace entry with it.
Both were verified. **Neither is the artifact that runs.**

| Probe | Installed cache | Source |
|---|---|---|
| Directory | `~/.claude/plugins/cache/fledgeling-plugins/reckon/**1.0.0**/` — no 1.1.0 exists | `~/Dev/fledgeling-plugins/plugins/reckon` |
| `grep -c unjoined reckon.py` | **0** | **14** |
| `tokens()` on a list | `AttributeError: 'list' object has no attribute 'lower'` | 3 tokens, via `flatten_text` |

The cached copy is the pre-fix classifier, not fixed code wearing a stale label. That is **DEF-216**.

**DEF-204** is the same error inside the repair for it. `reckoning.py`'s `compare` refuses a tool on
disk that is not the one that took the current reading — and keys the refusal on a declared version
string. The relabelled 1.0.0 cache is caught, but by a class-vocabulary check rather than by the
version. The **real** 1.1.0 source, `CLASSES` and `ratchet` intact, `classify()` altered to
reclassify `unjoined` as `verified-done`, manifest reading 1.1.0, was **accepted at exit 0** — and the
published delta silently became −163 tool / +79 project against a true −88 / +4. `run.json` already
records `tool.source_commit`. `compare` never reads it.

## The rule

> **When a version string is what goes wrong, a version string cannot be the test.**

The check that settles DEF-216 is `grep -c unjoined <the reckon.py that will actually run>`: 14 is
the repair, 0 is the old classifier. The check that settles DEF-204 is already recorded and unread —
compare `source_commit`, or hash the file.

## Who is exposed, and how loudly

**Per row, not per project.** A project is loud if **at least one** row is list-valued and silent only
if **none** is. This repository has 304 of 304 cases carrying list-valued evidence, so it gets the
crash — impossible to mistake for an answer. A registry of all-string evidence gets the silent
version: the pre-fix classifier, every defect row hardcoded to `broken`, and a fabricated backlog.
**A reproduction asserting at project granularity passes on a project that is half broken**, because
the crash announces the first list-valued row it reaches and says nothing about the string-valued
rows already misclassified behind it.

## What this asks for

1. Refresh the plugin cache, and make the refresh checkable by content rather than by version.
2. Teach `compare` to read the `source_commit` it already records.
3. Anywhere else a tool's identity gates a decision, identify it by content.
