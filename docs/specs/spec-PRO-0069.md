# PRO-0069: The run HUD, and the seven character states

**ID:** PRO-0069 · **Status:** Ready for Plan · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/63-run-hud-and-the-character.md`
**Branch:** `ai/pro-0069` off `ai/wave-9` · **Depends on:** PRO-0064, PRO-0065
**Mock:** `#mac/hud/idle` … `#mac/hud/error` — seven states

## The problem

The HUD is the most-shipped surface and the one the mock changed least in structure and most in
content. It gains the **provenance chip** — plane, route and machine on the panel — and the
four states the shipped panel does not draw.

The chip matters most here because this is where somebody is actually looking. A person sees
"Typing into Search in Mail" and cannot tell whether that went through the accessibility plane
in the background or through the shared event stream with the machine taken. Those prove
different things.

## Acceptance criteria

1. **A1** — all seven states resolve to their character asset at 1x/2x/3x, and the existing
   asset test extends to the chip content per state.
2. **A2** — `idle` renders no Pause and no Stop; every other state renders Stop.
3. **A3** — the chip's plane and route come from `StepResult` and are never inferred. A test
   with a `routedEvent` and an `unknown` plane asserts neither is described as background-safe.
4. **A4** — step text renders through `StepDescription`'s fence; a test asserts a raw string
   cannot reach the view. An app's own accessibility title carries the same injection payload a
   model's supplied name does.
5. **A5** — the panel ignores mouse events while a synthetic step is in flight. Existing
   behaviour, re-asserted because this redraw touches the view implementing it.
6. **A6** — every new drawing path goes through `ProctorCatch`.

## Decisions taken at triage

- **`ProctorCatch` is the highest-consequence constraint in the wave.** This panel is drawn by
  the *agent* process. AppKit raises `NSException`, Swift cannot catch one, and an uncaught one
  aborts the process — taking the run and the MCP server with it.
- **A synthetic click must not reach Stop.** PRO-0015 found this with a completeness critic
  rather than a build: a click Proctor posts under the panel can land on Stop and halt the run
  that posted it. The guard exists and the redraw does not step around it.
- **SF Symbols, not the mock's inline SVG.** The mock draws glyphs inline because a
  self-contained HTML file cannot bundle symbols. The symbol name per state is part of this
  item's Core value, tested for presence so a typo is a red test rather than a blank panel.

## Out of scope

`sharingType = .none` stays. Two campaign cases are permanently `n/a` because the panel cannot
be photographed by Proctor's own capture path, and that exclusion is deliberate: evidence must
not change because somebody was watching. Neither case is to be "fixed" into a pass.
