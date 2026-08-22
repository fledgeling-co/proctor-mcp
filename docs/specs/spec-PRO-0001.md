# PRO-0001: CUA schema façade

**ID:** PRO-0001
**Brief:** `docs/features-to-triage/01-cua-schema-facade.md`
**Status:** Merged
**Created:** 2026-08-13
**Last updated:** 2026-08-13
**Plan:** [plan-PRO-0001.md](../plans/plan-PRO-0001.md)

## Feature description

# Stock computer-use schema façade (Anthropic + OpenAI)

**Status:** untriaged · **Value:** high · **Effort:** medium · **Source:** both surveyed repos (domdomegg mirrors Anthropic's `computer` schema; zavora ships an `openai_computer` adapter)
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
An optional Proctor tool (or tool pair) that exposes the stock **Anthropic `computer`** action schema and **OpenAI `openai_computer`** batched-action schema, and maps those actions onto Proctor's native AX / Apple-Events `act`. The native toolset stays available and unchanged; this is an adapter layer, not a replacement.

## Why (for computer use / testing)
Models trained on the Anthropic or OpenAI computer-use tool schemas can drive Proctor with **zero adaptation**. This is the single biggest adoption lever: it makes "computer use for any agent" literally true for the two schemas most off-the-shelf agents already speak, without asking the model vendor to learn Proctor's richer native API.

## Proposed approach on Proctor
- Translate `key` / `type` / `mouse_move` / `left_click` / `scroll` / `screenshot` (Anthropic) and OpenAI's batched CUA actions into Proctor `act` steps.
- Map coordinate-space actions onto AX targets where possible (hit-test the point to the AX element), falling back to point actuation; keep per-step settle + post-state hash so even schema-driven runs stay deterministic.
- OpenAI adapter: batch of actions, **stop on first error**, return per-step outcome (matches zavora's shape).
- Report the translation in provenance so a run driven through the façade is auditable.

## Scope
- In: the two schemas above, mapped to `act`; coordinate→AX hit-testing; provenance of translated steps.
- Out: inventing a third bespoke schema; changing the native tool surface.

## Success looks like
A stock Anthropic or OpenAI computer-use agent, pointed at Proctor with no prompt changes, completes a multi-step task on a real macOS app, and the run is deterministic and auditable.

## Dependencies / notes
- Pairs with the native `act` / hit-test path already in place.
- Site-relevant once shipped: upgrades the "works with your stack" copy to "including Anthropic/OpenAI computer-use models, unmodified."
- Licensing: reimplement the schema mapping on Proctor's plane; do not lift synthetic-event code (MIT sources, attribution if any snippet is reused).

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible — behind the scenes. Adds an alternate MCP tool surface (Anthropic/OpenAI computer-use schemas) mapping onto the existing act path.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Data & scope]` Both schemas map onto existing act + hit-test; no new actuation plane. (reuses shipped act)
- `[Experience]` Native tool surface stays unchanged; façade is additive and opt-in. (adoption layer, not a replacement)
- `[Operations]` Translated steps recorded in provenance for auditability. (matches existing provenance discipline)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0001` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).
