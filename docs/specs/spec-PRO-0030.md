# PRO-0030: The build says which build it is

**ID:** PRO-0030
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0030.md`
**Brief:** `docs/features-to-triage/31-the-build-says-which-build-it-is.md`

## Feature description

> ### The problem
>
> `AgentBuild.version` is a hardcoded `0.1.0` that has never been bumped. Two
> things depend on it and both are degraded:
>
> - `proctor_doctor` reports `agentVersion`, which tells a reader nothing. Two
>   machines running builds three months apart report the same string.
> - PRO-0027 wanted to detect a stale running agent after an install and could not
>   use a version compare, so it fell back to comparing inode and size across three
>   paths. That works and is shipped, but it works around a fact rather than fixing
>   it.
>
> ### What it should do
>
> Make the version a real identifier of the build that is running, so that
> `agentVersion` distinguishes two builds and a staleness check can ask a direct
> question.
>
> ### The hard parts, named
>
> - **What the identifier should be** is the actual decision. A semantic version
>   from a tag is meaningful to a person and stale between releases. A commit sha
>   is exact and meaningless to a reader. A build timestamp orders correctly and
>   says nothing about content. The likely answer is more than one field, and the
>   spec should say which field answers which question.
> - **It has to be generated at build time, in a way three paths agree on:**
>   `swift build`, `scripts/install.sh`, and `.github/workflows/release.yml`. A
>   version baked by the release workflow and absent from a local build gives every
>   developer machine a null, which is the state we are in now wearing a different
>   hat.
> - **Do not break the release pipeline.** `release.yml` extracts the CHANGELOG
>   section matching the tagged version. Anything here that touches how a version
>   is named has to keep that match working.
> - **PRO-0027's inode+size check should be reconsidered, not automatically
>   replaced.** It answers "is the file on disk different from the file I am
>   running", which a version compare answers only if the version genuinely changes
>   every build. Say which is kept and why.
>
> ### Worth knowing
>
> `docs/specs/spec-PRO-0027.md` and `spec-PRO-0028.md` both record this as child
> work, from the staleness side and the `agentVersion` side respectively.

## The decision: five fields, because the question is five questions

The brief is right that one field cannot do this, and it names three candidates and
the defect of each. The answer is to stop making one string carry several meanings
and to say, per field, what it answers and what it deliberately does not.

| Field | Answers | Says nothing about |
|---|---|---|
| `version` — `0.1.0` | Which **release line** this is, in the same words as the git tag, the CHANGELOG heading and the release asset | Which build. It is stale between releases **on purpose**: it names a release, not a binary. |
| `commit` — `e1f6cbf4fd1c` | Whether this is **the same code** as that. Exact, and the only field two machines can compare without trusting a clock | Anything a person can read. Outside a git checkout it says so rather than guessing. |
| `dirty` — `true` / `false` | Whether the build is that commit, or that commit **plus somebody's edits** | *What* was edited. A dirty build is not identified by its commit and does not pretend to be. |
| `configuration` — `debug` / `release` | Whether this is the **same program**. A debug and a release build of one commit are not interchangeable, and "why is this slow" is answered here | Anything about the source. |
| `builtAt` — a date | Which of two builds is **newer**, and it is the only field that separates two builds of one dirty tree | Content. Two builds a month apart from one clean commit are the same code, and the commit says so. |

One derived string carries the first four to a reader who wants a single thing to
quote:

**`descriptor`** — `0.1.0+e1f6cbf4fd1c`, or `0.1.0+e1f6cbf4fd1c.dirty`, or
`0.1.0+e1f6cbf4fd1c.debug`, or `0.1.0+unknown`. It identifies the **program**;
`builtAt` identifies the **build event**, and they are separate on purpose. Two clean
release builds of one commit share a descriptor because they are the same program, and
a reader chasing "why do these two Macs behave differently" is better served by that
fact than by two strings that differ for a reason that does not matter.

The `+` is not decoration: it is semantic versioning's **build metadata**, which the
standard defines as ignored when comparing precedence. That is exactly this field's
meaning — two builds of one release line are the same release — so a parser that ever
does compare these strings gets the right answer for the right reason.

`DoctorReport.agentVersion` **becomes the descriptor** rather than gaining a
better-informed sibling and keeping its lie. A model that reads only `agentVersion`
— the shape of the complaint in the brief — has to be the one that stops being
misled, or nothing has been fixed.

### When `commit` cannot be resolved it says which kind of cannot

Two sentinels, not one, because they call for different responses and a single
`unknown` hides that:

- **`unknown`** — this is not a git checkout. A source tarball, an unpacked release.
  Expected, and nothing to do about it.
- **`unavailable`** — git is here and could not answer. A broken checkout, a sandbox
  that denied the read. Someone should look, and a single `unknown` would have sent
  them looking for a tarball that does not exist.

## Where each field comes from, and why none of them is a null

`version` is read from `Apps/Proctor/Info.plist` at build time. That file is already
the source `release.yml` trusts for the asset name and for the CHANGELOG match, so
reading it here means the running binary and the release it came from cannot disagree
about the release line — not because two places are kept in step, but because there is
one place.

`commit`, `dirty` and `version` come from build time. `configuration` is a compile-time
constant. `builtAt` is not baked at all: it is **captured once, during process startup**,
from the modification time of the running executable's file.

Both halves of that sentence are load-bearing.

**Why a file's own time rather than a baked constant.** A generated source file changes
whenever its contents change, and a wall-clock timestamp changes on every build, so
every `swift build` and every `swift test` would recompile Core and everything
downstream. Measured on this feature's spike: with content that does not change, a
second build is **0.64s**; a full recompile of this package is **~20s**. That tax would
be paid forever, by everyone, for a field that a file's own metadata already carries.

**Why captured at startup and not read on demand.** The out-of-family review caught
this and it is the sharpest finding of the pass: after an upgrade the *path* holds the
new file while the process is still running the old image. A `stat` at report time would
pair the old build's compiled `commit` with the new file's date — a wrong answer in
precisely the situation PRO-0027 exists for. Captured at startup, it describes the image
that is actually running. This is the same discipline `BuildStamp` already uses, for the
same reason.

**What it actually means, stated plainly:** when the running executable's file was last
written. For a plain `swift build` that is link time. For a packaged bundle it is
assembly-and-sign time, because `scripts/build-app.sh` copies each binary into the
bundle and then re-signs it — measured: `cp` sets the destination's modification time to
the time of the copy. That is the honest answer for a bundle and arguably the better
one, since a cached link can be days older than the build that shipped it.

PRO-0027 rejected modification time and this uses it, which is not a contradiction: it
rejected mtime as the trigger for a **decision**, where a stray `touch` would raise a
banner nobody could clear. Here it is a **report**, and no behaviour keys on it. A
forged date misleads a reader; it cannot make Proctor do anything.

### The one mechanism all three paths already share

`swift build`, `scripts/install.sh` (through `scripts/build-app.sh`) and
`.github/workflows/release.yml` (also through `build-app.sh`) have exactly one thing in
common: **they all run `swift build`.** So the generation hangs off that and nothing
else has to be taught anything. A SwiftPM **build-tool plugin** on `ProctorCore` runs a
prebuild command before every build, which writes the generated constants.

This was **spiked and measured before being specified**, because a mechanism that fails
under SwiftPM's plugin sandbox would cost the whole plan:

- A plain `swift build`, with no `--disable-sandbox` and no flags, ran the plugin and
  produced `commit = "e1f6cbf4fd1c"`, `dirty = true` — a real sha from a real
  repository, on the path the brief says must not be a null.
- **It was measured inside a git worktree**, which is where every runner on this repo
  builds and where `.git` is a 66-byte pointer file to objects outside the package
  directory. The out-of-family review predicted the plugin would fail there and get
  `unknown` on the path developers actually use; it does not, because SwiftPM's plugin
  sandbox restricts writes rather than reads.
- A second build took **0.64s**, because the generator writes the file only when its
  content differs. The freshness costs nothing when nothing moved.

A path with no git — a source tarball, an unpacked release — degrades to
`commit = "unknown"`, `dirty = false`, and **keeps `version`, `configuration` and
`builtAt` real**. That is the whole point of splitting the fields: the failure mode is
one field going honest, never the whole identity going null.

## Whose build is it: the agent's, or the window's

The status window's `Version` row sits inside a card titled **Background agent**, and it
reports what the agent said. That is correctly labelled and it is half an answer: the
window is its own process, from its own copy of the bundle, and PRO-0027 exists because
those two can be different builds for hours without anything saying so.

So the card gains one row for the window's **own** identity, compiled into it. Normally
the two strings match, because both binaries come out of one package in one build. They
differ in exactly one situation — PRO-0027's — and when they do, the difference is now
sitting on screen in words rather than being a thing a diagnosis has to rediscover from
timestamps. PRO-0027's banner says *that* a build was replaced; this says *which two
builds*, which is what a person needs in order to describe the problem to anyone else.

## PRO-0027's inode+size check is kept, unchanged

The brief asks for a decision rather than an automatic replacement. It is kept, and the
reason is not caution — a version compare **structurally cannot** do what `BuildStamp`
does:

1. `BuildStamp` compares **a file on disk** against what is running. A compiled-in
   version cannot be read from a file on disk without executing it, and the case that
   produced PRO-0027 was a UI process that could not ask anything of the bundle that had
   replaced it.
2. It stamps **the art as well as the binary**. A resource-only reinstall replaces a
   picture and leaves every compiled constant identical, so no version scheme could see
   the failure PRO-0027 was actually reported for.
3. On a dirty tree — the developer's normal state — two builds share a descriptor. A
   version compare would be blind in exactly the situation a developer is in most often.

So the two answer different questions and both stay. What changes is that the *diagnosis*
is now readable: when the banner says a different build is on disk, `proctor_doctor` can
say which build the agent is, in words that mean something.

## The release pipeline: one new guard, nothing renamed

Nothing about how a version is *named* changes, so the CHANGELOG extraction keeps
matching. What changes is that `Apps/Proctor/Info.plist` is now load-bearing for the
running binary as well as for the release asset, and a tag that disagrees with it would
now ship a binary that misreports its own release line.

So `release.yml` gains a **consistency check that runs before the build**. It runs first
because failing in seconds is better than failing after a notarisation round trip. Three
things must agree, and the out-of-family review found that both of the obvious ways to
write this check are wrong:

1. **The tag against the plist.** Tags are `v0.1.0` and the plist holds `0.1.0`, so a
   naive equality never passes and a guard written that way fails every release. The
   comparison is the tag against `v` + the plist's version.
2. **A CHANGELOG section that has something in it.** Checking that the heading exists is
   not enough, and neither is the existing `[ ! -s notes.md ]`. **Measured:** a
   `## [0.2.0]` heading immediately followed by the next heading extracts to a
   **one-byte file containing a newline**, which `test -s` calls non-empty. So today's
   fallback never fires for the case it was written for, and the release ships a blank
   notes body. The check requires at least one non-blank line, and the same rule is
   applied where the notes are extracted.

That second one is a live defect in the pipeline as it stands, found by reviewing this
feature rather than by a release going wrong, and fixing it is squarely inside "do not
break the release pipeline".

## Acceptance clauses

1. **A1 — a plain `swift build` produces a real identity.** In a git checkout,
   `BuildInfo.commit` equals what `git rev-parse --short=12 HEAD` reports for this
   package, and `BuildInfo.dirty` agrees with the tree's actual state. Not a
   placeholder, not empty, and not conditional on the release workflow. This holds
   **inside a git worktree**, where `.git` is a pointer file, because that is where the
   work is done.
2. **A2 — no path produces a null, and a missing commit says which kind of missing.**
   Outside a git checkout the generator still emits a compilable identity with
   `commit` exactly `unknown`; where git is present but cannot answer, `unavailable`.
   `dirty` is `false` in both. `version`, `configuration` and `descriptor` stay real,
   and `descriptor` is never empty for any combination of inputs.
3. **A3 — the fields answer the questions the table assigns them.** Two different
   commits give different descriptors; one commit clean and the same commit dirty give
   different descriptors; a debug and a release build of one commit give different
   descriptors; two release builds of one clean commit give the **same** descriptor and
   are distinguished by `builtAt` alone.
4. **A4 — `builtAt` describes the running image, not the path.** It is captured during
   startup rather than read when reported, so replacing the file on disk afterwards does
   not change what a running process reports. It resolves from a named executable's
   modification time, and is `nil` rather than a fabricated date when that cannot be
   read.
5. **A5 — there is one version in the package, not three.** `AgentBuild.version` and
   `ShimVersion.value` are gone as independent constants; the agent, the shim and the
   status window all report the same identity, derived from the same source. No
   forwarding shim is left behind that would let a stale spelling keep compiling.
6. **A6 — `version` and the release pipeline cannot drift.** `BuildInfo.version` equals
   `CFBundleShortVersionString` in `Apps/Proctor/Info.plist`. The release consistency
   check passes a tag that is `v` + that version and fails one that is not; it fails a
   version whose CHANGELOG section is absent **or contains no non-blank line**; and it
   passes a version whose section has real content. The existing extraction still finds
   that section.
7. **A7 — `proctor_doctor` reports the identity and its parts.** `agentVersion` carries
   the descriptor; a structured `agentBuild` object carries `version`, `commit`,
   `dirty`, `configuration` and `builtAt` for a reader that wants a field rather than a
   string. The output schema is updated to match, and the addition is optional on the
   wire so a mismatched agent and shim still decode.
8. **A8 — the build stays cheap.** The generator writes its output only when the content
   differs, so a second run over an unchanged tree leaves the file untouched and forces
   no recompile.
9. **A9 — PRO-0027 is untouched.** `BuildStamp` and its staleness detection are
   unchanged, and every test that pinned them still passes.
10. **A10 — the window can name both builds.** The status window shows the agent's
    identity and its own, so the case PRO-0027 detects can be described rather than only
    flagged.

## Assumptions recorded in place of questions

- `[Operations]` The identifier is five fields plus a derived string, not one.
  *(The brief names three candidates and the defect of each; the defects do not overlap,
  so no one field covers them. `configuration` was added by the out-of-family review:
  a debug and a release build of one commit are not the same program, and "why is this
  slow" is answered nowhere else.)*
- `[Operations]` Generation is a SwiftPM build-tool plugin on `ProctorCore`, because
  `swift build` is the only step all three paths already share. *(Spiked and measured
  before speccing, inside a worktree: a plain sandboxed `swift build` produced a real
  sha, and a no-change second build cost 0.64s. A generated file committed to the repo
  and refreshed by a script was rejected — a fresh clone's `swift build` would then
  carry whatever value was committed, which is today's problem wearing a different hat.)*
- `[Operations]` `builtAt` is captured at process startup from the running executable's
  modification time, not baked and not read on demand. *(Baked, it changes every build
  and recompiles Core and everything downstream, measured at ~20s against 0.64s. Read on
  demand, it reports the replaced file's date while the old image is still running —
  wrong in exactly PRO-0027's situation.)*
- `[Operations]` `builtAt` means "when this executable's file was last written", which
  for a packaged bundle is assembly-and-sign time rather than link time. *(Measured:
  `cp` sets the destination's modification time to the copy. For a bundle that is the
  better answer anyway, since a cached link can predate the build that shipped it. It
  can be forged by a `touch` or a restore, which is acceptable because nothing keys a
  decision on it — unlike PRO-0027, where mtime was rejected for exactly that reason.)*
- `[Operations]` `Apps/Proctor/Info.plist` is the single source of the release line.
  *(It is already what `release.yml` reads for the asset name and the CHANGELOG match.
  A second source would need keeping in step; one source cannot drift.)*
- `[Experience]` `agentVersion` changes what it carries rather than keeping its present
  value and gaining a sibling. *(It is the field the brief says tells a reader nothing.
  Leaving it as `0.1.0` and hiding the truth in a new field fixes the report for a reader
  who knows to look and leaves the reported defect where it was. It stays a free-form
  string, nothing parses it, and the `+` is semver build metadata whose precedence-
  ignored semantics are exactly what this field means.)*
- `[Experience]` Two clean release builds of one commit report the same descriptor.
  *(Deliberate: they are the same program. The review named this and it is the design
  rather than a defect — `builtAt` separates the build events, and a reader comparing
  two Macs is better served by "same code" than by two strings differing for a reason
  that changes nothing.)*
- `[Operations]` PRO-0027's `BuildStamp` is kept unchanged and is not replaced by a
  version compare. *(It compares a file on disk with a running process, covers the
  resource bundle, and works on a dirty tree — three things a compiled-in string cannot
  do. Reasons in full above.)*
- `[Operations]` `release.yml` gains a pre-build consistency check over the tag, the
  plist and the CHANGELOG section. *(The plist is now load-bearing for the running
  binary, so a tag that disagrees with it ships a binary that misreports its release
  line. The review found both natural spellings of this check are wrong — `v` prefix,
  and a one-byte section passing `test -s` — and the second is a live defect today.)*
- `[Data & scope]` No new tool, no new internal verb, no change to `Wire.protocolVersion`
  — which answers a different question (wire compatibility) and is not a build
  identifier. No change to the readiness ladder, the menu bar, the run HUD or the panel.
  The version rows stay single-line rows in the card they already live in.
- `[Operations]` Opening the package in Xcode prompts once to trust the plugin, and
  declining it is a build failure rather than a fallback. *(A known cost of any
  build-tool plugin. All three paths in the brief are command-line and unaffected.)*

## The out-of-family gate

Ran on grok (`grok-4.6`, effort `xhigh`, read-only), with the design and its measured
evidence inlined rather than read from disk. Codex is off for this repo. It did not
rubber-stamp: six findings, four of which changed the design.

| # | Finding | Disposition |
|---|---|---|
| 1 | Reading `builtAt` at report time reports the file on disk, not the running image — wrong in exactly the case PRO-0027 exists for | **Accepted, design changed.** Captured at startup instead. The sharpest finding of the pass. |
| 6 | The release guard as written cannot pass (`v` prefix) and cannot catch a blank section (`test -s` on a one-byte newline) | **Accepted, both.** Verified by running the existing extraction: an empty section produces one byte and reads as non-empty, so today's fallback never fires. |
| 5 | The split still cannot say debug vs release, or which of the two processes a version belongs to | **Accepted in part, two additions.** `configuration` added; the status window gains the window's own identity beside the agent's. The other two gaps it names — which edits a dirty tree holds, and telling apart the kinds of missing commit — are respectively out of scope and fixed by the two sentinels. |
| 2 | `build-app.sh` copies without `-p` and then re-signs, so an installed binary's mtime is copy-and-sign time, not link time; and a `touch` or a restore can forge it | **Accepted as a documented meaning, not a bug.** Measured: `cp` does reset it. For a bundle, assembly time is the better answer. Nothing keys a decision on the date. |
| 3 | The plugin's git read dies in a git worktree, where `.git` points outside the package, so developers get `unknown` | **Refuted by measurement.** The spike ran in a worktree with a 66-byte `.git` pointer and produced a real sha: the plugin sandbox restricts writes, not reads. |
| 4 | Same-commit rebuilds still collide, and semver parsers ignore `+metadata` so the string still compares equal to `0.1.0` | **Rejected as a defect, kept as rationale.** Both are the intended semantics: two builds of one commit are one program, and build metadata being precedence-ignored is the correct reading of what this string means. |

## What a test cannot reach here

`swift test` cannot witness: the release workflow running on GitHub, notarisation, the
status window drawing either version row, or Xcode's plugin trust prompt.

Everything else is reachable and is not to be signed off by code reading. In particular
A1 is witnessable by shelling out to `git` from a test and comparing, A2 by running the
generator in a directory with no git and in one where git cannot answer, A4 by resolving
a temporary file's date and then replacing the file, A6 by running the consistency check
over agreeing and disagreeing inputs including a blank CHANGELOG section, and A8 by
running the generator twice and observing the file was not rewritten.

Witnessed outside `swift test`, already measured: the plugin runs under SwiftPM's
default sandbox on a plain `swift build`, **inside a git worktree**, and produced
`commit = "e1f6cbf4fd1c"`, `dirty = true`; a second build with unchanged content took
0.64s; `cp` resets a destination's modification time; and the existing CHANGELOG
extraction yields a one-byte file that `test -s` calls non-empty.

## Child work found

*(none yet)*

## Progress — 2026-08-15

**Status: In Review.** Branch `ai/pro-0030`, worktree `.worktrees/PRO-0030`.
`swift build` clean from an empty `.build`, with exactly the three warnings that
pre-exist in `ProctorUI` (`ProctorUIApp.swift:75` twice, `Walkthrough.swift:303`) and
none added — one deprecation warning was introduced by the first draft of
`runningExecutablePath` and removed. `swift test`: **717 tests in 85 suites pass**, up
from **692 in 84**, both counts measured in this worktree rather than derived. The 25
new tests were run under a filter reporting `25 tests in 1 suite`, so the count was read
back.

Files: `Plugins/BuildIdentity/plugin.swift` (new), `scripts/gen-build-identity.sh`
(new), `scripts/check-release-version.sh` (new), `Sources/ProctorCore/BuildInfo.swift`
(new), `Tests/ProctorCoreTests/BuildInfoTests.swift` (new), `Package.swift`,
`Sources/ProctorCore/Wire.swift`, `ToolOutputSchemas.swift`, `BuildStamp.swift`
(comment only), `Sources/ProctorAgent/Session/Session.swift`, `SessionDoctor.swift`,
`Sources/ProctorAgent/main.swift`, `Sources/ProctorShim/{MCPServer,main,Install,RemoteServer}.swift`,
`Sources/ProctorUI/{MainWindow,ProctorUIApp}.swift`, `.github/workflows/release.yml`,
`CHANGELOG.md`.

### Clause → the test that proves it

| Clause | Proof |
|---|---|
| A1 | `compiledCommitMatchesGit`, `compiledDirtyMatchesGit`, `compiledVersionMatchesPlist` — each shells out to git or PlistBuddy and compares. Plus the measurement below. |
| A2 | `withoutGitTheIdentityIsStillReal`, `brokenRepositoryIsUnavailable`, `descriptorIsNeverEmpty`, `generatorNeverFails` |
| A3 | `differentCommitsDifferentDescriptors`, `dirtyIsDistinct`, `configurationIsDistinct`, `sameCodeSameDescriptor` |
| A4 | `builtAtReadsThePath`, `captureSurvivesAReplacement`, `runningExecutableResolves` |
| A5 | No `AgentBuild` or `ShimVersion` remains anywhere in `Sources`; the shim, the agent and the window all read `BuildInfo.current` |
| A6 | `releaseNamesAgree`, `tagWithoutVPrefixFails`, `tagDisagreesWithPlist`, `missingChangelogSectionFails`, `blankChangelogSectionFails`, `nearMissHeadingIsNotAMatch`, `longSectionStillPasses` |
| A7 | Schema updated; `agentBuild` optional and defaulted, so every existing construction still compiles and an older report still decodes |
| A8 | `generatorWritesOnlyOnChange` (inode and date unchanged by a second run), `generatorLeavesNoStrays` |
| A9 | `BuildStamp` untouched but for its comment; its tests are in the 692 that still pass |
| A10 | Code-complete; the window's own row is drawn, which `swift test` cannot witness |

Four rules were confirmed **red before green** by breaking them and reading the
failure: the `v` prefix, the write-if-changed guard, the blank-section rule (broken to
exactly the `test -s` shape `release.yml` carried, which failed the blank case while the
agreeing case still passed, so the test discriminates rather than merely being strict),
and the never-fail rule — which caught a real bug on its first run.

### The out-of-family gates, and what they changed

All three ran on grok (`grok-4.6`, effort `xhigh`, read-only), evidence inlined. Codex
is off for this repo. None rubber-stamped, and between them they changed the design in
six places.

The **plan gate failed on its first attempt** — it spent its whole budget reading the
repository and returned reasoning with no findings, which the runner contract defines as
a lane failure rather than a pass. Retried with every file path stripped out and the
evidence inlined, it answered. Recorded because a gate that returns nothing looks
exactly like a gate that found nothing.

- **Spec review** (six findings, four adopted): reading `builtAt` at report time
  describes the file on disk rather than the running image, which is wrong in exactly
  PRO-0027's case — now captured at startup. The release guard as first written could
  never pass (`v` prefix) and could not catch a blank section. `configuration` was added
  because a debug and a release build of one commit are not the same program. The window
  gained its own identity row. Its claim that the plugin would fail in a git worktree
  was **refuted by measurement**, and its point that two clean builds of one commit
  share a descriptor is the design rather than a defect.
- **Plan review**: the two sharpest findings — `Bundle.main.executableURL` being the
  wrong thing to stat, and argv[0] being no fallback — had already been fixed
  pre-emptively while it was running. It confirmed no Swift 6 concurrency hazard, and
  raised spaces in the package path (already quoted, now tested) and an unborn
  repository (already correct). Its claim that a build-generated Info.plist could flip
  the version was refuted: the plist read is a tracked source file.
- **Completeness critic** (four findings, two adopted): `set -e` in the generator could
  abort before the write and leave Core with no generated source at all, so `-e` is gone
  and every path falls through to a sentinel and an unconditional write. And the guard's
  `printf | grep -q` could SIGPIPE its writer under `pipefail` and fail a section that
  is perfectly fine — the same trap `scripts/notarize.sh` already documents about piping
  `codesign` into `grep`; replaced with a pipe-free `case`. It also prompted the
  literal-prefix heading match, since matching `## [1.2.3]` as a regular expression lets
  the dots match any character. Its claim about the sandbox blocking git was refuted for
  the third time by reading the file the sandboxed plugin had just generated, and its
  claim that the extracted slice includes the heading is refuted by the awk (`next`) and
  by a passing test.

**Writing the never-fail test found a real bug**, which is the reason it was written
rather than reasoned about: given a path that does not exist, `PlistBuddy` prints
`File Doesn't Exist, Will Create: /…` **on stdout** and exits **0**, so that sentence
became the version string. The call is now gated on the file existing, and both
interpolated values are filtered to characters that cannot escape a Swift string
literal.

### Accepted rather than fixed

- `builtAt` can be forged by a `touch`, a restore, or an archiver that does not preserve
  modification times. Nothing keys a decision on it, so a forged date misleads a reader
  and cannot make Proctor do anything.
- Two clean release builds of one commit report one descriptor. They are one program;
  `builtAt` separates the build events.
- A dirty tree does not say *what* is dirty. That is a diff, not an identifier.
- Opening the package in Xcode prompts once to trust the plugin, and declining is a
  build failure rather than a fallback. All three paths in the brief are command-line.

### Code-complete but not machine-witnessable here

`swift test` has no window server and there is no test target for `ProctorUI`. Not
witnessed: the two version rows drawing, the release workflow running on GitHub, and
notarisation.

**Witnessed outside `swift test`:**

- The plugin runs under SwiftPM's **default sandbox**, on a plain `swift build`, inside
  a git worktree whose `.git` is a 66-byte pointer file, and generated
  `commit = "e1f6cbf4fd1c"`, `dirty = true`.
- A no-change second build took **0.64s**; a full recompile takes ~20s.
- `scripts/build-app.sh` was run end to end. The packaged
  `Proctor.app/Contents/MacOS/proctor-shim` and the plain release binary both report
  `0.1.0+e1f6cbf4fd1c.dirty` — no `.debug` suffix, so `configuration` is right in a
  release build, and the tree really was dirty. **All three build paths carry the same
  real identity.**
- `builtAt` on the bundled copy read `2026-08-15T00:41:35Z` against `00:41:20Z` for the
  plain binary: the fifteen seconds between linking and assembly-and-sign, which is the
  documented meaning of the field rather than a discrepancy.
- Probed inside the bundle, `Bundle.main.executableURL` returned the helper's **own**
  path, so the misattribution the review predicted did not reproduce; as a bare CLI the
  two disagreed (symlinked against canonical). The code comment was rewritten to say
  that rather than to claim a bug that did not happen.
- `cp` resets a destination's modification time; the existing CHANGELOG extraction
  yields a one-byte file that `test -s` calls non-empty.
