# ORCHESTRATOR — Proctor remaining-work plan & ledger

**Status:** **Wave 9 running on `ai/wave-9`.** v0.2.0 released, notarised and pushed; all 63 items through PRO-0063 merged or retired. The gate is green: 1,520 tests in 175 suites. Proctor supports VM targets (lume & prlctl), witness tiers (native & delegated), SSH streamLocal reach, auto-routing gates, resolution-scaled captures, and precise scroll units.
**Updated:** 2026-08-17 — v0.2.0 tagged, notarised, stapled, and installed. **1,520 tests / 175 suites green on `main`**, fully synchronised with `origin/main`.

### Repository state (reconciled 2026-08-17)
- **Git remote:** `origin` → `github.com/fledgeling-co/proctor-mcp`. Local `main` is up to date with `origin/main` at tag `v0.2.0`.
- **Installed bundle:** `/Applications/Proctor.app` is rebuilt, Developer ID signed, notarised by Apple, and running in launchd `gui/501`.
- **Verification:** All 63 features verified across 175 test suites (1,520 tests) plus 7 acceptance journeys.

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
| PRO-0015 | Run HUD panel | `spec-PRO-0015.md` | PRO-0014 ✓ | `mocks/run-hud.html` (binding) | 2 | **MERGED** `9f497b4` · panel + run controls, +57 tests. Agent now runs `NSApplication.shared.run()` |
| PRO-0016 | Multi-session queue | `spec-PRO-0016.md` | PRO-0015 ✓ | `docs/design/run-hud-queue.md` | 3 | **MERGED** `aad4f2d` · three lanes + a keeper outside the actor, +43 tests |
| PRO-0017 | HUD character assets | `spec-PRO-0017.md` | PRO-0015 ✓ | `docs/design/run-hud-character.md` | 3 | **MERGED** `4f2fc60` · seven states @1x/2x/3x, hosted layer, +23 tests |

**Two things PRO-0015 settled that later work must not re-litigate.** The agent's run
loop is now `NSApplication.shared.run()`, because a bare `CFRunLoopRun()` spins the same
loop without draining the event queue, so a button can never receive a click. Three
constraints hold it together: the panel drags via `mouseDragged` + `setFrameOrigin` and
never `performDrag`, it never calls `activate(_:)`, and it ignores mouse events while a
synthetic step is in flight — without that last one a synthetic `click` posted under the
panel can land on Stop and halt the run that posted it. That bug was found by the
completeness critic, not by the build. With `PROCTOR_HUD` off, `main.swift` keeps the old
`CFRunLoopRun()`, so an opted-out run has exactly the process shape that shipped.

**The event-loop blocker is SOLVED** — see the note above the ledger table. It was the load-bearing
problem of the HUD line: a bare `CFRunLoopRun()` spins the same loop without draining the event queue,
so a kill switch's buttons could never be pressed.

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
- ~~**PRO-0014 quotes a caller-supplied object and not a derived one**~~ — **RESOLVED 2026-08-14 @ b60e906: quote both.** The quotes were doing containment, not attribution, and a reader cannot tell quoted-from-bare means supplied-from-derived because nothing teaches them that rule. What settled it: an app's own accessibility title carries the same clause-injection payload, which `sanitised` already conceded by running on derived names; only `render` treated them differently, leaving the half Proctor reads off the screen unfenced. `Object` still records provenance so PRO-0015 can fence with its own text run instead of punctuation. 259 tests / 29 suites green.
- **PRO-0014's completeness critic ran in-family**, on `claude-fable-5`, after grok failed four consecutive attempts on the artifact (exit 142, no output — it answers a ~40-line prompt, not a ~200-line one). That gate was Claude reviewing Claude; the plan review before it did run out-of-family on grok. Logged in the plan, carried here so it reaches the pre-merge evidence rather than dying in a runner transcript.
- **Runner model was Opus 4.8, not Opus 5**, in the wave-1/2 fleet. Wave 3's four runners self-reported `claude-opus-5[1m]` on the wire, so the convention string and the served model now agree.
- **Three deferred children above** are logged, not scheduled. Say if you want any promoted to a new fleet item.

## Wave 4 (2026-08-14) — four from the reader, one already shipped
Ids allocated to 22. **PRO-0022 is already MERGED** — the crash barrier was built directly
because a HUD drawing fault was killing the agent mid-session and the reader chose to fix it
before the fleet.

### Pre-triage adaptation, and why it is still safe
Phase 4 exists because `LEDGER.md` id allocation is a read-modify-write and concurrent runners
corrupt it. **The orchestrator has allocated all four ids serially, by hand, up front**, so no
runner allocates anything; each triages its own brief into `docs/specs/spec-<ID>.md` against an
id that is already fixed. The invariant Phase 4 protects is held. A runner that needs a *child*
spec still takes the ledger lock.

| ID | Title | Brief | Depends on | Stage | Status |
|----|-------|-------|------------|-------|--------|
| PRO-0021 | Menu bar switch for the panel, and the icon as the character | `22-menu-bar-switch-and-character.md` | — | 1 | **MERGED** `58b3ce4` |
| PRO-0019 | A foreground-only run is obvious before it takes the machine | `20-foreground-run-is-obvious.md` | — | 1 | **MERGED** `619bb30` |
| PRO-0020 | Route browser work to Obscura | `21-route-browser-work-to-obscura.md` | — | 1 | **MERGED** `3a3bb5f` |
| PRO-0018 | Yield when a person takes the machine back | `19-yield-when-a-person-takes-the-machine.md` | PRO-0019 ✓ | 2 | **MERGED** `435e1da` · +42 tests |
| PRO-0022 | A drawing fault must not kill the agent | `23-drawing-fault-must-not-kill-the-agent.md` | — | — | **MERGED** `b4a29e5` |

**Why PRO-0018 waits on PRO-0019.** Both answer "is this batch going to take the foreground";
0019 computes and discloses it, 0018 acts on it. Building them concurrently means two answers to
one question, and the briefs already say to triage them together. 0018 also needs 0019's decision
about whether a batch declares its synthetic content up front or at the first such step.

**Three concurrent runners**, the cap this repo has used since wave 1. Runners stop before merge;
the orchestrator serialises every merge to local `main` and never pushes.

## Wave 5 (2026-08-15) — six items, ids allocated to 28
Ids allocated in one serial write by the orchestrator, so no runner touches allocation
and the four triages run concurrently. Phase 4's invariant holds. A child spec still
takes the ledger lock.

**Three concurrent runners**, the cap since wave 1. Runners stop before merge; the
orchestrator serialises every merge to local `main` and never pushes.

| ID | Title | Brief | Depends on | Stage | Status |
|----|-------|-------|------------|-------|--------|
| PRO-0025 | Prefer the background, pointer in the target's plane | `26-prefer-background-and-pointer-in-plane.md` | — | 1 | **MERGED** `84062fa` |
| PRO-0023 | Offer to install Obscura when it is missing | `24-offer-to-install-obscura.md` | — | 1 | **MERGED** `f77df6c` |
| PRO-0027 | The menu bar shows the character when idle | `28-menu-bar-character-when-idle.md` | — | 1 | **MERGED** `c94799b` |
| PRO-0024 | A second browser lane for Obscura's limits | `25-second-browser-lane-for-obscuras-limits.md` | PRO-0023 ✓ | 2 | **MERGED** `4afc99c` |
| PRO-0026 | Foreground takeover overlay | `27-foreground-takeover-overlay.md` | PRO-0025 ✓ | 2 | **MERGED** `f198936` |
| PRO-0028 | Re-check now says what it checks | `29-re-check-now-says-what-it-checks.md` | PRO-0027 ✓ | 2 | **MERGED** `6f696c6` |

**Why the stages pair up the way they do.** Each stage-2 item lands in the same files
as its stage-1 sibling, so sequencing them costs nothing and removes the whole
conflict surface: 0023/0024 both rewrite the browser handoff, 0025/0026 both touch
`Sources/ProctorAgent/Overlay/`, and 0027/0028 both edit the menu bar. Running the
pairs concurrently would mean resolving two designs against each other at merge, and
wave 4 already showed what that costs when PRO-0019 and PRO-0021 arrived with two
rules for one glyph.

### Two items carry a decision that is the reader's, not the runner's
- **PRO-0024 conflicts with the reader's own standing instruction**, which names
  browser-use among tools that are removed and routes every browser task through
  Obscura. The reader asked for the lane; the spec must say whether it is
  capability-gated, detection-gated, or a preference defaulting to Obscura-only.
- **PRO-0026 needs a `CGEventTap` to swallow input** — the same API a keylogger uses,
  on the Accessibility grant this process already holds. A real escalation of what
  the agent does. Three readings are in the brief; the spec picks one and defends it,
  under two invariants: Stop always works, and the block never survives the process.

## Wave 6 (2026-08-15) — the deferred children, promoted

Every child item logged across PRO-0005 … PRO-0028 and left unscheduled, swept out
of the specs' own `Child work found` sections rather than from memory. Twenty-one
raw children group into eleven items; ids 0029-0039 allocated serially, LEDGER
`Last allocated: 39`.

PRO-0040 was found during a reinstall on 2026-08-15 rather than swept from a spec, and is
appended to stage 3 because it changes the installed bundle layout and must not race the
other items' builds.

Staged on **file contention**, not on dependency: none of these blocks another
logically, but several would collide in the same file if run together.

| Stage | Items | Held apart because |
|---|---|---|
| 1 | PRO-0030 · PRO-0032 · PRO-0033 · PRO-0035 · PRO-0037 | disjoint |
| 2 | PRO-0029 · PRO-0031 · PRO-0034 · PRO-0038 | PRO-0034 shares `SessionAct` with PRO-0033; PRO-0029 reshapes the status window |
| 3 | PRO-0036 · PRO-0039 | PRO-0036 follows PRO-0029 into the status window; PRO-0039 follows PRO-0031's decision on what `doctor` may expose about the gate |

| Id | Item | Brief | Children folded in | Stage | Status |
|---|---|---|---|---|---|
| PRO-0030 | The build says which build it is | `31-the-build-says-which-build-it-is.md` | PRO-0027 staleness · PRO-0028 `agentVersion` | 1 | **MERGED** `65f61c3` |
| PRO-0032 | The audit trail is signed, and records what Proctor recommended | `33-the-audit-trail-is-signed.md` | PRO-0013 unsigned · PRO-0024 lane recommendation | 1 | **MERGED** `06259b6` |
| PRO-0033 | A person's click reaches Stop | `34-a-persons-click-reaches-stop.md` | PRO-0018/0019 mouse gate · PRO-0019 plane declared late · PRO-0026 swallowed Stop | 1 | **MERGED** `dc48889` |
| PRO-0035 | The browser catalogue stops guessing | `36-the-browser-catalogue-stops-guessing.md` | PRO-0024 PWA prefix · `chromiumFamily` drift · prose-only `why` | 1 | **MERGED** `c30b3c9` |
| PRO-0037 | A hold names whose run it is | `38-a-hold-names-whose-run-it-is.md` | PRO-0018 unattributed hold · PRO-0016 `activate` takes no lane | 1 | **MERGED** `f2221f6` |
| PRO-0029 | A home for the PROCTOR_* switches | `30-a-home-for-the-proctor-switches.md` | PRO-0026 env-var knob · PRO-0024 `PROCTOR_SECOND_LANE` control | 2 | **CARRIED** → wave 7 stage 3, brief revised |
| PRO-0031 | The health report is complete | `32-the-health-report-is-complete.md` | PRO-0005/0013 no `policy` block · PRO-0023/0024 `doctor.sh` | 2 | **RETIRED** → absorbed by PRO-0050 |
| PRO-0034 | Scroll moves by what was asked | `35-scroll-moves-by-what-was-asked.md` | PRO-0025 delta units · page action ordering | 2 | **RETIRED** → the code it fixes is what Cua replaces |
| PRO-0038 | Stability knows when it is scoring a page | `39-stability-knows-when-it-is-scoring-a-page.md` | PRO-0020 page churn · PRO-0024 unexecuted lane | 2 | **CARRIED** → wave 7 stage 3, brief revised |
| PRO-0036 | The status window's checks say what they can check | `37-the-status-windows-checks-say-what-they-can-check.md` | PRO-0028 three Re-check buttons · PRO-0023 Shortcuts row heading | 3 | **CARRIED** → wave 7 stage 4, after PRO-0050 |
| PRO-0039 | Page-scoped refusal | `40-page-scoped-refusal.md` | PRO-0020 refusal rule | 3 | **RETIRED** → its question changed shape underneath it |
| PRO-0040 | `open -a Proctor` cannot launch Proctor while the agent is running | `41-open-cannot-launch-proctor.md` | found 2026-08-15 during a reinstall, not a child | 3 | **CARRIED** → wave 7 stage 1, RUNNING |
| PRO-0041 | `proctor_doctor` can hang forever on the Screen Recording probe | `42-doctor-can-hang-on-the-screen-recording-probe.md` | found 2026-08-15 gating PRO-0033, not a child | 3 | **CARRIED** → wave 7 stage 1, **MERGED** `0545219` |
| PRO-0042 | Backfill: `horizontalAlignment` on `proctor_assert` | `43-backfill-horizontal-alignment-assertion.md` | ratifies the stray commit `2b917ed` | 1 | **MERGED** `8fdddbc` |

**Two children are not fleet items, because they are questions rather than work.**
A model told "Obscura is missing" may install it anyway, and Proctor cannot remove
a model's own reach by withholding a command (PRO-0023). And the takeover overlay
signals mechanism rather than consequence, so an all-accessibility run can delete a
file through `AXPress` in silence (PRO-0026 finding 10). Both are recorded here and
carried to the reader rather than specced.

## Wave 7 (2026-08-15) — Cua underneath, Proctor on top

**Refill order as slots free** (the stages below are the DAG, not a barrier — an item starts
when its own dependencies have merged, not when its stage-mates finish):

1. **PRO-0048** (iOS deep links) — no dependency on PRO-0044, and mostly new files, so the
   lowest contention of anything queued. Takes the first free slot.
2. **PRO-0050** (doctor knows the toolchain) — also independent of PRO-0044. Second, not
   first, because it reshapes `SessionDoctor.swift`, which PRO-0041 has just rewritten.
3. **PRO-0045** and **PRO-0046** — held until PRO-0044 **merges**, since both are about what
   delegation costs and neither can be specified against an unmerged seam.
4. Then PRO-0049 (after PRO-0048), PRO-0051 (after PRO-0044), PRO-0029, PRO-0038.
5. PRO-0036 (after PRO-0050) and PRO-0052 last, which documents the whole wave.

**The cap stays at 3, and the reason is now measured rather than preference.** Two capacity
failures on 2026-08-15: the gateway returned 503 `over_reserve` and killed all four stage-1
runners at once, and `replayd` saturating machine-wide under fleet load is the wedge behind
PRO-0041. Raising the cap trades a few hours of elapsed time for both of those getting worse.

**The pivot.** `docs/research/2026-08-15-dossier-proctor-vs-cua.md` is the evidence and
`docs/features-to-triage/00-WAVE-7-DIRECTION.md` is the architecture every item inherits.
Actuation goes to Cua Driver. Proctor keeps observation (its own capture path, because
Cua's screenshots carry no frame status), the verdict layer (assertions, audit, fidelity,
determinism) and the whole supervised-run surface the reader asked to keep working. iOS
arrives as a second driver lane: deep links plus Maestro, following the lane
`acceptance-e2e` already documents.

**Retired rather than built**, with the reasoning kept in each brief: PRO-0031 (folded
into PRO-0050), PRO-0034 (scroll units, in code Cua replaces), PRO-0039 (page-scoped
refusal, whose question changed shape underneath it).

| Id | Item | Brief | Stage | Status |
|---|---|---|---|---|
| PRO-0043 | The build-identity tests fail on a moving HEAD | `44-…` | 1 | **MERGED** `d4a1565` |
| PRO-0044 | **Cua becomes the actuation backend** | `45-…` | 1 | **MERGED** `d65dc1e` |
| PRO-0047 | The run has a history you can read | `48-…` | 1 | **MERGED** `9756282` |
| PRO-0041 | doctor can hang on the Screen Recording probe | `42-…` | 1 | **MERGED** `0545219` |
| PRO-0040 | `open -a` cannot launch Proctor | `41-…` | 1 | **MERGED** `091d6c3` (carried) |
| PRO-0048 | Drive iOS through deep links | `49-…` | 2 | **MERGED** `8d2fde6` |
| PRO-0053 | `TakeoverWiringTests` reddens the gate at random | `54-…` | 2 | **MERGED** `477941f` · found mid-fleet, was a production defect |
| PRO-0045 | A delegated call is still gated and recorded | `46-…` | 2 | **MERGED** `1bff5c2` |
| PRO-0046 | Supervision survives delegation | `47-…` | 2 | **MERGED** `2f240bf` · closed 4 live defects |
| PRO-0050 | Doctor knows the whole toolchain | `51-…` | 2 | **MERGED** `0ea6f88` · absorbed PRO-0031 |
| PRO-0049 | Run Maestro flows as Proctor flows | `50-…` | 3 | **MERGED** `7ca9358` · verified live |
| PRO-0051 | Decide what happens to the native planes | `52-…` | 3 | **MERGED** `0f76c56` · reading 3 chosen |
| PRO-0029 | A home for the PROCTOR_* switches | `30-…` | 3 | **MERGED** `153951b` (carried, revised) |
| PRO-0054 | Three tests still redden the gate at random | `55-…` | 3 | **MERGED** `a4483ec` · all four were one ambient read |
| PRO-0055 | The suite wedges in `haltCheckpoint` on a shared RunControl | `56-…` | 4 | **MERGED** `e53176b` · the gate runs to a verdict |
| PRO-0038 | Stability knows when it is scoring a page | `39-…` | 3 | **MERGED** `30324a6` (carried, revised) |
| PRO-0036 | The status window's checks say what they can check | `37-…` | 4 | **MERGED** `c9e42c9` · fixed a live PRO-0050 defect |
| PRO-0052 | The proctor skill tracks what actually shipped | `53-…` | 4 | **MERGED** `d6cf947` · skill edits UNCOMMITTED in fledgeling-plugins |

## Wave 9 (2026-08-20) — the surface set becomes the app

**Direction:** `docs/features-to-triage/58-swiftui-conversion-direction.md`. Every item
inherits its method; read it before triaging any of them.

**Integration branch is `ai/wave-9`, not `main`.** A peer session holds 21 uncommitted files
on main. Runners branch from `ai/wave-9` and merge back into it; main is never written by
this wave. Worktree: `.worktrees/wave-9`.

**Armed with better-goal** as `wave9-swiftui-conversion` — six gates (build, tests, campaign,
ratchet, wave9, runners), 60 turns, deadline 2026-08-21 09:00. Brief and ledger at
`docs/goals/`. The fleet's own stop mechanisms fail silently past eight blocked turns, which
is exactly this run's length.

**The wave exists because** `Sources/ProctorUI` was built surface by surface across eight
waves and does not read as one designed thing. `design/surfaces/proctor-surfaces.html` is the
design of record — 51 states across 17 surfaces, gated — and this wave converts it.

**Three constraints decide the method** and are not negotiable: a rule in a View body cannot
be proven because there is no `ProctorUI` test target and `swift test` has no window server,
so every decision becomes a pure Core value with a test; fidelity is measured through
`ProctorReflector` embedded in `ProctorUI` rather than through a DOM, because macOS has no
cross-process computed-style API; and every converted control takes a durable accessibility
identifier from a Core constant.

### Dependency order (build order is not id order)

- **PRO-0064** (tokens) first and alone — everything reads its output.
- **PRO-0065** (fidelity harness) second. The fidelity records for every surface item are
  unwritable without it, and a wave that converts seven surfaces then looks for a way to
  check them has already drifted.
- **PRO-0066** ∥ **PRO-0067** — disjoint files.
- **PRO-0068** after PRO-0067 (the walkthrough's completion path sets first-run menu state).
- **PRO-0069**, **PRO-0070**, **PRO-0071** — disjoint, any order.
- **PRO-0072** after PRO-0066 (sheets are raised from the status window's switches).
- **PRO-0073** then **PRO-0074** — new binaries, independent of the surface line.

| Id | Item | Brief | Depends on | Stage | Status |
|---|---|---|---|---|---|
| PRO-0064 | Design tokens as a generated Swift value | `59-…` | — | 1 | **MERGED** |
| PRO-0065 | The fidelity harness: Proctor measures Proctor | `67-…` | PRO-0064 | 2 | **MERGED** |
| PRO-0066 | The status window becomes the mock | `60-…` | PRO-0064, PRO-0065 | 3 | **MERGED** (A2 partial) |
| PRO-0067 | The walkthrough becomes the mock | `61-…` | PRO-0064, PRO-0065 | 3 | **MERGED** (A3 needs the harness) |
| PRO-0068 | The menu bar, and the complete command surface | `62-…` | PRO-0067 | 4 | **MERGED** |
| PRO-0069 | The run HUD, and the seven character states | `63-…` | PRO-0064, PRO-0065 | 3 | **MERGED** |
| PRO-0070 | The takeover overlay, and what it does not claim | `64-…` | PRO-0064, PRO-0065 | 3 | **MERGED** |
| PRO-0071 | The history window, and the skipped verdict | `65-…` | PRO-0064, PRO-0065 | 3 | **TRIAGED** |
| PRO-0072 | The consent sheets, and the asymmetry | `66-…` | PRO-0066 | 4 | **TRIAGED** |
| PRO-0073 | `proctor`, the operator CLI | `68-…` | PRO-0064 | 3 | **TRIAGED** |
| PRO-0074 | `proctor tui`, the supervision surface | `69-…` | PRO-0073 | 4 | **TRIAGED** |

**Cap stays at 3**, unchanged since wave 1 and still measured rather than preferred: the two
capacity failures of 2026-08-15 (a 503 `over_reserve` that killed four stage-1 runners at
once, and `replayd` saturating machine-wide under fleet load) both get worse with more slots.

**Verification per item** is `/test-campaign`, extending the existing 32-case campaign rather
than starting a new one. The campaign and ratchet gates are what make "no testing unknowns"
a measured claim rather than an asserted one.

### Questions parked rather than asked

Per the goal brief's blocked-item policy, a fork that needs a human parks its item and is
appended here rather than stopping the fleet. Full text with the assumption taken for each is
in `docs/goals/goal-wave9-swiftui-conversion.md`.

- **PRO-0073** — how `act` takes a step batch (assumed: both, stdin JSON documented).
- **PRO-0073** — CLI session identity across invocations (assumed: per-invocation).
- **PRO-0074** — TUI over the remote HTTP transport, which puts Stop behind a bearer token
  (assumed: local socket only; the HTTP path is a security decision, not an inheritance).
- **PRO-0074** — a screen-reader mode (assumed: child work, not this item).

None of these blocks its item; each has a defensible default recorded in the spec.

## Event log (append-only, newest first)
- 2026-08-20 **PRO-0070 merged, and corrected the mock.** The guest-route refusal is not an overlay state: the refusal throws before any step runs, so a veil saying Proctor is driving this Mac over a refused batch would make the overlay mean two things. It is a notice; the veil keeps the one state it describes. Mock caption records the error rather than deleting it. 1,574 tests / 183 suites.
- 2026-08-20 **PRO-0069 merged.** Seven phases get distinct symbols and a per-phase control table; the panel drew Pause and Stop in every phase, including finished, where they acted on nothing. Rect and drawing are gated together so hit-testing and drawing cannot disagree. Stop-reachability and HUD wiring suites re-run green. 1,569 tests / 182 suites.
- 2026-08-20 **Second flake fixed.** `RunScheduler` took an injected clock and ignored it for its own ceiling, sleeping on the wall clock instead — so a wiring test that said time does not pass still raced a real 5s timer and refused a run that was about to succeed, ~1 run in 5 under load. `sleep:` is now injected too. Six consecutive clean full runs.
- 2026-08-20 **PRO-0068 merged.** The menu bar went from one command to 21 across four menus, and the kill switch now has a menu path — Pause/Stop were reachable only from the panel and the extras item. A test fails on any command offered elsewhere and missing from the menu bar. 1,563 tests / 181 suites.
- 2026-08-20 **PRO-0067 merged.** Walkthrough step is a pure function tested at all eight combinations; primary actions name their outcome instead of saying Continue three times. A3 (disabled button present) needs the rendered view and is carried to the campaign lane. 1,555 tests / 180 suites.
- 2026-08-20 **PRO-0066 merged.** Status window draws only the sections its state allows, so a dead agent no longer renders Tools/Switches/Agent over unread data; Lanes rendered for the first time. Found and fixed a production defect on the way: `IOSDeviceList.parse` threw a raw DecodingError on truncated simctl output, which was reddening and once wedging the suite. 1,547 tests / 179 suites, green ×4.
- 2026-08-20 **PRO-0065 merged.** Reflector embedded in ProctorUI (debug-only, release guard verified both ways); SurfaceFidelity with 28 anchors and a channel table that makes an unsettleable property unreachable from `.matches`. **Corrected the wave's premise**: the Reflector cannot read resolved SwiftUI modifier values — its own README says so — so the harness settles identifiers, geometry and pixels fully and reports layer style inconclusive where SwiftUI did not materialise it. 1,535 tests / 177 suites.
- 2026-08-20 **PRO-0064 merged.** Token generator + build plugin; 63 tokens (6 kit, 57 direction) generated from the mock. Caught its own first draft reading the increased-contrast overrides as the palettes. 1,526 tests / 176 suites.
- 2026-08-20 **Wave 9 opened on `ai/wave-9`.** 11 ids allocated serially (PRO-0064..0074) from the surface-set briefs 59-69; direction at brief 58. Integration branch is NOT main — a peer session holds 21 uncommitted files there. Armed with better-goal `wave9-swiftui-conversion`, six gates, 60 turns.
- 2026-08-17 **Backlog complete and verified on local `main`.** 1513 tests in 174 suites passing cleanly.
  - **Wave 8 (VM Targets & Witness Tiers) landed in full (PRO-0056 .. PRO-0062):**
    - PRO-0056: Run disclosure carrying machine identity across act, stability, audit, doctor.
    - PRO-0057: Witness tiers (native vs delegated) and fail-closed assertion gate.
    - PRO-0058: Guest providers for `lume` and `prlctl` with non-executing filesystem detection.
    - PRO-0059: `proctor_guest` lifecycle tool (`gst-` handles refused by window tools).
    - PRO-0060: SSH StreamLocal forwarding recipe generation for reaching native macOS guests.
    - PRO-0061: Auto-routing gate refusing host takeover batches when `PROCTOR_GUEST` is set.
    - PRO-0062: Run HUD overlay badge and host-takeover suppression for guest targets.
  - **PRO-0063:** Vision capture purpose scaling (768 targeting / 1024 verify / 1568 detail).
  - **PRO-0034:** Native scroll unit mapping to lines per page, preferring precise bar writes.
  - **PRO-0031 / PRO-0039:** Formally marked Retired in ledger (superseded by PRO-0050 and Cua architecture).

- 2026-08-16 **The gate is green, and the whole flaky set was one line.** `./scripts/test.sh`
  on `main`: **1426 tests in 158 suites pass in under 7 seconds**, seven consecutive runs
  (6.14 / 5.79 / 5.23 / 6.07 / 6.81 / 3.76s after the first). Two merges got there:
  - **PRO-0055 `e53176b` — the wedge.** `Session` defaulted `runControl` to `RunControl.shared`
    and `contentionMonitor` to `ContentionMonitor.shared`. The live monitor reads the actual
    Mac, and a test process can never satisfy "the application under test is frontmost", so
    sampled from inside `RunControl.checkpoint`'s poll it yielded the run, then yielded it
    again on the next poll, until the 900-second backstop. Five suites did this. **It was not
    one leaker suite leaving state behind, which is what brief `56-…` expected** — a probe on
    the singleton named the caller on the first run, and it was the poll's own contention
    probe. Fixed by inverting the defaults: a fresh latch and a `NullContentionMonitor` unless
    named, with the process-wide pair named once in `main.swift`, which is the construction
    that wants them. A park that happens anyway now writes one line after 20s naming the run
    and its cause; the backstop is unchanged, because how long a person's pause may hold a run
    is a product decision. Referred out of family: **grok died (exit 142)**, the Google lane
    argued for no-default-anywhere and was taken on direction but not on cost (47 call sites
    against 1, and its own named failure mode is a shared helper reintroducing the singleton).
    `ForegroundWiringTests`: killed at 10 minutes on `main`, **1.189s** on the branch.
  - **PRO-0054 `a4483ec` — the flaky four, which were thirty-seven.** With the suite finally
    reporting, the verdict was `1426 tests … failed with 37 issues`, and **35 of the 37
    reproduced byte-identically on unmodified `main`**, so none were caused by PRO-0055.
    All of them, plus both remaining brief cases, had **one cause**: `SessionAct.refusal`
    called `Grants.secureEventInputActive()` directly, in the hot path of every step. Secure
    input is on whenever anything on the Mac holds a password field, and a refused step raises
    no statement, arms no block, declares no post and yields nothing — so every assertion about
    synthetic behaviour failed together. The set looked random because it depended on what the
    person at the keyboard was doing. Secure input becomes a parameter, Accessibility a seam,
    six harnesses declare their machine. **Production is unchanged**: `main.swift` names
    neither probe, so both read the live grants, and refusing under secure input is still
    correct. `HoldAttributionWiringTests` went from **123 seconds to 1.5**, and the suite from
    126s to ~6, because a refused step still waited out its settle budget — most of the
    suite's runtime was spent waiting for actions already refused.
  - Two of the project's own load-bearing beliefs were wrong and are corrected here: brief
    `55-…` says three tests redden the gate (it was 14 tests / 37 issues, understated because
    nobody had seen a complete run), and `ScreenRecordingProbeWiringTests`, named in that brief
    as the hardest of the four to make honest, **needed no change at all**.

- 2026-08-16 **The wedge is diagnosed and allocated as PRO-0055.** Sampling the hung process
  gave six threads on one identical stack: `Session.scheduled` (SessionQueue.swift:96) ->
  `runSteps` (SessionAct.swift:360) -> `haltCheckpoint` (SessionHUD.swift:210) ->
  `RunControl.checkpoint` (RunControl.swift:252), which is an unbounded poll returning only on
  a halt or on becoming un-parked. A run parked with neither spins forever holding its lane.
  - **The cause was already written in the tree.** `YieldWiringTests.swift:121` carries a
    comment from the fix to its own instance: `Session.runControl` defaults to
    `RunControl.shared`, so a harness that injects only when asked hands every other test the
    production singleton, and one test yielding it leaves the next one's checkpoint waiting out
    a **900-second backstop**. That suite injects its own latch now; **every other suite still
    gets the singleton**, because the default was never changed.
  - **Ruled out by measurement, not by argument:** not load (reproduces at load 6), not
    `replayd` (survives a restart), not `BrowserLaneWiringTests` (skipping it changes nothing),
    and not any single suite (`DelegatedSupervisionWiringTests` alone passes 28 tests in
    0.644s).
  - Brief `56-…`, `Last allocated` 54 -> 55. It blocks PRO-0054's merge and any honest
    full-suite gate, so it goes first.
- 2026-08-16 **The whole test suite wedges, and it is not PRO-0054's three flaky tests.**
  Found while trying to gate PRO-0054, and it is now the thing blocking that merge.
  - **Reproduces on unmodified `main`**, at load average 6 with **zero** stuck test helpers,
    and it survives a `replayd` restart. So it is neither the machine saturation that
    explained the earlier deaths nor PRO-0041's `SCShareableContent` wedge.
  - **Shape:** 1571 tests start, 1520 finish, **24 to 59 never report**, and the process never
    prints a verdict line. `scripts/test.sh` correctly refuses to score it, which is the only
    reason this was visible at all.
  - **The lead:** every unfinished test goes through `Session.act` — foreground and
    background reporting, browser page disclosure, delegated batches, the replay trail. That
    is an actor or settle that never returns rather than a test problem, and it wants its own
    item.
  - **Also cleared out:** seven orphaned `swiftpm-testing-helper` processes whose test bundles
    had been deleted with their worktrees, two of them from `.worktrees/PRO-0044` and stuck on
    `--filter BrowserLaneWiringTests` since before PRO-0041 merged. They were holding resources
    for hours. Killing them dropped load from 28 to 22 and did **not** fix the wedge.
- 2026-08-16 **PRO-0054 partially fixed on `ai/pro-0054`, unmerged and ungated** (`0521416`).
  - **Two of the three flaky tests fixed, and the diagnosis was the stopped runner's.**
    `TakeoverWiringTests`' two `inFlight` assertions freeze the clock: `inFlight` is bounded in
    TIME rather than to the step (`now() - declaredAt < 0.25`), and both tests declare, run a
    whole batch on the wall clock, then assert the window is still open. Freezing cannot
    conceal the defect guarded, because a background run's error is to clear `declaredAt`, and
    `inFlight` reads false on nil at every instant. The sibling four lines up asserts
    `declaredThisStep`, has identical shape and never flaked, which is what identifies the
    cause rather than merely fitting it.
  - **The fourth case fixed, and it was the only non-intermittent one.** `ToolchainDoctorTests`
    injected a fake Screen Recording probe and nothing for Accessibility, so `doctor()` read
    the test host's live `AXIsProcessTrusted()`. `Session` now takes an `accessibilityProbe`
    defaulting to the live read, symmetric with `screenRecordingProbe`.
  - **`ForegroundWiringTests` deliberately untouched:** its fix needs a rendezvous through
    `FakeAX.perform` and is not worth landing unverified.
  - **Not merged, because it cannot be gated** while the wedge above stands. A parked item with
    a reason beats a green tick nobody checked.
- 2026-08-16 **PRO-0052 merged `d6cf947`. The skill matches what shipped.** No source change,
  and that is the correct outcome: the code was right and its description was not.
  **772 insertions, 105 deletions across `SKILL.md` and `references/tools.md`, edited in place
  in `~/Dev/fledgeling-plugins` and left UNCOMMITTED for the reader.**
  - **Six drifts beyond the brief's list**, found by checking every claim against
    `ToolCatalogue.swift` rather than against the brief: the tool count was 19 (now 20);
    `scripting` was documented as including `policy`, which is `full`-only; the `ax` profile was
    undocumented; "sixteen assertion kinds" is seventeen and `horizontalAlignment` was missing
    from the enum; `snapshot`'s `maxNodes` default is 600, not 2000; and the honesty section
    described a synthetic-plane step as the server falling back, **which is true only for
    `type` and `scroll`** — an outright refusal fails the step, the opposite guarantee.
  - **A correction the runner made against the direction file.** Its first draft said
    supervision holds intact under delegation, which is what `00-WAVE-7-DIRECTION.md` implies.
    Reading `spec-PRO-0046.md` instead showed three real regressions, now in the text: an
    off-Space window is refused on the Cua lane and reachable on the native one; the takeover
    statement goes up *after* an unrequested foreground escalation; and a batch whose driver
    Proctor cannot identify arms no input block, so click-to-Stop is never consulted and the
    person keeps Escape, the menu bar and the gaps between steps.
  - **The honesty caveat is in the text:** `which cua-driver` returns nothing on this machine,
    so the skill tells anyone selecting that lane to treat the first delegated step as a probe.
    `maestro` and `simctl` both resolve, so the Maestro lane carries no such caveat.
  - **Child work:** `Sources/ProctorShim/Install.swift:217` still prints "advertises all
    nineteen (~11.3k)" in its post-install help.
  - **Not touched:** the seven campaign stages, `references/methodology.md` and
    `references/evidence.md` (both flagged in Depth as macOS-lane and pre-seam), and the plugin
    version bump, which is the reader's call.
- 2026-08-16 **Two PRO-0054 runners collided in one worktree, and the orchestrator caused it.**
  `claude-lifeline`'s daemon auto-resumed the dead run `wf_b1b506b3-e9c` (pid 49407) at the
  same time as the orchestrator dispatched a clean re-run (`wf_7c3cc18e-9ec`). Both landed in
  `.worktrees/PRO-0054` on `ai/pro-0054`. The second runner detected the first, **touched
  nothing further, and handed back** rather than racing it — which is the correct behaviour and
  is why nothing was lost.
  - **The orchestrator's error, plainly:** `workflow-resume`'s first rule is to establish
    liveness before relaunching, and a lifeline auto-retry is exactly the case it names. That
    check was run for stage 1's four failures and skipped here.
  - **Resolution:** the live resumed runner keeps the item. Killing it would discard context it
    had already built (`.worktrees/pro-0054-partial.patch` showed working fixes for all three).
    No further PRO-0054 dispatch until it reports.
  - **Contract violation to note:** the resumed runner committed `03bf3f6` **directly to
    `main`**, which STOP BEFORE MERGE forbids. Content is documentation only — 20 lines
    annotating the brief with a fourth case — and `main` is green at 1416/157, so it stands
    rather than being reverted. This is the second time a runner has reached `main` unbidden
    (PRO-0042 ratified the first).
  - **A fourth case, and it is not intermittent.** `ToolchainDoctorTests.swift:203` injects
    `screenRecordingProbe: .fake()` but **nothing for Accessibility**, so `doctor()` reads the
    live `AXIsProcessTrusted()` of the test host. The suite therefore passes or fails on whether
    the terminal that launched `swift test` happens to hold the grant. Not a product
    regression: `ready` correctly reports a real ungranted Accessibility, which is PRO-0041's
    deliberate fail-closed behaviour. PRO-0041 already built the injectable seam that fixes it.
  - **The stopped runner's independent diagnosis, preserved here because it was derived before
    it knew the other existed, and the two agreeing matters:**
    - **`TakeoverWiringTests.swift:317` is a test defect, not PRO-0053's bug again.** `inFlight`
      is **time-bounded, not step-bounded**: `now() - declaredAt < PersonInput.graceSeconds`,
      and that grace is **0.25s** (`Sources/ProctorCore/Contention.swift:260`). The test
      declares, runs a whole batch on the wall clock, then asserts the window is still open, so
      a batch slower than 0.25s expires it naturally and the test reports a clearing nobody did.
      Batch measured at 0.108-0.136s across 12 isolated runs at load 103-180 — a 2x margin that
      whole-suite load closes. The fingerprint that confirms rather than merely fits:
      `aNonPostingRunLeavesTheDeclarationAlone` (line 300) has identical shape but asserts
      `declaredThisStep`, which is **not** time-bounded, and does not flake.
      `aRefusedSyntheticBatchLeavesTheKeeperAlone` asserts `inFlight` too and is vulnerable to
      the same expiry, unmeasured.
    - **`ForegroundWiringTests.swift:108` is a polling race with no defect behind it.**
      `Session.swift:347` sets `foregroundRuns[token]?.active = plane == .syntheticEvent` per
      step, so the state is true only between step 0's settle and step 1's, and the test polls
      from outside the actor on an 800ms budget. `actuator.perform` is `async` on a
      non-isolated backend, so `FakeAX.perform` runs off the `Session` actor and can be parked
      without deadlocking `recentActivity()` — that is the seam a rendezvous should use.
    - **`ScreenRecordingProbeWiringTests.swift:116` already drives the probe's clock**
      (`now: { 0 }`). The 300ms `Task.sleep` is not a clock but a bet that a detached straggler,
      resumed through `Gate`'s `DispatchQueue.global()` blocking wait on a queue the suite
      saturates, lands inside a fixed wall duration. PRO-0041's own design says that arrival is
      unbounded.
    - **On the process dying with no verdict: it could not say, and said so.** Six whole-suite
      runs at load 61-103 all produced a verdict. One observation rather than a conclusion: its
      base ran **1416 tests in 157 suites** while the deaths were reported at ~1523 tests
      already run, so those runs were on a different and larger tree.
- 2026-08-16 **PRO-0054's first attempt lost, and it cost a contract rule.** The runner died on
  the gateway 503 `over_reserve` that also killed all of stage 1, but the interesting part is
  what it did before dying: it ran a rebase that replayed **55 of `main`'s commits onto its own
  stale base** (`dc48889`, from wave 6) rather than moving its branch onto `main`. The branch
  ended up a rewritten copy of the whole wave's history containing **no PRO-0054 commit at
  all**, and its own edits — `ForegroundWiringTests.swift` had been touched — were destroyed.
  A content diff against `main` was pure deletion, so nothing was recoverable and there was
  nothing to resume. Branch and worktree removed, item re-run from scratch.
  - **`main` was never at risk**, because every merge in this wave was `--ff-only` and the
    branch was never merged.
  - **The contract now says runners never rebase, the orchestrator does.** It previously said
    only "stop before merge", which several runners read as licence to rebase first; two did so
    harmlessly and this one did not. A runner's branch being behind `main` is expected and is
    the orchestrator's problem.
- 2026-08-16 **PRO-0038 merged `30324a6`.** 1391 -> **1416 tests in 157 suites**. A determinism
  score now says what it was a score of, **and stops folding a hash it cannot vouch for.**
  - **Two defects, and the second was worse than the brief's.** The brief reads as a disclosure
    item. Underneath it, a PRO-0045 `indeterminate` step stores a post-state walk taken after
    an action Proctor cannot vouch happened, and **that hash was entering the fold**. Removing
    the fix showed a two-repeat sweep whose second repeat died that way reporting
    **`deterministic: true`**. The runner's own first spec draft claimed the short-column guard
    already withheld that verdict; it does not, because an indeterminate step is the last step
    of its repeat, so its hash leaves the column full. The spec was corrected against the
    measurement rather than the other way round.
  - **The design gate killed a draft that would have appeared to work.** The first version
    scanned before the sweep, but a step's target usually does not exist until earlier steps
    have run — so a flow that opens a page and then drives it would have shipped no disclosure
    while still publishing the page's number. Classification moved into the shared step loop.
  - **A step measured on one sample was still scoring `0.0`**, because `Canonical.instability`
    returns 0 for a one-hash column. The number is now omitted below two samples.
  - **The brief's fourth hard part was a premise this build contradicts**, and the runner said
    so rather than inventing a step state: no step here is handed off and not executed, because
    the browser handoff is advisory and there is no browser/CDP lane in `Actuation/`.
  - **The sharpest limit, from the completeness critic:** a state hash walks the whole window,
    so the page's tree is inside every step's hash in a browser window. **The label marks where
    a step acted; it does not partition the score.** Written into the spec and into
    `HashSubject`'s documentation, and logged as child work.
  - **Orchestrator note on the gate:** the branch died with no verdict line in 2 of its first 6
    runs while `main` was 4/4 clean in the same window, then went 6/6 green. Both failures were
    the whole process dying with ~1523 tests already reported, not an assertion failing, which
    is the saturation shape rather than a defect shape, and both landed while PRO-0054's runner
    was building. Merged on 10/12 with the observation recorded rather than explained away.
- 2026-08-15 **PRO-0029 merged `153951b`.** 1349 -> **1391 tests in 155 suites**. The switches
  have a home.
  - **The enumeration moved the design, which is why the brief told it to enumerate.** 32
    `PROCTOR_*` names exist; 8 are runtime agent switches. The brief's list of six was wrong
    three ways: `PROCTOR_TAKEOVER` exists and was never listed, so a card built from the brief
    would have silently omitted one of the two switches governing what appears over a person's
    screen; `PROCTOR_ACTUATION` is now first-class; and **`PROCTOR_SECOND_LANE` is no longer a
    boolean** — it takes the literal `browser-use`, so a checkbox writing `1` would have read
    enabled in the window and been off in the agent.
  - **Precedence is two rules, not one, and the gate found the first draft failing.**
    Environment wins and locks for the six ordinary switches. But **off wins from either
    source and the control never locks for the two capability switches**, because an env var
    could arm the keyboard-swallowing tap and the lock rule then disabled the only control
    that could turn it off.
  - **Nothing writes the launchd plist.** `install.sh` rewrites it wholesale with no
    environment block, so a preference stored there would be destroyed by the next upgrade —
    which is the disappearance the brief exists to fix.
  - **Seven of eight apply at next start**, said per row with a pending marker that clears
    only when the agent's own next report says the new value is what it is running with.
    Proctor never claims a change landed on the strength of having written it.
  - **The runner introduced a flake and removed it:** its first test suite mutated a
    process-wide global while 1286 tests ran concurrently.
  - **Deliberate refusal:** the two `PROCTOR_CUA_ALLOW_*` signature bypasses are not surfaced.
- 2026-08-15 **PRO-0054 allocated mid-fleet.** PRO-0029 measured `TakeoverWiringTests.swift:317`
  still failing 2 in 30 on unmodified main **after** PRO-0053 fixed line 122 of the same file.
  With `ForegroundWiringTests:108` and `ScreenRecordingProbeWiringTests:116` that is three
  load-sensitive tests reddening a full run about one time in ten. Given PRO-0053 proved this
  class was a live production defect rather than a test problem, they get an item rather than
  another note. Brief `55-…`, `Last allocated` 53 -> 54.
- 2026-08-15 **PRO-0049 merged `7ca9358`. The iOS lane can run and score Maestro flows.**
  1293 -> **1349 tests in 144 suites**, and this is the first wave 7 item **verified live
  against the real binary** rather than a fake: maestro 2.4.0 against a real simulator.
  - **It took PRO-0044's warning and did not fight it.** Not an `ActuationBackend`. The seam
    is `MaestroRun.swift` (pure) plus `SessionMaestro.swift` (impure), reusing PRO-0048's
    split.
  - **`firstDivergence` needed no new meaning, and reading the code was cheaper than
    designing one.** `proctor_stability` already folds repeats against *each other* rather
    than against a recording; only `proctor_flow`'s replay needs a recording. So the meaning
    carries over intact, `StabilityScore.fold` is reused unchanged, and the wire says
    `divergenceBasis: "repeats"` and `divergenceIndexIs: "maestro sequenceNumber"` so nobody
    infers it.
  - **The score's cell was measured, not reasoned.** Five identical passing runs gave an
    identical 7-command status vector while one unchanged command's duration spread
    **634/91/88/96/91 ms**. So the cell is `hash(command identity + status)`, and duration,
    timestamp, exit code, the JUnit report and the hierarchy dump are all excluded with their
    reasons recorded in place. Honestly thinner than the macOS lane and the result says so:
    three observers per step there, **one observer per command here**.
  - **Driver flake versus app flake is separated by the record, not the exit code.** An
    assertion failure, an absent device and a malformed YAML **all exit 1**; only the first
    writes a per-command record. Three signals give `driverFailed` and are excluded from the
    fold, marking the sweep truncated. What stays inseparable is stated rather than claimed
    away.
  - **The gate found a real bypass:** unresolvable constructs were refused only under an
    *allow* list, so a **block** list with no allow list was a hole. Now keyed on any policy
    in force. It also caught that enumerating app-id-bearing keys is a losing game (naming
    five immediately), replaced by collecting every reverse-DNS token, which over-detects and
    cannot under-gate.
  - **A surface the brief never named:** a Maestro YAML is caller content Proctor executes
    from a process holding Accessibility. The gate judges what the flow **declares**, weaker
    than `open`'s device-resolved judgement, and every field says `declared`. A `config.yaml`
    beside the flow is scanned too, since Maestro reads one implicitly, and the trail carries
    a content hash so an entry attests to the bytes that ran.
  - **Child work:** `maestro hierarchy` is measured working and is the natural route to an
    iOS `proctor_assert`; a shared flake-attribution vocabulary with PRO-0044's
    `suspected_noop`; a reset between repeats.
- 2026-08-15 **PRO-0046 merged `2f240bf`. Supervision survives delegation, and it closed four
  defects reachable on merged `main`.** 1242 -> **1293 tests in 140 suites**.
  - **The four, all found by reading the code before designing.** A delegated click could
    press Stop, because the tap tests the Stop rectangle for anything failing `isOurs` and is
    suppressed only while Proctor has a post in flight, which a delegated step never declares.
    An armed block ate the driver's events, because `RunQueuePlan.grantable` makes `.global`
    and an app lane disjoint, so a native posting run and a delegated run genuinely overlap
    while `InputBlocker.shared` is one tap. Both pointers drew. And a delegated
    `foreground: true` batch drove the declaration keeper with nothing to declare.
  - **Event discrimination:** `InputBlock.isOurs` admits one further identity — the driver's
    pid, corroborated against the signed program the lane verified, honoured only inside a
    call plus a trailing grace, and read by *both* the tap and the panel's own view.
    `isAPerson` is unchanged and pinned; that rule was already written the safe way round.
  - **Two cursors:** exactly one draws, decided per run. Proctor's is preferred and the driver
    is asked off on every action; where it cannot be asked, **Proctor stands down**, because
    that is the half it can enforce.
  - **The plan gate killed a mechanism before it was built.** A suspend/resume on the hold
    would have lifted a process-wide guard on one run's behalf that a concurrent run was
    keeping — PRO-0053's cross-run clear again. Replaced by having an unrecognised lane take
    `.global`, so the overlap is impossible rather than managed.
  - **The completeness critic found an acceptance clause of the runner's own spec that was
    not implemented:** a swallow during a delegated call was still reported as person input,
    so a driver whose events looked like hardware would make the run hold itself to the
    backstop. Fixed in the second commit.
  - **A1 proved mechanically:** `git diff -U0 -- Tests/ | grep -c "@Test"` is 0, so no
    existing test body changed, and four production gates were reverted one at a time to turn
    their named tests red.
  - **Two defects in its own work, recorded:** a test asserting the clock rather than the
    clobber, and a process-wide `static var` test seam two parallel suites stomped — now a
    constructor parameter, which is the exact class PRO-0053 spent a session on.
  - **Deliberately not built:** the grace window is not widened to the delegated lane. It does
    not insure against the threat it names, and `ContentionMonitor` is a singleton so it would
    blind a concurrent native run's signal.
  - **Stated limits:** `actuatingPid` and `cursorSuppressible` are documentary readings, since
    the driver is not installed; both fail closed, so being wrong costs a serialised lane or
    an undrawn pointer rather than an absent guard. And on this lane the full-screen takeover
    statement can only go up *after* the first unrequested escalation, because nothing outside
    the driver's process knows before it does.
  - **Child work:** the driver's prose still reaches the audit row's `reason` unfenced, so
    PRO-0045's rule should apply there; **PRO-0018's Known-limits prose contradicts its own
    code** about whether a remapper's events hold the run; `stepsAside` raises the full-screen
    statement pessimistically on this lane.
  - **Orchestrator note:** the rebase was a four-file semantic merge. `Wire.swift` and
    `SessionAct.swift` each had PRO-0051's `backend` against PRO-0046's `pointerDrawnBy` on
    the same initialiser, `CuaPreflight` had two disjoint field groups, and
    `CuaActuationBackend`'s init had `transport.adopt` against `self.corroborate`. All
    additive once separated.
- 2026-08-15 **PRO-0036 merged `c9e42c9`, and it found a defect PRO-0050 had shipped to
  `main`.** 1216 -> **1242 tests in 136 suites**.
  - **The shipped defect, found by building the app and looking at it.** `Dispatch.swift`
    overwrote `doctor`'s `policy` posture with the full ungated status. Two consequences, both
    live on `main` until this merge: every allow, block and sensitive entry, the filesystem
    roots, the trail path and the key id went back into the first call a model makes, so
    PRO-0050's clause 12 was true of the type and **false on the wire**; and it broke the
    status window outright, because an optional field that is present but wrong-shaped still
    throws, so `DoctorReport` could not decode its own agent's reply. **The window reported a
    healthy agent as "not answering", permanently.** Confirmed both ways at the exact error:
    `DecodingError.keyNotFound`, key `mode`, path `policy`.
  - **The per-button verdict the brief asked for: two of three were honest.** Buttons A and B
    each read something uncached, sit inside a remediation block, and change their answer when
    pressed; both kept. The footer's `Re-check` is deleted on two source measurements:
    `stopPolling()` is called by nothing, so the poll runs for the app's whole life, and
    `lastChecked` is re-stamped on every landing report, so the clock beside it already
    advanced without it. It refreshed rows that refresh themselves, and the one row anybody
    presses it for cannot move at all.
  - **The triage gate reversed the runner's own central decision.** Its draft argued for
    keeping the third button; the gate showed it was counting live rows rather than counting
    why anyone reaches for it. The plan gate then reversed the fail-safe direction: an
    unrecognised check name falls to Tools, not Permissions, because defaulting into
    Permissions re-creates the very defect. The Phase D critic found a clause matched by
    nothing and named the structural hole extraction creates — every rule is tested in the
    library, so the *view* could stop calling it and stay green. There is now a scan for that,
    proved red.
  - **Verified by eye without installing**, by running the build against a private agent on
    `PROCTOR_SOCKET` rather than replacing `/Applications/Proctor.app`, since three siblings
    were in flight. Seen: Permissions holding only the three permissions; "Optional — asked
    for per app" on Automation alone; the Tools card with `simctl` 26.6, `maestro` 2.4.0,
    `cua-driver` not found, and the `Shortcuts CLI` row the brief is named for.
  - **Not seen and not implied:** the denied and unconfirmed sentences and the restart offer,
    which need a permission revoked on this machine.
  - **Child work, two found today:** an older agent still breaks a current window with no
    message saying so; and **driving Proctor's UI through Proctor destabilises the agent** —
    it knocked the installed agent over twice.
- 2026-08-15 **PRO-0051 merged `0f76c56`. Reading 3: the native planes stay.** 1193 ->
  **1216 tests in 133 suites**. An operator selects the delegated lane deliberately, nothing
  falls back automatically, and native remains the default — the **maintained** default, not
  a frozen one.
  - **Deletion was not actually on the table.** The native code covers 22 step kinds across
    four planes and Cua replaces two. `appleScript` and `shortcut` have no delegated
    equivalent and PRO-0044's own spec already refuses them, so deleting removes two
    published verbs. Cua also returns only a menu bar for a window on another Space where a
    retained `AXUIElement` keeps resolving, and `cua-driver` has never executed on this
    machine. Any one of those defeats it.
  - **Automatic fallback lost because it does not stop.** It hands back a verdict that looks
    fine and measures the plumbing.
  - **The gate changed the decision twice.** It killed a written reversal condition as a
    *scheduled* automatic fallback — a default that flips when a condition becomes true
    contaminates the score across runs the way a mid-run fallback contaminates one within a
    run, and nobody chose it. And it killed the "frozen native lane" refinement, because
    PRO-0034 was retired as "Scroll is Cua's now" while closing a real defect in the path
    `main.swift` still selects by default. Maintenance continues; only expansion is capped.
  - **Two of the brief's premises were wrong and the runner corrected them.** "Several
    hundred tests pin the native planes" is false: 13 references across 3 files. What
    deletion would really have destroyed is the macOS characterisation in the comments (AX
    reports success for a write the app discards; lazy submenus; `AXSelectedText` inserts at
    the caret). And its own suspected gap was refuted by measurement — an actuated native
    step already encoded `"backend":"native"`.
  - **One behavioural change, proved red→green:** `requireSameBackend` checked only the
    tape's first backend and now checks every one.
  - **A plan gate caught a build-breaker:** an `init` default does not make `Codable`
    tolerate a missing key, so the new lane field is optional with no default, which also
    stops a forgetful call site asserting the wrong lane.
  - **Child work:** PRO-0034 was retired on a premise this item rejects; `appleScript` and
    `shortcut` are unreachable on the Cua lane; `KeyCodes` has no test.
- 2026-08-15 **PRO-0045 merged `1bff5c2`.** 1162 -> **1193 tests in 131 suites**.
  - **What the trail attests to, which was the deliverable as much as the code.** Every row
    is a claim Proctor makes about a request *it* made. For a native step, intent and act are
    one event. For a delegated step the row carries three facts of three strengths and never
    merges them: Proctor's own knowledge (the gate allowed this app, Proctor sent this
    request); an external claim (`mode`, `eff`, which Proctor did not witness and does not
    vouch for); and Proctor's own before/after reading of the accessibility tree (`obs`),
    the only part it witnessed. Where the two disagree the row records the disagreement
    instead of resolving it. **And the gate governs what Proctor does, not the machine** —
    stated in code, not only in the spec.
  - **Intent and outcome turned out to be three facts, not two**, and `obs` is the one that
    stops the trail becoming a record of intent.
  - **A new `indeterminate` outcome, deliberately not `failed`.** `failed` asserts the action
    did not happen, and a driver that dies mid-step may have delivered it first. Those rows
    keep Proctor's reading, stop the batch, are never auto-retried, and drop to the noun form
    so Proctor never says "Pressed" about something it could not establish.
  - **The gates found real defects at every stage.** The design review found a
    time-of-check/time-of-use gap between the path check and the spawn, which would have made
    the lane record attest the wrong build — an audit feature manufacturing evidence rather
    than losing it. The plan review found five bugs in the line reader (polling ahead of a
    buffered line, discarding the residual on expiry, EOF read as timeout, millisecond
    truncation to `poll(…,0)`, a wall clock) and an event drain that interleaves on a
    reentrant actor.
  - **Two deviations recorded rather than absorbed:** `PROC_PIDAUDITTOKEN` is absent from the
    public SDK, so identity uses `kSecGuestAttributePid` with the residual pid-recycling
    window named in code; and the typed failure became two fields on `AgentError` rather than
    a wrapper type.
  - **Foundation defect fixed:** `CuaEndpointTransport.callTimeout` was declared in PRO-0044
    and never read.
  - **Child work:** the driver wire has no request ids, which is why a timeout must poison the
    lane; two concurrent sessions share one driver, so one session's timeout closes another's
    lane; `proctor_doctor` does not report lane identity though the trail now does.
  - **Second load-sensitive flake found at merge**, unrelated to this item:
    `ScreenRecordingProbeWiringTests.swift:116` ("a late answer is picked up by the next
    call") failed 1 in 7 under fleet load. Not in PRO-0045's diff; it belongs to PRO-0041's
    own suite. Together with `ForegroundWiringTests.swift:108` (2 in 30 in isolation) there
    are now two timing tests wanting the PRO-0053 treatment.
- 2026-08-15 **PRO-0050 merged `0ea6f88`.** 1105 -> **1162 tests in 128 suites**. `doctor`
  reports the whole toolchain, per-lane, **and creates no subprocess at all**.
  - **The design changed twice and a gate forced it both times.** The first draft had
    `doctor` spawning `cua-driver doctor` behind an opt-in switch with a 1.5s bound and a
    backoff. Gone: every answer is now a read (stat, readlink, one plist, and a
    `SecStaticCode` signature check that reads the file and executes nothing). The spec gate
    killed the env-var spawn gate as a parameter boundary rather than an execution one, and
    killed the exit-code classifier on the ground that a driver can exit 0 while printing
    that it is unhealthy.
  - **Measurement drove the shape.** `maestro --version` costs 3.9-5.3s of JVM start against
    a 2.0s doctor poll, while the same version sits free in Homebrew's symlink target and
    Xcode's sits free in a root-owned plist.
  - **PRO-0044 merging mid-run made the item smaller, not larger.** `CuaPreflight` already
    reverses the never-execute rule narrowly behind a signature check pinning
    `com.trycua.driver`, and `CuaLaneReport`'s own doc comment already said it existed "for
    the run record and for `proctor_doctor`".
  - **Installed is not usable**, as a new axis beside `available`, carrying PRO-0041's three
    states over an evidence ladder `absent → presence → signature → installPath → laneReport`
    that never reports "nothing known" about a file it just located.
  - **The policy block reports mode, counts and audit posture and no bundle id, path, key or
    token** — and says plainly that this is a convention rather than a boundary, because
    `proctor_policy status` is ungated and answers in full. `doctor` is the first call a model
    makes, so no driver-supplied text reaches it, the keys of its permission map included.
  - **The shell doctor reports where a login shell honestly disagrees with the agent**,
    verified live by planting a binary outside the search list, under bash 3.2 as well as 5.
    The search order is generated from one Swift definition with a drift test that also
    asserts `doctor.sh` sources that exact path.
  - **Child work found:** `proctor_policy status` is ungated and returns the full lists, roots
    and audit path, so doctor's posture-only rule is a convention while that stands;
    **PRO-0044's delegated child inherits the agent's descriptors and runs in its process
    group, so `terminate()` does not reach grandchildren** (this one matters for PRO-0046);
    PRO-0049 should consume the `maestro` row rather than probing again.
  - **Not measured against a real `cua-driver`**, which is not installed. Its rows are proved
    against constructed facts and the absent path, stated in the spec rather than implied by
    a green suite.
- 2026-08-15 **PRO-0053 merged `477941f`. It was not a flake, and the gate rule this project
  had been using was wrong.** 1101 -> **1105 tests in 118 suites**.
  - **The test was reporting a live production defect.** Only `shows.count` failed while
    `arms.count` four lines below passed, and that asymmetry is only possible if
    `takeoverShown` was already true when the batch reached its first synthetic step.
    `SessionAct` set it from `SyntheticPost.shared.declaredThisStep`, a process-wide flag
    another suite had set. Reproduced on `main` at 7 in 8 paired, 1 in 3 whole-suite.
  - **What it broke in production.** `RunQueue` documents two sessions driving different apps
    in parallel, and every run called `beginStep()` at each step boundary, clearing state
    belonging to whichever run was actually posting: `declared`, so the poster stopped raising
    the statement that says the machine has been taken (**PRO-0026 failing silently**), and
    `declaredAt`, so the event tap's in-flight window closed early and it read the Stop
    rectangle while Proctor's own click was still travelling (**PRO-0033, the worse half**).
  - **The fix adds no lock and weakens no assertion.** A run joins the declaration protocol
    only when it can actually post, and such a run holds the exclusive global lane, so it has
    the shared instance to itself: `demand.mightPost && foreground`, reusing the scheduler's
    own value. `shows.count == 1` is byte-identical. The completeness critic supplied the
    `&& foreground` half: the stability sweep buys lanes from the flow's steps then runs
    `resetBetween` through the same loop, so `mightPost` alone did not imply holding the lane.
  - **`swift test` exits 1 on failure. The zero exit was ours.** Plain and under `--parallel`.
    The zero came from `swift test | tail` without `pipefail`, which returns `tail`'s status —
    a defect in how this orchestrator and two runners invoked it, not in the toolchain. The
    earlier event-log note claiming otherwise is superseded by this one.
  - **`scripts/test.sh` is the gate from here.** It refuses three ways a red suite reads as
    green, all measured on this repo: the lost exit code above; the XCTest summary printing
    `Executed 0 tests, with 0 failures` on failing runs, because these are swift-testing tests
    and that line counts the XCTest ones; and a filter matching nothing producing a real
    verdict line reading `Test run with 0 tests ... passed`.
  - **Evidence, because a race passing once proves nothing:** zero takeover failures in 80
    post-fix runs (45 paired, 35 whole-suite) at load averages 18 to 97, with another runner
    active. All four new tests checked red first by reverting the gate.
  - **Orchestrator observation at merge:** one of seven gate runs died mid-run at load average
    **146** with no verdict line, and `scripts/test.sh` correctly refused to score it. Not a
    test failure; the same machine-saturation family as PRO-0041's wedge, and a reason the
    concurrency cap stays at 3.
  - **Child work found, unspecced:** `ForegroundWiringTests.swift:108` fails 2 in 30 **in
    isolation**, so it is a polling race inside that test's own 800ms budget rather than
    cross-suite state. Needs its own item and a design call about observing mid-run state
    deterministically.
- 2026-08-15 **PRO-0044 merged `d65dc1e`. The pivot's centre is in.** 1043 -> **1101 tests in
  118 suites**. Actuation now sits behind an injected `ActuationBackend`, with
  `CuaActuationBackend` beside `NativeActuationBackend`; observation stays in Proctor.
  - **It is a seam, not a rewrite, and that is checkable rather than asserted.**
    `Sources/ProctorAgent/AX/Actuator.swift` has **no diff** on the branch, and every
    existing test passed with no edit to any `Session(...)` construction.
  - **The gates caught four contract-level errors, one of which would have gutted the
    feature.** `Session.refusal` refuses `click`/`key`/`hover`/`dragPath` whenever
    `foreground: false` — a fact about *Proctor's* actuator, not about clicking. Left
    untouched it would have shipped a Cua lane whose **background clicks were unreachable**,
    which is most of the reason to adopt Cua. The kind→plane prediction is now a question
    asked of the backend.
  - **A withdrawn argument, recorded as withdrawn.** The transport choice rested on spawn
    variance entering the determinism score; `StabilityScore.fold` folds state hashes and
    never time. Restated as a cost claim with the reversal threshold written down.
  - **`AXIdentifier` does not exist on Cua's side**, so the "most durable key" cascade
    collapsed to matching on a rectangle, which is coordinate addressing wearing a hat.
    Rebuilt on the `(role, label)` ancestor chain, with a two-observer agreement check
    before the strike, because a stale-token retry protects the second attempt only and a
    tree mutating under a still-current snapshot raises no error at all.
  - **Two defects its own tests caught:** the version gate admitted `0.14.0-nightly`, since
    semver sorts a pre-release below its release so `< 0.14.0` matched a build of 0.14; and
    a no-op step counted itself completed while letting the batch continue.
  - **`cua-driver` is not installed and was not installed.** The lane is proved behind
    `FakeCuaTransport`, and the spec carries an ordered first-contact checklist of what could
    not be measured live.
  - **Orchestrator note — the rebase was a real semantic merge**, not a textual one.
    `Session.swift` was additive (both sides added an init parameter). `SessionAct.swift` was
    not: PRO-0044's no-op verdict had to be combined with PRO-0047's enriched `auditStep`
    call, keeping the verdict's `ok:`/`reason:` and gaining `seq`/`ms`/`plane`/`node`.
  - **Child work found:** Cua's CDP browser lane may reverse PRO-0020's conclusion; a Maestro
    flow binds at flow level and does not fit this step-level seam, which **PRO-0049 should
    know before assuming otherwise**; two concurrent sessions would share one driver's
    snapshot map.
- 2026-08-15 **PRO-0048 merged `8d2fde6`.** 1015 -> **1043 tests in 113 suites**. The iOS
  lane exists.
  - **An iOS target is a new handle kind on a new tool** (`proctor_ios`, actions
    `list`/`boot`/`open`/`screenshot`), never a simulator dressed as an app.
    `Session.windowHandle` refuses a `dev-` handle **by name**, before it can fall through
    to "unknown window", with a message naming the ceiling and the route that works.
    PRO-0049 builds on `Sources/ProctorCore/IOSDevice.swift`, which holds the decision layer
    as pure code.
  - **simctl catches more than the brief feared, and the residue is named.** Measured before
    designing: `openurl` exits 194 for an unclaimed scheme and 149 for a shut-down device.
    The remaining silent success is a claimed scheme the app ignores, so `open` reports
    three channels separately and picks a verdict that never claims more than they support:
    `targetChanged`, `screenChanged`, `deliveredOnly` (inconclusive, **not** failed),
    `deliveredUnobserved`, `targetGone`, `refused`. It never claims which screen the app
    reached, because frontmost is not observable in this lane.
  - **The gates changed the design three times.** The spec gate killed the word "navigated"
    (a device-global pixel fraction cannot tell the target app from a banner), added the
    `screenshot` action (the lane was refusing every observation tool while taking device
    screenshots itself), and caught that gating on a caller-supplied bundle id reopened the
    hole `SessionPolicy` closed. The plan gate, on its retry with reading forbidden, found
    **two real defects in code already written**: the after-sample was taken before the app
    had painted, so every real navigation would have read `deliveredOnly`, and the output
    cap stopped reading and wedged the child.
  - **For callers:** a non-zero simctl exit is a `refused` **verdict in the result**, not a
    thrown error. Deliberate, but a caller checking for an exception sees success.
- 2026-08-15 **PRO-0047 merged `9756282`.** 943 -> **1015 tests in 111 suites**. History,
  and the reader gets the action log they asked to keep.
  - **What crosses the sealed boundary is a projection, asserted by a test that walks the
    emitted JSON.** Excluded: the `value`/`script` redaction fingerprints, `postStateHash`,
    seal and signing key ids, and the `app`/`window` session handles. That last exclusion
    came from the review and was also a bug — the record stores `app-3`, not "Mail", so the
    row as first specified could not have been drawn. Applications are named by bundle id.
    Decryption happens only when a person opens the window, never on a poll.
  - **The fence needed the record to change shape.** Proctor's verb and the object are now
    separate fields, because `Pressed "Send invoice"` cannot be fenced without fencing
    Proctor's own words. One `Fence` view is the only place foreign text is drawn, via
    `Text(verbatim:)` in a bordered run, and the window sets `sharingType = .none`.
  - **Retention: 14 days or 10,000 entries**, clamped 1-90 and 100-100,000, with no setting
    meaning "keep everything". Passing either cap rotates the trail whole, because the chain
    makes a front truncation unrepresentable; the new trail opens with a record committing to
    the discarded trail's identity, length and final hash. Clear is the same operation.
  - **The completeness critic found five real defects in shipped code.** A planted rotation
    marker could have had Proctor sign a discard that never happened; a corrupt marker drove
    a wipe; a rotation that finished but never cleaned up would have run twice and destroyed
    its own genesis; the cap decision sat outside the cross-process lock so two agents could
    both rotate; and the count came from an end-mark that freezes if the key store stops
    accepting writes, leaving the trail growing while reporting itself bounded.
  - **A pre-existing defect fixed on the way:** two suites each redirecting the process-wide
    trail seam ran in parallel and stamped on each other, since `.serialized` only orders
    tests within one suite. `Tests/ProctorAgentTests/TrailIsolation.swift` now holds the lock
    every trail-touching suite takes.
  - **Needs a human glance, not machine-witnessable:** the window's rendering, the fence as
    drawn, the Clear confirmation, light and dark, and the capture exclusion. `swift test`
    has no window server.
- 2026-08-15 **PRO-0053 allocated mid-fleet** for the `TakeoverWiringTests` defect, after a
  fourth independent measurement on `main`. Brief `54-…`, `Last allocated` corrected 42 -> 53
  (the wave 7 ids had been allocated without moving the pointer).
- 2026-08-15 **PRO-0040 merged `091d6c3`.** 937 -> **943 tests in 106 suites**.
  - **The layout decision was measured, not argued.** The runner built a probe binary and
    compared all three options before writing the spec. `Contents/Helpers/` works but nils
    `Bundle.main`: `resourceURL` becomes the Helpers directory, which is what `Bundle.module`
    resolves the HUD's character art through, and it moves paths in `install.sh`,
    `doctor.sh:76`, `Install.swift:51` and `AgentModel.swift:128`. An embedded
    `__TEXT,__info_plist` clears the LaunchServices record while leaving `bundlePath` and
    `resourceURL` pointing at the `.app`, so **the installed layout does not change at all**
    and none of those release paths needs a path edit. `build-app.sh`, the one step
    `install.sh` and `release.yml` share, carries the new gate.
  - **TCC preserved, and proven rather than assumed.** The designated requirement carries no
    path component, so keeping `codesign -i app.fledgeling.procter` preserves it. Measured
    before and after the upgrade: byte-identical, both grants `granted`, no consent dialog.
  - **The grok gate earned its place.** It raised that a later `codesign` omitting `-i` would
    adopt the embedded identifier and lose the grants a release later, silently. Tested
    rather than trusted: with `-i` dropped, `codesign -dv` really does report
    `Identifier=app.fledgeling.procter.agent`. The build gate now exits 1 on it.
  - **Changed from plan during work:** the linker flags are release-only. Applied
    unconditionally they propagated into `proctor-mcpPackageTests.xctest`, so every test
    process ran holding the agent's identity.
  - **Child work, superseded.** This entry claimed `swift test` exits 0 on a failure. It does
    not; see PRO-0053's entry above. The zero came from piping without `pipefail`. The
    measurement of `TakeoverWiringTests.swift:122` at 3 failures in 6 stands and became
    PRO-0053, which found it was a production defect rather than a flake.
  - **Not covered:** notarisation. `PROCTOR_SKIP_NOTARIZE=1` per instruction, so `spctl`
    reports the local install unnotarised. Expected, and not a property of this change.
- 2026-08-15 **PRO-0041 merged `0545219`. The full suite runs unskipped again.**
  881 (with two suites skipped) -> **937 tests in 105 suites, no skips**, green three times
  running at merge. `--skip ObscuraPresenceWiringTests --skip BrowserLaneWiringTests` is
  retired after two waves; the gate from here is a plain `swift test`.
  - **`unconfirmed`, not `denied`.** `Grant.state` is now granted / denied / unconfirmed,
    `granted: Bool` survives as the derived fail-closed bit meaning *confirmed granted*, and
    `ready` is false while a required grant is unconfirmed. The argument that settled it was
    already in the repo: `MenuBarBlock` was split because the doctor's blockers were two
    facts wearing one word, and a probe that did not answer is a third.
  - **Caching:** definite answers for process life, which is what macOS does anyway; a
    non-answer never cached, because it is a property of the moment; a late answer fills the
    cache for the next call and never rewrites a report already sent.
  - **Three measurements changed the design.** A structured `withTaskGroup` race does not
    bound this call, because the group awaits its children and `cancelAll()` cannot cancel a
    task parked in a non-cancellable continuation. The unstructured shape works and the
    process still exits with the probe parked. And `replayd` saturation aggravates rather
    than explains: a plain script answered in 0.037s while the test host got nothing in 120s.
  - **The grok gate ran three times and changed the work each time.** It rejected the first
    design as the safe lie wearing a new field, because `GrantRow` renders Open Settings off
    `granted == false` and never reads `blockers`; it killed strict single-flight, since a
    permanently parked probe would hold the slot and report unconfirmed for the agent's life;
    and the completeness critic found an unreaped slot, a straggler clearing a newer
    attempt's marker, and joiners sleeping the full bound after the answer landed.
  - **Child work, and it affects the gate.** `TakeoverWiringTests.raisedAtTheRightStep`
    fails 8 runs out of 8 on a clean detached checkout of `da4f48f` when run beside
    `StopReachabilityWiringTests`. A pre-existing cross-suite interaction, not a flake and
    nothing to do with grants; about 2 in 10 whole-suite runs. Wants its own item.
- 2026-08-15 **PRO-0043 merged `d4a1565`.** 879 -> **881 tests in 100 suites**, still with
  the PRO-0041 skips. Sent alone first as a capacity canary after the whole of stage 1 died
  on gateway 503 `over_reserve`; it survived, and PRO-0044 and PRO-0041 went out behind it.
  - **The brief's diagnosis was wrong in a way that changed the answer.** The runner
    measured the mechanism: the plugin's output is not cached against missing inputs, the
    prebuild command does not run at all when llbuild deems the plan up to date, and
    `swift build` / `swift test` keep separate plans. So there were no declared inputs to
    add and the brief's second reading had nothing to attach to.
  - **A third instance of the defect surfaced in gap-fix**, in `compiledVersionMatchesPlist`,
    which the brief never named. Editing the plist forward reschedules the generator;
    editing it back does not, so the binary can claim a version the plist has reverted.
  - **The grok gate changed the work.** It caught that the hermetic test wrote the
    generator's output inside the repo it was measuring, so the clean case observed its own
    artefact. Proven by mutation. First call died on the 300s deadline while opening files;
    the retry inlined the evidence, which is the documented remedy.
  - **Child work found, unscheduled:** the compiled identity can be stale in a freshly built
    binary, which qualifies PRO-0030's promise; nothing on the release path runs `swift test`,
    so a placeholder identity could ship green; and `TakeoverWiringTests.swift:122` is
    intermittently red in full-suite runs, proven pre-existing at `da4f48f` by five reverted
    runs.
- 2026-08-15 **Stage 1 CLOSED. PRO-0037 merged `f2221f6`, PRO-0032 merged `06259b6`.**
  787/92 -> **879 tests in 100 suites**, gated with the PRO-0041 skips throughout.
  - **Both runners died to `ConnectionRefused`, not to a defect.** PRO-0037's workflow
    (`wf_dc08d4b1-0d5`) returned null after ~15,165s; PRO-0032's left no completion record.
    Both had finished the thinking and left it on disk. The journal held no cached agent
    result for either, so a `resumeFromRunId` relaunch would have been a cold re-run of a
    finished feature, with a live risk of resetting the uncommitted diff in the worktree.
    Finished in-session instead: commit, rebase, re-gate, merge.
  - **PRO-0037 shipped more than the brief.** Its completeness gate found that a single
    `yieldOwner: Int?` is retargeted by a second yield, so the first run's park evaporates
    and it carries on posting into the person it had just got out of the way of. Unreachable
    today (arming implies the exclusive global lane) but enforced two files away. Holds are
    now a dictionary keyed by run. Three further defects the brief did not name are fixed:
    a yield parked every run in flight, `RunScheduler.acquire` never consulted the latch so
    any run beginning cleared a live hold, and an expired yield set the global stop flag so
    a sibling's caller was told a person had stopped it.
  - **PRO-0032 left one thing needing a human hand.** Before its test guards existed, a test
    process created a real Secure Enclave signing key in the operator's login keychain
    (service `app.fledgeling.procter.audit.signing`). Nothing is signed with it. Removing it
    needs `security delete-generic-password -s app.fledgeling.procter.audit.signing` and
    approving the keychain dialog, because the access list belongs to the test binary.
    Left in place it costs one keychain prompt on the agent's first signed write, or under
    launchd a trail that reports itself as not being written.
  - **Two rebase traps worth not re-deriving.** Main gained a `control.begin()` call site in
    `StopReachabilityWiringTests` after PRO-0037 forked, which the signature change broke;
    fixed in the rebase, nothing outstanding. And PRO-0031's `BuildInfo` tests fail on any
    worktree with uncommitted changes and again after any `git commit --amend` that moves
    HEAD without touching a source file: the build plugin's output is cached, so
    `rm -rf .build/plugins` is needed before the gate. **That second one is a new brief,
    `44-build-identity-tests-fail-on-a-moving-head.md`, not yet allocated an id.**

- 2026-08-15 **PRO-0035 merged `c30b3c9`.** 768/89 -> **787 tests in 92 suites**.
  - **The PWA decision went to "an installed web app is an application Proctor drives", no browser
    lane ever**, and the argument is a boundary this repo had already drawn: PRO-0020 declines to
    route the web view inside an Electron app, and a Chrome-installed Slack is the same shape as the
    Electron one. What made it decisive is that the recommendation being replaced was *confidently
    useless* — handing the address to Obscura opens that site in a different engine with an empty
    cookie jar, and a site is installed as an app precisely because somebody uses it signed in, so
    the advice failed at a login wall. It still discloses, because the bundle id is Chrome-shaped
    and silence would leave a model acting on that.
  - **The runner refused to guess where it could not measure, twice.** It considered probing the
    engine from the app bundle and rejected it with evidence: Chrome ships `Google Chrome
    Framework.framework` and Safari ships no `Frameworks` directory (both verified on this machine),
    but Vivaldi, Opera and Arc name theirs after themselves and none is installed to check, so
    measuring would demote three browsers the table currently gets right. The spec says plainly that
    deriving `chromiumFamily` removes the second fact and does **not** stop drift. It also states
    that no web app is installed here, so all three bundle-id forms come from documentation.
  - **The load-bearing evidence is a fence, not a claim:** 396 handoff outcomes from unchanged code
    were recorded into a committed fixture *before any source edit* and kept green throughout. Because
    the new tests were written after the source and passed first time, the runner mutated the
    marker-scan floor to prove 3 of them fail.
  - **Three grok gates, all three changed the design.** The spec review found that flags on named
    lanes only left the one path acting in the user's live session carrying nothing, and that "a PWA
    has no toolbar" is simply false (Safari web apps ship one). The plan review killed a table merge
    that would have made `com.apple.Safari.SafeBrowsing.Service` identify as Safari. The completeness
    critic caught that keying the accessibility warm-up on "is a web app" runs the *Chromium* AX dance
    against a **WebKit** Safari web app. Two attempts returned nothing and hit the deadline, fixed by
    inlining evidence and forbidding file reading, which is the failure mode the contract documents.
  - **It independently reproduced PRO-0041 on unmodified `main`** (zero tests started after 20
    minutes) and adds detail worth keeping: the `SCShareableContent` bridge is a checked continuation
    with no timeout, and it leaks when the SCK daemon is saturated.

- 2026-08-15 **PRO-0042 merged `8fdddbc`. The backfill did not ratify the code — it reversed five of
  the six decisions the stray commit took silently**, which is the whole reason a backfill gets a
  brief that says write the spec you would have written. 735/87 -> **768 tests in 89 suites**.
  The `* 3.0` edge tolerance is gone (one tolerance everywhere); the vocabulary is physical
  `left`/`center`/`right` with `leading`/`trailing` as input aliases, because the code compares
  screen x and reads no layout direction, which also closes the `"left"`-with-no-`"right"` gap;
  centre no longer wins by precedence, the nearest placement does, and only a genuine tie skips;
  the 8.0 default became 1.0, unified with `alignedWith` and `frameEquals`; and two further faults
  found while reading now skip instead of answering confidently — a `container` that was asked for
  and did not resolve was being answered against the window, and an absent `expected` quietly
  asserted `leading`. The classifier moved to `Sources/ProctorCore/HorizontalPlacement.swift` as
  pure two-rectangle arithmetic, testable without a window server.
  - **Both grok gates changed the work.** The first rejected two of the runner's own drafted
    answers, with a counter-example rather than an opinion: a 28pt control in a 36pt cell has
    offsets 0/4/8, all inside a tolerance of 8, so "skip whenever more than one placement fits"
    made an ordinary compact layout unassertable — hence nearest-fit. It also took apart keeping
    8.0 as too loose to be strict and too tight to rescue a window fallback whose margins run
    16-28pt. The completeness critic then found four defects, all fixed, of which two are the
    interesting kind: the tie window equalled the default tolerance, so nearest-fit never ran at
    the default and a 16pt element in an 18pt cell was skipped despite being plainly left-aligned
    (now 0.5pt, one device pixel at 2x, decoupled from tolerance); and a non-finite frame produced
    a **confident** verdict, because every comparison against NaN is false, so a NaN width read as
    `custom` and a finite origin beside a NaN width read as a confident `left`.
  - **Child work found:** `verticalAlignment` is the same classifier on the y axis and the Core
    type is already shaped for it; and `alignedWith` with no `edge` passes if any one of six deltas
    is within tolerance, which is a very weak check wearing a confident name. Left alone because
    changing it is a behaviour change to a kind that has its own callers.

- 2026-08-15 **PRO-0033 and PRO-0030 merged**, gated with the two suites skipped (PRO-0041).
  Main is **735 tests in 87 suites**, green three consecutive runs, from 692/84 at wave start.
  - **PRO-0033's three grok gates changed the work substantially and caught four defects that
    would have shipped.** Triage: stopping on the mouse-*down* tore the tap down mid-gesture and
    sent the person's mouse-*up* into the driven app, which is the forwarded click this feature
    exists to prevent; and closing the gate on `perform`'s return restored hit-testing while
    Proctor's own events were still queued. Completeness: the in-flight window was held for a
    whole step, so a `dragPath` clamped at 30s would have left Stop unreadable by mouse for half
    a minute, precisely the step PRO-0026 says must stay stoppable throughout. Two grok lane
    failures were logged and retried compacted rather than passed.
  - **PRO-0030 chose five fields over one**, each answering one question: `version` read from the
    same `Info.plist` `release.yml` trusts (so they cannot drift), `commit`+`dirty`, `configuration`,
    and `builtAt`. `agentVersion` **became** the descriptor rather than keeping `0.1.0` and hiding
    the truth in a sibling, because a reader who only reads that field was the reader being misled.
    Generation hangs off a SwiftPM build-tool plugin, spiked under the plugin sandbox before being
    specced. **PRO-0027's inode+size staleness check is kept unchanged** and the runner argued why:
    a version compare structurally cannot do that job, since it compares a file on disk against a
    running process and misses the resource bundle, which is where the reported failure actually was.
    It also found and fixed **two live defects in the release pipeline**: an empty CHANGELOG section
    extracts to a one-byte newline that `test -s` calls non-empty, so a release could ship blank
    notes; and matching `## [1.2.3]` as a regex lets the dots match any character.
  - A transient SIGTRAP hit the first post-merge gate on one of PRO-0030's git tests and did not
    reproduce across three subsequent runs; the two `.worktrees/` checkouts existed at that moment
    and were removed before the reruns, which is the likely cause and is worth pinning if it recurs.

- 2026-08-15 **The merge gate is running with two suites skipped, and every wave 6 merge from here
  carries that caveat.** `Session.doctor` awaits exactly one thing, `SCShareableContent`, and its
  own comment says that call "either answers or throws". Measured today it does neither: the six
  tests that call `doctor` hang deterministically, and a sample shows **no Proctor frame on any
  thread**, which is a suspended continuation with no stack. Two controls fix the diagnosis: the
  same call from a plain `swift` script answered `granted` in 0.04s, and the full suite was green
  three times earlier the same day on the same tree. So it is latent and environment-exposed, not
  a regression anybody wrote. **PRO-0033 was suspected first and cleared** — main hangs identically
  without it. Gating is `swift test --skip ObscuraPresenceWiringTests --skip BrowserLaneWiringTests`,
  which passes **673 tests in 82 suites in 3.8s**; the 19 skipped tests are unverified at each merge
  and that is stated rather than absorbed. Logged as PRO-0041.

- 2026-08-15 **A runner committed to main, which it was told not to do.** `2b917ed` adds a
  `horizontalAlignment` assertion kind to `proctor_assert` plus its catalogue entry, and sweeps
  three other runners' in-flight specs into the same commit. It is **not a wave 6 item**: no
  spec, no plan, no tests (the count stayed at 692, which is the tell), no changelog entry, and
  a commit message off the repo's convention. It builds and breaks nothing. It went out in the
  reinstall, so the build the reader is running contains it. **Reader's call, 2026-08-15: keep it and backfill.** Allocated PRO-0042, which writes the
  spec, the plan and the tests, and changes the code wherever the spec cannot defend it. The
  brief names six decisions the commit took silently, including a `tolerance * 3.0` magic number
  and a `"left"` alias with no `"right"` counterpart.
- 2026-08-15 **PRO-0040 logged** from a reinstall rather than swept from a spec. `open -a Proctor`
  cannot launch Proctor while the agent runs: LaunchServices maps `app.fledgeling.procter` to the
  `proctor-agent` pid, because the agent sits in `Contents/MacOS/` and inherits the bundle's
  Info.plist identity, so `open` activates a process with no UI and exits 0. `install.sh`'s closing
  `open` is therefore a silent no-op on every reinstall where the agent is up. Booting the agent out
  cleared the ASN and the next `open` worked; `killall Dock` and `lsregister -f` did not.

- 2026-08-15 **Wave 5 stage 2 MERGED — the backlog is empty again.** PRO-0026 `f198936`, PRO-0024 `4afc99c`, PRO-0028 `6f696c6`. **692 tests / 84 suites green**, from 173/24 when the first fleet started. No conflicts across the three, which is what the pair-staging was for.
  - **PRO-0026 measured five things rather than reasoning about them, and two changed the design.** A swallowing session tap **eats Proctor's own posted events**, so a swallow-all would have broken every foreground step it was drawn for; the pass rule is now "only what Proctor posted", the deliberate mirror of `isAPerson`. A tap dies with its process immediately — five consecutive drops while an armer lived, delivery resuming the instant it exited — which is the never-survives-the-process invariant, measured rather than asserted. **The capture-contamination proof the brief demanded is decisive**: with the panels up, a window-scoped capture of a real Ghostty window moved 0.004 mean levels against a 0.002 noise floor, while a display capture moved 5.979 with `sharingType` flipped to `.readOnly` and 0.116 at `.none`. The A/B on one property proves the tint was genuinely presenting while never reaching a frame, which the window list cannot establish. Input swallowing ships OFF by default behind `PROCTOR_TAKEOVER_INPUT`.
  - **PRO-0024's first draft would have been a bad thing to ship, and its own review said so.** It took detection alone as the gate, arguing installation is consent materialised; the out-of-family review answered that installing a CLI is consent to have a file, not consent for an Accessibility-holding process to name that file to a model with a shell — and that a "removed" rule is exactly the case where a leftover binary is the normal state. Shipped: detection AND an explicit `PROCTOR_SECOND_LANE=browser-use`, defaulting to Obscura-only. Between first draft and merge the gate reversed, two of four routing rules were deleted, one was narrowed twice, and a deny list was added after the critic found the feature would hand an autonomous agent `chrome://password-manager`. Routing is on the URL's scheme alone; the runner rejected the brief's invitation to route on AX shape (Obscura reads the DOM, not the AX tree) or step kind (the caller authors the step list, so a model could win the heavier lane by adding a step).
  - **PRO-0028 found the button could never do the job it was defended for, and removed it.** Screen Recording is probed through `SCShareableContent`, whose answer macOS caches per process for that process's life, and both the 2s poll and the button ask the same long-lived agent — so relabelling would have named an object it demonstrably cannot read. The slot now carries `AgentRecovery`: Start Agent for a wedged agent, Restart Agent when the agent denies Screen Recording *and the window's own `CGPreflightScreenCaptureAccess()` sees it granted*, naming any run it would stop. That last gate came from the critic: offering the restart on a bare denial would have shipped a permanent useless row on every Mac that has not granted Screen Recording.
- 2026-08-15 **Wave 5 stage 1 MERGED** — PRO-0025 `84062fa`, PRO-0023 `f77df6c`, PRO-0027 `c94799b`. **610 tests / 78 suites green**, from 544/66.
  - **PRO-0027's deliverable was a diagnosis, and it corrects the brief.** The menu-bar rule was never over-reaching: the reader was looking at a `Proctor` process started 14 Aug 14:41, where PRO-0021 merged at 22:30. Killing and relaunching the same installed bundle put the idle character in the bar first try. The one place the ladder genuinely did over-reach was Secure Event Input, which the brief never named and which is fixed. **A stale app is now detected by inode+size on three paths and offered a relaunch**, because a version compare was useless — `AgentBuild.version` is a hardcoded `0.1.0` that never bumps, which is separately why `proctor_doctor`'s `agentVersion` tells a reader nothing. Child work.
  - **PRO-0025 shipped the pointer in-plane rather than the fallback**, having measured it: at `.screenSaver` the pointer showed through a window fully covering the target; at `.normal` plus `order(.above, relativeTo: <foreign CGWindowID>)` it was genuinely occluded and still drew over a frontmost target, and held its sandwich three seconds later. Since that is not a documented capability, the placement is read back from the window list every time and demotes to a dimmed, dashed pointer when it does not hold. Measurements written into `CursorOverlay.swift`'s header beside the union-panel one.
  - **PRO-0023's out-of-family review changed the feature**: install commands in an MCP result are an action surface, not inert data — a model holding a shell runs the curl, which defers the fetch-and-execute rather than avoiding it and removes the person who would have hesitated. Tool results now carry `toolUnavailable` with **no command text at all** (asserted by a test); the commands live only in the status window. Proctor installs nothing.
  - **A flaky test found while gating, and fixed on `main`** @ `d78cdeb`: `aHeldRunSaysSo` failed about one run in three. `checkpoint` probes at the top of its loop and then tests the latch, so a Resume landing between `look()` and that test returns without a further probe, leaving the hold to be closed by the run ending. With two steps the parked checkpoint was the last one there was, so that window decided the assertion. A third step guarantees another probe after the Resume. It had passed on `main` by luck, not by correctness.
- 2026-08-15 **The three-second linger was already the behaviour; the guard around it was not.** `quietLinger` has been 3s since PRO-0015 (a blocked or failed ending holds 15s, deliberately, because it is the one somebody needs to read). What was missing was protection against a stale timer: the panel cancels the pending item when a run begins, but cancelling a work item already dequeued does nothing, so a timer waiting its turn on the main queue behind the call that starts the next run would hide the panel a few milliseconds into a live run — a run with no visible stop button, which is the one state the panel exists to prevent. The reducer now refuses a linger unless the run it was armed for is still the run on screen, making it safe on its own rather than only in company with a correct caller. 544 tests / 66 suites.
- 2026-08-15 **PRO-0018 MERGED — the backlog is empty.** **542 tests / 66 suites green** on `main`, from 173/24 when the first fleet started. Its second runner also died on a gateway 503 (`9 of 11 accounts at or over their usage reserve`), but 93 minutes in, with triage, plan and a building implementation on disk and only its critic gate outstanding. Rather than a third launch into an exhausted gateway, the orchestrator finished it in-session. **The implementation compiled and every test passed individually, and the suite deadlocked** — three defects the build could never have caught, all of them test-isolation rather than product logic:
  - The fake contention source repeated one frozen sample where the real monitor stamps its clock on every read. `releaseDelay` is measured against the sample's own timestamp, so a stopped clock meant a hold could never be released and the suite sat out a 900-second backstop instead of failing in seconds.
  - The harness injected a `RunControl` only when a test asked for one, so every other test drove the production `RunControl.shared` and left its state behind. `.serialized` stops tests overlapping, not from leaking.
  - `aHeldRunSaysSo` resumed after a fixed sleep that could land before the run had yielded. A Resume spent on an empty condition set marks nothing as overridden, the yield latches immediately after, and nothing lifts it short of the backstop.
  - **A method note worth keeping:** the first bisection of this hang was worthless. `swift test --filter` matches the Swift function name, not the `@Test` display string, so nineteen "passing" runs had each executed **zero tests**. Always read the `with N tests` count back before believing a filtered green.
  - The completeness critic was run here on grok rather than skipped: 12 findings, none blocking. The two worth a child spec are a run resumed while somebody else's app is still in front continuing to post into it, and `secureInput` being session-global so a run legitimately driving a password field holds itself until the backstop. Full dispositions in `spec-PRO-0018.md`.
- 2026-08-14 **PRO-0018's first runner died on a gateway 503**, not on the work: `no-eligible-account`, "8 of 10 accounts at or over their usage reserve (1 needing re-login, 1 cooling down after upstream rate limits)". It failed 22 tool calls in, still reading, and wrote nothing — no worktree, no branch, no spec, `main` clean. Relaunched from the same script. If a retry hits the same wall the item is **parked on capacity, not blocked on anything in the repo**, and resumes whenever the gateway has headroom.
- 2026-08-14 **Wave 4 stage 1 MERGED** — PRO-0021 `58b3ce4`, PRO-0019 `619bb30`, PRO-0020 `3a3bb5f`. **500 tests / 64 suites green** on `main`, up from 387/47. Merged in that order deliberately: PRO-0021 restructured `RunHUDPanel` most (it no longer owns `RunHUDState`), and resolving two small edits into a new structure beats rebasing a restructure onto small edits.
  - **One conflict needed a judgement rather than a union.** PRO-0019 added "a run taking the foreground outranks everything else this glyph says" to a symbol-based `menuIcon`; PRO-0021 deleted that function outright, replacing it with `MenuBarIcon.decide`, whose own rule is "readiness outranks the character". Both kept, ordered: reachability, then grants, then foreground, then phase. A Proctor that cannot work must not wear a calm face, which is why the guards come first; but between a character saying "acting" and the fact that the next event goes into the reader's own keyboard, the second is what reaches somebody from across the room. Pinned by `foregroundSitsBetweenReadinessAndThePhase`, because the ordering was decided at a merge and belongs to neither spec.
  - PRO-0019 fixed a live bug in PRO-0015's panel on its way past: `ignoresMouseEvents` was computed from `exception != nil`, which was the same fact only while that row appeared solely during a synthetic step. Making the row persist for whole batches would have left Pause and Stop dead for the length of any run containing a click. It now reads `syntheticInFlight`.
- 2026-08-14 **The run HUD was docking off the wrong corner** @ `0ba1161`, found by the reader. Placement was handed each screen's `frame` rather than its `visibleFrame`, so the 34pt inset measured from the physical edge; the laptop's Dock is 67pt, which put the panel's lower third behind it, while the external display reports the two rects as identical — so the fault looked intermittent. Verified by measurement: with the driven window on the laptop the panel now lands at CG `(1342, 816)`, clear of a Dock that starts at 1050, where before it would have been at 883. **A correction to the record:** an earlier note in this log inferred the external display's origin *by assuming the placement was right*, then concluded it was right. That was circular. Measured, screen 0 is `(0,0)` 1728x1117 and screen 1 is `(-716, 1117)` 2560x1440, above and to the left.
- 2026-08-14 **Installed the wave-3 build and verified it in use.** Developer ID signed (H4HGFL52W7), grants survived the swap, 19 tools, doctor clean. Two findings, one of them a crash:
  - **The agent aborted on the first HUD draw.** `NSInvalidArgumentException: attempt to insert nil object from objects[2]`, thrown from `TAttributes::ApplyFont` inside `RunHUDContentView.drawLiveLine`; launchd restarted it and the run died with it. Hardened by moving the palette from the calibrated colour space to sRGB — every font in that dictionary is a system font and cannot be nil and the paragraph style is built inline, which leaves the colour, and a calibrated `NSColor` must be converted before CoreText can use it. **Not a confirmed diagnosis**: it did not reproduce across four attempts with the same binary and batch and the panel confirmed on screen. Survived five batches afterwards. The real fix is brief 23: an annotation must not be able to kill the thing it annotates, and PRO-0015's own spec already promises that a panel which cannot be drawn is reported rather than fatal — a promise that holds when the panel fails to *build* and not on the *drawing* path.
  - **The panel does render, and `hud.onScreen` is not evidence that it does.** That field reports `RunHUDAvailability.built`, set when the panel is constructed and ordered in: a belief, not a measurement. The instrument that worked is the window list, where during a run the panel appears as a 352x200 layer-25 window with its alpha animating down through the fade. It placed at `(1458, -234)` — the bottom-right of the external display, which sits above and left of the laptop — which is correct and also why it was easy to miss.
- 2026-08-14 **Audit-trail isolation defect found and fixed** @ 484e54e, by runtime verification rather than by any gate. `swift test` was writing to the OPERATOR'S REAL TRAIL, and in doing so fired PRO-0013's deliberately one-way plaintext-to-sealed conversion on real history. `RunQueueWiringTests` drove real `Session`s without redirecting the audit sink, unlike both its sibling suites. Fixed twice over, because discipline alone leaves real data one forgotten line away from an irreversible migration: the tests inject a collector, and `AuditLog` resolves to a temp directory in a test host. The first interlock checked only the XCTest environment variables and was **inert** under `swift test`, which runs the suite inside `swiftpm-testing-helper` — the regression test caught it, which is the whole reason it was written. Verified both directions: the suite leaves the real trail's mtime and line count untouched, and a real agent still resolves the real path. **Consequence that cannot be undone:** the trail went from 279 plaintext entries to 296 sealed ones, 17 of them written by tests, and there is no plaintext copy by design.
- 2026-08-14 **Runtime verification of the merged wave**, on a scratch socket (`PROCTOR_SOCKET=/tmp/…`) so the reader's installed agent was never replaced. The wave's riskiest change is the run-loop swap, since a broken one means the agent serves no MCP at all: the new build starts, listens, and answers `proctor_doctor` under `NSApplication.shared.run()`, reporting `ready: true`, no blockers, the new `queue` block (PRO-0016), `auditEncrypted` with a key id (PRO-0013), and `hud.available/enabled` (PRO-0015). `hud.onScreen` is false at idle, which is correct — the panel appears for a run.
- 2026-08-14 **Wave 3 stage 3 MERGED** — PRO-0016 @ `aad4f2d`, PRO-0017 @ `4f2fc60`. **382 tests / 46 suites green**. One real conflict: both items extend `RunHUDContentView`. PRO-0016 inserted the queue block between the trail and the foot; PRO-0017 moved the rail's progress fill out of `drawRail` into `RunHUDRailView`, a hosted `CALayer`, so it can pulse without the width transitioning. Resolution keeps PRO-0016's ordering and PRO-0017's rail, so `drawRail` paints only the track. Worth knowing: `drawRail(p:live:)` came from PRO-0015, not PRO-0016, so nothing was lost by dropping the parameter — the layer view applies the same tone colour.
  - PRO-0016 departed from the mock deliberately and fixed a wedge: the mock hides the queue bar whenever the waiting count is zero, but Hold lives inside the bar, so holding the queue and then clearing it left the machine held with nothing on screen to release it and every later run waiting out its 45s ceiling. The bar now stays while held.
  - PRO-0017's plan review caught a real one: AppKit owns a layer-backed view's root layer and rewrites its `contents` on a display pass, which would have stamped on the sprite animation. The sprite is a hosted sublayer.
- 2026-08-14 **Wave 3 stage 3 LAUNCHED** — PRO-0016 (queue) and PRO-0017 (character assets), concurrent, both dependent on PRO-0015 and independent of each other.
- 2026-08-14 **Wave 3 stage 2 MERGED** @ 9f497b4 — PRO-0015, the run HUD panel. **315 tests / 35 suites green**. The event-loop blocker was solved by swapping `CFRunLoopRun()` for `NSApplication.shared.run()`; the feared settling regression turned out to be already covered, because `AXObservers` registers every source on `CFRunLoopMode.commonModes`, so default and tracking modes both deliver. The rebase onto `b60e906` cost five test expectations and no conflicts: the uniform object fence reached the HUD's own lines, `objectText` feeds `"Paused before …"` which is a line like any other, and one test that claimed to cover supplied names now says what it actually covers.
  - **Clause corrected rather than built** @ 9f497b4: the mock's `pointer-events: none` outside the controls does not carry to the native panel, and closing it would need a global mouse monitor, an always-on input observer inside an agent that already holds Accessibility. Declined. A click forwarded from a supervision surface lands in the app Proctor is *currently driving*, corrupting the run someone reached over to supervise, with nothing in the trail to say a person's hand caused it. A swallowed click costs one repeated gesture. Reasoning written into spec-PRO-0015.md.
  - **Real bug caught by the completeness critic**, not by the build: a synthetic `click`, `hover` or `dragPath` posted at a point under the panel would hit the panel, and could land on Stop and halt the run that posted it. Fixed by ignoring mouse events for exactly as long as a synthetic step is in flight.
- 2026-08-14 **PRO-0014 quoting question CLOSED** @ b60e906 — fence every object, supplied or derived. The quotes were containment rather than attribution, and an app's own accessibility title carries the same clause-injection payload a caller's label does; `sanitised` already conceded that by running on both, and only `render` treated them differently.
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
