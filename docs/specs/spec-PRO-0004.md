# PRO-0004: App scripting-dictionary introspection

**ID:** PRO-0004
**Status:** Merged
**Plan:** docs/plans/plan-PRO-0004.md
**Created:** 2026-08-13
**Last updated:** 2026-08-13

## Feature description

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

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible — behind the scenes. Exposes an app’s sdef (suites/commands/classes) as structured data, cached per PID.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Data & scope]` Read-only sdef parse; actuation still routes through act with settle. (no blind scripting)
- `[Operations]` Cache invalidated on app relaunch (PID change). (avoids stale dictionaries)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0004` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).
