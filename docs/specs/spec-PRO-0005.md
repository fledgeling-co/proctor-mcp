# PRO-0005: Audit trail + policy gate

**ID:** PRO-0005
**Status:** Ready for Plan
**Created:** 2026-08-13
**Last updated:** 2026-08-13

## Feature description

# Redacting audit trail + policy / approval gate

**Status:** untriaged · **Value:** med-high · **Effort:** medium · **Source:** zavora-ai/computer-use-mcp (policy lists, `approval_token`, redacting JSONL audit)
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
Two paired safety rails: (1) a **policy gate** — app allow/block lists and a credential-app approval step that requires an `approval_token` before Proctor drives a sensitive app; and (2) a **redacting audit trail** — a JSONL log of every action where free text, typed values, and script bodies are reduced to length + SHA-256 rather than stored in the clear.

## Why (for computer use / testing)
A tool with full control of a Mac — and one that can run **locked and unattended** — should be able to prove what it did without leaking what it typed. The audit trail matters *more* for Proctor than for a foreground tool precisely because of the unlock capability: an operator needs an after-the-fact record, and a redacted one is safe to keep. The policy gate stops an agent wandering into a password manager or banking app by accident.

## Why the redaction (not plain logging)
Passwords, tokens, and personal data pass through `type` / `setValue`. Logging them verbatim turns the audit trail into the biggest secret-leak in the system. Length + hash proves "a value was entered here, and it was *this* value" (verifiable against a known input) without storing the secret.

## Proposed approach on Proctor
- Allow/block lists keyed by bundle id; a configurable "sensitive app" set that requires an `approval_token` (short-lived, like the unlock turn's TTL) before actuation.
- Append-only JSONL audit: timestamp, tool, target (app/window/element id), outcome, post-state hash; values and scripts stored as `{len, sha256}`.
- Tie into the existing unlock-turn and doctor surfaces.

## Scope
- In: allow/block policy, approval token for sensitive apps, redacting JSONL audit.
- Out: a full RBAC system; encryption-at-rest of the log (note as a follow-up if wanted).

## Success looks like
An attempt to drive a blocked app is refused without a token; a completed run leaves a JSONL audit where no secret is readable but every action is accounted for.

## Dependencies / notes
- Strongest paired with the locked/unattended capability already shipped.
- Licensing: reimplement; MIT source.

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S2 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible in a product UI — this is operator-facing safety plumbing. Adds app allow/block lists, an approval token for sensitive apps, and a redacting JSONL audit log.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Compliance]` Typed values and scripts are stored as length + SHA-256, never in clear. (secret-safe audit)
- `[Compliance]` Approval tokens are short-lived (TTL), like the unlock turn. (bounded authority)
- `[Operations]` Blocked-app actuation is refused with a clear reason. (fail-closed)
- `[Data & scope]` Encryption-at-rest of the log is out of scope for this pass. (follow-up if wanted)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0005` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).
