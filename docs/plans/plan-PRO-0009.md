# Plan PRO-0009: Process kill + filesystem jail

**Spec:** docs/specs/spec-PRO-0009.md · **Tier:** Small · **Branch:** ai/pro-0009

## Shape

Two utilities, built the way PRO-0005 built the policy gate: the load-bearing
decision/serialisation logic is **pure and lives in ProctorCore** (so it is
`swift test`-able, since the test target depends only on ProctorCore); the
platform-touching glue (NSRunningApplication, kill(2), env, capture write path)
is a thin agent extension over the tested units. No parallel safety mechanism —
`process_kill` reuses `AppPolicy.decide` and the `AuditLog`; the jail reuses the
`.policyDenied` error code and audit conventions.

## 1. Filesystem jail (containment convention)

**`Sources/ProctorCore/FSJail.swift`** (new, pure):
- `FSJail(roots:)` — normalises declared roots (symlink-resolved, absolute).
- `check(_ path:) -> Decision` (`.allow(resolved:)` / `.refuse(reason:)`):
  - **Inert when no roots declared** — admits any path, so installing changes
    nothing until an operator sets `FS_ROOTS` (matches empty-policy-allows-all).
  - Rejects a raw `..` traversal component before resolution (named reason).
  - Resolves symlinks on the longest existing path prefix via `realpath(3)`,
    re-appends the literal tail, and admits only paths at or under a root
    (path-boundary prefix, so `/rootX` is not admitted by root `/root`).
  - Symlink-escape (a link inside a root pointing out) resolves out → refused.
- `parseRoots(_:)` — colon-separated list parse, drops empties.

**`Sources/ProctorAgent/Session/SessionFSJail.swift`** (new, glue):
- Lazily builds `fsJail` from `PROCTOR_FS_ROOTS`.
- `enforceFSJail(path:)` — throws `.policyDenied` on refusal; no-op when the
  caller supplied no path or no roots are declared.

**Wiring:** `Session.captureWindow` calls `enforceFSJail(path:)` on a
caller-supplied write path (one guard line). Declared roots surface in
`proctor_policy status` (`fsRoots`) for auditability.

## 2. process_kill

**`Sources/ProctorCore/ProcessControl.swift`** (new, pure):
- `ProcessInfoLite(pid,name,bundleId)`, `KillQuery(pid,bundleId,name,match)`,
  `KillSignal(.term/.kill)`.
- `ProcessMatcher.select(_:query:)` — conjunction over pid (exact) / bundleId
  (case-insensitive exact) / name (case-insensitive substring|exact). Empty
  query matches nothing.
- `ProcessMatcher.isProtected(pid:selfPid:)` — pid ≤ 1 or self.
- `killAudit(...) -> AuditRecord` — target + outcome, no secret slots set.

**`Sources/ProctorAgent/Session/SessionKill.swift`** (new, glue):
- Enumerate `NSWorkspace.runningApplications` (+ synthesise a bare-pid target).
- `select`, drop protected pids.
- `list` action: report matches. `kill` action: gate each target through
  `policy.decide`, audit (ok/failed/refused), deliver `terminate()` /
  `forceTerminate()` (or `kill(2)` for non-GUI pids). `force` → SIGKILL.

**`proctor_kill` tool** added to `ToolCatalogue.all` (auto-surfaces via shim),
dispatch case + decode in `Dispatch.swift`. `readOnly:false, destructive:true,
idempotent:false`. **Tool count 17 → 18.**

## Acceptance clauses → proving test (all ProctorCoreTests, red→green)

| # | Clause | Test |
|---|---|---|
| AC1 | in-root path admitted | `FSJailTests/inRootAllowed` |
| AC2 | `..` traversal refused w/ reason | `FSJailTests/dotDotRefused` |
| AC3 | symlink escape refused (resolved) | `FSJailTests/symlinkEscapeRefused` |
| AC4 | unconfigured jail is inert | `FSJailTests/emptyIsInert` |
| AC5 | name-prefix sibling outside root refused | `FSJailTests/prefixBoundaryRefused` |
| AC6 | `FS_ROOTS` colon parse | `FSJailTests/parseRoots` |
| AC7 | matcher selects by pid/bundleId/name, conjunction | `ProcessControlTests/matchByEach`,`matchConjunction` |
| AC8 | name exact vs substring, case-insensitive | `ProcessControlTests/nameMatchModes` |
| AC9 | empty query matches nothing | `ProcessControlTests/emptyQueryMatchesNothing` |
| AC10 | self / pid≤1 protected | `ProcessControlTests/protectedPids` |
| AC11 | kill reuses policy gate (block/allow-list/sensitive) | `ProcessControlTests/policyGateGovernsKill` |
| AC12 | kill audit names target+outcome, no secret slot | `ProcessControlTests/killAuditShape` |
| AC13 | `proctor_kill` advertised, count 18, destructive+non-idempotent | `CatalogueTests/count`,`AnnotationTests/destructiveSet`,`killIsDestructive` |

## Out of scope (per spec)
Whole-process sandboxing, non-file resource jailing, killing arbitrary daemons
beyond name/PID targeting.
