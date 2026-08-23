---
sources: [REQ-006]
---
# The run HUD, and the seven character states

**Wave 9, brief 5 of 11.** Reads `58`, `59`. Mock anchors: `#mac/hud/idle` through
`#mac/hud/error` — seven states.

## The problem

The HUD is the most-shipped surface in the app and the one the mock changed least in
structure and most in content. `RunHUDContentView` draws a step line, a character, a target
badge and the controls. The mock adds the **provenance chip** — plane, route and machine on
the panel itself — and fills in the four states the shipped panel does not draw.

The chip is the wave's signature and this is the surface it matters most on. A person
watching a run sees "Typing into Search in Mail" and has no way to tell whether that
happened through the accessibility plane, in the background, or through the shared event
stream with the machine taken. Those two runs prove different things, and the panel is where
somebody is actually looking when it happens.

## What it should do

Seven states, each with the character posture the mock draws, and the chip on every state
that has a plane to report.

| State | Panel |
|---|---|
| idle | no controls — there is nothing to control |
| travelling | Pause and Stop, plane chip, progress |
| acting | the step, the settle reason, plane and route |
| blocked | which lane, who holds it, the ceiling |
| paused | why it paused, how it resumes, the 15-minute cap |
| finished | steps, foreground count, run id |
| error | what disagreed, and the route that was tried |

## The conversion contract

- `RunHUDCharacter` already owns the seven-state enumeration and has tests. Extend it with
  the chip content per state.
- `RunHUDPlacement` already owns the geometry and is pure. Unchanged.
- The panel's `sharingType = .none` is load-bearing and stays: evidence must not change
  because somebody was watching. Two campaign cases are permanently `n/a` for that reason
  and must not be "fixed" into a pass.

## Acceptance

1. Every one of the seven states resolves to its character asset at 1x, 2x and 3x, and the
   existing asset test extends to cover the chip content per state.
2. `idle` renders no Pause and no Stop; every other state renders Stop.
3. The chip's plane and route come from the `StepResult` and are never inferred. A test with
   a `routedEvent` and an `unknown` plane asserts neither is described as background-safe.
4. The step text is derived and fenced. `StepDescription` already sanitises and quotes text
   from outside Proctor whichever side it came from; the panel renders through that type and
   the test asserts a raw string cannot reach the view.
5. The panel ignores mouse events while a synthetic step is in flight — existing behaviour,
   re-asserted here because the redraw touches the view that implements it.

## The hard parts, named

**A drawing fault must not kill the agent.** `ProctorCatch` exists because AppKit raises
`NSException`, Swift cannot catch one, and an uncaught one aborts the process — taking the
run and the MCP server with it. Every new drawing path in this brief goes through the same
barrier. This is the single highest-consequence constraint in the wave: the panel is drawn
by the agent process, not the UI process.

**Do not let a synthetic click reach Stop.** PRO-0015 found this with a completeness critic
rather than a build: a click Proctor posts under the panel can land on Stop and halt the run
that posted it. The guard exists; the redraw must not step around it.

**SF Symbols, not the mock's SVG.** The mock draws its glyphs inline because a self-contained
HTML file cannot bundle SF Symbols. The SwiftUI side uses real symbols, and the mapping is
part of this brief's Core value — a symbol name per state, tested for presence so a typo is a
red test rather than a blank panel.
