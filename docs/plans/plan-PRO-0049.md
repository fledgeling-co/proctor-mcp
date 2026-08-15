# Implementation plan — PRO-0049: Run Maestro flows as Proctor flows

**Spec:** `docs/specs/spec-PRO-0049.md`
**Branch:** `ai/pro-0049` · **Worktree:** `.worktrees/PRO-0049`
**Size tier:** Standard. Two new source files, three touched, one new test file group. No UI, no
schema migration, no change to any existing behaviour.

## Shape

Mirrors PRO-0048 exactly: a pure decision layer in `ProctorCore` and an impure runner in
`ProctorAgent/Session`, so the verdict ladder, the score basis and the flow scan are all provable
without Maestro, without Xcode and without a booted device.

```
ProctorCore/MaestroRun.swift        pure   record parsing · hash cells · verdict · flow scan · argv
ProctorAgent/Session/SessionMaestro.swift  impure  process · debug dir · gate · queue · audit
ProctorCore/ToolCatalogue.swift     touched  the "flow" action on proctor_ios
ProctorAgent/Dispatch.swift         touched  accept the action and its arguments
ProctorCore/ReplayGate.swift        touched  two AuditTool names
```

Nothing else moves. `ActuationBackend`, `RecordedFlow`, `FlowStore`, `SessionFlow` and
`StabilityScore` are all read and none is modified — `StabilityScore.fold` is called as it stands.

## 1 · `Sources/ProctorCore/MaestroRun.swift` (new, pure)

**`MaestroCommand`** — one entry from `commands-*.json`, decoded.
`type: String` (the single key of the `command` object), `parameters: JSONValue` (its body),
`status: String` (carried through verbatim, not remapped), `sequenceNumber: Int`,
`durationMs: Int`, `timestampMs: Double`, `errorMessage: String?`, `hasHierarchy: Bool`.

**`MaestroRecord.parse(_ data: Data) throws -> [MaestroCommand]`** — decodes the array and **sorts by
`sequenceNumber`**. The measured array order is not sequence order; sorting is not cosmetic. A record
that decodes to zero entries is an error, not an empty run, because "produced nothing" is the driver
failure this lane turns on.

**`MaestroRecord.injectedTypes: Set<String>`** = `["defineVariablesCommand", "applyConfigurationCommand"]`,
with the measurement in the doc comment. Used only to mark entries, never to drop them: they are in
the status vector because Maestro executed them and they were stable across all five measured runs.

**`MaestroRecord.locate(in directory: String) -> [String]`** — the glob rule. Returns candidate paths
matching `commands-*.json` at any depth under the directory, newest first. Constructing the name is
what breaks: the same flow produced `commands-(settings).json` and `commands-(settings.yaml).json` on
different invocations. Pure over a supplied file listing so it is testable; the agent hands it the
listing.

**`MaestroRun.cell(for: MaestroCommand) -> String`** —
`Canonical.hash(type + "|" + Canonical.canonicalJSON(parameters) + "|" + status)`.
Duration, timestamp and error text are absent by construction, not by filtering, so a later edit
cannot leak one in. Doc comment carries the 634/91/88/96/91 ms measurement as the reason.

**`MaestroVerdict`** — `flowPassed | flowFailed | appGone | driverFailed | refused`, with
`isAppFault` and `isDriverFault` accessors and a `decide(_:) -> (verdict, note)` over a
`MaestroEvidence` value:

```
MaestroEvidence { exitCode, timedOut, recordFound: Bool, commands: [MaestroCommand],
                  targetRunningBefore: Bool?, targetRunningAfter: Bool?, failureReason: String? }
```

Order of the ladder, and it matters: **`recordFound == false` → `driverFailed` first**, before exit
code is consulted at all, because exit 1 covers an assertion failure, an absent device and a bad
YAML alike. Then `targetRunningBefore == true && targetRunningAfter == false` with any `FAILED`
command → `appGone`. Then any `FAILED` → `flowFailed`. Else `flowPassed`. Each note states what the
verdict does and does not claim, in the register PRO-0048 established.

**`MaestroFlowScan`** — the conservative textual scan of §8.
`scan(text:) -> Declaration { appIds: Set<String>, includes: [String], unresolved: [Unresolved] }`
where `Unresolved` is `.script(String)`, `.interpolatedAppId(String)`, `.unreadableInclude(String)`.
Reads `appId:`, `launchApp:` (bare and with an `appId:` child), `runFlow:`, `runScript:` and
`evalScript:`. An app id containing `${` is `.interpolatedAppId`. Deliberately over-refuses: the doc
comment says it is a scan and not a parser, and names under-detection as the direction that matters.
`resolve(root:read:)` walks `runFlow` includes transitively with `maxDepth = 5` and a visited set,
turning an unreadable include into `.unreadableInclude` rather than throwing.

**`MaestroGate.decide(declaration:policy:hasValidToken:) -> PolicyDecision`** — every declared app id
through `IOSPolicy.decide` under the `ios:` qualified key; the first refusal wins and names the app.
Then: **if `!policy.allow.isEmpty` and `!unresolved.isEmpty`, refuse**, naming the construct. With no
allow list, allow and return the unresolved list for the caller to report.

**`MaestroInvocation.arguments(flowPath:udid:debugDirectory:)`** — the argv, in one place so a test
can assert what is and is not in it: `["--device", udid, "test", flowPath, "--debug-output", dir,
"--flatten-debug-output", "--no-ansi"]`. `--flatten-debug-output` because the measured default nests
under `.maestro/tests/<timestamp>/`. **Never `--analyze`**, and a test asserts its absence.

## 2 · `Sources/ProctorAgent/Session/SessionMaestro.swift` (new, impure)

`Session.maestroFlow(path:device:runs:pixelEvidence:timeoutMs:) async throws -> JSONValue`.

Order of operations, each step failing closed:

1. **Presence** — `tools.maestro.presence()`. Absent → `AgentError(.notImplemented)` naming the
   `proctor_doctor` toolchain row and `MaestroTool.docs`, carrying **no command text**. Never runs
   `maestro --version` (4.67 s, measured).
2. **Jail** — the flow path through the existing `enforceFSJail(path:)`.
3. **Read and scan** — read the flow file, `MaestroFlowScan.resolve`, `MaestroGate.decide`. A refusal
   is audited under `AuditTool.maestroFlow` with outcome `refused` before throwing.
4. **Device** — resolve through the same private helper the other actions use, and require booted,
   with the same refusal text shape.
5. **Busy guard** — take `iosBusyDevices` for the *whole sweep*, not per repeat, for the reason
   `proctor_stability` takes its lanes once: another call driving the device mid-sweep is both the
   interleaving this prevents and a guaranteed false divergence. No `RunQueue` lane is taken, for
   PRO-0048's reason — nothing here posts an event into the Mac's input system or raises a window.
6. **Per repeat** — Proctor's own liveness + device frame before; run the process; read the debug
   directory; liveness + frame after; build evidence; decide; audit one record per repeat with the
   declared app ids in `reason`, the flow body as `script: Redaction(of:)` and the flow's absolute
   path in the clear. `Redaction` gives length-plus-hash, which is the "attests to bytes" property
   from §8 with no new field.
7. **Fold** — `driverFailed` repeats are excluded from `perRun` and mark the sweep truncated;
   everything else contributes its cell vector. `StabilityScore.fold(perRun:stepCount:runs:)` where
   `stepCount` is the command count of the longest surviving repeat.
8. **Report** — a `StabilityReport`-shaped object plus the Maestro-specific blocks.

Process execution reuses `Session.runSimctl`'s hardened shape (concurrent pipe drain, watchdog
terminate, output cap) — extracted to a shared `runBoundedProcess` rather than copied, since a JVM
that writes more than a pipe buffer would deadlock the same way `simctl listapps` does.

## 3 · Result shape

```
{ lane: "maestro", flowPath, flowHash, device, verdict, verdictNote,
  runs, requestedRuns, truncated,
  commands: [ { sequenceNumber, type, status, injected, durationMs } ],   // from the last repeat
  durations: { "<seq>": { min, median, max } },                          // across repeats
  score: { firstDivergence, divergenceBasis: "repeats", stepInstability,
           deterministic, divergenceDetail },
  perRunVerdicts: [ ... ],
  endStateAgreement: { agreed: Bool?, changedFractions: [Double], note },  // evidence, not score
  declaredApps: [...], declaredNote, unresolvedConstructs: [...],
  frameCaveat, notes: [...] }
```

`divergenceBasis` is a literal, always `"repeats"` — it exists so no reader has to infer that this
`firstDivergence` is not the replay-versus-recording one.

## 4 · Touched files

- **`ToolCatalogue.swift`** — add `"flow"` to the `action` enum, add `path` and `runs` properties,
  and a description paragraph carrying: this executes a separate binary on a file you name; what
  `flowPassed` does and does not claim; that `firstDivergence` is repeat-versus-repeat over Maestro
  sequence numbers; that durations are reported and never scored; and that the gate judges what the
  flow *declares*. Existing paragraphs are not rewritten.
- **`Dispatch.swift`** — `"flow"` into the action allow-list and the two new arguments threaded.
- **`ReplayGate.swift`** — `maestroFlow = "proctor_ios.flow"` and `maestroRepeat =
  "proctor_ios.flow.repeat"`, both added to `AuditTool.all` so the existing distinctness property
  covers them.

## 5 · Tests

`Tests/ProctorCoreTests/MaestroRunTests.swift` (pure — clauses 1–6, 13, 14),
`Tests/ProctorCoreTests/MaestroGateTests.swift` (clauses 7–9),
`Tests/ProctorAgentTests/MaestroSeamTests.swift` (clauses 10–12).

Fixtures are synthesised `commands-*.json` documents built from the measured shape, plus two captured
verbatim from the live runs (one passing seven-command record, one failing four-command record with
`error.hierarchyRoot` present) so the parser is proved against real bytes and not only against what
this build expects.

Clause 10 and clause 11's "no command text" are source-level assertions in the style of PRO-0048's
no-shutdown test: read the two new source files and assert they contain no `ActionStep(`, no
`ActuationBackend`, and no `--analyze`.

## Risks

- **A wedged JVM.** Bounded by the same watchdog `runSimctl` uses; a timeout is `driverFailed`, which
  is already excluded from the score.
- **The scan under-detecting an app id.** Mitigated by refusing every unresolvable construct under an
  allow list, and stated as a residual ceiling in the spec rather than claimed away.
- **A five-repeat sweep takes 70–90 s** at the measured 14–18 s per invocation. `runs` defaults to 1;
  the tool description names the cost so a caller chooses it deliberately.
