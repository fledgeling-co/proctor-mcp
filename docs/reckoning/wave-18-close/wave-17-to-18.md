# Reckoning delta — proctor-mcp

`ad0c196` (reckon 1.2.0) → `68431dc` (reckon 1.2.0), attribution **decomposed**.

## What moved

**3 of 5 axes improved, 2 flat, 0 worsened; evidence work up at 37 and the unmeasured class larger at 37 rows.**

| Axis | Was (same tool) | Now | Move | Reading |
|---|---|---|---|---|
| Cases adjudicated | 396/400 (99.0%) | 422/426 (99.1%) | +0.1 pts | better; denominator moved 400 → 426 |
| Cases ruled out by decision | 0/400 (0.0%) | 0/426 (0.0%) | +0.0 pts | flat; denominator moved 400 → 426 |
| Requirements observed | 89/116 (76.7%) | 98/125 (78.4%) | +1.7 pts | better; denominator moved 116 → 125 |
| Surfaces spoken for | 27/27 (100.0%) | 30/30 (100.0%) | +0.0 pts | flat; denominator moved 27 → 30 |
| Briefs joined to evidence | 24/100 (24.0%) | 26/102 (25.5%) | +1.5 pts | better; denominator moved 100 → 102 |

**The class this exists for.** `unmeasured` went 35 → 37 rows under a constant tool (worse). 1 row(s) left it, 1 entered. The published baseline recorded 39; the difference between that and the control column is the tool, not the project. The ratchet below is what says the rows that left were measured rather than reclassified.

## Where the movement came from

The two readings were taken with different versions of the reckoning tool, so the published ledgers are not directly comparable: part of any difference is the tool learning to read this registry. The earlier run's own inputs were rebuilt at its own commit (`ad0c196`) with the current tool, and that control is what the current reading is differenced against. **Only the project column is progress.**

| Count | Previous (as published) | Control (same tree, current tool) | Current | Tool moved | Project moved |
|---|---:|---:|---:|---:|---:|
| Work items | 150 | 150 | 138 | 0 | -12 |
| · product | 24 | 24 | 9 | 0 | -15 |
| · evidence | 39 | 35 | 37 | -4 | +2 |
| · decision | 87 | 91 | 92 | +4 | +1 |
| Ledger rows | 796 | 796 | 839 | 0 | +43 |

## The ratchet

An item may leave `unmeasured` only by being measured. This is the check the second run exists to turn on: a snapshot gate catches a bad run, and this catches the slow version, where a row is quietly reclassified across runs until nothing remembers it was never checked.

| Pair | From | To | Exit | Verdict |
|---|---|---|---:|---|
| published | ad0c196 | 68431dc | 3 | 5 silent transition(s) |
| tool-constant | ad0c196 (rebuilt) | 68431dc | 3 | 1 silent transition(s) |

> RATCHET BRIEF-100-a-screenshot-gallery-the-gate-cannot-see moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-81-the-capture-path-reports-frames-it-did-not-get moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-82-tests-that-touch-the-real-machine-and-tests-that-time-themselves moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-88-three-that-slipped-the-grouping moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-96-what-1-1-0-still-groups-and-still-grades moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-96-what-1-1-0-still-groups-and-still-grades moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

## Rows that changed class (16), appeared (43), vanished (0)

Tool held constant, so each of these is the project moving.

| Row | Was | Now | What |
|---|---|---|---|
| `BRIEF-96-what-1-1-0-still-groups-and-still-grades` | `unmeasured` | `undecided` | What 1.1.0 still groups, and what it still lets a citation grade |
| `BRIEF-98-a-version-string-is-not-the-artifact` | `broken` | `unmeasured` | A version string is not the artifact |
| `DEF-204` | `broken` | `verified-done` | Two different tools with the same version string compare as the same tool |
| `DEF-216` | `broken` | `verified-done` | The installed reckon plugin is still 1.0.0, and 1.0.0 crashes on this registry |
| `DEF-218` | `broken` | `verified-done` | Nine files named for nine engine surfaces are app-icon renders |
| `DEF-219` | `broken` | `verified-done` | Three files named for the takeover shield contain no image at all |
| `DEF-220` | `broken` | `verified-done` | sweepK-scaling.json lists two frames its own mode table has no capture of |
| `DEF-221` | `broken` | `verified-done` | One image carries three captions across two unrelated sweeps, and two wedged timestamps share one frame |
| `DEF-222` | `broken` | `verified-done` | sweepL-status-agent-down.png depicts a Ready window, and the two agent-down frames are one image |
| `DEF-223` | `broken` | `verified-done` | A file's surface prefix binds it to a surface the picture does not show |
| `DEF-224` | `broken` | `verified-done` | Case evidence and the lineage manifest disagree about the same five files |
| `DEF-225` | `broken` | `verified-done` | A passing case cites a shots file that does not exist, and no gate looks |
| `DEF-228` | `broken` | `verified-done` | LEDGER.md is the ledger of record and no standing instrument reads it |
| `DEF-229` | `broken` | `verified-done` | capture-lineage.py never reads cases.json either, so DEF-227's class reaches the gate |
| `DEF-230` | `broken` | `verified-done` | A requirement carries an evidence word its own schema rejects, and the tool explained it as a self-report |
| `DEF-243` | `broken` | `verified-done` | evidence/shots/mock/ is excluded from every instrument that reads the shots directory |

**New rows (43):** 2 `unmeasured`, 41 `verified-done`.

New rows that are not already done — the ones a reader schedules: `BRIEF-101-reconcile-captures-with-cases` (`unmeasured`), `BRIEF-102-standing-checks-for-the-unread-registers` (`unmeasured`)

## What each side of this comparison carries

- *previous* — Wave 17 close. Fourth reading. Both vocabulary violations from the first reading were this session's own errors and are now at their rows: REQ-072's evidence word is unknown, the planted CASE-9999 sits in a fence. Compare against 2026-08-22-2bdc808.
- *current* — Wave 18 close. PRO-0105, PRO-0108, PRO-0109, PRO-0110 merged. 0 unmerged ai/ branches, 0 unclaimed briefs, 5 remaining open defects (all recorded limits / measured negative).

## Totals, last

Read these second. A total says how much there is; the tables above say whether it is moving, and only the second question needs two runs.

| Class | Previous | Control | Current |
|---|---:|---:|---:|
| `broken` | 24 | 24 | 9 |
| `undecided` | 8 | 15 | 16 |
| `unjoined` | 79 | 76 | 76 |
| `unmeasured` | 39 | 35 | 37 |
| `verified-done` | 646 | 646 | 701 |

