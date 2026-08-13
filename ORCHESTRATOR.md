# ORCHESTRATOR — Proctor remaining-work plan & ledger

**Status:** Complete
**Updated:** 2026-08-13 — ALL 10 features MERGED to local `main` @ d237361. 169 tests / 23 suites green, 19 tools advertised. Worktrees + ai/* branches cleaned. One deferred child recorded (pointer marker in stability artifacts).

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
| PRO-0001 | CUA schema façade | ready-for-plan | — | none | none | opus | merged (cleaned) | **MERGED** | batch 1 · +2 façade tools → 14 advertised |
| PRO-0002 | Set-of-marks captures | ready-for-plan | — | none | none | opus | merged (cleaned) | **MERGED** | batch 1 · unblocks PRO-0010 · SetOfMarks+MarkRenderer |
| PRO-0003 | Menu-bar key-equivalents | ready-for-plan | — | none | none | opus | merged (cleaned) | **MERGED** | batch 2 · proctor_menu |
| PRO-0004 | App scripting-dictionary | ready-for-plan | — | none | none | opus | merged (cleaned) | **MERGED** | batch 2 · proctor_dictionary |
| PRO-0005 | Audit trail + policy gate | ready-for-plan | — | none | none | opus | merged (cleaned) | **MERGED** | batch 2 · proctor_policy (fail-closed gate + redacting audit) |
| PRO-0006 | Vision-capture normalisation | ready-for-plan | — | none | none | opus | merged (cleaned) | **MERGED** | batch 3 · capture normalize option (no new tool) |
| PRO-0007 | Zoom region crop | ready-for-plan | — | none | none | opus | merged (cleaned) | **MERGED** | batch 3 · proctor_zoom |
| PRO-0008 | MCP surface modernization | ready-for-plan | — | none | none | opus | merged (cleaned) | **MERGED** | batch 1 · proctor_resource |
| PRO-0009 | Process kill + fs jail | ready-for-plan | PRO-0008 ✓ | none | none | opus | merged (cleaned) | **MERGED** | batch 3 · proctor_kill + FSJail (reuses PRO-0005 rails) |
| PRO-0010 | Pointer overlay in captures | ready-for-plan | PRO-0002 ✓ | none | none | opus | merged (cleaned) | **MERGED** | batch 4 · opt-in pointer marker on act/flow per-step captures |

## Deferred children discovered mid-fleet
All three SCHEDULED 2026-08-13 (whats-left ingest, reader answered "all three") — promoted to backlog briefs + ledger rows, not yet triaged.
| Child | Parent | Backlog item | Status |
| Pointer marker in proctor_stability per-step artifacts | PRO-0010 | PRO-0011 (`docs/features-to-triage/11-stability-per-step-pointer.md`) | **Scheduled** — untriaged (needs per-step PNG emission first) |
| Re-gate flow replay + stability through the policy gate & audit | PRO-0005 | PRO-0012 (`docs/features-to-triage/12-gate-flow-replay-stability.md`) | **Scheduled** — untriaged (security) |
| Encryption-at-rest for the JSONL audit log | PRO-0005 | PRO-0013 (`docs/features-to-triage/13-audit-log-encryption-at-rest.md`) | **Scheduled** — untriaged (security) |

## Needs input (consolidated for the user)
- **Runner model was Opus 4.8, not Opus 5.** Every runner self-checked as `claude-opus-4-8[1m]` at high effort; the fleet convention names `claude-opus-5`, which is not the model actually served on this machine. All work is gated green (build + red→green tests per clause), so this did not degrade the run — flagging only so the convention string can be corrected if desired.
- **Three deferred children above** are logged, not scheduled. Say if you want any promoted to a new fleet item.

## Event log (append-only, newest first)
- 2026-08-13 whats-left follow-through (reader's clarifying answers): README updated to document all 19 tools (was 11) + new capture options. **Repo is no longer local-only** — pushed public to `fledgeling-co/proctor-mcp` (secret-scanned clean; private `docs/status/` gitignored). Marketing site published via GitHub Pages Actions workflow (deploy green) with custom domain `proctor-mcp.fledgeling.app` (DNS CNAME added on Namecheap → fledgeling-co.github.io, mirroring the existing mcp-router record). Awaiting DNS propagation + cert; a background watcher enforces HTTPS when live. Still open: `notarise-now` (needs ASC key) — until then the site's download CTA is a dead end for anyone but the signing machine.
- 2026-08-13 whats-left ingest: reader answered the 6 status-page questions. Only actioned answer was `deferred → all-three` (enables-planning): the three deferred children promoted to backlog briefs PRO-0011/0012/0013 + ledger rows (Last allocated 10→13). The other answers are blocked or unconfirmed — rebuild-signed / notarise / publish are all blocksAutomation:true (need the reader's hands, Apple creds, outward confirmation); git-remote came back `as-found` (not confirmed). None acted on. Domain in notes is spelled inconsistently (proctor-mcp vs procter-mcp). No git remote created; main stays local-only.
- 2026-08-13 FLEET COMPLETE. All 10 features merged to local main @ d237361; 19 tools, 169 tests / 23 suites green. PRO-0010 runner mis-wrote to the main path first, self-detected via empty worktree diff, and relocated cleanly via git stash (verified: main clean, no residual stash, branch held the full diff). All worktrees + ai/* branches removed.
- 2026-08-13 batch 4 launched (final): PRO-0010 off bd3a08c.
- 2026-08-13 batch 3 MERGED to main (bd3a08c): PRO-0006 (capture normalize), PRO-0007 (proctor_zoom), PRO-0009 (proctor_kill + FSJail). Wire.CaptureResult carries both normalization+crop; count 17->19; 157 tests / 22 suites green. Worktrees+branches cleaned.
- 2026-08-13 batch 3 launched (3-concurrent): PRO-0006, PRO-0007, PRO-0009 off 07d7ea3. PRO-0010 queued for batch 4.
- 2026-08-13 batch 2 MERGED to main (07d7ea3): PRO-0003 (proctor_menu), PRO-0004 (proctor_dictionary), PRO-0005 (proctor_policy). Three tool specs split apart in ToolCatalogue; count 14->17; 118 tests / 18 suites green. Worktrees+branches cleaned.
- 2026-08-13 batch 2 launched (3-concurrent): PRO-0003, PRO-0004, PRO-0005 in worktrees off 670389b.
- 2026-08-13 batch 1 MERGED to main (670389b): PRO-0001 (14 tools), PRO-0002 (set-of-marks), PRO-0008 (proctor_resource). Shared-file conflicts (ToolCatalogue/Dispatch/Session/Tests) hand-resolved by union; worktrees+branches cleaned; .worktrees/ gitignored and de-polluted. 82 tests / 13 suites green.
- 2026-08-13 pre-triage complete: 10 specs written, all Ready for Plan; LEDGER Last allocated: 10.
- 2026-08-13 baseline committed (8430fd9); site self-hosted its JS (48447f4); scaffold created.
