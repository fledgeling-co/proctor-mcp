# ORCHESTRATOR — Proctor remaining-work plan & ledger

**Status:** **WAVE 3 COMPLETE.** All 17 items merged; nothing open in the pipeline.
**Updated:** 2026-08-14 — wave 1+2 MERGED (10 features), wave 3 MERGED (7 features). **382 tests / 46 suites green on `main` @ 484e54e**, up from 173/24 at the start of the wave. No worktrees, no `ai/*` branches, clean tree, nothing pushed.

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
| PRO-0018 | Yield when a person takes the machine back | `19-yield-when-a-person-takes-the-machine.md` | PRO-0019 ✓ | 2 | **RUNNING** |
| PRO-0022 | A drawing fault must not kill the agent | `23-drawing-fault-must-not-kill-the-agent.md` | — | — | **MERGED** `b4a29e5` |

**Why PRO-0018 waits on PRO-0019.** Both answer "is this batch going to take the foreground";
0019 computes and discloses it, 0018 acts on it. Building them concurrently means two answers to
one question, and the briefs already say to triage them together. 0018 also needs 0019's decision
about whether a batch declares its synthetic content up front or at the first such step.

**Three concurrent runners**, the cap this repo has used since wave 1. Runners stop before merge;
the orchestrator serialises every merge to local `main` and never pushes.

## Event log (append-only, newest first)
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
