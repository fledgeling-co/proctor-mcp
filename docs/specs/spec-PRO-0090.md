# PRO-0090 — What the surfaces say, what they draw, and the branch that cannot be reached

**Status:** To Do → Ready for AI · **Brief:** `docs/features-to-triage/83-what-the-surfaces-say-and-what-they-draw.md`
· **Defects:** DEF-035, DEF-037, DEF-039, DEF-056 · **Lane:** headless `./scripts/test.sh`
· **Branch:** `ai/pro-0090` off `ai/wave-9` · **Ids:** CASE-0250..0269, DEF-130..139, REQ-073..075.

## Measured before any change

`./scripts/test.sh` at `bed92f0`: **1,934 tests in 236 suites, exit 0.**

`scripts/campaign/status_literals.py`, run over every file in `Sources/ProctorUI`:

| File | display / examined |
|---|---|
| `HistoryWindow.swift` | 71 of 91 |
| `ProctorUIApp.swift` | 53 of 69 |
| `Walkthrough.swift` | 49 of 56 |
| `HistoryModel.swift` | 46 of 47 |
| `AgentModel.swift` | 39 of 47 |
| `MainWindow.swift` | **0** of 45 |
| `MenuBarCharacter.swift` | 0 of 1 |
| `Motion.swift` | 0 of 0 |

258 in the five, which is the brief's figure. `ProctorUIApp` examines 69 rather than the
brief's 68; the brief's table was copied from DEF-039, which was written at a different
commit. The instrument's number is the one used here.

## What the `display` bucket actually holds, and why it changes the shape of the work

The classifier is default-deny by design, so `display` is *everything not in an identifier
construct it recognises* — and over these five files that is **not only copy**. Counted by
reading the dump:

- **Copy** a person reads. `HistoryWindow` is almost entirely this; `Walkthrough` largely so.
- **JSON wire keys.** `HistoryModel` is 39 of its 46 — `value["capDays"]`, `value["startedAt"]`
  — and `AgentModel` about half. A dictionary subscript is not an identifier construct the
  classifier knows, and teaching it one would be editing the gate.
- **Command ids.** `ProctorUIApp` calls `commandButton("pause")`, where the string is a lookup
  key into `CommandSurface.all`.
- **A defaults key**, `"walkthroughCompleted"`, in three places, one of which is
  `WalkthroughFlow.completionDefaultsKey` already spelled out again by hand.
- **Symbol names returned from a computed property** rather than passed to `systemName:`,
  which is the exact case PRO-0081 met and resolved by moving the mapping to Core beside the
  value.

So "move the strings to a Core type" resolves to four destinations rather than one, and the
right destination is set by what the string addresses. A wire key put into `Copy` would be a
lie about what `Copy` means, and `Copy` is the enum whose doc comment this item exists to
make true.

**The wire keys are the DEF-035 shape one layer down.** `SessionHistory.swift:111` writes
`"capDays"` and `HistoryModel.swift:207` reads `"capDays"`, and nothing binds them. Two
sources for one contract is what DEF-035 is; the reader-only fix would leave it standing.
Both sides move to the same Core constants.

## Behaviour

### A — the conversion (DEF-039)

Five files, **one at a time with `./scripts/test.sh` run between each**, in the order
`Walkthrough` → `HistoryModel` → `HistoryWindow` → `ProctorUIApp` → `AgentModel`. That
sequencing is PRO-0081's and it is why its conversion did not break a working window.

Destinations, by what the string addresses:

| Kind | Destination |
|---|---|
| Walkthrough copy | `WalkthroughFlow.Copy` |
| History window copy | `HistorySurface.Copy` |
| Menu-bar and app-level copy | `StatusSurface.Copy` / `CommandSurface` |
| History wire keys | `HistorySurface.Wire`, used by the agent's writer too |
| Doctor / HUD / queue wire keys | `Wire` and the Core type beside the value |
| Command ids | `CommandSurface.CommandID`, used by `CommandSurface.all` too |
| Defaults key | `WalkthroughFlow.completionDefaultsKey`, which already exists |
| Symbols from a computed property | Core, beside the value they describe |

**Every string moves character for character.** No wording changes. PRO-0081 had one
wording drift — a section heading shortened in the move — found by a fresh verifier and
restored; the guard against a repeat is that each file's pre-conversion text is committed as
evidence and every moved literal is checked to resolve verbatim.

**Decisions stay where they are.** PRO-0081's carried clause came from moving a decision
function out of a view alongside its copy, and that is what left A2's identifier check
reporting four departures. Any decision this item does move is named in the report with its
reason. One is planned: DEF-056's, below, which is a decision that did not exist before.

### B — the branch that cannot be reached (DEF-037)

**Decided: the branch is dead code and is removed.** `AgentDownSection` is the whole story.

The tell the brief names is the two buttons, and they resolve the question rather than
leaving it open: `AgentDownSection` draws **the same two buttons, calling the same two
actions**, and unlike the dead branch it gives them accessibility identifiers
(`proctor.status.action.start-agent`, `.recheck`). A person who needs them reaches them
today. The branch is redundant rather than a lost capability, and the mapping is right: an
unreachable agent should withhold the permission rows rather than draw them, which is the
one failure `StatusSurface`'s own doc comment says this surface must not have.

**One thing inside the branch is not redundant and does not get deleted with it.** The
branch's first sub-branch draws a progress spinner and *"Applying the new permission…"* when
`model.isApplying`, and `AgentDownSection` has no such treatment. `isApplying` is set only by
`reprobeAfterGrant()`, which restarts the agent after a grant lands; the window polls every
2.0 s and a poll that meets a restarting agent fails fast with a refused connection rather
than waiting out its 5 s timeout. So `unreachable && isApplying` is reachable, and what it
draws today is a red warning claiming the agent is not answering — during a restart Proctor
itself asked for. The `isApplying` treatment moves into `AgentDownSection`, which is the
block that draws in that state.

This was referred out of family. Grok's lane was down (HTTP 402, balance exhausted);
gemini-3.7-flash-high answered, recommended a third `.applying` surface state, and named the
hazard above. The third state is declined and the reason recorded: the hazard is not created
by removing dead code — it is there at `bed92f0` and would remain under a pure deletion — and
a new state in `StatusSurface` with its own section list is a change to what the window can
draw, which is scope this brief declined for exactly this defect. Putting the condition in
the section that already draws closes the same hazard, moves no decision into Core, and
leaves `sections(for:)` alone. Its own objection to its recommendation is recorded with it:
`isApplying` is driven by a 1.2 s timer rather than the restart's lifecycle, so neither
option makes the state trustworthy, and that is written up as a defect rather than fixed
here.

### C — one prominent Grant at a time (DEF-056)

The design of record states the rule in the permissions frame's own caption: *"Only one Grant
is prominent at a time: the one to press next"*
(`design/surfaces/proctor-surfaces.html`, walkthrough, `data-state="permissions"`), drawing
Accessibility's Grant filled and Screen Recording's plain. `HeroPermRow` gives every
ungranted row `.borderedProminent` unconditionally, with nothing reading the other row's
state.

`WalkthroughFlow.prominentGrant(accessibility:screenRecording:) -> Grant?` decides it in
Core: the first ungranted grant in `Grant.allCases` order, or nil when both are in. The view
reads it and passes `prominent: Bool` into each row. **This is a decision moved into Core and
it is named as one** — it is a decision that did not exist in the view before rather than one
lifted out of it, which is the same footing as PRO-0081's `primaryEnabled`, and a rule about
which of two rows is prominent cannot be asked of a repo with no `ProctorUI` test target
unless it is a value.

Tested at all four combinations, and asserted against the design of record's own drawing:
neither granted → Accessibility; Accessibility only → Screen Recording; Screen Recording only
→ Accessibility; both → nil.

### D — the rendered surface, not the constant (DEF-035)

PRO-0081 resolved the three divergent pairs by keeping both and naming each — `toolsNote`
beside `toolsNoteInDesign`, `switchesNote` beside `switchesNoteInDesign`, `restartAgent`
beside `restart` — because choosing which sentence ships is a reader's call and wave 9
settled the status window's composition. That stands and is not revisited.

What is still owed is the brief's second clause: *a test that the rendered surface — not the
constant — carries the sentence*. A value-level check reads the constant while the window
draws the literal, which is how DEF-035 survived.

This repo has no `ProctorUI` test target and `swift test` has no window server, so inside the
gate the strongest available oracle is **source-binding**: the file that draws the Tools card
is read from disk and the site is asserted to reference `StatusSurface.Copy.toolsNote`, with
no view file mentioning either `…InDesign` twin. That is `source-analysis`, it is stronger
than a value-level check because it binds the drawing site to the named constant, and it is
**weaker than a rendered check** — it is recorded on that rung and claims nothing above it.

The rendered check itself is the glass lane: a Developer ID signed `.build/Proctor.app` on a
private socket, its status window read by a separate process over the accessibility tree,
asserting the drawn string equals `Copy.toolsNote`. Attempted; whatever it returns is
recorded as what it is, and if the tree cannot resolve the text of that card the case
resolves `inconclusive` naming the instrument rather than being dropped or downgraded
silently.

## Acceptance

- **A1** `status_literals.py` reports `display 0` on all five files, run rather than
  described, with each file's examined count printed. The denominators do not fall: a drop in
  what the classifier examines is the same shape as editing it.
- **A2** Every moved literal resolves verbatim in `Sources/`. The five pre-conversion files
  are committed as evidence and diffed against for wording.
- **A3** The classifier is armed per file: a sentence put back into a rendering construct is
  reported as a violation with exit 1, in the same session as the clean run.
- **A4** `ReadinessSection` has no `.unreachable` case; `AgentDownSection` draws the applying
  treatment; a source guard in the gate asserts both, armed by re-inserting the branch.
- **A5** `prominentGrant` returns exactly one grant in each of the three ungranted states and
  nil in the fourth, and `HeroPermRow` takes prominence as a parameter rather than deciding.
- **A6** The Tools card's drawing site is bound to `Copy.toolsNote` by a test in the gate,
  armed by repointing it at the twin.
- **A7** `./scripts/test.sh` green, suite count before and after, exit code read off the
  script rather than off a pipe.

## What this does not do

- **No composition decisions from wave 9 are revisited.** The status window keeps its
  explanation, its title block and its grant-row "why" text, and no rendered wording changes
  anywhere in this item.
- **No new `StatusSurface` state and no change to `sections(for:)`.**
- **`/Applications/Proctor.app` is untouched**; every glass measurement runs against
  `.build/Proctor.app` on a private socket.
- **No second machine.** `proctor-guest` and `anvil-mac-node` stay stopped.
- **No gate, bound or threshold is edited to make anything green**, and the classifier is not
  widened by a single construct.
