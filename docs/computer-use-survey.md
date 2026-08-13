# Computer-use MCP survey — 2026-08-13

Provenance and non-brief context for the candidate features in
`docs/features-to-triage/`. This file lives outside that directory on purpose:
`ship-fleet` treats every `*.md` under `docs/features-to-triage/` (except
`LEDGER.md`) as an untriaged feature brief, so baseline/rejected/reference
material must not sit there.

## What was surveyed

Two third-party computer-use MCP servers, read-only, for capability ideas:

- **`github.com/domdomegg/computer-use-mcp`** — single `computer` tool
  (Anthropic computer-use schema) over nut.js synthetic events; full-screen
  capture; global pixel coordinates, no window/element model.
- **`github.com/zavora-ai/computer-use-mcp`** — Rust NAPI native core, 64 tools,
  synthetic `CGEvent` actuation, `NSWorkspace`/`CGWindowList`/`AXUIElement`
  targeting, `screencapture` CLI, clipboard, app management.

Both are **foreground, focus-stealing, synthetic-event** tools: they need the
target frontmost, cannot drive background/occluded/other-Space windows or a
locked Mac, and their "settle" is a bare `sleep`. Proctor is architecturally a
superset of both. Ten additive ideas were extracted; they are the briefs in
`docs/features-to-triage/`.

**Licensing:** both repos are MIT. Borrowing is permitted with attribution, but
the recommendation in every brief is to **reimplement the idea** on Proctor's
AX / Apple-Events / SCK plane, not to lift synthetic-event code that does not fit
that plane.

## Candidate briefs (in the triage dir)

| File | Feature | Value | Effort |
|---|---|---|---|
| 01 | Stock CUA schema façade (Anthropic + OpenAI) | high | med |
| 02 | Set-of-marks annotated captures | high | med |
| 03 | Menu-bar enumeration with key-equivalents | med-high | easy |
| 04 | App scripting-dictionary introspection | med-high | med |
| 05 | Redacting audit trail + policy/approval gate | med-high | med |
| 06 | Vision-capture normalisation + reported scale | med | easy |
| 07 | Zoom native-resolution region crop | med | easy |
| 08 | MCP surface modernization | med | easy |
| 09 | Process kill + filesystem jail | med | easy |
| 10 | Pointer / target overlay in captures | low-med | low |

## Shipped baseline (already in the product / on the marketing site)

Listed so candidates are triaged against a known floor, not re-proposed:

- Background / occluded / other-Space operation via AX + Apple Events, no focus
  steal.
- Runs while the Mac is locked; optional `proctor_unlock` turn (TTL, relock,
  password fallback).
- ScreenCaptureKit window capture with freshness (frame status, dirty rects,
  content rect).
- Reflector (owned apps): resolved colours/fonts/radius/constraints, CALayer
  model + presentation, render revision.
- Tools: attach, snapshot (pruned AX tree, stable ids, since-revision diffs),
  find, act (batched, per-step settle + post-state hash + diff), capture, wait,
  assert, flow (record + replay), stability (replay N, first divergence),
  inspect, doctor.
- Settle as a conjunction (never a bare sleep); determinism by replay;
  tri-observer disagreement as a defect oracle.
- Not blocked by Secure Event Input; MCP over stdio and HTTP with bearer token;
  stable TCC identity via a launchd user agent.

## Considered and rejected (out of scope)

Recorded so they are not re-proposed:

- **All synthetic-event / foreground / focus-steal actuation** — Proctor's plane
  is superior.
- **Focus-contention recovery** (`FocusFailure` / `suggestedRecovery`,
  `prepare_display`) — moot when actuation doesn't depend on foreground focus.
- **Windows / Linux-only**: `registry`, DXGI capture, toast `notification`,
  `resize_window`, virtual-desktop lifecycle, `xdotool`, the `screencapture`-CLI
  capture fallback. Not relevant to a macOS-first tool.

## Marketing-site note

The site markets shipped capability only. Of the candidates, **01** and **02**
earn a site place *once built* (01 → "any agent" story; 02 → vision/testing
story). Nothing above is on the site today, and nothing should be until it
exists.
