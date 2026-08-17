# Product Requirements Document (PRD): Proctor

**Document Status:** Approved & Shipped (v0.2.0)  
**Date:** 2026-08-17  
**Owner:** Proctor Engineering Team  
**Scope:** macOS native testing harness, computer-use substrate, and multi-witness verification platform.

---

## 1. Executive Summary & Vision

Proctor is a native macOS agent and Model Context Protocol (MCP) server that provides AI agents with full computer-use and automated UI testing capabilities on a Mac.

Unlike web-only browser automations or coarse coordinate-based VLM drivers, Proctor operates on a foundational thesis:
> **"A result carrying no provenance is indistinguishable from a correct one."**

Every accessibility tree returned by Proctor records its revision, capture timestamp, and derivation method. Every screen capture records its frame status (`SCFrameStatus`), pixel freshness, and dirty-region bounding box. Every actuation records the exact plane (`process-directed` vs. `syntheticEvent`) and specific route (`attribute`, `selectedText`, `scrollBar`, `eventStream`) through which it executed.

Proctor bridges native macOS apps, browser workloads (via Obscura and browser-use), iOS simulators, Maestro test flows, Cua multi-platform actuation backends, and virtualized macOS/Linux/Windows guests (`lume`, `prlctl`), presenting a unified 21-tool MCP surface to LLM hosts.

---

## 2. Target Personas & Use Cases

1. **Autonomous AI Coding Agents (Claude Code, Cursor, Codex):**
   - Execute native macOS UI testing, end-to-end user flows, accessibility audits, and visual fidelity checks.
   - Run background tests on non-frontmost windows without interrupting human work.
2. **Mac Software Engineers & QA Teams:**
   - Record, replay, and deterministically evaluate complex multi-step flows.
   - Measure UI flakiness (`firstDivergence` and per-step instability scores) and tri-observer consistency (`agree`).
3. **Automated CI/CD & Multi-Platform Matrix Testing:**
   - Execute tests in isolated macOS virtual machines (`lume`) or Windows on ARM / Linux VMs (`prlctl`) over SSH unix sockets, preventing host takeover.

---

## 3. System Architecture & Process Model

```
┌────────────────────────────────────────────────────────┐
│   MCP Host (Claude Code, Cursor, Custom Agent Client)  │
└──────────────────────────┬─────────────────────────────┘
                           │ stdio (JSON-RPC)
                           ▼
┌────────────────────────────────────────────────────────┐
│   ProctorShim (Permissionless stdio CLI)               │
└──────────────────────────┬─────────────────────────────┘
                           │ AF_UNIX Domain Socket (Framed JSON)
                           │ ~/Library/Application Support/app.fledgeling.procter/agent.sock
                           ▼
┌────────────────────────────────────────────────────────┐
│   ProctorAgent (Launchd Daemon in Proctor.app)         │
│   Identity: app.fledgeling.procter (Developer ID)      │
│   Activation Policy: Accessory (AppKit Event Loop)     │
├────────────────────────────────────────────────────────┤
│ • AXUIElement (Accessibility Trees, Observers, Writes) │
│ • ScreenCaptureKit (Window-scoped & Vision Captures)   │
│ • CGEventPost (Synthetic Mouse, Keyboard, Drag)        │
│ • Run HUD & Overlay (Per-screen Cocoa Panels)          │
│ • Contention Yield & Input Blocker                     │
│ • Policy Gate & Encrypted/Signed Audit Log             │
│ • Multi-Session Queue & Machine Run Controls           │
│ • Providers: Lume, Prlctl, Cua, Obscura, iOS DeepLink │
└────────────────────────────────────────────────────────┘
```

### 3.1 Process Separation & TCC Privilege Anchor
- **`ProctorShim`:** Stateless, permissionless binary spawned by the host. Forwards requests over a Unix domain socket.
- **`ProctorAgent`:** Long-lived launchd user agent running inside `Proctor.app`. Holds TCC grants (Accessibility, Screen Recording) tied to its Developer ID team signature.
- **Dual Identity Separation:** Linked with an internal `__TEXT,__info_plist` identifier (`app.fledgeling.procter.agent`) preventing LaunchServices collisions with `open -a Proctor`.

### 3.2 Dual Actuation Planes
1. **Process-Directed Plane (`accessibility`, `declared`, `appleEvents`):**
   - Direct IPC to target applications via `AXUIElementPerformAction`, `AXUIElementSetAttributeValue`, and AppleScript dictionaries.
   - Operates on occluded, background, and other-Space windows without stealing focus.
   - Immune to Secure Event Input locks.
2. **Synthetic Event Plane (`syntheticEvent`):**
   - System event-stream injection via `CGEventPost`.
   - Requires foreground activation, moves mouse pointer, and contends with human input.
   - Guarded by Takeover Overlay, Contention Yield, and Input Blocker.

---

## 4. Functional Specifications

### 4.1 The 21-Tool MCP Catalogue

| Tool Name | Domain / Action | Key Capabilities |
|---|---|---|
| `proctor_apps` | Application Lifecycle | List, attach, activate apps. Warm AX trees, enable Chromium AX, report provenance. |
| `proctor_snapshot` | Hierarchy Capture | Full or subtree AX snapshot with durable selectors (`AXIdentifier`) and bounds. |
| `proctor_find` | Selector Query | Fast search by role, label, identifier, or hierarchy without full tree dumps. |
| `proctor_act` | Batched Actuation | Multi-step execution (`click`, `type`, `press`, `scroll`, `hover`, `dragPath`, `setValue`). |
| `proctor_capture` | Screen Capture | Window-scoped SCKit captures with `SCFrameStatus`, scale normalisation, dirty rects. |
| `proctor_zoom` | Visual Inspection | Sub-region high-resolution crop for fine visual analysis and text verification. |
| `proctor_wait` | Settle Synchronization | Multi-signal settle (`allSignalsQuiet`, `reflectorIdle`, `axQuietOnly`). |
| `proctor_assert` | Automated Oracles | Evaluate labels, contrast, touch targets, focus order, and tri-observer `agree`. |
| `proctor_flow` | Record & Replay | Record interactive flows with step hashes, replay flows, and verify divergence. |
| `proctor_stability` | Determinism Analysis | 5-run statistical stability sweep, `firstDivergence` pinpointing, per-step markers. |
| `proctor_inspect` | Reflector Inspection | Read exact computed styles, layout constraints, layer models via `ProctorReflector`. |
| `proctor_doctor` | Environment Diagnostics | Comprehensive health probe (TCC, tools, lanes, secure input, providers). |
| `proctor_unlock` | Keychain / Security | Prompt for authorized keychain unlock for encrypted audit logs. |
| `proctor_computer` | CUA Schema Façade | Anthropic Computer Use API compatible tool interface. |
| `proctor_openai_computer` | OpenAI Schema Façade | OpenAI Computer API compatible tool interface. |
| `proctor_menu` | Menu Introspection | Extract menu items, key equivalents, and execute menu actions. |
| `proctor_dictionary` | AppleScript Introspection | Introspect `.sdef` scripting terminology and generate AppleScript calls. |
| `proctor_policy` | Policy & Audit Governance | Configure action filters, redact patterns, and inspect cryptographically signed logs. |
| `proctor_kill` | Process & Sandbox | Terminate target processes and enforce filesystem jail boundaries. |
| `proctor_ios` | iOS Simulator Driving | Open deep links, inspect simulator targets, and drive iOS flows. |
| `proctor_guest` | VM Target Management | Lifecycle (`list`, `status`, `start`, `stop`, `clone`, `reach`) for `lume` and `prlctl`. |

### 4.2 Witness Tiers & Multi-Platform Matrix

Proctor formalizes platform capabilities into strict witness tiers:

1. **Native Witness Tier (`native`):**
   - **Target:** macOS host, macOS guest VM (`lume`), remote Mac over SSH.
   - **Capabilities:** Full Accessibility tree, `SCFrameStatus` verification, tri-observer `agree`, visual fidelity audit, determinism scoring.
2. **Delegated Witness Tier (`delegated`):**
   - **Target:** Windows / Linux VMs or remote containers via Cua backend.
   - **Capabilities:** Coordinate-based actuation and screenshots.
   - **Rule:** Tree-based assertions and `agree` checks fail-closed with `.skipped("Unsupported on delegated tier")`, never returning a false pass.

### 4.3 Guest Routing & VM Isolation (`lume` / `prlctl`)
- **Isolation:** Guest sessions operate under `gst-<id>` handles, distinct from host window IDs.
- **Auto-Route Refusal Gate:** Takeover batches initiated on the host with `PROCTOR_GUEST` configured are refused with an explicit diagnostic remedy rather than silently taking host control.
- **SSH StreamLocal Tunneling:** Reaches remote/guest Proctor agents by forwarding the Unix domain socket (`ssh -L local.sock:remote.sock`).

### 4.4 User Safety, HUD & Contention Control
- **Per-Screen Run HUD:** Floating Cocoa overlay displaying current step, running character sprite, target badge, and interactive `Pause` / `Stop` buttons.
- **Takeover Shield:** Full-screen translucent veil preventing accidental user input during active synthetic-event batches.
- **Contention Yield:** Detects human mouse movement or keystrokes during a run and yields control immediately.
- **Audit Trail:** HMAC-SHA256 signed audit entries encrypted at rest with CryptoKit (AES-GCM) against keys in the macOS Login Keychain.

---

## 5. Non-Functional & Technical Requirements

1. **Concurrency & Thread Safety:**
   - 100% Swift 6 strict concurrency compliance (`Sendable`, `actor` models, no data races).
   - Zero synchronous lock-taking across asynchronous suspension points.
2. **Performance & Latency:**
   - Batched actuation executes multi-step workflows in a single socket round trip.
   - Normalised screen captures default to vision-optimal resolutions (1280×720 or 1536×960) with sub-second settle times.
3. **Packaging & Security:**
   - Hardened runtime, Developer ID signed, notarised by Apple, and stapled.
   - TCC entitlements configured for launchd user daemon.

---

## 6. Acceptance & Quality Gates

- **Unit & Integration Suite:** `./scripts/test.sh` must pass 100% with 0 failures, 0 timeouts, and clean exit codes.
- **Current Metric:** 1,513 tests across 174 suites passing in under 10 seconds.
- **Deterministic Verification:** Every state transition and policy check verified against isolated test doubles and mock actors.
