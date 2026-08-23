# Reckoning delta — proctor-mcp

`7674c7f` (reckon 1.2.0) → `ad0c196` (reckon 1.2.0), attribution **direct**.

## What moved

**0 of 5 axes improved, 5 flat, 0 worsened; evidence work flat at 39 and the unmeasured class flat at 39 rows.**

| Axis | Was (same tool) | Now | Move | Reading |
|---|---|---|---|---|
| Cases adjudicated | 396/400 (99.0%) | 396/400 (99.0%) | +0.0 pts | flat |
| Cases ruled out by decision | 0/400 (0.0%) | 0/400 (0.0%) | +0.0 pts | flat |
| Requirements observed | 89/116 (76.7%) | 89/116 (76.7%) | +0.0 pts | flat |
| Surfaces spoken for | 27/27 (100.0%) | 27/27 (100.0%) | +0.0 pts | flat |
| Briefs joined to evidence | 21/100 (21.0%) | 21/100 (21.0%) | +0.0 pts | flat |

**The class this exists for.** `unmeasured` went 39 → 39 rows under a constant tool (flat). 0 row(s) left it, 0 entered. The published baseline recorded 39; the difference between that and the control column is the tool, not the project. The ratchet below is what says the rows that left were measured rather than reclassified.

## Where the movement came from

Both readings were taken with reckon 1.2.0, so the difference is the project's alone and no control was needed.

| Count | Previous (as published) | Control (same tree, current tool) | Current | Tool moved | Project moved |
|---|---:|---:|---:|---:|---:|
| Work items | 150 | 150 | 150 | 0 | 0 |
| · product | 24 | 24 | 24 | 0 | 0 |
| · evidence | 39 | 39 | 39 | 0 | 0 |
| · decision | 87 | 87 | 87 | 0 | 0 |
| Ledger rows | 796 | 796 | 796 | 0 | 0 |

## The ratchet

An item may leave `unmeasured` only by being measured. This is the check the second run exists to turn on: a snapshot gate catches a bad run, and this catches the slow version, where a row is quietly reclassified across runs until nothing remembers it was never checked.

| Pair | From | To | Exit | Verdict |
|---|---|---|---:|---|
| published | 7674c7f | ad0c196 | 0 | clean |

## Rows that changed class (0), appeared (0), vanished (0)

Tool held constant, so each of these is the project moving.

## What each side of this comparison carries

- *previous* — Wave 17 close, third reading. First named two unclassifiable inputs; both were this session's own vocabulary errors and are corrected at their rows. Compare against 2026-08-22-2bdc808 for the wave-16 delta.
- *current* — Wave 17 close. Fourth reading. Both vocabulary violations from the first reading were this session's own errors and are now at their rows: REQ-072's evidence word is unknown, the planted CASE-9999 sits in a fence. Compare against 2026-08-22-2bdc808.

## Totals, last

Read these second. A total says how much there is; the tables above say whether it is moving, and only the second question needs two runs.

| Class | Previous | Control | Current |
|---|---:|---:|---:|
| `broken` | 24 | 24 | 24 |
| `undecided` | 8 | 8 | 8 |
| `unjoined` | 79 | 79 | 79 |
| `unmeasured` | 39 | 39 | 39 |
| `verified-done` | 646 | 646 | 646 |

