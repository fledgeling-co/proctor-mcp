# Reckoning delta — proctor-mcp

`2bd01be` (reckon 1.0.0+local-patch) → `2bdc808` (reckon 1.1.0), attribution **decomposed**.

## What moved

**2 of 5 axes improved, 2 flat, 1 worsened; evidence work flat at 36 and the unmeasured class flat at 36 rows.**

| Axis | Was (same tool) | Now | Move | Reading |
|---|---|---|---|---|
| Cases adjudicated | 227/231 (98.3%) | 289/293 (98.6%) | +0.3 pts | better; denominator moved 231 → 293 |
| Cases ruled out by decision | 0/231 (0.0%) | 0/293 (0.0%) | +0.0 pts | flat; denominator moved 231 → 293 |
| Requirements observed | 49/76 (64.5%) | 63/90 (70.0%) | +5.5 pts | better; denominator moved 76 → 90 |
| Surfaces spoken for | 22/22 (100.0%) | 23/23 (100.0%) | +0.0 pts | flat; denominator moved 22 → 23 |
| Briefs joined to evidence | 16/91 (17.6%) | 16/96 (16.7%) | -0.9 pts | worse; denominator moved 91 → 96 |

**The class this exists for.** `unmeasured` went 36 → 36 rows under a constant tool (flat). 0 row(s) left it, 0 entered. The published baseline recorded 31; the difference between that and the control column is the tool, not the project. The ratchet below is what says the rows that left were measured rather than reclassified.

## Where the movement came from

The two readings were taken with different versions of the reckoning tool, so the published ledgers are not directly comparable: part of any difference is the tool learning to read this registry. The earlier run's own inputs were rebuilt at its own commit (`2bd01be`) with the current tool, and that control is what the current reading is differenced against. **Only the project column is progress.**

| Count | Previous (as published) | Control (same tree, current tool) | Current | Tool moved | Project moved |
|---|---:|---:|---:|---:|---:|
| Work items | 218 | 130 | 134 | -88 | +4 |
| · product | 183 | 11 | 10 | -172 | -1 |
| · evidence | 31 | 36 | 36 | +5 | 0 |
| · decision | 4 | 83 | 88 | +79 | +5 |
| Ledger rows | 516 | 516 | 620 | 0 | +104 |

## The ratchet

An item may leave `unmeasured` only by being measured. This is the check the second run exists to turn on: a snapshot gate catches a bad run, and this catches the slow version, where a row is quietly reclassified across runs until nothing remembers it was never checked.

| Pair | From | To | Exit | Verdict |
|---|---|---|---:|---|
| published | 2bd01be | 2bdc808 | 0 | clean |
| tool-constant | 2bd01be (rebuilt) | 2bdc808 | 0 | clean |

## Rows that changed class (5), appeared (104), vanished (0)

Tool held constant, so each of these is the project moving.

| Row | Was | Now | What |
|---|---|---|---|
| `DEF-099` | `broken` | `verified-done` | REQ-028 cites a source file the branch under test does not contain |
| `DEF-140` | `broken` | `verified-done` | Two force-unwrap shapes sit outside `grep -rn ')!' Tests` and carry DEF-136's hazard unswept |
| `DEF-162` | `broken` | `verified-done` | The design of record's permissions pane draws no Skip setup, and the build draws one on every step but connect |
| `DEF-163` | `broken` | `verified-done` | The disabled primary still draws filled accent while the design of record draws it plain, so a control that ca |
| `DEF-165` | `broken` | `verified-done` | BrowserLaneWiringTests asserts doctor's `ready` is invariant while reading two live machine probes |

**New rows (104):** 4 `broken`, 5 `unjoined`, 95 `verified-done`.

New rows that are not already done — the ones a reader schedules: `BRIEF-92-a-spec-says-which-brief-it-came-from` (`unjoined`), `BRIEF-93-the-reckoning-tool-mis-read-this-registry` (`unjoined`), `BRIEF-94-a-reckoning-worth-comparing-against` (`unjoined`), `BRIEF-95-six-named-repairs` (`unjoined`), `BRIEF-96-what-1-1-0-still-groups-and-still-grades` (`unjoined`), `DEF-180` (`broken`), `DEF-200` (`broken`), `DEF-201` (`broken`), `DEF-202` (`broken`)

## What each side of this comparison carries

- *previous* — Provenance transcribed from the report's own first line, not measured: this run predates the stamp and was deliberately not re-taken, because a baseline edited to suit is not a baseline.
- *previous* — The published report carries a human-adjudicated join of 78/91 briefs (66 cited plus 12 confirmed by title). The ledger's mechanical join is 16/91, and every delta computed from these files is mechanical on both sides.
- *previous* — The ledger's own headline — 218 remain, 183 product — is the one the report declined to reproduce. Two faults produced it: all 108 defects classed broken without reading status, and 75 briefs classed unbuilt for failing to join. Both are repaired in reckon 1.1.0, so any delta against this ledger measures the tool unless the tool is held constant.
- *previous* — The report excludes PRO-0082, PRO-0085 and PRO-0099 from its prose counts as mid-flight. The ledger does not exclude them.
- *current* — Taken at wave 16's close-in-progress rather than after it: PRO-0101 had not merged when this was read, so its REQ-100/101, CASE-0430-0440, DEF-215 and SURF-024 are not in this tree.
- *current* — PRO-0103's own campaign rows (REQ-102-107, CASE-0441-0456, DEF-216, SURF-025) land two commits after this reading and are not in it. They will appear as movement at the next wave close.

## Totals, last

Read these second. A total says how much there is; the tables above say whether it is moving, and only the second question needs two runs.

| Class | Previous | Control | Current |
|---|---:|---:|---:|
| `broken` | 108 | 11 | 10 |
| `unbuilt` | 75 | 0 | 0 |
| `undecided` | 4 | 8 | 8 |
| `unjoined` | 0 | 75 | 80 |
| `unmeasured` | 31 | 36 | 36 |
| `verified-done` | 298 | 386 | 486 |

