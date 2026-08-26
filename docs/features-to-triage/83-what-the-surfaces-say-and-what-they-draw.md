---
sources: [REQ-073, REQ-074, REQ-075, DEF-035, DEF-037, DEF-039, DEF-056]
status: retired
validated-by: REQ-048, REQ-073, REQ-075 via CASE-0155, CASE-0156, CASE-0251, CASE-0252, CASE-0253, CASE-0255
validated-rungs: metamorphic, outcome
validated-provider: none
validated-through-defect: REQ-048 via DEF-035
---
# What the surfaces say, what they draw, and the branch that cannot be reached

**Wave 13, brief 3 of 6.** DEF-035, DEF-037, DEF-039, DEF-056. Four surface defects with one shape:
the value and the render disagree, and no test could see it.

## DEF-039 — 258 literals in four files no test can see

PRO-0081 closed A2 for `MainWindow.swift`, which now reports **0 user-facing literals over 45
examined**. The reason A2 existed applies unchanged to its siblings, and they were measured rather
than assumed. By `scripts/campaign/status_literals.py`:

| File | user-facing / examined |
|---|---|
| `HistoryWindow.swift` | 71 of 91 |
| `ProctorUIApp.swift` | 53 of 68 |
| `Walkthrough.swift` | 49 of 56 |
| `HistoryModel.swift` | 46 of 47 |
| `AgentModel.swift` | 39 of 47 |

**258 total.** The instrument exists and is committed, so this is the same conversion PRO-0081 did,
four more times. Do it one file at a time with the gate run between each, as PRO-0081 did — that
sequencing is why its conversion did not break a working window.

Learn from PRO-0081's carried clause rather than repeating it: moving a *decision function* out of
the view alongside its copy is a widening, and it is what left A2's identifier check reporting four
departures. Move strings; leave decisions where they are, or say plainly that you moved one and why.

## DEF-035 — the copy and the window said different things

PRO-0066 wrote `toolsNote`, `switchesNote` and `restart` into `StatusSurface.Copy` and the view kept
literals of its own. They are not paraphrases. `Copy.toolsNote` read *"What is on this Mac. Proctor
finds these by reading the filesystem and never runs them to check. It installs nothing — the
commands are here for you to run."* while the window rendered *"Programs on this Mac that Proctor
uses but does not ship. None of them is a permission…"*.

Two sources, both live, neither wrong-looking on its own. This is the exact failure the A2 rule
exists to prevent, and it survived because a value-level test reads the constant while the window
draws the literal. **A value-level check standing in for a rendered-surface check is not a
substitute** — that is already recorded here as DEF-006's lesson.

## DEF-037 — a branch that cannot be reached, drawing buttons nothing can press

`MainWindow.ReadinessSection` switches on `model.reachability` and has a `case .unreachable(let why)`
branch drawing *"The background agent is not answering"*, a **Start the agent** button and a
**Re-check** button.

It is unreachable. `MainWindow.state` maps `.unreachable` to
`StatusSurface.state(reachable: false, answered: true, …)`, which returns `.down`;
`StatusSurface.sections(for: .down)` returns exactly `[.agentDown]`; so `ReadinessSection` is never
drawn while reachability is `.unreachable`.

Decide which is true rather than deleting the cheaper one: either the agent-down block is the whole
story and this branch is dead code, or the branch is a state the window should reach and the mapping
is wrong. The two buttons are the tell — if nothing can draw them, either they are not needed or a
person who needs them cannot get to them.

## DEF-056 — both grant rows prominent, so neither says "press this one"

The design of record states the rule in the permissions frame's own caption: *"Only one Grant is
prominent at a time: the one to press next"*
(`design/surfaces/proctor-surfaces.html`, walkthrough, `data-state="permissions"`). It draws
Accessibility's Grant filled and Screen Recording's plain.

The build does not implement it: `HeroPermRow` gives every ungranted row
`Button("Allow").buttonStyle(.borderedProminent)` unconditionally
(`Sources/ProctorUI/Walkthrough.swift`).

This bears directly on PRO-0086, which is adding a stated reason to the walkthrough's disabled
primary action. Two prominent buttons and a disabled primary is a screen that tells a person nothing
about what to do first, so sequence this with PRO-0086 or hand it to the same runner.

## The conversion contract

- All four files' user-facing literals moved to a Core type, `scripts/campaign/status_literals.py` reporting
  `display 0` on each, run as evidence rather than described.
- The duplicated copy resolved to one source, with a test that the *rendered* surface — not the
  constant — carries the sentence.
- DEF-037 decided: dead branch removed, or mapping corrected so the branch is reachable, with a test
  either way.
- One prominent Grant at a time, matching the design's own caption, with a test per grant state.
- `./scripts/test.sh` green, suite count before and after.

## What this brief does not do

It does not revisit the composition decisions settled in wave 9 — the status window keeps its
explanation, its title block and its grant-row "why" text.
