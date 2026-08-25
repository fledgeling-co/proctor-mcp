---
sources: [REQ-001]
status: retired
---
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

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-001
- surface: SURF-001, SURF-002
- cases: CASE-0001, CASE-0002, CASE-0038, CASE-0074, CASE-0154, CASE-0370
- rungs reached: metamorphic, outcome
- provider: none
