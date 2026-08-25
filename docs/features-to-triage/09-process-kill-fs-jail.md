---
sources: [REQ-016]
status: retired
---
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

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-016
- surface: SURF-001, SURF-012
- cases: CASE-0001, CASE-0017, CASE-0018, CASE-0038, CASE-0061, CASE-0076
- rungs reached: effect-witness, metamorphic, outcome
- provider: none
