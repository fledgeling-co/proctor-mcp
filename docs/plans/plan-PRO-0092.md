# Implementation plan — PRO-0092: ProctorAgent's mutants mostly survive

**Spec:** `docs/specs/spec-PRO-0092.md`
**Brief:** `docs/features-to-triage/85-proctoragents-mutants-mostly-survive.md`
**Tier:** Standard
**Integration branch:** `main` · **Work branch:** `ai/pro-0092`

## The thirteen, resolved against source

Every row below is one survivor of `mutation-agent.json`, seed 20260821, minus the five
`MutationSurvivorTests` already kills and the one recorded equivalent. The line is the line the
sample recorded; where the file has moved since, the source is read at `123fa02` and the current
location named beside it.

| # | Site (as sampled) | Mutant | Class | Disposition |
|---|---|---|---|---|
| 1 | `AX/AXEngineImpl.swift:33` `guard includeWindowless \|\| app.activationPolicy == .regular` | `\|\|`→`&&` | no seam | seam + kill |
| 2 | `Dispatch.swift:381` `includeTiles: args.bool("includeTiles", false)` | `false`→`true` | no seam | seam + kill |
| 3 | `Overlay/TakeoverOverlay.swift:771` `plateHeight = … + 44` | `44`→`45` | no seam | no-independent-oracle |
| 4 | `Session/Session.swift:92` `var includeInvisible: Bool = false` | `false`→`true` | uncovered | kill (no new seam) |
| 5 | `Session/SessionFlow.swift:493` `timeoutMs: 3000` | `3000`→`3001` | no seam | no-independent-oracle |
| 6 | `Capture/MarkRenderer.swift:141` `padX = max(3, scale * 2)` | `2`→`3` | no seam | no-independent-oracle |
| 7 | `Session/SessionKill.swift:26` `!candidates.contains(where: { $0.pid == pid })` | `==`→`!=` | no seam | seam + kill |
| 8 | `Dispatch.swift:394` `presentation: args.bool("presentation", true)` | `true`→`false` | no seam | seam + kill |
| 9 | `Overlay/RunHUDPanel.swift:653` `override var canBecomeMain: Bool { false }` | `false`→`true` | no seam | seam + kill |
| 10 | `AX/CGWindowCorrelation.swift:59` `matches.count == 1 ? matches[0].number : nil` | `0`→`1` | uncovered | kill (seam already exists) |
| 11 | `Overlay/RunHUDContentView.swift:97` `ink3: hex(17, 18, 21, 0.36)` | `17`→`18` | uncovered | kill (structural invariant) |
| 12 | `Overlay/TakeoverOverlay.swift:363` `if type == .tapDisabledByTimeout \|\| …` | `==`→`!=` | no seam | seam + kill |
| 13 | `Session/AuditKeyStore.swift:47` `appendingPathComponent("audit.pub", isDirectory: false)` | `false`→`true` | no seam | seam + kill |

Ten killed, three recorded — count the table above: seven `seam + kill` plus three other kills. The
three are argued in `REPORT.md` and in the spec's progress section,
not asserted here.

## Why the three are not chased

`3000`→`3001` is one millisecond on a capture timeout; `44`→`45` is one point of plate padding
below a text run that both values still clear; `scale * 2`→`scale * 3` changes the badge padding at
scale 2 and not at scale 1, where `max(3, …)` binds either way. Each of the three genuinely changes
behaviour, so none is `equivalent`. Each is killable only by a test that writes the same constant a
second time. PRO-0080's five kills each stood on an oracle the source does not supply — Carbon's own
`kVK_ANSI_*`, a mean derived from the pixel gap, the hex alphabet a UUID is drawn from — and that is
the standard this item holds to. A test that copies a literal raises the score and lowers what the
suite knows.

Survivor 11 looks like the same shape and is not, which is why it is killed rather than recorded.
The light palette's four ink tones are one base colour at four alphas. `17`→`18` in `ink3` breaks
that invariant, and the invariant is checkable without naming 17 at all.

## The seams, and what each one is

Each is an extraction: a decision or a value lifted out of a method that needs a window server, a
Keychain or a live `Session`, with the production call site rewritten to call it. Production
behaviour is unchanged by construction, which is the property that makes the extraction safe.

1. **`AXEngineImpl.listApps` running-app seam.** `listApps` reads `NSWorkspace.shared.runningApplications`
   directly. Add a `RunningApp` value and an injectable lister, defaulted to the live one, in the
   `GuestProvider` shape: `init(runningApps: @escaping @Sendable () -> [RunningApp] = AXEngineImpl.liveRunningApps)`.
   The kill: `includeWindowless: true` must return an accessory app.
2. **`Dispatch` boolean-default agreement.** Every optional boolean argument's schema in
   `ToolCatalogue` states its default in prose, and `Dispatch.swift` writes the same default as a
   literal at each of 34 call sites. The seam is `DispatchDefaults`, a parser over both, so the two
   statements can be compared at runtime. The kill covers survivors 2 and 8 and the other 32 sites
   with them.
3. **`SessionKill` candidate seam.** The bare-pid synthesis is inline in a method that enumerates
   `NSWorkspace`. Extract `ProcessCandidates.includingBarePid(_:query:)` as a pure static.
4. **`RunHUDPanel`'s panel class.** `HUDPanel` is `private`, so nothing can ask it anything. Make it
   internal and leave both overrides as they are.
5. **`TakeoverOverlay` tap-disabled predicate.** Extract `InputHold.isTapDisabledNotice(_:)`.
6. **`AuditKeyStore` public-key path.** Extract `AuditKeyStore.publicKeyURL(in:)` as a pure static
   over a directory, and have the instance property call it with `AuditLog.directory`.

Survivors 4, 10 and 11 need no seam. `Session.SnapshotOptions` is constructible,
`CGWindowIndex.correlate(frame:title:in:)` already takes its records as a parameter, and
`RunHUDPalette.light` is a static a test can read. They were never `no seam`; they were untested.

## The instrument change, and the arming that puts it in scope

`mutate_swift.py` scores a timeout as a kill. Two of PRO-0080's five kills were 600.0s under a load
average of 271, and that is the direction that flatters the suite: starvation turns a survivor into
a false kill and can never turn a kill into a false survivor.

Add a fourth verdict, `TIMEOUT`, counted apart from `killed` and excluded from the survival-rate
denominator, with the elapsed seconds and the bound printed beside it. In scope only if armed:
`scripts/campaign/mutation_timeout_arm.py` drives the scoring decision with `why="timeout"` through
both the old expression and the new one and shows the old returning `killed` where the new returns
`TIMEOUT`. A change to an instrument that cannot be shown to report differently has measured nothing.

## The measurement

1. Sample the machine three times about twenty seconds apart before the run — `pressure.py` and
   `thermal.py`, both recorded verbatim.
2. `mutate_swift.py --targets <all 84 ProctorAgent files> --count 24 --seed <fresh>` writing to
   `docs/test-campaign/evidence/mutation-agent-pro0092.json`.
3. Sample the machine the same way at the end, and say which mutants were scored after any turn.
4. Report the rate with its denominator, and every mutant at or near the bound listed apart.

The seed is fresh rather than 20260821 because re-running the seed whose survivors were the targets
measures the tests rather than the package. The targets and the count are held identical so the two
samples are comparable.

## Order of work

1. Spec and plan committed by explicit path.
2. The six seams, one commit each, with the production call site rewritten in the same commit.
3. `MutationSurvivorTests` extended, or a sibling suite added, with one test per killed survivor.
4. Arm every new test: re-apply the mutant, confirm it landed, run the named test filtered, watch it
   red, revert.
5. The runner's timeout verdict and its arming.
6. `./scripts/test.sh` through the governor, green, count recorded.
7. The fresh mutation sample, with machine readings at both ends.
8. Registry rows: requirements, cases with their oracle rung, the DEF-033 update.
9. Gates, then out-of-family review by gemini.

## Risks

- **The machine.** The sample was held for a quiet machine and the machine is not reliably quiet.
  A run under contention inflates the kill rate. Any mutant at or near the bound is reported apart
  regardless of how the run went, and the readings are published at both ends.
- **The tree.** `mutate_swift.py` edits `Sources/` in place and refuses a dirty tree. Nothing else
  may write to the worktree while it runs, and no review lane may be pointed at it.
- **Commits.** Explicit paths only. A blanket add during a live harness swept a mutated source file
  into a real commit elsewhere tonight.

## What this plan does not do

It does not chase the equivalent mutant, it does not raise the mutation timeout, and it does not
copy the re-measured figure into `.warrant/suite-health.json`, where `mutation_measured: false` is
correct and means warrant's own assay has not run.
