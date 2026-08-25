---
sources: [REQ-001]
status: retired
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

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-001
- surface: SURF-001, SURF-002
- cases: CASE-0001, CASE-0002, CASE-0038, CASE-0074, CASE-0154, CASE-0370
- rungs reached: metamorphic, outcome
- provider: none
