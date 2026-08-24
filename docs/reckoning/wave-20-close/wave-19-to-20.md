# Reckoning delta — proctor-mcp

`a29e3bd` (reckon 1.3.0) → `4da1424` (reckon 1.3.0), attribution **decomposed**.

## What moved

**2 of 5 axes improved, 3 flat, 0 worsened; evidence work down at 27 and the unmeasured class smaller at 27 rows.**

| Axis | Was (same tool) | Now | Move | Reading |
|---|---|---|---|---|
| Cases adjudicated | 438/442 (99.1%) | 458/461 (99.3%) | +0.2 pts | better; denominator moved 442 → 461 |
| Cases ruled out by decision | 0/442 (0.0%) | 0/461 (0.0%) | +0.0 pts | flat; denominator moved 442 → 461 |
| Requirements observed | 107/134 (79.9%) | 119/138 (86.2%) | +6.3 pts | better; denominator moved 134 → 138 |
| Surfaces spoken for | 33/33 (100.0%) | 37/37 (100.0%) | +0.0 pts | flat; denominator moved 33 → 37 |
| Briefs joined to evidence | 105/105 (100.0%) | 109/109 (100.0%) | +0.0 pts | flat; denominator moved 105 → 109 |

**The class this exists for.** `unmeasured` went 41 → 27 rows under a constant tool (better). 14 row(s) left it, 0 entered. The published baseline recorded 41; the difference between that and the control column is the tool, not the project. The ratchet below is what says the rows that left were measured rather than reclassified.

## Where the movement came from

The two readings were taken with different versions of the reckoning tool, so the published ledgers are not directly comparable: part of any difference is the tool learning to read this registry. The earlier run's own inputs were rebuilt at its own commit (`a29e3bd`) with the current tool, and that control is what the current reading is differenced against. **Only the project column is progress.**

| Count | Previous (as published) | Control (same tree, current tool) | Current | Tool moved | Project moved |
|---|---:|---:|---:|---:|---:|
| Work items | 138 | 138 | 133 | 0 | -5 |
| · product | 8 | 8 | 8 | 0 | 0 |
| · evidence | 41 | 41 | 27 | 0 | -14 |
| · decision | 89 | 89 | 97 | 0 | +8 |
| Ledger rows | 873 | 873 | 908 | 0 | +35 |

## The ratchet

An item may leave `unmeasured` only by being measured. This is the check the second run exists to turn on: a snapshot gate catches a bad run, and this catches the slow version, where a row is quietly reclassified across runs until nothing remembers it was never checked.

| Pair | From | To | Exit | Verdict |
|---|---|---|---:|---|
| published | a29e3bd | 4da1424 | 3 | 6 silent transition(s) |
| tool-constant | a29e3bd (rebuilt) | 4da1424 | 3 | 6 silent transition(s) |

> RATCHET BRIEF-17-multi-session-queue moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-30-a-home-for-the-proctor-switches moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-38-a-hold-names-whose-run-it-is moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-48-the-run-has-a-history-you-can-read moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-59-design-tokens-as-a-swift-value moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-65-history-window-to-the-mock moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-17-multi-session-queue moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-30-a-home-for-the-proctor-switches moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-38-a-hold-names-whose-run-it-is moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-48-the-run-has-a-history-you-can-read moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-59-design-tokens-as-a-swift-value moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-65-history-window-to-the-mock moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

## Rows that changed class (15), appeared (35), vanished (0)

Tool held constant, so each of these is the project moving.

| Row | Was | Now | What |
|---|---|---|---|
| `BRIEF-17-multi-session-queue` | `unmeasured` | `undecided` | Multi-session scheduling — session identity, lanes, and the queue |
| `BRIEF-30-a-home-for-the-proctor-switches` | `unmeasured` | `undecided` | A home for the PROCTOR_* switches |
| `BRIEF-38-a-hold-names-whose-run-it-is` | `unmeasured` | `undecided` | A hold names whose run it is |
| `BRIEF-48-the-run-has-a-history-you-can-read` | `unmeasured` | `undecided` | The run has a history you can read |
| `BRIEF-59-design-tokens-as-a-swift-value` | `unmeasured` | `undecided` | The design tokens are a Swift value, generated from the mock |
| `BRIEF-65-history-window-to-the-mock` | `unmeasured` | `undecided` | The history window, and the detail that says what it could not check |
| `CASE-0087` | `unmeasured` | `verified-done` | SURF-003 · ? |
| `REQ-024` | `undecided` | `verified-done` | Automatic browser routing dispatches web URLs to Obscura or browser-use engines |
| `REQ-030` | `unmeasured` | `verified-done` | The supervision surface draws what the design compiled, at 100x30 and at the 80x24 floor |
| `REQ-031` | `unmeasured` | `verified-done` | Every command the catalogue declares for the menu bar is actually rendered in it |
| `REQ-033` | `unmeasured` | `verified-done` | A supervision client can read the machine's readiness, switches and history, not only its run and queue |
| `REQ-037` | `unmeasured` | `verified-done` | A session attaches to a macOS guest and executes its steps inside that guest; the host agent routes calls over |
| `REQ-038` | `unmeasured` | `verified-done` | Guest attachments are held against a counted lane whose capacity is a parameter: macOS at two, one session per |
| `REQ-039` | `unmeasured` | `verified-done` | The pool never evicts: a guest a person started, or one another session holds, is waited for and never stopped |
| `REQ-040` | `unmeasured` | `verified-done` | A guest's witness tier is derived from the platform its provider reports, so a provider saying darwin yields m |

**New rows (35):** 1 `retirable`, 3 `undecided`, 31 `verified-done`.

New rows that are not already done — the ones a reader schedules: `BRIEF-106-supervision-tui-and-menu-bar-glass-witness` (`undecided`), `BRIEF-107-subprocess-actuation-witness-for-cua-driver` (`undecided`), `BRIEF-108-native-ocr-and-high-dpi-zoom-inspector` (`retirable`), `BRIEF-109-guest-vm-lifecycle-and-attachment-oracle` (`undecided`)

## What each side of this comparison carries

- *previous* — Wave 19 close. PRO-0111, PRO-0112, PRO-0113 merged. 100% brief join rate, 0 weak join warnings, warrant charter verified, limits audited.
- *current* — Wave 20 close. PRO-0114, PRO-0115, PRO-0116, PRO-0117 merged. All 117 ledger rows resolved, 259 instrument checks passing, 100% brief join rate.

## Totals, last

Read these second. A total says how much there is; the tables above say whether it is moving, and only the second question needs two runs.

| Class | Previous | Control | Current |
|---|---:|---:|---:|
| `broken` | 8 | 8 | 8 |
| `retirable` | 0 | 0 | 1 |
| `undecided` | 89 | 89 | 97 |
| `unmeasured` | 41 | 41 | 27 |
| `verified-done` | 735 | 735 | 775 |

