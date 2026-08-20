# PRO-0023: Offer to install Obscura when it is missing

**ID:** PRO-0023
**Status:** Merged
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** docs/plans/plan-PRO-0023.md
**Branch:** ai/pro-0023 (worktree `.worktrees/PRO-0023`)

## Feature description

Verbatim brief: `docs/features-to-triage/24-offer-to-install-obscura.md`. PRO-0020 taught
Proctor to recognise a browser target and hand the page to Obscura. It does that whether or
not Obscura is on the machine, so a model can be handed a command that does not exist —
worse than no advice, because the handoff reads as an instruction from a tool that knows what
it is talking about. `proctor_doctor` reports what Proctor itself needs and says nothing about
the tool Proctor routes work to. And the status window, which already walks a person through
two permission grants, says nothing about a missing helper with a much easier fix.

This extends PRO-0020's object rather than adding a second one.

## Triage — 2026-08-15

### The decision the brief asked for: what "offer to install" may do

**Proctor never installs anything, and the shell commands that would install it never appear
in a tool result. They exist on one surface only — the status window, where a person is
present — and Proctor's part is the clipboard, the project page, and a re-check afterwards.**

Three readings were live. A tool verb (`proctor_install`) is ruled out by the brief. A button
in the status window that performs the install is the convenient reading, and it is rejected.
The third — detect, explain, hand over the commands as data — is taken, but with a boundary
the first draft of this spec did not have and the out-of-family review found (below): *data
in an MCP result is an action surface*. A model holding a shell that is handed
`curl … | tar …` will run it, which defers the fetch-and-execute rather than avoiding it, and
strips out the one thing that would have made a person hesitate. So the tool surfaces say
that Obscura is missing and that the person driving has to install it; the commands
themselves live in the app.

Why not the button, in the order the reasons weigh:

1. **There is no install to automate that is not "fetch an unsigned binary over the network
   and put it on `PATH`".** Checked rather than assumed: `brew info obscura` reports no such
   formula, and the project's own macOS instructions are a `curl -LO` of an
   architecture-specific tarball from GitHub Releases, extracted to **two** executables
   (`obscura` and `obscura-worker`) that have to stay in the same directory. A button doing
   that inside a launchd agent already holding Accessibility and Screen Recording is remote
   fetch-and-execute in the most privileged process on the Mac.
2. **Proctor cannot check what it downloaded.** No signature, no notarisation on the
   artifact, and nothing it could pin that it would also be able to refresh. A compromised
   release or a hijacked DNS answer becomes code running as the user and Proctor has no way
   to notice. Leaving the command with a person leaves that judgement where it can be made.
3. **The app's existing answer to a missing permission is *Open Settings*** — it takes you to
   where the act happens and never performs the act. The review objected that a Settings deep
   link retrieves no third-party code and so is not comparable to a tarball install. That is
   the point: the safe precedent is the conservative one, and the asymmetry argues for
   inheriting it rather than against.
4. **What a button buys is one paste**, on a three-line install a person runs once.
5. **It does not foreclose the button.** Detection that works from launchd, the correct
   commands for this Mac's architecture, and a re-check that confirms it worked are all built
   here. What is left is the execution and the consent around it, which deserves its own
   decision rather than arriving as a side effect of this one.

### The second decision, which the brief left open: detection reads the filesystem and never runs the binary

`obscura --version` is one of the two methods the brief names. It is not the one taken.
Detection is `isExecutableFile` over an ordered candidate list, the shape
`shortcutsCLIAvailable` already uses for `/usr/bin/shortcuts`, and the shape the brief asked
to match.

The reason is not cost. The candidate directories that make a launchd agent's lookup work —
`~/.local/bin`, `~/.cargo/bin`, `/opt/homebrew/bin` — are **user-writable**. Executing
whatever answers to that filename, inside a process holding Accessibility, on the strength of
a name in a directory anything can write to, is a code-execution path Proctor would be opening
on its own initiative. Reading a mode bit runs nothing. It is the same argument as the
decision above, one layer down, and the two should not disagree.

The review pressed the obvious counter: Proctor refuses to install unsigned bits and then
trusts any executable file with the right name. Half of that is answered — **the genuine tool
is unsigned**, so a signature check would reject the real one and prove nothing — and half is
conceded and written down: a file planted at one of those paths makes Proctor report
"available" for something that is not Obscura. The consequence is bounded by Proctor never
running it. What Proctor reports is *presence of a name at a path*, and the spec says so in
those terms rather than claiming the tool is verified.

The cost is that Proctor learns no version. That is a real gap for PRO-0024, which may want
to gate a lane on a capability that arrived in a particular release; the argument is recorded
so that item can re-open it deliberately. If it does, a version probe belongs behind an
explicit operator opt-in rather than on by default.

## Scope

**In.** A pure locator and absence description in `ProctorCore`; an agent-side cached probe;
one new optional field on `BrowserHandoff`; three new fields on `DoctorReport`; the Obscura
row, callout and buttons in the status window; README, output schema and CHANGELOG.

**Out.** Installing, downloading, unpacking or executing anything. Shell commands anywhere in
a tool result. Any new tool verb. A version probe. A second browser lane (PRO-0024). Any
change to the boundary PRO-0020 drew, to planes, settling, hashing, or the audit trail.

## Behaviour

### Detection

`ToolLocator.locate(binary:companions:pathEnvironment:home:extraDirectories:isExecutable:)` in
`ProctorCore` is pure: it takes the `PATH` string the process actually inherited, the home
directory, the extra directories, and a predicate. It returns a `ToolPresence` — `tool`,
`available`, `path`, `searched`, `missingCompanions`.

Search order is `PATH` entries first, in their own order, then the explicit list:

| | Why it is on the list |
|---|---|
| each `PATH` entry | Whatever launchd gave the agent — usually `/usr/bin:/bin:/usr/sbin:/sbin`. |
| `/opt/homebrew/bin` | Apple Silicon Homebrew. |
| `/usr/local/bin` | Intel Homebrew, and where most manual installs land. |
| `~/.local/bin` | Where Obscura is installed on this machine, verified. |
| `~/.cargo/bin` | Obscura is Rust; `cargo install` is a real path to it. |
| `/opt/local/bin` | MacPorts. |

Candidates are made absolute (`~` is expanded from the supplied home and never appears in
`searched`) and deduplicated, so a `PATH` entry repeating an explicit directory is checked and
reported once.

`searched` exists because "installed but Proctor cannot see it" is the failure a launchd agent
actually produces, and it is only diagnosable if Proctor says where it looked.

**`companions` catches a half install.** The release archive ships `obscura` and
`obscura-worker`, and the project says they must stay in the same directory; the parallel
`scrape` command needs the second one. So a hit also checks for its siblings beside it and
reports `missingCompanions` when they are absent. Availability stays true — `fetch` and
`serve` work without the worker — but a state that will fail one subcommand and no others is
worth naming rather than discovering.

**What a presence answer claims, and what it does not.** It says a file with that name, marked
executable, exists at that path, as seen from a launchd agent's environment. It is not a claim
about the shell the reader will type into: a model's login shell has a different `PATH`, so
Proctor can report missing where the reader's terminal finds it, and the reverse. The absence
text says this in words and points at `proctor_doctor`, which carries the searched list, so
the disagreement is resolvable instead of confusing.

### Caching, and when it expires

The agent holds one probe result with a timestamp. **A present answer is cached for 300
seconds; an absent answer for 15.** The state somebody is actively changing is the one worth
re-reading often, and re-reading costs six `stat` calls; an uninstall mid-session is not a
thing that happens, while an install mid-session is exactly what this feature provokes. The
short absent side is what makes the recommendation come back on its own after the person
installs Obscura, without restarting the agent.

A `proctor_doctor` call always re-probes **and writes the result through the cache the
handoffs read**, so after a doctor call the two surfaces cannot disagree. The app's *Re-check*
button drives exactly that path.

The clock is injected. The cache belongs to the `Session` instance and is created in its
initialiser rather than reached for as a shared singleton, so a test drives its own and leaves
nothing behind.

### Surface 1 — the handoff object

`BrowserHandoff` gains one optional field, `toolUnavailable: ToolAbsence?`, named to sit
beside the `urlUnavailable` PRO-0020 already has, because it is the same kind of fact: a
reason the recommendation is not what it would otherwise be.

`ToolAbsence` carries `tool`, `missing` (one sentence, including that this is what a launchd
agent could see), `docs` (the project page) and `askThePerson`. It carries **no shell
commands**, which is the review's finding folded in. `askThePerson` states a capability rather
than a promise — Proctor has no way to install this, so the person driving has to, and the
Proctor status window has the command ready to copy — because a permanent "Proctor will never
install" written into the protocol would become a lie the day the reader asks for the button.

When Obscura is missing **and the page is one Obscura could open**:

- `toolUnavailable` is present, at both detail levels. It is the reason the recommendation is
  absent, and a brief handoff that merely lacked `use` would be indistinguishable from the
  non-openable case PRO-0020 already defines. There is no brief/full split on this object; the
  evidence (the searched list) lives on `proctor_doctor`, which is where a reader who wants it
  should go.
- `use` and `commands` are **absent**. Printing `obscura fetch <url>` on a machine with no
  `obscura` is what the brief objects to.
- `url` **stays**. The address is a fact about the page, not a recommendation, and it is what
  makes the advice actionable the moment the install finishes. The gap is short by design: the
  absent answer expires in 15 seconds, and a `proctor_doctor` call closes it immediately, so
  the next handoff carries the full recommendation without a restart.
- `boundary`, `continuity`, `evidence`, `caveats` and `urlUnavailable` are unchanged. Which
  half of a browser window is Proctor's does not depend on what happens to be installed.

When Obscura is missing and the page is **not** one Obscura could open — every scheme that is
not `http`/`https`, which PRO-0020 already handles uniformly through `isWebScheme` — there is
no `toolUnavailable`: there was no recommendation to repair, and naming a missing tool that
would not help this page anyway is noise.

When Obscura is present, the object is byte-identical to what PRO-0020 emits today.

### Surface 2 — `proctor_doctor`

Three fields, each doing one job:

- `obscuraAvailable: Bool`, sitting beside `shortcutsCLIAvailable` — the flat, greppable
  answer, in the shape the brief named.
- `obscura: ToolPresence?` — the evidence: the path it was found at, everywhere it looked, and
  any missing companion. The path is on the wire because a reader whose own shell disagrees
  with Proctor can only settle it by comparing paths.
- `obscuraUnavailable: ToolAbsence?` — the same object the handoff carries, present only when
  it is missing, so there is one description of this situation in the codebase rather than two.

`ready` and `blockers` are untouched. The review objected that anything keying off `ready`
skips the signal; that is the intent. `ready` means Proctor can do its own job, and Proctor
drives native applications without Obscura. A health report that failed on an advisory tool
would be lying about what is broken. The signal is a top-level boolean precisely so it does
not need to be dug out of `blockers`.

### Surface 3 — the app

In the *Background agent* card, beside the Shortcuts CLI row: `Obscura — available` /
`not installed`, and when a companion is missing, a row saying so.

When it is missing, a callout under the rows — the component the ad-hoc-signature and Secure
Event Input warnings already use — saying that Proctor recommends Obscura for browser pages,
that it is not installed, and that Proctor does not install it. Three buttons: **Copy install
commands**, **Open the project page**, **Re-check**. The last closes the loop, and works
because `proctor_doctor` re-probes and writes through.

### The install commands, which exist only here

Architecture-specific, because the release archive is. The app reads the **hardware**
architecture (`hw.optional.arm64` via `sysctlbyname`), not the process's, so a Proctor running
under Rosetta still names the Apple Silicon build. `ProctorCore` takes the answer as an enum
and produces the commands, so both branches are testable without a second machine.

```
curl -LO https://github.com/h4ckf0r0day/obscura/releases/latest/download/obscura-aarch64-macos.tar.gz
tar xzf obscura-aarch64-macos.tar.gz
mkdir -p ~/.local/bin && mv obscura obscura-worker ~/.local/bin/
```

with `obscura-x86_64-macos.tar.gz` on Intel. The third line is there because the archive ships
two executables the project says must stay together, and because a tarball extracted into a
download folder is not an install. The destination is `~/.local/bin`, which is on the
candidate list above and is where the verified install on this machine lives.

The URL is unpinned (`latest/download`) and carries no checksum, which the review flagged.
That is deliberate and stated rather than fixed: a version and a hash Proctor cannot refresh
would go stale and start instructing people to install an old build, which is a worse failure
than an unpinned link to the project's own current release. The project page is named as the
authority beside it, and the commands are a convenience copied from that page, not a
substitute for it.

## Acceptance clauses

1. The locator searches `PATH` entries in order first and the explicit directories after, and
   reports the path it found; a launchd `PATH` of `/usr/bin:/bin:/usr/sbin:/sbin` still finds
   a Homebrew install at `/opt/homebrew/bin/obscura`.
2. `~/.local/bin` and `~/.cargo/bin` are expanded from the supplied home; no candidate in
   `searched` begins with `~`.
3. Nothing found: `available` is false, `path` is nil, and `searched` lists every candidate in
   order, deduplicated — a `PATH` entry equal to an explicit directory appears once.
4. A candidate that exists but is not executable is not a hit.
5. `obscura` found without `obscura-worker` beside it stays `available` and reports
   `missingCompanions: ["obscura-worker"]`; found with it, `missingCompanions` is empty.
6. `ToolAbsence` names the project page, says Proctor cannot install it, says the answer is
   what a launchd agent could see, and contains **no shell command text** anywhere in any of
   its fields.
7. Install commands are architecture-specific (`aarch64` vs `x86_64` archive) and place both
   executables in one directory that the locator searches.
8. Obscura missing, page openable: the handoff carries `toolUnavailable`, omits `use` and
   `commands`, keeps `url`, and leaves `boundary` and `continuity` unchanged.
9. Obscura present: the handoff is exactly what PRO-0020 emits — no `toolUnavailable` key.
10. Obscura missing, page not openable: no `toolUnavailable`, and the rest of the disclosure is
    unchanged.
11. Both detail levels carry the same `toolUnavailable`.
12. `proctor_doctor` reports `obscuraAvailable`, a `ToolPresence` carrying path and searched
    list, and `obscuraUnavailable` only when missing; `ready` and `blockers` are identical
    whether Obscura is there or not.
13. A `proctor_doctor` call re-probes and writes through: a handoff taken immediately after it
    reflects the doctor's answer rather than the previous cached one.
14. Handoffs read the cache — several handoffs inside the window cost one probe — and an absent
    answer expires sooner than a present one, under an injected clock.
15. `proctor_apps` attach on a browser with Obscura missing carries `toolUnavailable` through
    the encoded JSON, end to end.
16. The advertised tool surface gains no verb, and the `proctor_doctor` output schema documents
    the three new fields.

## Assumptions recorded in place of questions

- `[Decision]` **Proctor never installs, and shell commands never enter a tool result.**
  Argued above. If the reader wants the button, this spec is what it is built on.
- `[Behaviour]` **Detection never executes the binary**, so there is no version, and a planted
  file with the right name would be reported as present. Both stated rather than mitigated;
  the genuine tool is unsigned, so a signature check would reject the real one.
- `[Behaviour]` **A missing Obscura is not a blocker.** `ready` stays true.
- `[Behaviour]` **`url` survives a missing tool but `commands` does not.** The URL is a fact;
  the command is advice that would fail today.
- `[Scope]` **The install commands are static data in the source, unpinned, not fetched.**
  Trade-off argued above. If the project changes how it ships, this is a line to edit — the
  same cheapness the browser catalogue was designed for.
- `[Scope]` **Two flat booleans is the right shape for two tools.** A third is the point at
  which `shortcutsCLIAvailable` / `obscuraAvailable` should become a `tools: [ToolPresence]`
  array. PRO-0024 is the item that would add the third, so it makes that call.
- `[Cost]` **300s present / 15s absent** are chosen, not measured; a probe is six `stat` calls,
  so the absent side can afford to be short.

## Where PRO-0024 lands

PRO-0024 adds a second lane and extends this same object. Left for it deliberately:

- `ToolLocator.locate` takes a binary name, its companions and extra directories, so
  `browser-use` is a call with different arguments rather than a second locator, and its
  answer is the same `ToolPresence`.
- `ToolAbsence` is keyed by `tool`, so a second tool's absence is a second value of an existing
  type. The handoff names **one** lane at a time, so `toolUnavailable` stays singular:
  whichever lane the recommendation chooses is the tool whose absence is described.
- All three gate readings in PRO-0024's brief are expressible on this: detection-gated is
  `ToolPresence.available` on the second tool. This item takes no position on which to pick.
- The version question, and the flat-booleans-to-array question, are PRO-0024's to settle.

## Child work found, not built here

- **The Shortcuts CLI row in the status window renders under "Optional — asked for per app"**,
  text belonging to the Automation grant and wrong for a CLI. Pre-existing; this item does not
  add to it, because Obscura is reported as a tool rather than appended to `grants`.
- **`scripts/doctor.sh` runs without the agent and does not know about Obscura.** The same
  probe in shell duplicates the search order in a second language, so it is a separate item.
- **A model told "Obscura is missing" may install it anyway.** Withholding the commands from
  the tool surface removes Proctor's instruction to do so; it cannot remove the model's own
  reach. Whether Proctor should say anything about that is a policy question, not this item's.

## What a test cannot reach here

Machine-witnessable from `swift test`: every clause above, against an injected predicate,
injected clock and the existing fake AX engine.

Not witnessable here, and reported as code-complete rather than proven: that the status window
renders the Obscura row and the callout, that the three buttons do what they say, that
`sysctlbyname("hw.optional.arm64")` reports this Mac's hardware correctly under Rosetta, and
that the printed commands install Obscura on a machine that lacks it — the first three need a
window server or a second machine, and the last would mean running the install, which is the
one thing this spec says Proctor does not do. `swift test` has no window server, and Obscura is
web-only so it cannot see a native surface either.

## Out-of-family review

Spec reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15, no downgrade.
It found ten defects. Five changed the design and are folded in above:

1. **Install commands in an MCP result are an action surface**, not inert data — a model with a
   shell runs them, deferring the fetch-and-execute rather than avoiding it. The commands left
   the tool surfaces entirely and now exist only in the app. This is the finding that changed
   the feature.
2. **The archive's second executable was unmodelled**, so a half install would have reported
   clean. `companions` and `missingCompanions` exist because of this.
3. **The detector and the reader are not the same program**: a launchd `PATH` is not the
   reader's shell `PATH`. The absence text now says what the answer is a claim about, and the
   found path is on the wire so a disagreement can be settled.
4. **`proctorWillNotInstall` froze a policy into the protocol** and would become a lie the day
   the button ships. Replaced with a capability statement.
5. **A doctor probe that does not write through the handoff cache lets the two surfaces
   disagree.** Now explicit, and clause 13.

Three were answered rather than adopted, with the answer written into the spec: `ready` should
stay true because Proctor works without Obscura; a signature check would reject the genuine
tool because it is unsigned; and *Open Settings* is the right precedent precisely because it
runs no third-party code. One — that the non-`http(s)` rule reads as a single `chrome://`
special case — was a wording problem, since `isWebScheme` has always covered every scheme
uniformly. The last, that an unpinned URL with no checksum sits oddly beside a refusal to
install unverified bits, is conceded and stated as a trade-off rather than fixed.

## Progress — 2026-08-15

Built on `ai/pro-0023` in `.worktrees/PRO-0023`. **567 tests / 69 suites green** (544/66 at
`cae5f80`), `swift build` clean; the three warnings the build prints are pre-existing in
`ProctorUI` and are not in the code this change touches.

**What shipped.** `Sources/ProctorCore/ToolPresence.swift` (the pure locator, `ToolPresence`,
`ToolAbsence`), `Sources/ProctorCore/ObscuraTool.swift` (the catalogue entry, the absence
sentences, and the app-only install commands), `BrowserTarget.withTool` (the handoff
adjustment, pure), `Sources/ProctorAgent/Session/ToolProbe.swift` (the cached probe and the
executable-regular-file predicate), one funnel in `Session` so all five advisory surfaces go
through it, three fields on `DoctorReport` filled from `SessionDoctor`, the schema, and the
Obscura row, callout and three buttons in `MainWindow`.

**Clause → test.** 1-7 → `Tests/ProctorCoreTests/ToolLocatorTests.swift`. 8-11 →
`BrowserHandoffToolAvailabilityTests` in `Tests/ProctorCoreTests/BrowserTargetTests.swift`.
12-16 → `Tests/ProctorAgentTests/ObscuraPresenceWiringTests.swift`, notably
`aDoctorCallWritesThroughToTheHandoffCache`, which is the one that stops the health report and
the advisory describing the same machine differently at the same instant.

`Tests/ProctorAgentTests/BrowserRoutingTests.swift` (PRO-0020's) now injects an installed
probe. Without that its assertions would have depended on whether the machine running the
suite happens to have Obscura, which is exactly the host dependence this feature introduces.

**Not machine-witnessable here.** The status window's Obscura row, its callout and its three
buttons; that `sysctlbyname("hw.optional.arm64")` reads the hardware rather than the process
under Rosetta; and that the printed commands install Obscura on a machine that lacks it. The
first two need a window server or a second machine, the last would mean running the install.
Code-complete and unverified, not proven.

**Reviews.** Spec review and completeness critic both ran out-of-family on `grok-4.6`
(`--effort xhigh --sandbox read-only`), no downgrade. The spec review changed the feature five
ways (see the section above); the plan review changed four more before any code was written:
first-hit-wins became first-*complete*-hit-wins, the probe became a locked class rather than a
struct whose cache forks on copy, the `sysctl` read moved out of the pure target into the app,
and PRO-0020's existing tests were pinned to an injected probe.

**Completeness critic, 2026-08-15 — dispositions.** Nine findings, one adopted, the rest
answered or recorded:

- *Three health fields with no rule for which are null.* **Adopted.** The rule is now stated on
  the type and pinned by an assertion: the presence record is always there, and the absence
  object is there exactly when the boolean is false.
- *A session that only ever drives `chrome://` never learns Obscura is missing.* Answered.
  Window handles only exist after `proctor_apps` attach, and the app-level handoff carries the
  absence, so every session that could reach such a page has already been told
  (`anAppLevelHandoffDisclosesTheAbsence`).
- *`askThePerson` might not point anywhere, and Re-check might be a third surface.* Answered.
  It names the status window and the project page, and Re-check calls `proctor_doctor` over the
  socket, which is the same probe object and the same write-through.
- *`available` is not "will run"* — quarantine, a wrong-architecture thin binary, a broken
  dylib, a worker from another build. Recorded as a limitation rather than mitigated: this
  reports the presence of a name at a path, and the alternative is executing it, which the spec
  argues against at length. A signature check would reject the genuine tool, which is unsigned.
- *A stale present answer outlives an uninstall by five minutes.* Accepted, and asymmetric on
  purpose: the answer somebody is in the middle of changing is the fifteen-second one.
- *The directory list misses nix profiles, mise/asdf shims and keg-only Homebrew.* Real, and
  logged as child work. Adding one is a line in a table, and `searched` plus the launchd
  sentence in `missing` is what makes a false absence diagnosable rather than mystifying.
- *An unreadable directory or a failing stat looks identical to absent.* True; the cost is a
  false absence, and `searched` is again what makes it findable.
- *Readiness ignores all of it.* Deliberate, argued in the spec.
- *No version probe.* Recorded above as PRO-0024's to re-open.

**Child work found here, not built.** Two more search locations worth adding when somebody
hits them (`~/.nix-profile/bin`, version-manager shims, keg-only Homebrew prefixes), and a
split install — `obscura` in one directory, `obscura-worker` in another — which is reported as
a half install today because completeness is judged per directory.
