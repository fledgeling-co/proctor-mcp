# Reckoning delta — proctor-mcp

`4da1424` (reckon 1.3.0) → `56a46fc` (reckon 1.3.0), attribution **decomposed**.

## What moved

**2 of 5 axes improved, 3 flat, 0 worsened; evidence work down at 26 and the unmeasured class smaller at 26 rows.**

| Axis | Was (same tool) | Now | Move | Reading |
|---|---|---|---|---|
| Cases adjudicated | 458/461 (99.3%) | 463/466 (99.4%) | +0.1 pts | better; denominator moved 461 → 466 |
| Cases ruled out by decision | 0/461 (0.0%) | 0/466 (0.0%) | +0.0 pts | flat; denominator moved 461 → 466 |
| Requirements observed | 119/138 (86.2%) | 124/141 (87.9%) | +1.7 pts | better; denominator moved 138 → 141 |
| Surfaces spoken for | 37/37 (100.0%) | 40/40 (100.0%) | +0.0 pts | flat; denominator moved 37 → 40 |
| Briefs joined to evidence | 109/109 (100.0%) | 113/113 (100.0%) | +0.0 pts | flat; denominator moved 109 → 113 |

**The class this exists for.** `unmeasured` went 27 → 26 rows under a constant tool (better). 2 row(s) left it, 0 entered. The published baseline recorded 27; the difference between that and the control column is the tool, not the project. The ratchet below is what says the rows that left were measured rather than reclassified.

## Where the movement came from

The two readings were taken with different versions of the reckoning tool, so the published ledgers are not directly comparable: part of any difference is the tool learning to read this registry. The earlier run's own inputs were rebuilt at its own commit (`4da1424`) with the current tool, and that control is what the current reading is differenced against. **Only the project column is progress.**

| Count | Previous (as published) | Control (same tree, current tool) | Current | Tool moved | Project moved |
|---|---:|---:|---:|---:|---:|
| Work items | 133 | 133 | 134 | 0 | +1 |
| · product | 8 | 8 | 4 | 0 | -4 |
| · evidence | 27 | 27 | 26 | 0 | -1 |
| · decision | 97 | 97 | 103 | 0 | +6 |
| Ledger rows | 908 | 908 | 925 | 0 | +17 |

## The ratchet

An item may leave `unmeasured` only by being measured. This is the check the second run exists to turn on: a snapshot gate catches a bad run, and this catches the slow version, where a row is quietly reclassified across runs until nothing remembers it was never checked.

| Pair | From | To | Exit | Verdict |
|---|---|---|---:|---|
| published | 4da1424 | 56a46fc | 0 | clean |
| tool-constant | 4da1424 (rebuilt) | 56a46fc | 0 | clean |

## Rows that changed class (6), appeared (17), vanished (0)

Tool held constant, so each of these is the project moving.

| Row | Was | Now | What |
|---|---|---|---|
| `BRIEF-23-drawing-fault-must-not-kill-the-agent` | `broken` | `undecided` | A drawing fault must not kill the agent |
| `BRIEF-40-page-scoped-refusal` | `broken` | `undecided` | Page-scoped refusal |
| `BRIEF-99-instruments-that-do-not-prove-their-own-step` | `broken` | `undecided` | Instruments that do not prove their own step |
| `DEF-215` | `broken` | `verified-done` | Four ledger rows have no spec file, so two briefs have no artifact that could cite them |
| `REQ-043` | `unmeasured` | `verified-done` | No drawn pointer over a window the person cannot see: where the pointer's plane cannot be confirmed and someth |
| `REQ-081` | `unmeasured` | `verified-done` | Input the takeover block swallows during a run is reported as a yield record with a held reason, whatever the  |

**New rows (17):** 3 `undecided`, 1 `unmeasured`, 13 `verified-done`.

New rows that are not already done — the ones a reader schedules: `BRIEF-110-covered-target-cursor-plane-witness` (`undecided`), `BRIEF-111-retired-items-spec-closure` (`unmeasured`), `BRIEF-112-cross-automation-stack-reporting-harness` (`undecided`), `BRIEF-113-retire-pro-0108-native-ocr-zoom` (`undecided`)

## What each side of this comparison carries

- *previous* — Wave 20 close. PRO-0114, PRO-0115, PRO-0116, PRO-0117 merged. All 117 ledger rows resolved, 259 instrument checks passing, 100% brief join rate.
- *current* — Wave 21 close. PRO-0118, PRO-0119, PRO-0120, PRO-0121 merged. 100% 1-to-1 spec mapping, DEF-215 closed, BLOCK-0002 & BLOCK-0003 unblocked, Brief 108 retired.

## Totals, last

Read these second. A total says how much there is; the tables above say whether it is moving, and only the second question needs two runs.

| Class | Previous | Control | Current |
|---|---:|---:|---:|
| `broken` | 8 | 8 | 4 |
| `retirable` | 1 | 1 | 1 |
| `undecided` | 97 | 97 | 103 |
| `unmeasured` | 27 | 27 | 26 |
| `verified-done` | 775 | 775 | 791 |

