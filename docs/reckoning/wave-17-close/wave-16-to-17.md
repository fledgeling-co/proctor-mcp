# Reckoning delta — proctor-mcp

`2bdc808` (reckon 1.1.0) → `ad0c196` (reckon 1.2.0), attribution **decomposed**.

## What moved

**3 of 5 axes improved, 2 flat, 0 worsened; evidence work up at 39 and the unmeasured class larger at 39 rows.**

| Axis | Was (same tool) | Now | Move | Reading |
|---|---|---|---|---|
| Cases adjudicated | 289/293 (98.6%) | 396/400 (99.0%) | +0.4 pts | better; denominator moved 293 → 400 |
| Cases ruled out by decision | 0/293 (0.0%) | 0/400 (0.0%) | +0.0 pts | flat; denominator moved 293 → 400 |
| Requirements observed | 63/90 (70.0%) | 89/116 (76.7%) | +6.7 pts | better; denominator moved 90 → 116 |
| Surfaces spoken for | 23/23 (100.0%) | 27/27 (100.0%) | +0.0 pts | flat; denominator moved 23 → 27 |
| Briefs joined to evidence | 16/96 (16.7%) | 21/100 (21.0%) | +4.3 pts | better; denominator moved 96 → 100 |

**The class this exists for.** `unmeasured` went 36 → 39 rows under a constant tool (worse). 0 row(s) left it, 1 entered. The published baseline recorded 36; the difference between that and the control column is the tool, not the project. The ratchet below is what says the rows that left were measured rather than reclassified.

## Where the movement came from

The two readings were taken with different versions of the reckoning tool, so the published ledgers are not directly comparable: part of any difference is the tool learning to read this registry. The earlier run's own inputs were rebuilt at its own commit (`2bdc808`) with the current tool, and that control is what the current reading is differenced against. **Only the project column is progress.**

| Count | Previous (as published) | Control (same tree, current tool) | Current | Tool moved | Project moved |
|---|---:|---:|---:|---:|---:|
| Work items | 134 | 134 | 150 | 0 | +16 |
| · product | 10 | 10 | 24 | 0 | +14 |
| · evidence | 36 | 36 | 39 | 0 | +3 |
| · decision | 88 | 88 | 87 | 0 | -1 |
| Ledger rows | 620 | 620 | 796 | 0 | +176 |

## The ratchet

An item may leave `unmeasured` only by being measured. This is the check the second run exists to turn on: a snapshot gate catches a bad run, and this catches the slow version, where a row is quietly reclassified across runs until nothing remembers it was never checked.

| Pair | From | To | Exit | Verdict |
|---|---|---|---:|---|
| published | 2bdc808 | ad0c196 | 0 | clean |
| tool-constant | 2bdc808 (rebuilt) | ad0c196 | 0 | clean |

## Rows that changed class (4), appeared (176), vanished (0)

Tool held constant, so each of these is the project moving.

| Row | Was | Now | What |
|---|---|---|---|
| `BRIEF-96-what-1-1-0-still-groups-and-still-grades` | `unjoined` | `unmeasured` | What 1.1.0 still groups, and what it still lets a citation grade |
| `DEF-200` | `broken` | `verified-done` | CASE-0392 records armed: false with a reason the verification disproved |
| `DEF-201` | `broken` | `verified-done` | A quoted placeholder id is read as a citation at confidence 1.0 |
| `DEF-202` | `broken` | `verified-done` | An unrecognised status word decides the headline, and it can fail in either direction |

**New rows (176):** 17 `broken`, 2 `unmeasured`, 157 `verified-done`.

New rows that are not already done — the ones a reader schedules: `BRIEF-100-a-screenshot-gallery-the-gate-cannot-see` (`unmeasured`), `BRIEF-97-an-input-the-check-cannot-classify` (`unmeasured`), `BRIEF-98-a-version-string-is-not-the-artifact` (`broken`), `BRIEF-99-instruments-that-do-not-prove-their-own-step` (`broken`), `DEF-204` (`broken`), `DEF-215` (`broken`), `DEF-216` (`broken`), `DEF-218` (`broken`), `DEF-219` (`broken`), `DEF-220` (`broken`), `DEF-221` (`broken`), `DEF-222` (`broken`), `DEF-223` (`broken`), `DEF-224` (`broken`), `DEF-225` (`broken`), `DEF-228` (`broken`), `DEF-229` (`broken`), `DEF-230` (`broken`), `DEF-243` (`broken`)

## What each side of this comparison carries

- *previous* — Taken at wave 16's close-in-progress rather than after it: PRO-0101 had not merged when this was read, so its REQ-100/101, CASE-0430-0440, DEF-215 and SURF-024 are not in this tree.
- *previous* — PRO-0103's own campaign rows (REQ-102-107, CASE-0441-0456, DEF-216, SURF-025) land two commits after this reading and are not in it. They will appear as movement at the next wave close.
- *current* — Wave 17 close. Fourth reading. Both vocabulary violations from the first reading were this session's own errors and are now at their rows: REQ-072's evidence word is unknown, the planted CASE-9999 sits in a fence. Compare against 2026-08-22-2bdc808.

## Totals, last

Read these second. A total says how much there is; the tables above say whether it is moving, and only the second question needs two runs.

| Class | Previous | Control | Current |
|---|---:|---:|---:|
| `broken` | 10 | 10 | 24 |
| `undecided` | 8 | 8 | 8 |
| `unjoined` | 80 | 80 | 79 |
| `unmeasured` | 36 | 36 | 39 |
| `verified-done` | 486 | 486 | 646 |

