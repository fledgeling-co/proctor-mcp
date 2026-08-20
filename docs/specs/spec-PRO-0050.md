# PRO-0050: Doctor knows the whole toolchain

**ID:** PRO-0050
**Status:** Merged `0ea6f88`
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/51-doctor-knows-the-whole-toolchain.md`
**Supersedes:** `docs/features-to-triage/32-the-health-report-is-complete.md` (retired, not built — both its halves are absorbed here)
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` (wave 7 architecture; this spec follows it)
**Builds on:** PRO-0041 `0545219` (the three-state grant model), PRO-0048 `8d2fde6` (the `simctl` row), and **PRO-0044 `d65dc1e`, which merged while this was being triaged** and already ships `CuaDriverTool`, `CuaVersion`, `CuaPreflight` and `CuaLaneReport`
**Consumed by:** PRO-0036, which renders whatever shape lands here. The **report shape is the deliverable that outlives this item.**

## Feature description

> **Read `00-WAVE-7-DIRECTION.md` first.** This item supersedes brief 32, which is
> retired: its `doctor.sh` half survives here and its policy-block half is folded in.
>
> ## The problem
>
> `proctor_doctor` is the first call the Proctor skill tells a model to make, and after
> this wave it will be reporting on a machine whose ability to do anything depends on
> software Proctor does not ship: `cua-driver`, `xcrun simctl` and Xcode, and `maestro`.
> Today it reports its own grants and two browser tools.
>
> Two gaps carried over from the retired brief: there is still no `policy` block, so the
> gate that will refuse a model's next call is invisible to it, and `scripts/doctor.sh`
> runs without the agent and knows about none of this.
>
> ## What it should do
>
> Report the whole toolchain, per lane, with each tool's presence, version and usability,
> and say which lanes are actually available on this machine.
>
> ## The hard parts, named
>
> - **"Installed" is not "usable", and this wave makes the difference expensive.** A
>   `cua-driver` that is present but unsupported by version, or present but whose daemon
>   is not running, or whose own permissions are unhealthy, is a lane that will fail at
>   the first call. Cua has its own `doctor`; using it is better than re-deriving its
>   answers, and it is also a second process's opinion arriving as text.
> - **Deciding what a `policy` block may say.** `doctor` is called before anything is
>   established. Reporting the gate's rules there makes `doctor` a way to read the
>   configuration without passing the gate. Report shape and posture rather than rules.
> - **A launchd agent does not see a login shell's PATH.** That is why Obscura needed
>   explicit search locations, and every tool added here inherits the problem. It is also
>   why `scripts/doctor.sh`, which runs in a login shell, can honestly disagree with the
>   agent about whether a tool exists. Report the disagreement rather than hiding it.
> - **The shell doctor duplicates the search order in a second language.** Two
>   implementations of one list drift. Generate it or state plainly that the shell copy
>   is advisory.

Absorbed verbatim from retired brief 32, which is where these two halves were first logged:

> **`proctor_doctor` has no `policy` block.** PRO-0005's plan called for one and it
> is not in the tree, so the audit and policy state of a live agent is visible only
> through `proctor_policy status`. A model checking whether Proctor is ready to work
> gets the grants, the observers, Secure Event Input, the shortcuts CLI and both
> browser tools, and nothing at all about the gate that will refuse its next call.
>
> **`scripts/doctor.sh` knows about neither browser tool.** It runs without the
> agent, which is its whole point, and PRO-0023 and PRO-0024 both logged that it is
> now behind what the agent reports. A person running the shell doctor to work out
> why a handoff failed learns nothing about the tool the handoff names.

## What was measured before designing

Every number below was measured on this machine on 2026-08-15. They decide the design.

| Probe | Result |
|---|---|
| 100 executable-regular-file stats | **0.01 s total.** Detection by stat is free. |
| `maestro --version` | **5.6 s cold, 3.9–5.3 s warm.** JVM start. Reports `2.4.0`. |
| `simctl help`, direct at `/var/db/xcode_select_link/usr/bin/simctl` | 0.10 s |
| `obscura --version` | 0.008 s. Reports `0.2.0`. |
| the status window's `proctor_doctor` poll | **every 2.0 s** (`Sources/ProctorUI/AgentModel.swift:205`) |
| **signature check of an 82 MB binary** (`codesign -v`, the CLI form of what `CuaPreflight.verifySignature` does in process) | **0.32–0.39 s** |
| the same check on a small binary | 0.01 s |
| `/opt/homebrew/bin/maestro` | a symlink to `../Cellar/maestro/**2.4.0**/bin/maestro` |
| `<developer dir>/../version.plist` | root-owned; `CFBundleShortVersionString` **26.6**, `ProductBuildVersion` **17F113** |
| `~/.local/bin/obscura` | a plain regular file — no version anywhere but inside it |
| `cua-driver`, `/Applications/CuaDriver.app`, `~/.cua-driver` | **all absent.** The absent path is what is testable here. |

Five things follow, and each settles a decision that would otherwise be argued.

**A version costs a process, and one of those processes costs more than the poll interval.**
`maestro --version` takes about twice the gap between two doctor calls from the status
window, so it would not merely be slow, it would queue.

**Two of the three versions are readable without running anything.** Maestro's is in the
symlink target Homebrew wrote; Xcode's is in a root-owned plist beside the developer
directory. A version obtained that way is *what the install layout says*, not what the
binary answers, and the report says which it got.

**A signature check is a read, not an execution, and it is the check that decides whether
the driver may run at all.** It is also expensive enough — a fifth of the poll interval on
a large binary — that it has to be cached rather than repeated every two seconds.

**The one tool whose usability matters cannot be reached by a stat**, and the code that
reaches it already exists: PRO-0044 merged `CuaPreflight`, which establishes presence,
signature, version, vocabulary and the driver's own health, in that order.

**The measurement that is missing is missing honestly.** `cua-driver` is not on this
machine. Nothing here claims to have been measured against the real binary, and the fact
that the design does not spawn it is partly *because* an unmeasured timeout budget for an
unmeasured CLI is a guess wearing a number.

## What PRO-0044 already settled, and why this item got smaller

PRO-0044 merged as `d65dc1e` between this item being queued and being triaged. It ships:

- `CuaDriverTool` — the binary name, the search directories, `/Applications/CuaDriver.app`,
  and the `PROCTOR_ACTUATION=cua` switch that selects the delegated lane.
- `CuaPreflight` — presence → **signature** → version → capabilities → the driver's own
  health, each failure its own refusal with a reason. Its `CuaLaneReport` doc comment
  already says it is "for the run record **and for `proctor_doctor`**".
- `CuaVersion`, with a supported range and a parser that returns nil rather than guessing.
- The narrow, deliberate reversal of the never-execute rule: the driver *is* executed, but
  only when an operator selected the lane and only after a signature check pinning
  `identifier "com.trycua.driver" and anchor apple generic`, which is what closes the
  planted-binary hole that made the rule right.
- `CuaActuationBackend`, which **memoises** the lane report once preflight has run.

So this item does not build a second probe. **It surfaces what that one establishes**, and
adds the one thing preflight cannot give: an answer *before* a lane has been selected or a
step attempted. That is the whole of hard part 1, and it is the reason the design below
spawns nothing at all.

## The report shape, which is the part that outlives this item

### Tool rows gain a usability axis; `available` keeps its meaning

`ToolPresence.available` goes on meaning exactly what `Sources/ProctorCore/ToolPresence.swift`
says: an executable regular file of that name exists at one of the searched paths. It is not
redefined — every existing consumer reads it, and a boolean that quietly changes meaning is
the worst kind of protocol change. Usability is a **new axis** beside it.

| Field | Meaning |
|---|---|
| `usability` | `usable`, `unusable`, or `unconfirmed` — the three states, and the spelling, PRO-0041 gave the grants |
| `evidence` | **what was consulted**, as an ordered ladder: `absent` → `presence` → `signature` → `installPath` → `selfReport` |
| `version` | the version when something produced one; the `evidence` value says which route did |
| `detail` | one line, **in Proctor's own words**: what was established and what was not |
| `checkedAt` | when that answer was established |

Every new field is optional, so a report from this agent decodes against the shipped shim
and an older agent's report still decodes here — the rule `agentBuild` and `Grant.state`
already follow.

Two shapes were rejected during review and the reasons are worth keeping. A separate
`versionSource` field is **not** carried: it is derivable from `evidence`, and two fields
that can disagree about one fact will eventually disagree. And `evidence: none` is never
reported for a tool that was found — a row saying "we know nothing" about a file we just
located reads as a bug; the honest floor for a located tool is `presence`.

`unconfirmed` means here what PRO-0041 made it mean for a grant: **a fact about what Proctor
knows, not about the tool.** There is deliberately no derived `usableConfirmed` boolean on a
tool row — nothing decides on one row. The decision is the lane, and that is where the
fail-closed boolean lives.

### Lane rows say what this machine can actually do

```
lane      "mac" | "browser" | "ios" | "cua"
state     "ready" | "unavailable" | "unconfirmed"
available Bool — derived, fail-closed: true only when state == ready
requires  [String] — the tool rows this lane depends on
blockers  [String] — one line per reason it is not ready
note      String? — a standing qualification, when there is one
```

`available` is derived exactly as `Grant.granted` is: an `unconfirmed` lane reads `false`,
so a consumer reading only the boolean stays as conservative as it was, and one that needs
to tell "broken" from "not established" reads `state`.

- **mac** — Proctor's own planes, still the default. Requires no external tool; its blockers
  come from the grants, so a machine whose Screen Recording grant is `unconfirmed` reports
  this lane `unconfirmed` rather than `unavailable`. A permission that may be sitting there
  granted the whole time must not read as a broken lane.
- **cua** — the delegated lane. `unavailable` when the driver is absent or its signature
  fails; `ready` when preflight has established it; `unconfirmed` when the driver is present
  and signed but nothing has been established yet, with a note saying that happens on the
  first delegated step. When `PROCTOR_ACTUATION` does not select it, the row still reports
  the machine's readiness *for* it and notes that it is not the lane in force.
- **browser** — requires `obscura`, and `browser-use` when and only when the operator's
  second-lane variable names it. The existing invariant that the string does not appear in a
  tool result at all with the lane off is unchanged.
- **ios** — requires `simctl`. Maestro's absence does not make the lane unavailable, because
  deep links work without it; it carries a note instead, which is what PRO-0049 consumes.

### A `policy` block that reports posture and shape, never rules

| Reported | Withheld |
|---|---|
| `mode`: `allowList`, `blockOnly` or `open` | the members of any list |
| `allowCount`, `blockCount`, `sensitiveCount` | which bundle ids they hold |
| `approvalTokenLive` | the token, and the bundle id it is scoped to |
| `fsJailDeclared`, `fsRootCount` | the roots |
| `auditWritable`, `auditSealed`, `auditSigned` | the trail's path |
| `auditClean`, `auditKeyConfirmed`, `auditEntries`, `auditDroppedThisRun` | the key id, and any record content |

A model learns the two things it needs before its first call — **will the gate refuse me**,
and **will my actions be recorded** — and learns nothing that names an application.

**Two honesty notes, because the review was right that the boundary is softer than it
looks.** A count is close to a rule at the extremes: an allow list with zero entries is
deny-all, and one with a single entry is fully known to anyone who has driven one app
successfully. And the gate's own refusals already name the bundle id they refused. So
withholding rules here narrows what a determined caller can learn by very little. It is
still right to do: a health check is the wrong place to hand out configuration, the retired
brief asked for it, and the day `proctor_policy status` narrows, `doctor` will not have to
be changed to match. What must not happen is this block being described as a security
boundary — **it is a convention this report keeps**, and `proctor_policy` action `status`
remains ungated and fully descriptive. That gap is recorded as child work rather than closed
here, because closing it changes a shipped tool's answer.

### What does not change

`ready` and `blockers` are untouched by every tool and every lane. Proctor drives native
macOS applications with no Obscura, no Xcode, no `cua-driver` and no Maestro, so a health
report that failed on any of them would be lying about what is broken — the reasoning
`Wire.swift` already records for Obscura, applied to four more tools.

## The four hard parts, answered

### 1. Installed is not usable — and `doctor` establishes it without spawning anything

**`proctor_doctor` executes no located binary. Not the driver, not Maestro, not Obscura.**
Everything it reports comes from one of three places, and each is a read:

1. **The filesystem** — presence, the searched paths, companions, and a version where the
   install layout carries one (Maestro's symlink target, Xcode's `version.plist`).
2. **The signature**, through `CuaPreflight.verifySignature`, which uses `SecStaticCode` on
   the file and runs nothing. This is the strongest cheap signal available: it distinguishes
   a real signed `cua-driver` from an ad-hoc local build and from a file somebody planted at
   that path, and it is exactly the check that decides whether the lane may execute at all.
   Cached on the resolved path with its size and modification time, so a replaced binary is
   re-checked and an unchanged one is checked once — it costs 0.32–0.39 s on an 82 MB binary,
   a fifth of the poll interval, which is affordable once and not every two seconds.
3. **What PRO-0044's preflight already established**, read from the memoised `CuaLaneReport`
   rather than re-derived. When preflight has not run, that is reported as `unconfirmed`
   with a sentence saying when it will be — on the first delegated step.

Three things this buys, and they are the point:

- **No new switch, no new bound, no new backoff.** An earlier draft of this spec invented an
  opt-in environment variable, a 1.5 s deadline, a `[2, 10, 60, 300]` backoff and an
  exit-code classifier for `cua-driver doctor`. The out-of-family review killed all of it,
  correctly, on two grounds: an environment variable names a tool but does not pin its
  identity, so it is a weaker gate than the signature check PRO-0044 already ships; and a
  timeout budget for a CLI nobody here has ever run is a guess that fails closed forever
  once the backoff climbs. The design that spawns nothing has neither failure.
- **The health verdict is structured, not sniffed.** Preflight asks the driver a `health`
  verb over its transport and reads `ok` plus a reason. An exit-code classifier would have
  reported `usable` for a driver that exits zero while printing that its permissions are
  unhealthy, which is the exact failure this item exists to prevent.
- **`doctor` cannot be a prompt-injection surface.** `proctor_doctor` is the first call the
  Proctor skill tells a model to make. Nothing from the driver's free text reaches its
  output: the report carries Proctor's own sentence, the preflight stage that failed
  (`presence`, `signature`, `version`, `capabilities`, `grants`), the version Proctor
  parsed, the vocabulary entries it recognised, and the driver-reported grants as the
  booleans `CuaLaneReport` already holds — all structured values Proctor produced or parsed.
  A driver's message is not passed through, so a hostile or merely verbose one cannot write
  into the first tool result a model reads.

What it costs, stated plainly: on a machine where the lane has never been used, `doctor`
reports the driver as present, correctly signed, of an unknown version and unknown health.
That is a weaker answer than running it, a stronger one than a bare stat, and it says
exactly which act turns it into a full answer.

### 2. What the policy block may say

Answered in the shape section: mode, counts, token liveness, jail shape, audit posture;
never a member, a path, a key id or a token — and described as a convention rather than a
boundary, because `proctor_policy status` is ungated and the gate's refusals already name
bundle ids. The discipline that makes it hold is testable rather than aspirational: **the
acceptance test encodes the block from a policy built with known bundle ids, roots and a
scoped token, and asserts none of those strings appear in the encoded bytes**, so a future
field that leaks one fails a test rather than passing a review.

### 3. The agent and a login shell can honestly disagree, and the disagreement is the output

A launchd agent inherits no login shell's `PATH`. `scripts/doctor.sh` runs in one. For any
tool, four things can be true, and the shell doctor names which:

| The login shell finds it | Proctor's explicit search list finds it | What the shell doctor says |
|---|---|---|
| yes | yes | present, and the agent sees it |
| **yes** | **no** | **present for you, invisible to the agent** — the launchd `PATH` problem, named, with the path it found and the list it is missing from |
| no | yes | the agent sees it; your shell does not |
| no | no | absent |

The second row is the point. It is the failure that produces "but it *is* installed", it is
diagnosable only by comparing paths, and it needs no talking to the agent — the shell doctor
knows what its own `PATH` found and it knows Proctor's list, so the disagreement is computed
locally. No IPC, no socket, no dependency on the agent running, which is the property that
makes `doctor.sh` worth having at all.

### 4. One search order, in one language, with a test that fails on drift

The shell copy is **generated, not advisory.** A single Swift definition — the common tool
directories plus each tool's binary name and companions — renders a shell fragment that
`scripts/doctor.sh` sources. The generated file is committed, so the script works from a
fresh clone with nothing built, and a test renders the fragment from the Swift definition
and compares it to the committed file, so **the build goes red the moment they disagree**.
The file states at the top that it is generated and how to regenerate it.

Two things stay out of it on purpose: the developer-directory route for `simctl`, which is a
different search shape rather than a directory list and is small enough to state once in
each language with a comment naming the other; and anything about usability — the shell
doctor reports presence and disagreement and makes no claim about whether a lane is healthy.

## Acceptance criteria

Each clause is one thing that must be true, and each is provable by a Swift test.

1. **Every located tool has a row.** `tools` carries `obscura`, `simctl`, `cua-driver` and
   `maestro` in a fixed order, present or absent, with `browser-use` appearing when and only
   when the operator's second-lane variable names it — the existing invariant that the
   string never appears in a tool result with the lane off is preserved.
2. **`available` still means what it meant.** An executable regular file at a searched path;
   a directory carrying the execute bit is still not a tool; a complete install still wins
   over an earlier incomplete one.
3. **`proctor_doctor` spawns no process.** Proved at the source level, the way PRO-0048
   proves no `shutdown` argument is ever constructed: no process is created on the doctor
   path, and no tool-call parameter reaches one.
4. **Usability is three states over an evidence ladder.** A tool whose presence is sufficient
   reports `usable`/`presence` when found and `unusable`/`absent` when not. A located tool
   never reports `evidence: none`.
5. **The driver's row reports its signature.** Present and correctly signed reports
   `evidence: signature` with `usability: unconfirmed` and a detail naming version and health
   as the parts not yet established; present and ad-hoc, unsigned or wrongly signed reports
   `unusable` naming which of those it is.
6. **The signature verdict is cached on identity, not on time.** Re-checked when the resolved
   path's size or modification time changes, reused otherwise, and never treated as
   authorisation — preflight re-checks before it executes.
7. **An established lane report is surfaced, not re-derived.** With a memoised
   `CuaLaneReport`, the row reports its version, `evidence: selfReport`, and `usable`; the
   failing stage becomes the row's reason when preflight refused.
8. **No driver text reaches the report.** Given a lane report whose driver-supplied strings
   contain instruction-shaped text, none of it appears in the encoded doctor output.
9. **A version names its route through `evidence`.** Maestro's comes from the install path;
   Xcode's accompanies the `simctl` row, read from the root-owned `version.plist` with
   nothing executed; a tool with neither route reports no version rather than a guess.
10. **Lanes report tri-state with a fail-closed boolean.** `mac`, `browser`, `ios` and `cua`
    each carry `state`, a derived `available` true only for `ready`, the tools they require,
    and one blocker line per reason. An `unconfirmed` required grant makes the mac lane
    `unconfirmed`, not `unavailable`.
11. **`ready` is untouched.** A machine with the grants in place but no Obscura, no Xcode, no
    `cua-driver` and no Maestro still reports `ready: true` with no new blocker.
12. **The policy block carries no rules.** It reports mode, three counts, token liveness,
    jail shape and audit posture; a test encodes it from a policy built with known bundle
    ids, roots and a scoped token and asserts none of those strings appear in the bytes.
13. **The two search orders cannot drift.** A test renders the shell fragment from the Swift
    definition and fails when it differs from the committed file.
14. **The shell doctor reports the disagreement.** Given a tool found on the login `PATH` at
    a directory outside Proctor's search list, it says so and names both paths rather than
    reporting a plain success.
15. **The wire stays compatible.** Every new field is optional; a report encoded here decodes
    against the previous model; `obscuraAvailable` and `obscura` still agree with the
    `obscura` row.

## Non-goals

- **Not re-deriving what `CuaPreflight` establishes**, and not spawning the driver to fill in
  a health report.
- **Not touching `Sources/ProctorUI`.** PRO-0036 renders this shape and is sequenced after.
- **Not changing what `ready` means.** An unwritable audit trail is reported in the policy
  block and does not make the agent unready; that belongs to PRO-0005 and PRO-0013.
- **Not narrowing `proctor_policy status`**, and not claiming the policy block is a boundary.
- **Not deciding the native planes' future** — that is PRO-0051. This reports both lanes.
- **Proctor still installs nothing**, and no install command appears in a tool result.

## Assumptions recorded in place of questions

- `[Operations]` `proctor_doctor` spawns nothing at all. *(a health check must not be a side-effect channel, and the review killed every invented budget)*
- `[Operations]` The driver's usability comes from a signature read plus PRO-0044's memoised report. *(the code exists; a second probe would be a second answer)*
- `[Operations]` The signature verdict is cached on path, size and modification time. *(0.32–0.39 s on a large binary is too much to repeat every 2 s)*
- `[Data & scope]` The `cua` lane row appears whether or not the lane is selected. *(readiness for it is the question this item exists to answer)*
- `[Data & scope]` Maestro absent leaves the iOS lane available. *(deep links work without it; PRO-0049 owns flows)*
- `[Compliance]` The policy block reports counts, and is described as a convention rather than a boundary. *(a count cannot name an app; `policy status` is ungated anyway)*
- `[Operations]` The generated shell fragment is committed. *(the shell doctor must work from a fresh clone with nothing built)*
- `[Operations]` The `simctl` developer-directory route stays hand-written in both languages. *(a different search shape, too small to generate, cross-referenced by comment)*

*If any of these are wrong, correct it inline in this file and re-run `/triage PRO-0050` before the planner picks this up.*

## Out-of-family review — grok-4.6, `xhigh`, 2026-08-15

Five findings, three adopted, one adopted in part, one rejected with a reason. The review
changed the design rather than decorating it: the spawning half of the first draft is gone
because of it.

| # | Severity | Finding | Disposition |
|---|---|---|---|
| 1 | High | The proposed opt-in environment variable is a *parameter* boundary, not an *execution* one: it names a tool without pinning its identity, so a replaced binary at the same path is executed on the next poll. | **Accepted.** The whole invented probe is deleted; identity is pinned by PRO-0044's signature check, which this item reads and caches on path identity. |
| 1b | High | The spawned child's descriptor and process-group hygiene is unspecified, so the prize is the agent's sockets and audit handles rather than its grants. | **Accepted as child work.** No longer this item's code — nothing here spawns — but it is true of PRO-0044's shipped client, and it is recorded below. |
| 2 | High | An unmeasured 1.5 s bound plus a climbing backoff fails the lane closed forever on a driver that is merely slow, and an exit-code classifier reports `usable` for a driver that exits zero while printing that it is unhealthy. | **Accepted.** No bound, no backoff, no exit-code classification: the health verdict comes from preflight's structured `health` reply. |
| 3 | Medium | Four fields (`available`, `usability`, `evidence`, `versionSource`) make illegal states representable, and `evidence: none` on a located file reads as knowing nothing about a file you found. | **Adopted in part.** `versionSource` is dropped and derived from `evidence`; `evidence` becomes an ordered ladder whose floor for a located tool is `presence`. A single tagged union was not adopted: `available` is a shipped field and must keep its meaning. |
| 4 | Medium | Counts leak at the extremes; and `proctor_doctor` already attaches the full policy status, so withholding is pointless. | **Split.** The leak-at-the-extremes half is **accepted** and written into the spec as an honesty note. The second half is **rejected on fact**: `SessionDoctor` today carries no policy key at all — the claim describes code that does not exist. |
| 5 | Medium | The child's stdout is prompt injection on the first tool call a model makes, and "never instructions" binds Proctor's control flow rather than the model's. | **Accepted, and it is the best finding of the five.** No driver-supplied text reaches the report; only Proctor's own sentence, the failing stage, and values Proctor parsed. Clause 8 tests it. |

## Child work found

1. **`proctor_policy` action `status` is ungated and returns the full allow, block and
   sensitive lists, the filesystem roots and the audit path.** This item keeps rules out of
   `doctor` as a convention; that convention is not a boundary while `policy status` answers
   freely. Someone should decide whether that tool narrows.
2. **PRO-0044's delegated child inherits the agent's descriptors and process group.**
   `CuaClients` sets only `standardInput`, `standardOutput` and `standardError`; any other
   descriptor without close-on-exec is inherited, and with no separate process group a
   `terminate()` does not reach grandchildren. Belongs to PRO-0044 or PRO-0051.
3. **PRO-0049 should consume the `maestro` row and the iOS lane's note** rather than probing
   for Maestro a second time.
4. **`cua-driver`'s install layout is unverified here.** The documented layout is a
   `~/.local/bin/cua-driver` symlink into `~/.cua-driver/releases/<version>/`, which would
   make its version readable without execution the way Maestro's is. Nothing on this machine
   can confirm it, so the `installPath` route is not claimed for the driver.
5. **Nothing in this spec was measured against a real `cua-driver`.** Its rows are tested
   against fixtures and the absent path only.

## Progress — 2026-08-15

Built on `ai/pro-0050` in `.worktrees/PRO-0050`. **`swift test` 1101 → 1158 in 128 suites, all
green.** 57 new tests: 36 in `ProctorCoreTests/ToolchainTests.swift` (the deciding half), 21 in
`ProctorAgentTests/ToolchainDoctorTests.swift` (the wiring, the signature cache, the
spawn-free clause, and three that read this actual machine).

### What changed while this was in flight, and it changed the design

**PRO-0044 merged as `d65dc1e` between this item being queued and being triaged**, so the
brief's instruction not to build against its seam no longer applied. The worktree was rebased
onto it and the design got smaller: `CuaDriverTool`, `CuaVersion`, `CuaPreflight` and
`CuaLaneReport` already existed, `CuaPreflight` already reversed the never-execute rule
narrowly behind a signature check pinning `com.trycua.driver`, and `CuaLaneReport`'s own doc
comment already said it was "for the run record **and for `proctor_doctor`**". This item
surfaces what that establishes rather than building a second probe.

### Clause → test

| # | Clause | Test |
|---|---|---|
| 1 | Every located tool has a row, in one order; browser-use only when named | `everyToolHasARow`, `browserUseStaysBehindItsSwitch` |
| 2 | `available` still means an executable regular file at a searched path | unchanged, and `BrowserLaneWiringTests` still holds it |
| 3 | The doctor path creates no process | `doctorPathSpawnsNothing` (source scan, widened to `posix_spawn`, `NSTask`, `/bin/sh`, `popen`) |
| 4 | Three states over an evidence ladder; a located tool is never `evidence: none` | `locatedToolAlwaysHasEvidence`, `presenceIsEnoughForOneShotTools` |
| 5 | The driver's row reports its signature | `signedDriverIsUnconfirmed`, `badlySignedDriverIsUnusable`, `adhocDriverIsUnusable` |
| 6 | The verdict is cached on file identity, not time | `verifiesOnce`, `replacedFileIsRechecked`, `absentFileIsNotChecked` |
| 7 | An established lane report is surfaced, not re-derived | `laneReportIsSurfaced`, `refusedLaneReportsItsStage` |
| 8 | No driver text reaches the report | `noDriverProseOnTheWire`, `unknownGrantKeysAreDropped`, `noDriverProseInARow` |
| 9 | A version names its route through `evidence` | `installPathVersionIsEvidenced`, `homebrewTargetParses`, `xcodeVersionWithoutRunningAnything` |
| 10 | Lanes are tri-state with a fail-closed boolean | `lanesAreReported`, `laneBooleanIsDerived`, `readyIsAlwaysDerived`, `unconfirmedGrantIsNotADeadLane` |
| 11 | `ready` is untouched by every tool and lane | `readyIsUntouchedByTheToolchain` |
| 12 | The policy block carries no rule | `postureLeaksNothing`, `postureIsCarried` |
| 13 | The two search orders cannot drift | `shellFragmentMatchesTheCommittedFile`, `shellDoctorSourcesTheGeneratedFile` |
| 14 | The shell doctor reports the disagreement | verified live (below); `fragmentContents` guards its inputs |
| 15 | The wire stays compatible | `wireStaysCompatible`, `obscuraFieldsAgreeWithItsRow` |

### Verified against this machine, not only against fixtures

- `scripts/doctor.sh` run for real: Obscura and browser-use found in `~/.local/bin`, Maestro at
  `/opt/homebrew/bin/maestro`, `simctl` with **Xcode 26.6**, `cua-driver` absent.
- The disagreement row proved by planting a binary on `PATH` outside Proctor's search list: it
  reports "found at …, which the agent cannot see" and names both. **Run under `/bin/bash`
  (bash 3.2) as well as bash 5**, because the shell doctor's whole point is a machine with
  nothing installed.
- `ToolchainOnThisMachineTests` runs the real probes: Maestro's version off the install layout,
  Xcode's off the root-owned plist, and a full report with four lanes and a posture.

### What a test here cannot reach

**No claim in this item was measured against a real `cua-driver`.** It is not on this machine,
so its rows are proved against constructed facts and the absent path. The signature verdict was
timed against an 82 MB binary that *is* here (0.32-0.39 s), which is what the cache is sized
for, but the driver's own preflight behaviour is inherited from PRO-0044 rather than re-proved.

### Two things found on the way

`TakeoverWiringTests` reddened once in a full run and passed 3/3 in isolation, reporting a
different wrong value each time (0, then 2). That is PRO-0053, already allocated, and no file
of its is in this diff.

The changelog entry was written through `/create-luke-content` (format `marketing`) and passes
its lint clean on the hard checks.
