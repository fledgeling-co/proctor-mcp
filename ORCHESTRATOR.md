# ORCHESTRATOR — Proctor remaining-work plan & ledger

**Status:** In Progress — wave 3 stage 1 **MERGED** (4 features), stage 2 running
**Updated:** 2026-08-14 — wave 1+2 remain MERGED (10 features). Wave 3 stage 1 merged @ 62cd969: PRO-0014, PRO-0011, PRO-0012, PRO-0013. **258 tests / 29 suites green on `main`**, up from 173/24. Worktrees and `ai/*` branches removed. Stage 2 (PRO-0015) launched.

### Corrections to earlier rows (reconciled 2026-08-14)
- **This repo DOES now have a git remote** (`origin` → github.com/fledgeling-co/proctor-mcp). The earlier "no git remote, main is LOCAL-ONLY" note is stale. Local `main` is **4 commits AHEAD** of `origin/main` and those commits carry unreviewed WIP: **merge to local `main` only, never push.**
- Worktrees branch from **local HEAD**, set via `.claude/settings.local.json` (`worktree.baseRef: head`), because `origin/main` does not contain the design artifacts wave 3 depends on.
- The agent-panel rendering blocker that gated the run HUD is **FIXED** at `2e478ec` (one panel per screen; the union panel's 26Mpx backing store is accepted by the window server and never presented). Its brief has been deleted from `docs/features-to-triage/`.

## How to resume
You are the fleet orchestrator (ship-fleet skill). Read this file top to bottom, reconcile
the ledger below against reality (`docs/feature-specs/LEDGER.md`, `docs/specs/*`,
`git worktree list`, merged branches), correct drifted rows, then continue filling slots. Rules:
- ≤ **3** concurrent runners (user-chosen, 2026-08-13); an item starts only when every "Depends on" ID has **MERGED**.
- Runners are Opus agents (launched via the verified single-agent-Workflow lane, `model:'opus'`,
  `effort:'high'`, `agentType:'claude'`) that invoke the ship-feature skill and **STOP BEFORE MERGE**;
  the orchestrator serializes all finalization (rebase → gate → merge → worktree cleanup) one branch at a time.
- **`main` is the integration branch and is AHEAD of `origin`. "Merge" means merge to local `main`; NEVER push.**
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

### External model CLIs — READ THIS BEFORE EVERY EXTERNAL CALL
Superseded 2026-08-14 by the reader's explicit choice. The 2026-08-13 line
(`external-model-clis: off`, Codex relay down) no longer describes this repo.

- **Codex / `gpt-5.6-sol`: OFF.** Do not invoke it, for gates or for executor slices. Not a
  fallback, not for a retry.
- **The three out-of-family review gates run on GROK instead** — the triage spec review, the plan
  review gate, and work Phase D's completeness critic. Verified working on this machine
  2026-08-14 (read a real repo file and returned its content accurately):

  ```
  perl -e 'alarm shift @ARGV; exec @ARGV' 240 \
    grok -p "<prompt>" --model grok-4.6 --effort xhigh --sandbox read-only
  ```

  `grok 1.0.3`, logged in to grok.com, `grok-4.6` is the default model. `-p` is single-turn and
  prints to stdout. An **empty or absent response is a LANE FAILURE, not a pass** — on any failure
  the gate falls back **in-family with a logged downgrade in the artifact**, never to Codex and
  never silently skipped.
- **Executor slices stay in-family.** Grok is seated as the independent *reviewer* only; there is no
  cheap-executor lane on this run.
- **Egress warning, and it is load-bearing for two items in this wave.** A grok call transmits the
  artifact and every source file it opens to xAI. PRO-0012 (policy gate + audit) and PRO-0013
  (audit-log encryption-at-rest) are security features. The reader chose this lane knowing that;
  do not widen it beyond the three named gates.

## Wave plan
Wave 1 (no unmerged internal deps — 8 slots): PRO-0001 CUA façade, PRO-0002 set-of-marks, PRO-0003 menu-bar
  shortcuts, PRO-0004 app-dictionary, PRO-0005 audit+policy, PRO-0006 capture-normalisation, PRO-0007 zoom,
  PRO-0008 MCP-surface.
Wave 2 (after their dep merges): PRO-0009 process-kill+fs-jail (soft after PRO-0008 — annotation/gating
  conventions), PRO-0010 pointer-overlay (after PRO-0002 — shared overlay path).
Wave 3 (2026-08-14, reader chose the full backlog — all 7): the run HUD line PRO-0014 → PRO-0015 →
  {PRO-0016, PRO-0017}, run alongside the three items scheduled 2026-08-13 and never triaged
  (PRO-0011 stability pointer marker, PRO-0012 re-gate flow/stability, PRO-0013 audit encryption).
  The three carry no dependency on the HUD line or on each other, so they fill slots freely.
  IDs 0014-0017 are allocated at pre-triage, serially, under the ledger lock.

Holding pen (external deps / needs input): none.

### Wave 3 dependency order
- **PRO-0014 step descriptions** — independent. Pure agent logic, no window. Goes first.
- **PRO-0015 run HUD panel** — after PRO-0014 (needs its derived descriptions for the live line).
  Design is SETTLED and binding: `mocks/run-hud.html` is the rendered reference, with
  `docs/design/run-hud-queue.md` and `docs/design/run-hud-character.md` as the specs. Do NOT re-open
  the design and do NOT run design-craft on it. The HUD is a borderless NSPanel from the agent
  process and MUST follow the one-panel-per-screen rule; the header comment in
  `Sources/ProctorAgent/Overlay/CursorOverlay.swift` explains why, with the measurement.
- **PRO-0016 multi-session queue** — scheduler half is independent of the UI; the queue UI is after
  PRO-0015. Spec: `docs/design/run-hud-queue.md`, whose open questions triage should settle rather
  than leave to the implementer.
- **PRO-0017 HUD character assets** — after PRO-0015. Design settled; scope is asset production and
  binding, not choosing a character.
- **PRO-0011/0012/0013** — independent of the HUD line and of each other. 0012 and 0013 are security.

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

## Wave 3 ledger (triaged 2026-08-14 @ 8e0206c; ids 0011-0017 allocated, LEDGER Last allocated: 17)
Runners STOP BEFORE MERGE. Stages exist because a dependency must be **merged**, not merely finished,
and the orchestrator serialises every merge — so the fleet runs in three stages with merges between.

| ID | Title | Spec | Depends on | Mock / design | Stage | Status |
|----|-------|------|------------|---------------|-------|--------|
| PRO-0014 | Step descriptions, derived not supplied | `spec-PRO-0014.md` | — | — | 1 | **MERGED** `061ca0a` · `StepDescription.swift` in Core, +33 tests |
| PRO-0011 | Pointer marker in stability artifacts | `spec-PRO-0011.md` | — | — | 1 | **MERGED** `a8d9a7a` · `captureEach`/`pointerMarks` on stability, +19 tests |
| PRO-0012 | Re-gate flow replay + stability (security) | `spec-PRO-0012.md` | — | — | 1 | **MERGED** `d9ae7fd` · `ReplayGate` + new `ProctorAgentTests` target, +23 tests |
| PRO-0013 | Audit-log encryption at rest (security) | `spec-PRO-0013.md` | — | — | 1 | **MERGED** `62cd969` · `AuditSeal` + `AuditKeyStore`, +10 tests |
| PRO-0015 | Run HUD panel | `spec-PRO-0015.md` | PRO-0014 ✓ | `mocks/run-hud.html` (binding) | 2 | **RUNNING** |
| PRO-0016 | Multi-session queue | `spec-PRO-0016.md` | PRO-0015 merged | `docs/design/run-hud-queue.md` | 3 | **Blocked** on stage 2 merge |
| PRO-0017 | HUD character assets | `spec-PRO-0017.md` | PRO-0015 merged | `docs/design/run-hud-character.md` | 3 | **Blocked** on stage 2 merge |

**PRO-0015 carries a second architectural blocker its runner must solve, not discover late:** the agent
process runs a bare `CFRunLoopRun()` with no `NSApplication` event loop, so a panel's Pause/Stop buttons
have no way to receive a click. It is recorded as a spec requirement; the runner owns the fix.

## Deferred children discovered mid-fleet
All three SCHEDULED 2026-08-13 (whats-left ingest, reader answered "all three") — promoted to backlog briefs + ledger rows, **still not triaged as of 2026-08-14**.
| Child | Parent | Backlog item | Status |
| Pointer marker in proctor_stability per-step artifacts | PRO-0010 | PRO-0011 | **MERGED** in wave 3 |
| Re-gate flow replay + stability through the policy gate & audit | PRO-0005 | PRO-0012 | **MERGED** in wave 3 |
| Encryption-at-rest for the JSONL audit log | PRO-0005 | PRO-0013 | **MERGED** in wave 3 |

### New children discovered during wave 3 stage 1 (not scheduled)
| Child | Found by | Note |
|---|---|---|
| ~~`ProctorAgent` has no test target, so no feature can red-green its agent-side wiring~~ | PRO-0011 | **Already fixed by PRO-0012 in the same stage**, which added `Tests/ProctorAgentTests` driving a real `Session` against fake AX/capture engines. Both runners found the same gap; one of them closed it. No action. |
| `proctor_doctor` has no `policy` block | PRO-0013 | PRO-0005's plan called for one and it is not in the tree, so audit state is visible only through `proctor_policy status`. Belongs to PRO-0005's scope. |
| Audit entries are sealed but not signed | PRO-0013 | Sealing needs only the public key, so a forged append is undetectable. Now a **stated non-goal** in the code, the plan and the changelog rather than an implied guarantee. Signing is a separate change worth its own spec. |

## Needs input (consolidated for the user)
- **PRO-0014 quotes a caller-supplied object and not a derived one** — `Pressing "Pay the supplier"` versus `Pressing Send invoice`. The spec is silent on it. The runner added it because nothing otherwise stopped a supplied `label` appending a second clause to a kill-switch line (`Pressing OK. About to press Delete`); sanitising folds double quotes to single so a supplied name cannot close the quotation. The same quoting covers a menu path, a keystroke and a shortcut name, which also arrive in the tool call. Reversing it is one line. Flagging, not blocking.
- **PRO-0014's completeness critic ran in-family**, on `claude-fable-5`, after grok failed four consecutive attempts on the artifact (exit 142, no output — it answers a ~40-line prompt, not a ~200-line one). That gate was Claude reviewing Claude; the plan review before it did run out-of-family on grok. Logged in the plan, carried here so it reaches the pre-merge evidence rather than dying in a runner transcript.
- **Runner model was Opus 4.8, not Opus 5**, in the wave-1/2 fleet. Wave 3's four runners self-reported `claude-opus-5[1m]` on the wire, so the convention string and the served model now agree.
- **Three deferred children above** are logged, not scheduled. Say if you want any promoted to a new fleet item.

## Event log (append-only, newest first)
- 2026-08-14 **Wave 3 stage 1 MERGED** @ 62cd969 — four features, **258 tests / 29 suites green** on `main` (was 173/24). Merge order was chosen to isolate the overlap: PRO-0014 (untouched files) → PRO-0011 → PRO-0012 → PRO-0013, each rebased onto the growing `main`, built and tested in its own worktree before a fast-forward. Two real conflicts, both resolved by combining rather than choosing:
  - `SessionFlow.stability()`: PRO-0011 had lifted the determinism fold into `StabilityScore.fold` in Core so that "an artifact cannot move a score" is a property of the signature; PRO-0012 had extracted a `stabilityReport` helper with truncation semantics so that a run cut short is never reported deterministic. The merged code keeps the helper *and* scores through the hash-only fold, ANDing `!truncated` at the call site — the fold still cannot see a capture, and a truncated run still cannot claim determinism. PRO-0012 had also renamed `runs` to `requested`; the `runs < 2` note moved into the helper, where it counts repeats **measured** rather than repeats **asked for**, which is the more honest of the two.
  - `SessionPolicy.policyStatus()`: PRO-0013's audit-state fields kept, read through PRO-0012's injectable `clock()` seam rather than the wall clock it replaced.
  - Both `ProctorCoreTests.swift` conflicts looked like clean append-append unions and were not: the shared trailing braces close only the *later* suite, so the earlier one needed its own closers added. A naive union compiles as a syntax error rather than silently — caught by the build, not by inspection.
- 2026-08-14 **Wave 3 fleet stage 1 LAUNCHED** — PRO-0014, PRO-0012, PRO-0013 in the three slots, PRO-0011 refilling the first free one. Runners are Opus at high effort via the workflow lane, invoking ship-feature, stopping before merge. The fleet runs in **three stages** rather than one continuous slot loop, because PRO-0015 depends on PRO-0014 having *merged* and only the orchestrator merges: stage 1 (the four independent items) → merges → stage 2 (PRO-0015) → merge → stage 3 (PRO-0016 + PRO-0017).
- 2026-08-14 **Wave 3 pre-triage COMPLETE** @ 8e0206c — seven specs written serially under the ledger lock, all now Ready for Plan (LEDGER Last allocated: 17). PRO-0013 was the one Needs More Info item; its single Essential Question (recovery copy for the audit-log unsealing key) was answered by the reader as **(a) no recovery copy** — convert the existing trail in place, a lost key means a permanently unreadable history, and no export path, second secret, or "just in case" plaintext copy, each of which would weaken the guarantee the option was chosen for. The destructive first run must be obvious in whatever performs it. Answer recorded in `spec-PRO-0013.md`; its runner folds it in and flips the status as its first action.
- 2026-08-14 **Out-of-family review lane switched from Codex to grok** at the reader's instruction (`grok -p … --model grok-4.6 --effort xhigh --sandbox read-only`, 240s alarm). Codex is OFF for this repo, not a fallback and not for a retry. Measured behaviour during triage: five of seven gates hit the deadline mid-reasoning and needed the evidence inlined into the prompt rather than read from disk; PRO-0013 failed twice and fell back in-family with a logged downgrade.
- 2026-08-14 UI: permission-state fix + always-on menu bar + live activity + quit-everything + mock redesign. Three problems from real use, all fixed. (1) **Permission bug:** the window polled the agent with `tool:"doctor"` but dispatch only matches `"proctor_doctor"`, so every check read "agent not answering" even with both grants on — one-line fix in `AgentModel.swift`; verified by socket probe (`proctor_doctor` ok + grants, bare `doctor` = unknown tool). Granting Screen Recording now kickstarts the agent so its cached `SCShareableContent` probe re-runs, with an "Applying…" transient. Dropped the stale `~/Applications` reveal-and-drag copy (now `/Applications`, listed in the picker). (2) **Menu bar always-visible:** app registers as a login item via `SMAppService.mainApp` and both installers (`install.sh`, `Install.swift`) `open` the app after loading the agent; polling moved to app-lifetime (model `init`) so the menu stays live with the window closed; login start is quiet (window `orderOut`). (3) **Live activity:** ring buffer `(tool, at, ok)` + in-flight marker on the `Session` actor, recorded at the `Dispatcher.handle` choke point, tracked set derived from `ToolCatalogue` (so health polls, internal verbs, and unknown tools are all excluded automatically — caught a leak during verify where a stale UI's bare-`doctor` polls flooded the feed). Exposed as internal `proctor_recent_activity` (NOT in ToolCatalogue); rendered in the menu line + a status-window Activity card. (4) **Quit = everything:** `applicationWillTerminate` boots out the agent on every quit path; label "Quit Proctor". Both return at next login. Native look kept; mock's motion implemented in SwiftUI (`Motion.swift`: spring `cubic-bezier(.32,.72,0,1)`, step slide, dot-fill keyframe, grant-success pop+ring, status-pill spring-in) all gated on Reduce Motion. Mock `mocks/onboarding-and-menu.html` redesigned as the design source (Codex-register hero sheet, 3 dots, live-activity surfaces, de-staled). **Verified live** (signed Developer ID reinstall, grants survived the same-identity rebuild): runtime `tools/list` = 19, internal verbs hidden, doctor reflects grants (ready), activity feed excludes polls and captures real tools. Not machine-witnessable here (obscura is web-only): the native app's visual/animation fidelity and the login-item/quit GUI paths — code-complete against the mock, need a human glance.
- 2026-08-14 Install relocated to /Applications + notarised-by-default + CI release pipeline + CHANGELOG. install.sh now installs to `/Applications` (was `~/Applications`; sudo fallback), auto-detects the Developer ID identity, and notarises fresh builds by default (keychain profile `proctor`; `PROCTOR_SKIP_NOTARIZE=1` to skip). uninstall.sh + README follow the path change. notarize.sh generalised to accept an ASC API key via env (`NOTARY_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER_ID`) for CI alongside the local keychain-profile path. Added `.github/workflows/release.yml`: on a `v*` tag it imports the Developer ID cert into a temp keychain, builds+signs, notarises+staples via ASC API key, packages, extracts the matching CHANGELOG section, and publishes the GitHub release (6 repo secrets documented in the header). CHANGELOG.md created (Keep a Changelog; v0.1.0 entry written via create-luke-content, lint clean). **Live relocation performed:** booted out the old `~/Applications` agent, installed the already-stapled build to `/Applications` (reused, no rebuild), agent running, doctor clean, runtime `tools/list` = 19, Gatekeeper Accepted/Notarized. Grants did NOT carry: prior install was ad-hoc, so the new Developer ID identity is a fresh TCC identity needing a one-time manual re-grant (Accessibility + Screen Recording) — panes opened; future upgrades keep the identity and will survive. Left uncommitted + flagged: stale `design/icon/build_icon.py` + `design/icon/icon-proctor.svg` working changes from the icon rounds (unrelated to this request).
- 2026-08-13 Icon finalised = raster C. Reader judged the GPT-Image raster take (proctor-raster-7c3d62-2, glowing glass-gel cubes) decisively better than the hand-authored SVG master even after 4+ fidelity rounds ("C wins by a landslide") — the known vector-can't-out-material-a-diffusion-raster ceiling. Shipped the raster directly: squircle-masked via design/icon/apply-squircle.sh (reproducible) into app-icon-shaped source art, verified legible at 16/32/48px. App rebuilt + re-notarised (Accepted) + stapled; v0.1.0 asset replaced (4.58MB); site icons regenerated (Pages redeploys). Tradeoff: shipped icon is now the raster, not the parametric SVG — future tweaks need a new generation/pixel edit, not a build_icon.py param. SVG master kept as superseded provenance. Local reinstall still the reader's step.
- 2026-08-13 App icon designed + shipped. The site's existing mark was illegible at 16-32px (cream-on-cream windows). Re-materialised via create-mac-icon (12/12 audit): a deep-graphite window with a terracotta pixel-dissolve "actuation edge" on warm paper — brand DNA kept, small-size legibility fixed (verified 16/32/48px). Source art committed at Apps/Proctor/icon-1024.png; build-app.sh now generates Proctor.icns from it. App rebuilt + re-notarised (Accepted) + stapled; v0.1.0 release asset replaced with the icon'd build (0 downloads, identical code). Site icons regenerated to match (auto-redeploys Pages). Editable SVG master under design/icon/ (heavy iteration provenance gitignored). Local reinstall to see the icon in Finder remains the reader's step.
- 2026-08-13 NOTARISED + RELEASED. Fresh Developer ID build from main (verified 19 tools via runtime tools/list, not the unreliable `strings` oracle), notarised (Apple: Accepted, submission a3c39364), stapled, Gatekeeper-accepted. Published as GitHub release **v0.1.0** on fledgeling-co/proctor-mcp with `Proctor-0.1.0.zip` (1.92MB, stapled). Build-only — the running local agent was NOT reinstalled (reader chose "you run the install"); its rebuild + one-time re-grant remains theirs. App still ships without an icon (Apps/Proctor/Proctor.icns absent) — generic in the consent dialog and Finder; flagged, not blocking.
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
