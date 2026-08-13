# Plan — PRO-0008: MCP surface modernization

**Spec:** docs/specs/spec-PRO-0008.md (Status: Ready for Plan)
**Branch:** ai/pro-0008 · **Worktree:** .worktrees/PRO-0008
**Plan size:** Standard (protocol-layer only; no new macOS capability, no transport change)
**Gate:** `swift build && swift test` from the worktree root

## Scope (from the spec, authority = its Feature description)

Four MCP-protocol ergonomics, all in scope:

1. **Tool profiles** at launch (`core | ax | scripting | full`) — a host loads a trimmed
   `tools/list` instead of the whole surface.
2. **MCP resources** — `display`, `windows`, `frontmost`, and a cache-only
   `screenshot/latest` — exposed as readable resources.
3. **Tool annotations** — `readOnlyHint` / `destructiveHint` / `idempotentHint` per tool.
4. **Output schemas** — a per-tool `outputSchema` on the advertised tool.

Out (spec): changing tool behaviour, changing the transport (stdio/HTTP unchanged), new
macOS surface. This is metadata + a discovery filter + a re-projection of state the agent
already produces.

## Grounding — what exists today

- `Sources/ProctorCore/ToolCatalogue.swift` — 12 `ToolSpec`s (`apps, snapshot, find, act,
  capture, wait, assert, flow, stability, inspect, doctor, unlock`); each has
  `name/title/description/inputSchema/readOnly`. Shared by shim (advertises) and agent
  (dispatches). **`unlock` is present but the count test still asserts 11 — a stale test
  from the sibling `unlock` merge; baseline `swift test` is red on that one case.**
- `Sources/ProctorShim/MCPServer.swift` — stdio JSON-RPC. `initialize` advertises only
  `tools`; `tools/list` maps `ToolCatalogue.all` through `toolEntry` (which already emits
  `annotations.readOnlyHint`); `tools/call` forwards to the agent over `SocketClient`.
  `response(for:)` is a pure function of one message — shared with the HTTP path.
- `Sources/ProctorShim/RemoteServer.swift` — HTTP transport; owns one `MCPServer()` and
  forwards to the same `response(for:)`. Each POST is `Connection: close` (no session
  continuity across requests).
- `Sources/ProctorShim/main.swift` — CLI entry; `serve` (+ `--remote` flags).
- `Sources/ProctorAgent/Dispatch.swift` — `route()` switches on tool name; unknown tools
  throw. `Session.listApps` already returns apps + attached-window handles.
- `Sources/ProctorAgent/Session/Session.swift` — `actor Session`; `captureWindow` returns
  the encoded `CaptureResult`. `NSWorkspace`/`NSScreen` are already linked in the agent
  (AXEngineImpl, StreamCapture, Actuator import AppKit).
- `Sources/ProctorCore/Transport.swift` — `public final class SocketClient { func send(_:) }`.

## Design decisions (and why)

- **Profile is launch-time config, not an `initialize` param.** The shim is deliberately
  stateless per message and the HTTP path closes the connection after every POST, so a
  profile chosen in `initialize` could not survive to the `tools/list` call over HTTP.
  A launch flag works identically over stdio and HTTP: `proctor-shim serve --profile core`
  (env `PROCTOR_PROFILE` fallback). Unknown/absent → `full`.
- **Profiles form a nested hierarchy** so membership is obvious and testable:
  `ax ⊂ core ⊂ scripting ⊂ full`.
  - `ax` = apps, snapshot, find, act, wait, assert, doctor (accessibility only).
  - `core` = ax + capture (the observe/drive/verify loop).
  - `scripting` = core + flow, stability (campaign authoring).
  - `full` = everything (adds inspect, unlock).
  Every profile contains `apps` and `doctor` (nothing works without attach; doctor is the
  "run first" tool).
- **Profile filters discovery only.** `tools/list` is trimmed; `tools/call` still accepts
  any real tool. Rejecting a valid call based on profile would be a behaviour change (out
  of scope) and would surprise a host; hard gating of dangerous tools is what the
  `destructiveHint` annotation is for.
- **Annotations, MCP-faithful.** `destructiveHint`/`idempotentHint` are "meaningful only
  when `readOnlyHint == false`" (MCP 2025-06-18), so they are emitted only for non-read-only
  tools. `destructive == true` for tools that can alter target-app/system state a host would
  gate: `act`, `flow`, `stability` (all actuate/replay), `unlock` (screen). `apps` is
  non-read-only but non-destructive and idempotent (attach/detach/list touch no target
  state). This matches the spec's "gate act/unlock" and extends it principled to flow/stability.
- **`outputSchema` is permissive and advisory.** `ToolCatalogue.outputSchema(for:)` returns
  a `type:object` schema documenting the known top-level fields of each tool's success
  payload, with no `additionalProperties:false` and no over-strict `required` — so a richer
  success payload never fails validation. Error results (`isError:true`) carry the error
  object, matching how SDK clients validate (success only). Kept in a separate file so
  `ToolCatalogue.swift` stays a small diff.
- **Resources are agent-backed re-projections, forwarded by the shim.** The shim stays a
  pure forwarder: `resources/read` maps the `proctor://` URI to an internal verb
  `proctor_resource` (never in the catalogue, so a host cannot call it as a tool) and
  forwards it over the existing `SocketClient`. The agent answers from data it already has
  or can read without any TCC grant:
  - `proctor://windows` → `Session.listApps` (existing).
  - `proctor://frontmost` → `NSWorkspace.frontmostApplication` (+ main window if attached).
  - `proctor://display` → `NSScreen.screens` geometry/scale.
  - `proctor://screenshot/latest` → cache-only last `CaptureResult`; never triggers a
    capture (so it needs no Screen Recording grant) and returns `{cached:false}` until one
    exists. Consistent with the design rule that capture bytes are never returned inline —
    the resource returns the metadata + on-disk path, not the PNG.
  All resource contents are `application/json` text.

## Changes

### ProctorCore (shared)
- `ToolCatalogue.swift`: add `destructive: Bool` and `idempotent: Bool` to `ToolSpec`
  (init defaults `destructive:false, idempotent:true` so read-only/`apps` specs are
  unchanged); set `destructive:true, idempotent:false` on `act`, `flow`, `stability`,
  `unlock`.
- New `ToolProfiles.swift`: `enum ToolProfile { core, ax, scripting, full }` with
  `init?(argument:)`, `names`, and `ToolCatalogue.tools(for:)`.
- New `ToolOutputSchemas.swift`: `ToolCatalogue.outputSchema(for name:) -> JSONValue`,
  a per-tool permissive object schema (falls back to `{type:object}`).
- New `ResourceCatalogue.swift`: `ResourceSpec { uri, key, name, title, description,
  mimeType }`, `ResourceCatalogue.all` (the 4), `spec(uri:)`.

### ProctorShim
- `MCPServer.swift`: `init(profile:)`; advertise `resources:{}` in `initialize`;
  `tools/list` uses `ToolCatalogue.tools(for: profile)`; `toolEntry` emits
  `destructiveHint`/`idempotentHint` (non-read-only only) and `outputSchema`; add
  `resources/list` and `resources/read` (forward `proctor_resource`, wrap `contents`,
  `-32002` on unknown URI). Factor the agent call out of `callTool` for reuse.
- `main.swift`: parse `--profile` / `PROCTOR_PROFILE`; pass to `MCPServer` and
  `RemoteServer`; document in usage.
- `RemoteServer.swift`: carry `profile` in `RemoteConfig`; build `MCPServer(profile:)`.

### ProctorAgent
- `Dispatch.swift`: `case "proctor_resource"` → `session.resource(key:)`.
- `Session.swift`: `import AppKit`; `resource(key:)` for the four keys; `private var
  lastCapture: JSONValue?` set in `captureWindow` after a successful capture.

### Tests (Tests/ProctorCoreTests)
- Fix the stale count assertion `11 → 12`.
- Profiles: nesting `ax ⊂ core ⊂ scripting ⊂ full`; every profile ⊆ `all` and ⊇
  `{apps, doctor}`; `full == all`; `ToolProfile(argument:)` parsing incl. unknown→nil.
- Annotations: `destructive` set == `{act, flow, stability, unlock}`; every read-only tool
  has `destructive==false`; `act.idempotent==false`.
- Output schemas: every tool's `outputSchema(for:)` is a non-empty `type:object`.
- Resource catalogue: the four expected URIs; `spec(uri:)` round-trips; each has
  `application/json` and a non-empty description.

## Verification

Per-clause red→green in `Tests/ProctorCoreTests` (the only test target; all new logic is
pure ProctorCore), then `swift build && swift test` green from the worktree. The runtime
wiring (shim `resources/read` → agent) is exercised structurally by the catalogue/registry
tests; the live agent path needs a granted macOS host and is out of unit-test reach —
noted, not silently skipped.

## Deferred / not done
- No `resources/templates/list`, `subscribe`, or `listChanged` (capability advertises
  neither; the four resources are static URIs).
- Profile-gated `tools/call` rejection deliberately not implemented (behaviour change).
