---
sources: [REQ-009, REQ-027]
status: retired
validated-by: REQ-009, REQ-027 via CASE-0011, CASE-0028, CASE-0029, CASE-0062, CASE-0084, CASE-0791
validated-rungs: effect-witness, outcome
validated-provider: Darwin.bind/listen/accept in Sources/ProctorAgent/Server.swift; Darwin.connect in Sources/ProctorCore/Transport.swift
---
# The status window becomes the mock

**Wave 9, brief 2 of 11.** Reads `58` and `59`. Mock anchors:
`design/surfaces/proctor-surfaces.html#mac/status/ready`, `…/checking`, `…/partial`, `…/down`.

## The problem

`Sources/ProctorUI/MainWindow.swift` is 1,030 lines and holds seven sections that were
written across five waves. It carries its own spacing values, its own font sizes, its own
idea of a section header, and around 40 colour and size literals inline. It also has one
state — the populated one. The mock has four, and two of them are the ones a person meets
when something is wrong.

The section that matters most is the one the mock changed hardest: **when the agent is not
answering, the mock withholds the rest of the window rather than dimming it.** The shipped
window keeps drawing permission rows it cannot read. That is the single worst thing any of
these surfaces can do, because a stale Ready pill over a dead agent is a false statement
about a security-relevant grant, and the test campaign already caught a version of it
(CASE-0028, since retracted as a measurement artifact — but the pattern it looked for is
real and the mock removes the possibility).

## What it should do

Redraw the seven sections to the mock, and carry all four states.

| State | What it shows |
|---|---|
| `ready` | Permissions, Tools, Switches, Activity, Connect, Agent, Footer |
| `checking` | Skeletons matching the rows they stand in for, on the surface those rows will sit on |
| `partial` | The five lanes, with `unconfirmed` and `unavailable` drawn as different answers |
| `down` | The agent-down block, and **nothing below it** |

`unconfirmed` and `unavailable` being visually distinct is not a nicety. PRO-0041 closed a
defect where a person was sent to fix a lane that was merely unestablished; the three-state
handling exists because "nothing has established this" and "this is known broken" have
different remedies, and drawing them the same way reintroduces the defect at the surface.

## The conversion contract

- `StatusSurface` in `ProctorCore`: the state enumeration, the per-state section list, the
  copy for every row, and the identifier for every control. Pure.
- `StatusChecks` already exists and owns the check-kind vocabulary; extend rather than
  duplicate it.
- `MainWindow.swift` reads `ProctorTokens` and `StatusSurface` and holds no literal colour,
  size or user-facing string.
- Every row and control sets `.accessibilityIdentifier` from the Core constant.

## Acceptance

1. Each of the four states resolves to its section list, and the `down` state's list is
   exactly the agent-down block — a test that fails if any other section is reachable while
   the agent is unreachable.
2. Every user-facing string in the window comes from `StatusSurface`; a grep for a quoted
   string literal in `MainWindow.swift` outside an identifier returns nothing.
3. Identifiers are unique across the window and stable across states.
4. The switch rows render the value the **agent** reported, never this process's own
   environment. The existing `DoctorReport.switches` field carries it and the window already
   reads it; the test asserts the window has no path to `ProcessInfo` for a switch value.
5. `unconfirmed` and `unavailable` map to different pills, and a test asserts the two are
   not the same token.

## The hard parts, named

**The skeleton has to match the row it replaces.** A skeleton of the wrong height guarantees
a jump when the real answer lands, and this window polls every two seconds, so the jump is
frequent and visible. The mock's skeleton rows carry the same heights as the permission rows;
put those heights in the Core value so both read one number.

**Do not widen what `ready` means.** It is untouched by every optional lane and by the audit
trail's writability. That is settled (PRO-0050's non-goals) and this brief does not reopen it.

**The window is not the walkthrough.** Brief 61 owns first run. This window replaces it once
setup is done, and the two must not both try to own the "no grants yet" state.

## Child work found

- The mock draws a **Lanes** section that the shipped window does not have at all; the data
  is on the wire (`DoctorReport.lanes`) and unrendered. PRO-0036's non-goals deliberately
  left it. This brief renders it, which closes that child.
- The policy-posture block is also on the wire and still unrendered after this brief. Left
  as child work rather than folded in, because it answers a different question and belongs
  beside the audit surface rather than beside the grants.
