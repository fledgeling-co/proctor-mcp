# ORCHESTRATOR — Proctor remaining-work plan & ledger

**Status:** Running
**Updated:** 2026-08-13 — batch 1 launched (3-concurrent): PRO-0002, PRO-0008, PRO-0001 running.

## How to resume
You are the fleet orchestrator (ship-fleet skill). Read this file top to bottom, reconcile
the ledger below against reality (`docs/feature-specs/LEDGER.md`, `docs/specs/*`,
`git worktree list`, merged branches), correct drifted rows, then continue filling slots. Rules:
- ≤ **3** concurrent runners (user-chosen, 2026-08-13); an item starts only when every "Depends on" ID has **MERGED**.
- Runners are Opus agents (launched via the verified single-agent-Workflow lane, `model:'opus'`,
  `effort:'high'`, `agentType:'claude'`) that invoke the ship-feature skill and **STOP BEFORE MERGE**;
  the orchestrator serializes all finalization (rebase → gate → merge → worktree cleanup) one branch at a time.
- **This repo has no git remote — `main` is LOCAL-ONLY. "Merge" means merge to local `main`; never push.**
- Serial-only shared writes: `LEDGER.md` (id allocation, done), this file (orchestrator is sole writer),
  the `Sources/` tool catalogue (all items touch it → serialize at merge), integration-branch merges.

### Swift adaptation (this repo is NOT a Diolog web app)
- `proctor-mcp` is a **Swift Package**. The acceptance gate is **`swift build` + `swift test`** (new tests
  per acceptance clause), NOT Playwright e2e.
- **Skip** ship-feature's web-only stages: design-craft/DESIGN.md, `design/mocks/html`, mockup-fidelity,
  Playwright acceptance-e2e. There is **no customer-facing UI**; every feature is backend MCP/AX/AppleEvents/SCK work.
- Best-practices context (no CODING_PRACTICES.md here): `README.md`, `docs/architecture.md`, and the existing
  `Sources/ProctorCore` / `ProctorReflector` patterns are the engineering authority.
- Verification is NOT dropped — it is Swift-shaped: typed acceptance evidence = a red→green `swift test`
  per acceptance clause, plus the affected-test sweep. Never ship "verified by code reading".

### External model CLIs
- `external-model-clis: off` — the Codex `gpt-5.6-sol` lane (executor + the three out-of-family review gates)
  is **unavailable on this machine** (relay down). Every gate and executor slice runs **in-family** with a
  **logged downgrade** in the artifact/ledger. This is a **correct** run, not degraded — do NOT burn attempts
  probing Codex. (Recorded as the repo opt-out so any in-flight runner's grep honours it.)

## Wave plan
Wave 1 (no unmerged internal deps — 8 slots): PRO-0001 CUA façade, PRO-0002 set-of-marks, PRO-0003 menu-bar
  shortcuts, PRO-0004 app-dictionary, PRO-0005 audit+policy, PRO-0006 capture-normalisation, PRO-0007 zoom,
  PRO-0008 MCP-surface.
Wave 2 (after their dep merges): PRO-0009 process-kill+fs-jail (soft after PRO-0008 — annotation/gating
  conventions), PRO-0010 pointer-overlay (after PRO-0002 — shared overlay path).
Holding pen (external deps / needs input): none.

## Ledger
| ID | Title | Category | Depends on | Deep research | Mock | Lane | Worktree/branch | Status | Notes / outcome |
|----|-------|----------|------------|---------------|------|------|-----------------|--------|-----------------|
| PRO-0001 | CUA schema façade | ready-for-plan | — | none | none | opus | .worktrees/PRO-0001 · ai/pro-0001 | running | batch 1 |
| PRO-0002 | Set-of-marks captures | ready-for-plan | — | none | none | opus | .worktrees/PRO-0002 · ai/pro-0002 | running | batch 1 · unblocks PRO-0010 |
| PRO-0003 | Menu-bar key-equivalents | ready-for-plan | — | none | none | opus | — | queued | — |
| PRO-0004 | App scripting-dictionary | ready-for-plan | — | none | none | opus | — | queued | — |
| PRO-0005 | Audit trail + policy gate | ready-for-plan | — | none | none | opus | — | queued | — |
| PRO-0006 | Vision-capture normalisation | ready-for-plan | — | none | none | opus | — | queued | — |
| PRO-0007 | Zoom region crop | ready-for-plan | — | none | none | opus | — | queued | — |
| PRO-0008 | MCP surface modernization | ready-for-plan | — | none | none | opus | .worktrees/PRO-0008 · ai/pro-0008 | running | batch 1 · unblocks PRO-0009 |
| PRO-0009 | Process kill + fs jail | ready-for-plan | PRO-0008 (soft) | none | none | opus | — | queued | test setup/teardown + containment |
| PRO-0010 | Pointer overlay in captures | ready-for-plan | PRO-0002 | none | none | opus | — | queued | target marker in flow/stability artifacts |

## Deferred children discovered mid-fleet
| Child | Parent | Where it runs | Status |

## Needs input (consolidated for the user)
- (none yet)

## Event log (append-only, newest first)
- 2026-08-13 pre-triage complete: 10 specs written, all Ready for Plan; LEDGER Last allocated: 10.
- 2026-08-13 baseline committed (8430fd9); site self-hosted its JS (48447f4); scaffold created.
