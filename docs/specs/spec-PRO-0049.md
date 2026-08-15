# PRO-0049: Run Maestro flows as Proctor flows

**ID:** PRO-0049
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0049.md`
**Brief:** `docs/features-to-triage/50-run-maestro-flows-as-proctor-flows.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` (wave 7 architecture; this spec follows it)
**Depends on:** PRO-0048 (`8d2fde6`) for the device handle model and the honesty ladder it established;
PRO-0050 (`0ea6f88`) for the `maestro` toolchain row this consumes rather than re-probing.

## Feature description

> Deep links get an iOS app into a state. Exercising it from there needs a driver, and the lane
> `acceptance-e2e` documents is Maestro: `.maestro` YAML flows run against the iOS Simulator.
>
> Proctor already has a flow concept with a recording, a replay and a determinism score. A Maestro
> flow is a flow too, and a caller should not have to hold two mental models.
>
> Run a `.maestro` flow against a targeted simulator, parse what it reports, and surface it in
> Proctor's own flow shape so the same campaign can cover a Mac app and an iOS app.
>
> The hard parts, named: the unit of execution is different and the reporting must not pretend
> otherwise; determinism scoring is the interesting question, not the invocation; Maestro's own
> flakiness is now inside the measurement; and Maestro's individual commands must not be proxied
> through `proctor_act`.
>
> Maestro is a separate binary with its own install. Detect it, report it in `proctor_doctor`, and
> follow PRO-0023's rule: Proctor detects and explains, it never installs, and a tool result carries
> no command text.

## What was measured before designing

Every decision below rests on probes run on this machine on 2026-08-15: **maestro 2.4.0** (Homebrew,
`/opt/homebrew/bin/maestro` → `../Cellar/maestro/2.4.0/bin/maestro`), iPhone 16 Pro simulator
`29FEA02E…` on iOS 18.2, booted. These are the numbers, not recollections.

| Probe | Result |
|---|---|
| `maestro --version` | `2.4.0`, **4.67 s** wall — a JVM start, never allowed in a hot path |
| Flow passes | exit **0** |
| Flow assertion fails | exit **1** |
| Device udid does not exist | exit **1**, `Device … was requested, but it is not connected.` |
| Flow YAML has an unknown command | exit **1**, a YAML parse error, and **no per-command record written** |
| Per-command record | `--debug-output` writes `commands-(<name>).json`: per entry a structured `command` object and `metadata { status, timestamp, duration, sequenceNumber }`; on failure also `metadata.error.message` and `metadata.error.hierarchyRoot` — Maestro's own view tree |
| Array order | **not** sequence order. Observed `[2, 0, 1, 3]`; sorting by `sequenceNumber` is mandatory |
| Injected commands | Maestro prepends `defineVariablesCommand` (seq 0) and `applyConfigurationCommand` (seq 1). Neither appears in the YAML |
| Debug filename | `commands-(settings).json` in one invocation and `commands-(settings.yaml).json` in others — **glob for it, never construct it** |
| `--flatten-debug-output` | writes the artefacts directly into the given directory, with no `.maestro/tests/<timestamp>/` nesting |
| Five identical passing runs | status vector **identical all five times**: 7 commands, all `COMPLETED` |
| Same five runs, per-command duration | `backPressCommand` **634 / 91 / 88 / 96 / 91 ms** (a 7× spread); `launchAppCommand` 1483–1558 ms |
| Wall time per invocation | 14.0–17.7 s for a flow whose commands sum to ~6.2 s → **~8 s of fixed driver overhead per run** |
| JUnit report (`--format junit`) | flow-level only: one `<testcase>`, whole-flow `time`, one failure message. No per-command granularity |
| `~/.maestro/analytics.json` | `enabled: true` on this machine — Maestro's own telemetry is on by default |

Two of these decide the whole design. **Exit status cannot separate a driver failure from an app
failure** — an assertion that did not hold, a device that does not exist and a YAML that does not
parse all exit 1 — which is PRO-0048's lesson arriving in a different coat. And **the per-command
status vector is stable across repeats while the durations are not**, which is what makes a
determinism score possible at all and which single field would destroy it.

## Design

### 1. This is a flow-level seam, and deliberately not `ActuationBackend`

PRO-0044 left this item a warning and it is correct: `ActuationBackend` performs *a step*, and
Maestro executes *a file*. Nothing here implements `ActuationBackend`, extends it, or registers a
backend id. The binding is at the flow level, so the new code is a peer of the flow surface rather
than a member of the actuation one:

- `Sources/ProctorCore/MaestroRun.swift` — the decision half. Pure: no `Process`, no `FileManager`,
  no clock it is not handed. Parsing a command record, deriving a per-command hash cell, deciding a
  verdict, scanning a flow file for the apps it declares, and building the invocation's argument
  vector all live here, which is what makes the whole ladder provable on a machine with no Maestro
  and no booted device.
- `Sources/ProctorAgent/Session/SessionMaestro.swift` — the impure half. Runs the binary, reads the
  debug directory, takes Proctor's own before/after device samples, and wires the gate, the queue
  guard and the audit trail.

That split is PRO-0048's, reused rather than reinvented.

### 2. It surfaces as `proctor_ios` action `flow`

One new action on the existing tool, taking a flow file `path`, an optional `runs` count, and the
`device` reference `proctor_ios` already resolves. The tool count does not change.

The two alternatives were considered and are worse:

- **Extending `proctor_flow` / `proctor_stability` to accept a Maestro file** would keep the field
  names and change what they measure. Those tools operate on a `RecordedFlow` in Proctor's own store:
  `start`/`stop` recording, an `ActionStep` list, a per-step accessibility `stateHash` Proctor
  produced, `settle`, `includeTiles`, `pointerMarks`, `resetBetween` as Proctor steps. A Maestro file
  has none of them. `firstDivergence` would then mean one thing or another depending on an invisible
  property of the flow that was named — precisely the "two meanings, one field" trap this item exists
  to avoid. PRO-0048 already refuses a `dev-` handle by name in every window-taking tool for the same
  reason.
- **A separate `proctor_maestro` tool** would re-solve device resolution, the boot precondition, the
  `ios:` policy key, the per-device busy guard and the doctor row, and would split one lane across
  two tools a campaign has to remember the boundary of.

The out-of-family review agreed with the pick and with both rejections (see the triage section).

The action is not `proctor_flow` in miniature: there is no `start`, `stop`, `show` or `delete`,
because there is nothing to record — the flow file is authored outside Proctor and Proctor's store
never holds it.

### 3. What `firstDivergence` means when Proctor did not run the steps

The brief asks this directly, and the honest answer turned out to be simpler than expected once the
existing code was read.

**On the macOS lane `firstDivergence` already has two different meanings, and only one of them
needs a recording.** `proctor_flow` action `replay` compares a replay against the recording's
per-step hashes — that one is recording-versus-replay and has no analogue here. But
`proctor_stability` folds the repeats **against each other** (`StabilityScore.fold`), and its
`firstDivergence` is the first step index at which the repeats stopped agreeing. That meaning
carries over intact.

So, stated plainly and carried in the result as a `divergenceBasis` field so no reader has to infer
it:

- **`divergenceBasis: "repeats"`.** `firstDivergence` is the first position at which two repeats of
  this flow disagreed. It is never a comparison against a recording, because there is no recording:
  Proctor did not perform these steps and holds no expected state for any of them.
- **The position is a Maestro `sequenceNumber`, not a YAML line and not a JSON array index.** The
  array is not in sequence order, and Maestro injects two commands that are not in the file, so a
  caller reading `firstDivergence: 2` as "the second step of my YAML" would be wrong twice over. The
  result therefore carries a `commands` array with each entry's `sequenceNumber`, its command type,
  and an `injected: true` marker on the ones Maestro added, so the index resolves to something a
  person can point at.
- **A single run reports `firstDivergence: null` and `deterministic: false`** with a note saying one
  run cannot measure divergence — the same rule `proctor_stability` already applies, for the same
  reason.

**What `flow` proves is coarser than what a replay proves, and the result says so in one sentence
rather than leaving it to be worked out:** a Maestro-backed flow establishes that the driver
executed a command sequence and reported an outcome for each command, not that Proctor observed the
application reach any particular state.

### 4. The per-run signal, and what is kept out of it

Each repeat produces one cell per command position:

```
cell = hash( canonical(command identity) + "|" + status )
```

**Command identity** is Maestro's command type together with the parameters the command was invoked
with, canonicalised through the existing `Canonical` helper. The type alone is not enough: `tapOn:
"General"` and `tapOn: "About"` are both `tapOnElement`, and a flow with conditional branching
(`runFlow: when:`) genuinely executes different commands on different repeats — which is exactly the
divergence worth catching.

**Status** is `COMPLETED` or `FAILED` (Maestro's own vocabulary, carried through unchanged rather
than remapped, so a value this build has not seen survives into the report instead of being
flattened).

Those cells feed the **existing `StabilityScore.fold`** unchanged. Its cells are opaque hash strings
and its column arithmetic is not macOS-specific, so the Maestro lane gets the same `firstDivergence`,
`stepInstability`, `deterministic`, `divergenceDetail` and undersampling handling with no second
implementation of the maths — including the rule that a repeat which ended early diverges at its own
length, and that a truncated sweep is never reported `deterministic`.

**Everything below is excluded from the hash, each for a measured reason.** This table is the
substance of the "determinism scoring is the interesting question" hard part.

| Signal | Why it cannot enter the hash |
|---|---|
| `metadata.duration` | Measured 634 / 91 / 88 / 96 / 91 ms for one unchanged command. Every repeat would diverge at the first command and the score would read 100% unstable on a perfectly stable flow |
| `metadata.timestamp` | Unique per command per run by construction |
| Wall-clock time | 14–18 s for a 5-command flow, ~8 s of which is JVM and driver start. It measures the process, not the app |
| Exit code | 0 or 1, and 1 covers an assertion failure, a missing device and a malformed flow alike. A bit that cannot separate driver from app cannot be a determinism bit |
| The JUnit report | One testcase for the whole flow. A score built on it has two values, which is the failure mode the brief names |
| `error.hierarchyRoot` | Present only on failure, uncanonicalised, and full of geometry and identifiers. It would flake the hash on exactly the runs worth reading. Carried as evidence instead — the fourth iOS channel PRO-0048 reserved for this item |
| `error.message` | Free text, same problem |
| JSON array position | Not command identity, and not in sequence order |
| Device screen pixels | See below — kept as evidence, deliberately not folded |

Durations are not discarded, they are **reported beside the score** as a per-command min / median /
max across the repeats. A command whose duration spread is 7× while its status never moves is a real
signal about the app, and it is one this lane can offer that the pass/fail summary cannot — it is
simply not a determinism verdict.

### 5. The device-frame channel is evidence, never a score input

Proctor takes its own device screenshot before and after each repeat, through PRO-0048's existing
path (which already excludes the top 5% status-bar band, so the clock cannot be mistaken for a
change). The comparison across repeats is reported as an `endStateAgreement` block: whether every
repeat left the device looking the same, with the changed-pixel fractions.

It is **not** folded into `deterministic`, and the reason is the direction file's own standard. A
device frame carries no `SCFrameStatus`, so its freshness cannot be established; letting an
unconfirmable frame decide a field named `deterministic` would be the blending PRO-0048 refused.
Reported separately, a caller can read both and see when they disagree — and a disagreement between
"Maestro says every command completed identically" and "the device did not end up in the same place"
is one of the more interesting things this lane can produce.

### 6. Separating a driver flake from an app flake

The brief names this as the tri-observer problem in a different coat, and the shape of the answer is
that **there is only one observer of the steps.** Worth stating in exactly those terms, because it
quantifies the thinness:

- The macOS lane has three channels per step — the accessibility tree, the geometry, the pixels —
  and `proctor_assert` kind `agree` exists to report where they disagree.
- **The Maestro lane has one observer per command: Maestro itself.** Proctor adds two independent
  channels *around the outside of the run* — the app's process liveness on the device, and the
  device frames — and those bound the run, not the individual commands. Proctor cannot interleave an
  observation between two Maestro commands without driving them, which is forbidden (§7).

What that supports is a verdict ladder, following PRO-0048's pattern rather than inventing a second
one. Every value is a claim defensible from a channel that actually reported:

| Verdict | What it rests on |
|---|---|
| `flowPassed` | A per-command record exists and every command reported `COMPLETED`. Claims that the driver executed the sequence and reported success, not that Proctor observed anything |
| `flowFailed` | A per-command record exists and at least one command reported `FAILED`. Maestro's view says the flow did not hold; Proctor cannot independently confirm which of the app or the driver is responsible, and the note says so |
| `appGone` | A command reported `FAILED` **and** Proctor's own liveness channel says the app under test was running before the run and is not running after it. Outranks `flowFailed`, exactly as PRO-0048's `targetGone` outranks a screen change: an app that died must never be filed as a failed assertion |
| `driverFailed` | **No per-command record was produced at all** — a device that does not exist, a YAML that does not parse, a driver install failure, a JVM error, or a timeout Proctor imposed. The flow never reached the app |
| `refused` | Proctor refused before invoking anything: the policy gate, the filesystem jail, no Maestro on the machine, or a device that is not booted |

**`driverFailed` is the load-bearing one, and it is excluded from the determinism fold entirely.** A
repeat that never reached the app is not a sample of the app's behaviour, and folding it in would
score the driver's reliability as the application's non-determinism — the exact confusion the brief
warns about. It is reported as a truncated sweep, reusing the shape `proctor_stability` already uses
when permission is withdrawn between repeats, and a sweep with any `driverFailed` repeat is never
reported `deterministic`.

Three signals put a repeat in `driverFailed`, and only the first was in the original design:

1. **No per-command record was produced.** All three measured driver-side failures exit 1 exactly as
   an assertion failure does, but none of them writes a record, while an assertion failure writes one
   containing a `FAILED` command. The presence of the record — not the exit code — is the
   discriminator.
2. **The only failing command is a harness or precondition command.** A `FAILED` `launchAppCommand`
   is a precondition that did not hold, not app behaviour under test; a `FAILED` `runScript`,
   `evalScript` or `runFlow` is the harness failing. The out-of-family review named all four as
   driver faults that would otherwise be folded into the app's score, and they are separable from
   data already parsed.
3. **Proctor's own liveness channel stopped answering.** A device that went away mid-flow makes
   `simctl` liveness return *unavailable* rather than *not running* — a distinction PRO-0048 already
   preserves — which is evidence about the device rather than about the app.

**What remains genuinely inseparable, stated rather than claimed away.** A `tapOn` or an
`assertVisible` that failed because the simulator was loaded, because the driver's view-hierarchy
dump timed out, or because a hit test missed is indistinguishable from the app not showing what it
should. It writes a record, it fails an app-facing command, the app stays alive, and it is folded.
The measured shape is suggestive but not discriminating: the failing assertion in the live probe ran
**17,289 ms** against 130–2,000 ms for every command that passed, because Maestro retries until its
own timeout. That duration is reported beside the failure with exactly that caveat. This is the
residue of the "a flake in the driver is indistinguishable from a flake in the app" problem after
every separable case has been separated, and the notes say so on any run that contains one.

**Dropping `driverFailed` repeats biases the score, and the direction is named in the notes.** The
excluded repeats are the anomalous ones, so the surviving `stepInstability` figures are an
*optimistic* bound — the agreement of the repeats that got far enough to be compared. The bias cannot
reach the headline verdict, because a truncated sweep is never reported `deterministic`; the cost is
the opposite error, where driver flake denies the label to an application that was in fact stable.
Both directions are stated in the run's notes rather than left for a reader to work out.

**A conditional flow changes its own length, and that is reported as one divergence rather than
many.** A `when:` branch taken differently between repeats shifts every subsequent `sequenceNumber`,
so a column-wise comparison would report a divergence at every position after the branch. The first
position is honest; the rest are an alignment artefact. When the repeats have different command
counts the report says so in one note and names the first position, instead of publishing a wall of
apparent divergences from one branch decision.

### 7. Maestro's commands are never proxied through `proctor_act`

PRO-0020 settled this for browser tools and the reasoning transfers exactly: a tool driving its own
engine is not driving the window Proctor is attached to, so a routed step would report success
against something Proctor never touched. Concretely, nothing in this item translates a Maestro
command into an `ActionStep`, accepts a Maestro command in `proctor_act`, or exposes a way to
execute one command at a time. The unit is the file. A test asserts at source level that the new code
constructs no `proctor_act` step from a Maestro command.

### 8. Executing a caller-named YAML is a governance surface, and the gate is weaker here

This is not in the brief and it is the sharpest thing triage surfaced. `proctor_ios` action `open`
gates on **the app the device resolves the URL to**, never on a name the caller supplied, because
gating on a caller-supplied name would let a caller allow-list one app and drive another. A Maestro
flow does not offer that: which app it drives is **declared in the file**, and a file is caller
content.

The design does not pretend otherwise:

- **Proctor reads the flow file for the apps it declares.** Rather than enumerating the keys that
  can carry a bundle id — a list that goes stale the first time Maestro adds a command, and which
  the out-of-family review broke immediately by naming `onFlowStart`, `stopApp`, `killApp`,
  `clearState` and `setPermission` — the scan collects **every reverse-DNS-shaped token in the
  file**, plus the structured `appId` / `launchApp` / `runFlow` keys. It over-detects by
  construction: a bundle id mentioned in a comment is gated too. That is the safe direction, extra
  ids can only cause a refusal and never authorise one, and the refusal names the token and the line
  so it is actionable.
- **`runFlow` includes are followed transitively** (depth 5, visited set), and **so is a `config.yaml`
  sitting beside the flow** — Maestro reads a workspace config implicitly when `--config` is not
  passed, so content outside the named file influences the run and must be scanned with it.
- **`openLink` is gated on the device, not on the file.** A flow can `openLink` a URL whose scheme
  resolves to an app it never declares, which is precisely the substitution PRO-0048's deep-link gate
  closed by resolving the handler on the device. A literal `openLink` URL is therefore resolved
  through the same `SchemeMap` action `open` uses and gated on the app the *device* resolves it to.
- **This is a conservative textual scan, not a Maestro parser.** The package has no YAML dependency
  and reimplementing Maestro's command language would go stale. Where a YAML construct structurally
  defeats a textual scan — an anchor or alias (`&`/`*`), a merge key (`<<:`), a block scalar
  (`|`/`>`) — the scan does not guess: it reports the construct as unresolved. An under-detection
  becomes an over-refusal, which is the direction that matters.
- **Anything the scan cannot resolve is refused whenever any policy is in force** — an allow list, a
  block list *or* the sensitive set. The out-of-family review caught the original rule keying on the
  allow list alone: a block list with no allow list is a policy in force, and an unresolvable
  construct sailing past it would be a block-list bypass. With a **completely empty** policy the flow
  runs and the construct is reported in the result and the trail, which keeps the same
  inert-until-configured convention `AppPolicy` and `FSJail` already follow — refusing
  unconditionally would make the action unusable on a default install and would be stricter than any
  other Proctor path.
- **Unresolvable constructs are reported in two classes, because they are not the same risk.**
  `opaqueTarget` — an interpolated app id, an unreadable include, a defeating YAML construct — means
  Proctor cannot tell which app is driven. `capability` — `runScript` or `evalScript` — means the
  flow can execute JavaScript with network access, which is an egress capability the app allow list
  does not govern at all. Both refuse under a policy; the notes differ, so a reader is never told
  "could not resolve an app id" about a flow that can make network calls.
- **The audit record says `declared`, never `resolved`.** The trail records the gated app ids under a
  field that names them as the flow's declaration, and the flow file is recorded by absolute path
  plus a content hash — so a trail entry attests to the exact bytes that ran, and a flow edited
  between two runs is visible as two different hashes rather than one name.
- **The flow file path goes through the existing `FSJail`** on the same terms as every other
  caller-supplied path, so an operator who declared filesystem roots gets them here too.

The residual ceiling, stated rather than left to be discovered: **a flow can reach an app it does not
declare**, through a construct the scan does not model. Proctor's claim is over what the flow
declares, and the field name says exactly that.

### 9. Detect and explain, never install; and Maestro's own telemetry is disclosed

Following PRO-0023: Maestro's presence comes from **PRO-0050's existing `maestro` toolchain row**
(`tools.maestro`), not from a second probe — and never from running `maestro --version`, which
measured 4.67 s. A machine without it gets a refusal naming the doctor row and the project's own
documentation URL, carrying **no command text** for a caller to paste.

One disclosure the brief does not ask for and the reader should have: `~/.maestro/analytics.json`
reads `enabled: true` on this machine, so invoking Maestro runs Maestro's own telemetry. Proctor does
not alter that file — it is the operator's configuration and silently rewriting third-party config
would be exactly the overreach PRO-0023 rules out. The fact is reported once in the result's notes
when telemetry is enabled, so a caller running a flow in a sensitive context knows what the
invocation carries. `--analyze`, Maestro's cloud AI feature, is never passed.

### 10. The lane is named in every record

PRO-0051 settled that lanes are deliberately selected and never automatic, and that every run record
names the lane that ran. This lane is selected by calling this action — there is no automatic
routing into it and no fallback out of it — and both the result and the `StabilityReport`-shaped
report carry `lane: "maestro"` beside the existing `backend` field, so a score is never readable
without the path that produced it.

## Acceptance criteria

Each clause is proved by a test named beside it.

1. **A flow runs and reports per-command.** Given a per-command record, the result carries an ordered
   `commands` array sorted by `sequenceNumber`, each with its type, status and duration, and with
   Maestro's two injected commands marked `injected: true`. — `MaestroRunTests`
2. **`firstDivergence` is repeat-versus-repeat and says so.** A multi-run report carries
   `divergenceBasis: "repeats"`, and `firstDivergence` is a `sequenceNumber` present in the
   `commands` array. A single run reports `firstDivergence: null`, `deterministic: false` and the
   one-run note. — `MaestroRunTests`
3. **Identical repeats score deterministic; a status change diverges; a duration change does not.**
   Five identical status vectors fold to `deterministic: true`; changing one command's status folds
   to a divergence at that command's `sequenceNumber`; changing only durations and timestamps folds
   to `deterministic: true` with no divergence. — `MaestroRunTests`
4. **A driver failure is never scored as an app result.** A repeat with no per-command record yields
   `driverFailed`, is excluded from the fold, and makes the sweep `truncated` and never
   `deterministic`. — `MaestroRunTests`
5. **An app that died outranks a failed assertion.** A `FAILED` command with liveness reporting
   running-before and not-running-after yields `appGone`, not `flowFailed`. — `MaestroRunTests`
6. **Exit status alone decides nothing.** Exit 1 with a per-command record containing a `FAILED`
   command is `flowFailed`; exit 1 with no record is `driverFailed`; the two are distinguished with
   identical exit codes. — `MaestroRunTests`
7. **Every declared app is gated, under the iOS-qualified key.** A flow declaring a header `appId`
   and a different `launchApp` target has both gated; a block on either refuses the run; the refusal
   is audited. A reverse-DNS token appearing under a key the scan does not model is gated too.
   — `MaestroGateTests`
8. **Unresolvable constructs fail closed whenever any policy is in force.** A flow containing
   `runScript`, `evalScript`, an unreadable `runFlow` target, an interpolated app id, a YAML anchor,
   alias, merge key or block scalar is refused when an allow list, a block list **or** the sensitive
   set is non-empty, with the construct named; under a completely empty policy it runs and the
   construct is reported. `runScript` and `evalScript` are reported as class `capability`, the rest
   as `opaqueTarget`. — `MaestroGateTests`
9. **The trail attests to bytes, not a name.** The audit record carries the declared app ids, the
   absolute flow path and a content hash of the flow file, and is marked `declared`.
   — `MaestroGateTests`
10. **`openLink` is gated on what the device resolves.** A literal `openLink` URL is resolved through
    the same scheme map action `open` uses and gated on that app, not on anything the flow declares;
    an interpolated one is `opaqueTarget`. — `MaestroGateTests`
11. **A `config.yaml` beside the flow is scanned with it.** An app id declared only in an adjacent
    workspace config is gated; an unreadable one is `opaqueTarget`. — `MaestroGateTests`
12. **A harness failure is not an app failure.** A repeat whose only `FAILED` command is
    `launchAppCommand`, `runScript`, `evalScript` or `runFlow` is `driverFailed` and is excluded from
    the fold; a repeat whose `FAILED` command is app-facing is `flowFailed` and is folded. A repeat
    whose liveness channel stopped answering is `driverFailed`. — `MaestroRunTests`
13. **The bias is stated.** A sweep with an excluded repeat carries a note naming the exclusion, the
    optimistic direction of the surviving instability figures, and that the sweep cannot be reported
    deterministic. — `MaestroRunTests`
14. **A length change reads as one divergence.** Repeats with different command counts produce one
    note naming the first position and the length change, not a divergence entry per trailing
    position. — `MaestroRunTests`
15. **No Maestro command becomes a Proctor step.** The new sources construct no `ActionStep` from a
    Maestro command and register no `ActuationBackend`. — `MaestroSeamTests` (source-level assertion,
    the same shape as PRO-0048's no-shutdown test)
16. **Absent Maestro is a clean refusal with no command text.** With the toolchain row reporting
    absent, the action refuses naming the doctor row and the docs URL, and the message contains no
    installable command string. — `MaestroSeamTests`
17. **The device handle model is unchanged.** The action resolves a device exactly as the existing
    actions do, refuses a device that is not booted, and holds the per-device busy guard for the
    whole sweep. — `MaestroSeamTests`
18. **The lane is named.** Both the single-run result and the multi-run report carry `lane:
    "maestro"`. — `MaestroRunTests`
19. **The debug directory is read by glob, not by construction.** A record written as
    `commands-(x).json` and one written as `commands-(x.yaml).json` are both found, and the newest is
    taken when an invocation leaves more than one timestamped directory — measured, one failing run
    left two. — `MaestroRunTests`

## What could not be measured live

Maestro **is** installed on this machine (2.4.0), and a booted iPhone 16 Pro simulator was available,
so the invocation, the record shape, the failure shapes and the five-repeat stability were all
measured live rather than against a fake — the numbers are in the table above. Two things were not:

- **A flow whose executed command list genuinely differs between repeats** (conditional `runFlow:
  when:`), which is the case command identity exists to catch. It is covered by unit tests over
  synthesised records rather than by a live divergent flow.
- **`appGone` against a real crashing iOS app**, which needs an app built to crash on a deep link.
  The ladder is proved over synthesised evidence, exactly as PRO-0048 proved its own.

The decision layer is pure and takes its records as data, so both are provable without either.

## Not in scope

- **A reset between repeats.** `proctor_stability` takes `resetBetween` as Proctor steps; there is no
  equivalent here and none is invented. A Maestro flow conventionally opens with `launchApp` (with
  `clearState` when it wants one), so it carries its own preconditions in a way a Proctor step list
  does not. Recorded as child work rather than guessed at.
- **Android.** Maestro drives it; Proctor's device lane is `simctl`, which does not.
- **Recording a Maestro flow, or authoring one.** The file is authored outside Proctor.
- **Maestro's cloud features** (`--analyze`, the API key flags). Never passed.
- **The run HUD, the queue surface and the status window** — PRO-0046 and PRO-0036 are in flight over
  both. This item stays inside the iOS/Maestro lane.

## Child work found

- **A reset step between repeats**, as a flow file Proctor runs between measured repeats. It would
  make a sweep meaningful for a flow that does not reset itself, and it needs its own gating pass
  because a reset flow is a second piece of caller content.
- **Region-scoped end-state comparison**, inherited from PRO-0048's own child list and sharper here:
  comparing a named rectangle across repeats would let an app with an animating chrome still report a
  usable `endStateAgreement`.
- **A YAML dependency for the flow scan.** The conservative textual scan is honest but coarse; a real
  parser would let the gate resolve more constructs instead of refusing them under an allow list.
- **Maestro's `hierarchyRoot` as a queryable channel.** `maestro hierarchy` returns a full view tree
  on demand and was measured working. Used as failure evidence here; a `proctor_ios` action that
  reads it deliberately would give the iOS lane its first structural observation, and is the natural
  route to an iOS `proctor_assert`.
- **A shared flake-attribution vocabulary.** `driverFailed` and PRO-0044's `suspected_noop` are the
  same idea in two lanes; if a third lane arrives, they want one enum.

## Triage — 2026-08-15 — Ready for Implementation Plan

**Sentinel verdict:** S3 (governance-adjacent). Three properties move here: Proctor executes a
third-party binary on caller-supplied content from a process holding Accessibility and Screen
Recording; the policy gate's key changes from *resolved* to *declared* for this one action; and the
audit trail gains a record whose claim is weaker than the one beside it. Each is stated in §8 rather
than inherited silently.

**Essential gaps:** none. Every open question was resolvable from the direction file, a shipped
decision in this repo, the live probes above, or the out-of-family review, and each is recorded as a
decision rather than asked.

### Out-of-family review — grok-4.6, effort xhigh, read-only

Ran on the surface fork and the score basis with the measurements inlined. **Verdict: agreed with the
pick and with both rejections**, and changed the spec in three places:

1. **`firstDivergence` must be a Maestro `sequenceNumber`, and the injected commands must be tagged.**
   Its point that a caller would otherwise read `firstDivergence: 2` as "YAML step 2" was correct and
   the `injected: true` marker in §3 exists because of it.
2. **Reuse `StabilityScore.fold` rather than writing a second score.** It observed that
   `proctor_stability` already folds repeats against each other rather than against a recording,
   which resolves the "what does `firstDivergence` mean with no recording" question by inheritance
   instead of invention. Verified against `Sources/ProctorCore/StabilityCaptures.swift` before
   adopting, not taken on its word.
3. **Command identity must include the command's parameters, not just its type**, because a
   conditional flow genuinely executes different commands per repeat. Adopted in §4.

One recommendation was **not** taken: it argued the device-frame channel should be dropped entirely,
partly on the grounds of the status-bar clock. PRO-0048 already excludes that band, and dropping the
only Proctor-owned channel would leave the lane with a single observer and no independent evidence at
all. It is kept as evidence and excluded from the score instead (§5), which addresses the real
concern — an unconfirmable frame deciding a verdict — without discarding the channel.

Egress note: the review carried the design question and the measured numbers. No key material, no
audit-chain code and no policy-gate source was sent.

### Plan review gate — grok-4.6, read-only

The first attempt hit the deadline mid-reasoning: given inlined evidence it went off reading the repo
anyway and returned no verdict. Per the fleet contract that is a lane failure and not a pass, so it
was retried once with tool use forbidden and a word cap, which is the documented fix. The retry
returned a verdict and **found a real defect plus four escapes**, all accepted:

1. **A block list with no allow list was a bypass.** The original rule refused an unresolvable
   construct only when an allow list was in force. A block list is a policy in force too, and an
   unresolvable target sailing past it defeats it. The rule now keys on *any* non-empty policy. Its
   stronger recommendation — refuse unconditionally — was **not** taken: `AppPolicy` and `FSJail` are
   both inert until configured, and refusing on a default install would be stricter than every other
   path in this codebase for no gain in a posture where everything is already permitted.
2. **`openLink` escapes a file-level gate**, reaching whatever app the device resolves the scheme to
   while the flow declares another. This is the exact substitution PRO-0048 closed, and it is now
   closed the same way, through the same scheme map.
3. **Enumerating app-id-bearing keys is a losing game** — it named `onFlowStart`, `stopApp`,
   `killApp`, `clearState` and `setPermission` immediately. Replaced with collecting every
   reverse-DNS-shaped token, which over-detects and therefore cannot under-gate.
4. **YAML anchors, aliases, merge keys and block scalars defeat a textual scan.** Now detected as
   syntax and reported unresolved rather than scanned past.
5. **Four driver faults would have been folded into the app's score** — a failed `launchApp`, a
   device that dies mid-flow, a harness `runScript`/`runFlow` failure, and a hit-test miss. Three are
   separable from data already parsed and are now `driverFailed`; the fourth is not, and §6 says so
   with the measured 17,289 ms figure rather than claiming the ladder solved it.

It also confirmed the exclusion's bias direction independently (optimistic surviving subset, and a
determinism label denied to a stable app by driver flake), which is now written into the run notes.

A `config.yaml` adjacent to the flow — read by Maestro implicitly when `--config` is not passed, so
content outside the named file steers the run — was found in this repo's own reading of Maestro's CLI
help rather than by either reviewer, and is scanned as an include.

## Progress

**Delivered on `ai/pro-0049`, worktree `.worktrees/PRO-0049`. Stopped before merge as instructed.**

`swift build` clean and `scripts/test.sh` green: **1,216 tests before, 1,272 after** — 54 new gated
tests plus 2 live tests that skip unless `PROCTOR_LIVE_MAESTRO=1`. The full suite was run three times
end to end to confirm stability.

| File | What |
|---|---|
| `Sources/ProctorCore/MaestroRun.swift` | New, pure. Record parsing, the hash cell, the verdict ladder, the flow scan, the gate, the argument vector |
| `Sources/ProctorAgent/Session/SessionMaestro.swift` | New, impure. Process, debug directory, gate wiring, busy guard, audit, report |
| `Sources/ProctorCore/ToolCatalogue.swift` | The `flow` action, `runs`, and the description paragraphs carrying what it does not prove |
| `Sources/ProctorAgent/Dispatch.swift` | The action and its arguments |
| `Sources/ProctorCore/ReplayGate.swift` | `proctor_ios.flow` and `proctor_ios.flow.repeat` |
| `Sources/ProctorAgent/Session/SessionIOSProcess.swift` | `runSimctl`'s hardened body generalised to `runBounded` and shared, not copied |
| `Sources/ProctorAgent/Session/SessionIOS.swift` | Five helpers widened from private to internal so the new file reuses device resolution rather than re-implementing it |

One existing test was updated: `IOSLaneTests` pins the exact action set on `proctor_ios`, and `flow`
belongs in it.

**Verified live, not only against a fake.** Maestro 2.4.0 is installed on this machine and a booted
iPhone 16 Pro was available, so `Tests/ProctorAgentTests/MaestroLiveTests.swift` drives the real
binary against the real simulator: a two-repeat sweep of a five-command Settings flow scored
`deterministic: true` with `firstDivergence: null`, and a deliberately failing flow came back
`flowFailed` with Maestro's own hierarchy attached to the failure. Both took ~32 s. They are guarded
by an environment variable so a fleet machine without Xcode reports on the code rather than on the
machine.

**One flake seen and traced, not caused here.** `ScreenRecordingProbeWiringTests` "a late answer is
picked up by the next call" failed once under full-suite parallel load and passed on five subsequent
runs (three filtered, two full). It is a timing-sensitive probe test in the same family as PRO-0053's
finding, and this diff touches no capture or probe timing code.

### Deliberately not built

- **A reset between repeats.** No `resetBetween` analogue is invented; a Maestro flow conventionally
  opens with `launchApp` and carries its own preconditions. Recorded as child work.
- **A YAML parser.** The flow scan is textual and says so; a real parser would let the gate resolve
  constructs it currently refuses, and is recorded as child work rather than smuggled in here.
- **Anything touching the run HUD, the queue surface or the status window.** PRO-0046 and PRO-0036 are
  in flight over both.
