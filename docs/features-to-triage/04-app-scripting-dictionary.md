---
sources: [REQ-001]
status: retired
validated-by: REQ-001 via CASE-0001, CASE-0002
validated-rungs: outcome
validated-provider: none
---
# App scripting-dictionary introspection

**Status:** untriaged · **Value:** med-high · **Effort:** medium · **Source:** zavora-ai/computer-use-mcp (`get_app_dictionary`, `get_app_capabilities`)
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
A tool that reads an app's **scripting definition (sdef)** — suites, commands, classes, properties — and returns it as structured data, cached per PID. Optionally a shorter `get_app_capabilities` / tool-guide summary that says what the app can be told to do via Apple Events.

## Why (for computer use / testing)
It makes the **Apple-Events plane self-describing**. Instead of an agent guessing whether an app is scriptable or hard-coding AppleScript, it can query the app's own dictionary and choose the cheapest reliable route per task: scripting (exact, fast) vs AX (universal) vs pixels (last resort). This directly amplifies Proctor's existing AppleEvents driver.

## Proposed approach on Proctor
- Resolve the app's sdef (from the bundle, or via the Open Scripting Architecture) for the attached PID; parse suites/commands/classes/properties.
- Cache per PID (invalidate on relaunch); return a compact structured form plus a one-line capability summary.
- Surface it to the agent as a hint feeding route selection in `act` (scripting-vs-AX-vs-pixels).

## Scope
- In: sdef parse, per-PID cache, structured output, capability summary.
- Out: executing arbitrary scripting commands blindly (actuation stays through `act` with settle + provenance).

## Success looks like
For a scriptable app, `get_app_dictionary` returns its commands and classes, and an `act` flow chooses the scripting route where it's exact and falls back to AX where it isn't.

## Dependencies / notes
- Pairs with the AppleEvents driver already in place; pairs with 03 (menu shortcuts) as the "prefer the precise route" theme.
- Licensing: reimplement sdef parsing; MIT source.
