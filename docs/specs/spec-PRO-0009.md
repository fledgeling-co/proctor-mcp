# PRO-0009: Process kill + filesystem jail

**ID:** PRO-0009
**Brief:** `docs/features-to-triage/09-process-kill-fs-jail.md`
**Status:** Merged
**Created:** 2026-08-13
**Last updated:** 2026-08-13
**Plan:** docs/plans/plan-PRO-0009.md

## Feature description

# Process kill + filesystem jail

**Status:** untriaged · **Value:** medium · **Effort:** easy · **Source:** zavora-ai/computer-use-mcp (`process_kill`, `FS_ROOTS`)
<!-- Surfaced 2026-08-13 from a survey of two third-party computer-use MCPs. Provenance + licensing: docs/computer-use-survey.md -->

## What it is
Two small test-harness utilities: (1) **`process_kill`** — list and terminate processes by name/PID, for test setup/teardown (relaunch an app into a known state, kill a hung target); and (2) a **filesystem jail** — an `FS_ROOTS` allow-list that any file operation must stay within, rejecting `..` traversal and symlink escape.

## Why (for computer use / testing)
Real test campaigns need to reset state between runs: kill the app under test, relaunch it clean, and know it started fresh. The filesystem jail is a **containment convention** — a tool with broad control should not be able to read or write outside a declared root, and stating the root up front makes that guarantee auditable.

## Proposed approach on Proctor
- `process_kill`: wrap `NSRunningApplication` / signal delivery; list by bundle id / name / PID; return what was terminated. Gate behind the policy/annotation layer (05, 08) since it's destructive.
- FS jail: a configured set of allowed roots; every file path Proctor touches is resolved (symlinks included) and checked to be inside a root, else refused.

## Scope
- In: list/kill processes, configurable FS root allow-list with traversal/symlink rejection.
- Out: sandboxing the whole process (that's the OS's job); managing non-file resources.

## Success looks like
A test flow kills and relaunches the target app to reset state; a file operation outside the declared roots is refused with a clear reason.

## Dependencies / notes
- `process_kill` is destructive → annotate it (08) and gate it (05).
- Licensing: reimplement; MIT source.

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions (Swift/macOS backend feature; no customer-facing UI surface)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** Nothing visible — behind the scenes. Adds list/kill of processes for test setup-teardown and an FS root allow-list rejecting traversal/symlink escape.
- **Behaviour changes:** a new or extended MCP capability for driving/observing macOS apps; existing tools and their contracts are unchanged.

**Assumptions**
- `[Compliance]` process_kill is destructive → annotated and gated behind the policy layer. (depends on PRO-0008/PRO-0005 conventions)
- `[Operations]` File paths are resolved (symlinks included) and checked inside a declared root. (containment)

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0009` before the planner picks this up.*

**Grounding note:** the plane/tool this builds on exists in `Sources/` today (AX + Apple Events driver, ScreenCaptureKit capture, the tool catalogue in ProctorCore). This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). The out-of-family Codex review gate is unavailable on this machine, so triage review ran in-family (logged downgrade).

---

## Progress — 2026-08-13

**Status: In Review** (branch `ai/pro-0009`, not merged)

Delivered on `ai/pro-0009`:
- **Filesystem jail** — `Sources/ProctorCore/FSJail.swift` (pure: symlink-resolved
  containment, `..` rejection, path-boundary check, inert when unconfigured),
  loaded from `PROCTOR_FS_ROOTS` and enforced on caller-supplied `proctor_capture`
  paths (`Session/SessionFSJail.swift`). Declared roots surfaced in
  `proctor_policy status` (`fsRoots`) for auditability.
- **process_kill** — `proctor_kill` tool (list/kill by pid/bundleId/name); pure
  matcher + authorisation in `Sources/ProctorCore/ProcessControl.swift`, agent
  signal delivery in `Session/SessionKill.swift`. Reuses the PRO-0005 policy gate
  (`AppPolicy.decide`) and audit trail (`AuditLog`); kernel/launchd/self protected.
- Tool count 17 → 18.

Gate: `swift build` clean; `swift test` 132 tests / 20 suites pass, including new
suites "Filesystem jail" and "Process control".

Downgrade: Codex gpt-5.6-sol lane unavailable on this machine — executor and
review gates ran in-family (Claude).
