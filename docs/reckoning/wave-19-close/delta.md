# Reckoning delta — proctor-mcp

`68431dc` (reckon 1.2.0) → `a29e3bd` (reckon 1.3.0), attribution **decomposed**.

## What moved

**2 of 5 axes improved, 3 flat, 0 worsened; evidence work up at 41 and the unmeasured class larger at 41 rows.**

| Axis | Was (same tool) | Now | Move | Reading |
|---|---|---|---|---|
| Cases adjudicated | 422/426 (99.1%) | 438/442 (99.1%) | +0.0 pts | flat; denominator moved 426 → 442 |
| Cases ruled out by decision | 0/426 (0.0%) | 0/442 (0.0%) | +0.0 pts | flat; denominator moved 426 → 442 |
| Requirements observed | 98/125 (78.4%) | 107/134 (79.9%) | +1.5 pts | better; denominator moved 125 → 134 |
| Surfaces spoken for | 30/30 (100.0%) | 33/33 (100.0%) | +0.0 pts | flat; denominator moved 30 → 33 |
| Briefs joined to evidence | 26/102 (25.5%) | 105/105 (100.0%) | +74.5 pts | better; denominator moved 102 → 105 |

**The class this exists for.** `unmeasured` went 37 → 41 rows under a constant tool (worse). 4 row(s) left it, 8 entered. The published baseline recorded 37; the difference between that and the control column is the tool, not the project. The ratchet below is what says the rows that left were measured rather than reclassified.

## Where the movement came from

The two readings were taken with different versions of the reckoning tool, so the published ledgers are not directly comparable: part of any difference is the tool learning to read this registry. The earlier run's own inputs were rebuilt at its own commit (`68431dc`) with the current tool, and that control is what the current reading is differenced against. **Only the project column is progress.**

| Count | Previous (as published) | Control (same tree, current tool) | Current | Tool moved | Project moved |
|---|---:|---:|---:|---:|---:|
| Work items | 138 | 138 | 138 | 0 | 0 |
| · product | 9 | 9 | 8 | 0 | -1 |
| · evidence | 37 | 37 | 41 | 0 | +4 |
| · decision | 92 | 92 | 89 | 0 | -3 |
| Ledger rows | 839 | 839 | 873 | 0 | +34 |

## The ratchet

An item may leave `unmeasured` only by being measured. This is the check the second run exists to turn on: a snapshot gate catches a bad run, and this catches the slow version, where a row is quietly reclassified across runs until nothing remembers it was never checked.

| Pair | From | To | Exit | Verdict |
|---|---|---|---:|---|
| published | 68431dc | a29e3bd | 3 | 4 silent transition(s) |
| tool-constant | 68431dc (rebuilt) | a29e3bd | 3 | 4 silent transition(s) |

> RATCHET BRIEF-102-standing-checks-for-the-unread-registers moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-60-status-window-to-the-mock moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-97-an-input-the-check-cannot-classify moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-98-a-version-string-is-not-the-artifact moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-102-standing-checks-for-the-unread-registers moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-60-status-window-to-the-mock moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-97-an-input-the-check-cannot-classify moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

> RATCHET BRIEF-98-a-version-string-is-not-the-artifact moved from unmeasured to 'undecided' with no evidence-bearing event (status None, evidence None)

## Rows that changed class (83), appeared (34), vanished (0)

Tool held constant, so each of these is the project moving.

| Row | Was | Now | What |
|---|---|---|---|
| `BRIEF-00-WAVE-7-DIRECTION` | `unjoined` | `undecided` | Wave 7 direction: Cua underneath, Proctor on top |
| `BRIEF-01-cua-schema-facade` | `unjoined` | `undecided` | Stock computer-use schema façade (Anthropic + OpenAI) |
| `BRIEF-02-set-of-marks-captures` | `unjoined` | `undecided` | Set-of-marks annotated captures |
| `BRIEF-03-menu-bar-key-equivalents` | `unjoined` | `undecided` | Menu-bar enumeration with key-equivalents |
| `BRIEF-04-app-scripting-dictionary` | `unjoined` | `undecided` | App scripting-dictionary introspection |
| `BRIEF-05-audit-trail-policy-gate` | `unjoined` | `undecided` | Redacting audit trail + policy / approval gate |
| `BRIEF-06-vision-capture-normalisation` | `unjoined` | `undecided` | Vision-capture normalisation + reported scale factor |
| `BRIEF-07-zoom-region-crop` | `unjoined` | `undecided` | Zoom native-resolution region crop |
| `BRIEF-08-mcp-surface-modernization` | `unjoined` | `undecided` | MCP surface modernization |
| `BRIEF-09-process-kill-fs-jail` | `unjoined` | `undecided` | Process kill + filesystem jail |
| `BRIEF-10-pointer-overlay-captures` | `unjoined` | `undecided` | Pointer / target overlay in captures |
| `BRIEF-102-standing-checks-for-the-unread-registers` | `unmeasured` | `undecided` | Standing checks for the registers nothing reads |
| `BRIEF-11-stability-per-step-pointer` | `unjoined` | `undecided` | Pointer marker in proctor_stability per-step artifacts |
| `BRIEF-12-gate-flow-replay-stability` | `unjoined` | `undecided` | Gate recorded flow-replay and stability through the policy gate + audit |
| `BRIEF-13-audit-log-encryption-at-rest` | `unjoined` | `undecided` | Encryption-at-rest for the JSONL audit log |
| `BRIEF-15-step-descriptions` | `unjoined` | `undecided` | Human-readable step descriptions, derived not supplied |
| `BRIEF-16-run-hud-panel` | `unjoined` | `undecided` | Run HUD — the overlay shown while Proctor drives an app |
| `BRIEF-17-multi-session-queue` | `unjoined` | `unmeasured` | Multi-session scheduling — session identity, lanes, and the queue |
| `BRIEF-18-hud-character-assets` | `unjoined` | `undecided` | HUD character — sprite assets and state binding |
| `BRIEF-19-yield-when-a-person-takes-the-machine` | `unjoined` | `undecided` | Notice when a person is taking the machine back, and yield |
| `BRIEF-20-foreground-run-is-obvious` | `unjoined` | `undecided` | Make a foreground-only run obvious before it takes the machine |
| `BRIEF-21-route-browser-work-to-obscura` | `unjoined` | `undecided` | Route browser work to Obscura instead of driving a browser by hand |
| `BRIEF-22-menu-bar-switch-and-character` | `unjoined` | `undecided` | A menu bar switch for the panel, and a menu bar icon that is the same character |
| `BRIEF-23-drawing-fault-must-not-kill-the-agent` | `unjoined` | `broken` | A drawing fault must not kill the agent |
| `BRIEF-24-offer-to-install-obscura` | `unjoined` | `undecided` | Offer to install Obscura when it is missing |
| `BRIEF-25-second-browser-lane-for-obscuras-limits` | `unjoined` | `undecided` | A second browser lane for what Obscura cannot do |
| `BRIEF-26-prefer-background-and-pointer-in-plane` | `unjoined` | `undecided` | Prefer the background, and draw the pointer where the work is happening |
| `BRIEF-27-foreground-takeover-overlay` | `unjoined` | `undecided` | When Proctor must take the front, take it visibly and hold it |
| `BRIEF-28-menu-bar-character-when-idle` | `unjoined` | `undecided` | The menu bar shows the character when idle, not a status symbol |
| `BRIEF-29-re-check-now-says-what-it-checks` | `unjoined` | `undecided` | "Re-check now" does not say what it checks |
| `BRIEF-30-a-home-for-the-proctor-switches` | `unjoined` | `unmeasured` | A home for the PROCTOR_* switches |
| `BRIEF-31-the-build-says-which-build-it-is` | `unjoined` | `undecided` | The build says which build it is |
| `BRIEF-32-the-health-report-is-complete` | `unjoined` | `undecided` | The health report is complete |
| `BRIEF-33-the-audit-trail-is-signed` | `unjoined` | `undecided` | The audit trail is signed, and it records what Proctor recommended |
| `BRIEF-34-a-persons-click-reaches-stop` | `unjoined` | `undecided` | A person's click reaches Stop |
| `BRIEF-35-scroll-moves-by-what-was-asked` | `unjoined` | `undecided` | Scroll moves by what was asked |
| `BRIEF-36-the-browser-catalogue-stops-guessing` | `unjoined` | `undecided` | The browser catalogue stops guessing, and the handoff is machine-readable |
| `BRIEF-37-the-status-windows-checks-say-what-they-can-check` | `unjoined` | `undecided` | The status window's checks say what they can check |
| `BRIEF-38-a-hold-names-whose-run-it-is` | `unjoined` | `unmeasured` | A hold names whose run it is |
| `BRIEF-39-stability-knows-when-it-is-scoring-a-page` | `unjoined` | `undecided` | Stability knows when it is scoring a page |

_…and 43 more in delta.json_

**New rows (34):** 3 `undecided`, 31 `verified-done`.

New rows that are not already done — the ones a reader schedules: `BRIEF-103-the-three-recorded-limits-audit` (`undecided`), `BRIEF-104-warrant-charter-and-release-integrity` (`undecided`), `BRIEF-105-brief-join-rate-and-retirement-ladder` (`undecided`)

## What each side of this comparison carries

- *previous* — Wave 18 close. PRO-0105, PRO-0108, PRO-0109, PRO-0110 merged. 0 unmerged ai/ branches, 0 unclaimed briefs, 5 remaining open defects (all recorded limits / measured negative).
- *current* — Wave 19 close. PRO-0111, PRO-0112, PRO-0113 merged. 100% brief join rate, 0 weak join warnings, warrant charter verified, limits audited.

## Totals, last

Read these second. A total says how much there is; the tables above say whether it is moving, and only the second question needs two runs.

| Class | Previous | Control | Current |
|---|---:|---:|---:|
| `broken` | 9 | 9 | 8 |
| `undecided` | 16 | 16 | 89 |
| `unjoined` | 76 | 76 | 0 |
| `unmeasured` | 37 | 37 | 41 |
| `verified-done` | 701 | 701 | 735 |

