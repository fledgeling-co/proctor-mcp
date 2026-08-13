# PRO-0008: MCP surface modernization

**ID:** PRO-0008
**Status:** Ready for Plan
**Created:** 2026-08-13
**Last updated:** 2026-08-13

## Feature description

# MCP surface modernization

**Status:** untriaged · **Value:** medium · **Effort:** easy · **Source:** zavora-ai/computer-use-mcp
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
A cluster of MCP-protocol ergonomics, adopt any or all:
- **Tool profiles** at init (`core | ax | scripting | full`) so a host loads a trimmed tool list instead of the whole surface.
- **MCP resources** — `display`, `windows`, `frontmost`, and a cache-only `screenshot/latest` — exposed as readable resources rather than tool calls.
- **Tool annotations** — `readOnly` / `destructive` / `idempotentHint` — and per-tool `outputSchema`.

## Why (for computer use / testing)
Discoverability and host ergonomics. A large tool list is noise for a host that only needs the core; profiles cut it. `readOnly` / `destructive` hints let a host **gate the dangerous tools** (act, unlock, process-kill) behind its own confirmation UI, which pairs with the policy gate (05). `outputSchema` makes tool results machine-checkable.

## Proposed approach on Proctor
- Add a profile selector honoured at MCP init; map each profile to a tool subset.
- Expose the read-only state (`display` / `windows` / `frontmost` / latest capture) as MCP resources.
- Annotate every tool with the read-only/destructive/idempotent hints and attach `outputSchema` to the structured returns.

## Scope
- In: profiles, resources, tool annotations, output schemas.
- Out: changing tool behaviour or the transport (stdio/HTTP unchanged).

## Success looks like
A host loads the `core` profile and sees a short tool list; it reads `frontmost` as a resource; and it auto-gates `act`/`unlock` because they're annotated destructive.

## Dependencies / notes
- Protocol-layer only; no new macOS surface.
- The destructive annotations reinforce 05 (policy/approval gate).
- Licensing: protocol conventions, not code; MIT source.

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible in the product UI — this is MCP-protocol ergonomics a host consumes: tool profiles, resources, tool annotations, output schemas.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Data & scope]` Tool behaviour and the stdio/HTTP transport are unchanged; this is metadata + a profile filter. (non-breaking)
- `[Operations]` readOnly/destructive annotations let hosts gate act/unlock/process-kill. (reinforces the policy gate)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0008` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).
