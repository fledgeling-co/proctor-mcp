# Plan — PRO-0030: The build says which build it is

**Spec:** `docs/specs/spec-PRO-0030.md`
**Branch:** `ai/pro-0030` · **Worktree:** `.worktrees/PRO-0030`
**Tier:** Standard — one new build-system mechanism, one new Core type, a wire
addition, three call-site migrations, two pipeline fixes.

## Shape

One generated file, one public type that reads it, and every existing version
constant deleted and re-pointed at that type. Nothing else in the app changes
behaviour.

```
scripts/gen-build-identity.sh      writes commit/dirty/version constants
        ▲ run by
Plugins/BuildIdentity/plugin.swift prebuild command on ProctorCore
        ▼ produces
Sources/ProctorCore/BuildInfo.swift  BuildIdentity (wire struct) + BuildInfo.current
        ▼ consumed by
  agent (doctor + startup line) · shim (MCP serverInfo, --version) · UI (two rows)
```

## Files

### New

| File | What it is |
|---|---|
| `scripts/gen-build-identity.sh` | The generator. Resolves version/commit/dirty and writes `BuildIdentityGenerated.swift`, **only when the content differs**. Callable by hand, which is what makes A2 and A8 testable without a build. |
| `Plugins/BuildIdentity/plugin.swift` | SwiftPM `BuildToolPlugin`. One `prebuildCommand` running `/bin/sh` on the generator, output directory `pluginWorkDirectoryURL/Generated`. |
| `Sources/ProctorCore/BuildInfo.swift` | `BuildIdentity` (the five fields + `descriptor`) and `BuildInfo.current` (the launch snapshot). |
| `scripts/check-release-version.sh` | Tag ↔ plist ↔ CHANGELOG consistency. Called by `release.yml`; runnable locally, which is what makes A6 testable. |
| `Tests/ProctorCoreTests/BuildInfoTests.swift` | A1–A4, A6, A8. |

### Changed

| File | Change |
|---|---|
| `Package.swift` | `.plugin(name: "BuildIdentity", capability: .buildTool())`; `plugins: ["BuildIdentity"]` on `ProctorCore`. |
| `Sources/ProctorCore/Wire.swift` | `DoctorReport.agentBuild: BuildIdentity?`, defaulted `nil` in `init` so existing call sites compile. |
| `Sources/ProctorCore/ToolOutputSchemas.swift` | `agentBuild` in `proctor_doctor`'s schema; the description says what `agentVersion` now carries. |
| `Sources/ProctorAgent/Session/Session.swift` | Delete `enum AgentBuild`. |
| `Sources/ProctorAgent/Session/SessionDoctor.swift` | `agentVersion: BuildInfo.current.descriptor`, `agentBuild: BuildInfo.current`. |
| `Sources/ProctorAgent/main.swift` | Startup line prints the descriptor. This is also the agent's launch touch. |
| `Sources/ProctorShim/MCPServer.swift` | Delete `enum ShimVersion`; `serverInfo.version` is the descriptor. |
| `Sources/ProctorShim/main.swift` | `--version` prints the descriptor; usage banner likewise. Early touch. |
| `Sources/ProctorShim/Install.swift` | The `shim:` line uses the descriptor. |
| `Sources/ProctorUI/MainWindow.swift` | `Version` row shows the agent's descriptor; a new row shows this window's own. Early touch in the app entry point. |
| `.github/workflows/release.yml` | Call `check-release-version.sh` **before** the build; apply the non-blank rule where notes are extracted. |
| `CHANGELOG.md` | `## [Unreleased]`, prose through `/create-luke-content`. |

## Steps

### 1 — The generator (`scripts/gen-build-identity.sh`)

Arguments: output directory, package directory. Resolution order, each step falling
through rather than failing:

- **version** — `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString'` on
  `Apps/Proctor/Info.plist`; if PlistBuddy is not executable or errors, a pure-shell
  extraction of the string element following the `CFBundleShortVersionString` key. Two
  paths because a build must not fail on a sandbox denial, and because the plist is
  committed XML that a shell can read.
- **commit** — `unknown` when `$PKG_DIR/.git` does not exist. Otherwise
  `git --no-optional-locks -C "$PKG_DIR" rev-parse --short=12 HEAD`; `unavailable` when
  that fails. `--no-optional-locks` so git cannot try to write an index inside a
  sandbox that forbids it.
- **dirty** — `true` when `git --no-optional-locks -C "$PKG_DIR" status --porcelain`
  prints anything, `false` otherwise. `status --porcelain` rather than `diff` because an
  untracked source file changes the build and belongs in the answer; it already excludes
  ignored paths, so `.build/` does not make every build dirty. **Verify that:** if
  `.build` or `.worktrees` shows up, the tree reads dirty forever and the field is
  worthless.
- **write** — compose into a temporary file, `cmp -s` against the existing output, and
  move it into place only on a difference. This is A8 and it is what keeps the build
  cache intact.

Emit an internal enum, not public — `BuildInfo` is the public face:

```swift
enum BuildIdentityGenerated {
    static let version = "0.1.0"
    static let commit = "e1f6cbf4fd1c"
    static let dirty = true
}
```

### 2 — The plugin

`createBuildCommands` returns one `prebuildCommand` with `executable`
`/bin/sh`, arguments `[<generator>, <outDir>, <packageDir>]`, and
`outputFilesDirectory: <outDir>`. Prebuild commands run before every build with no
up-to-date check, which is the freshness; the generator's own write-if-changed is the
economy.

### 3 — `BuildInfo.swift`

```swift
public struct BuildIdentity: Codable, Sendable, Equatable {
    public let version: String
    public let commit: String        // sha | "unknown" (not a checkout) | "unavailable" (git failed)
    public let dirty: Bool
    public let configuration: String // "debug" | "release"
    public let builtAt: String?      // ISO-8601 UTC, nil when the executable cannot be read
    public var descriptor: String { ... }   // pure, testable on arbitrary values
}
```

`descriptor` is `version + "+" + commit`, then `.dirty` when dirty, then `.debug` when
the configuration is debug. Release and clean add nothing, so the common shipped string
stays short. `builtAt` is **not** in it: it identifies the build event, not the program.

`builtAt` is a `String?` rather than a `Date` so the wire does not depend on an
encoder's date strategy, and so a model reading the JSON gets something it can read.

Two pieces, split so the capture is testable:

- `public static func builtAt(ofExecutableAt path: String) -> String?` — pure over a
  path; `nil` when it cannot be stat'd.
- `public static let current: BuildIdentity` — the launch snapshot. A `static let`, so
  it resolves once and never again; `builtAt` is a **stored** property of the resulting
  value, which is what makes a later replacement of the file on disk unable to change
  what a running process reports (A4). Each executable touches `current` in its first
  lines so the resolution happens at startup rather than at the first doctor call.

`configuration` comes from `#if DEBUG`. **Verify SwiftPM defines it** for a debug build;
if it does not, use `_isDebugAssertConfiguration()`, which reports the same fact from the
optimisation level.

### 4 — Migrate the three constants

Delete `AgentBuild` and `ShimVersion` outright. No forwarding shims: PRO-0027's plan
review rejected exactly that, because a shim keeps the old spelling compiling and the
old value reachable.

### 5 — Wire and schema

`agentBuild: BuildIdentity?` on `DoctorReport`, optional so an older agent's report
still decodes against a newer shim. `agentVersion` keeps its name and its type.

### 6 — The status window

The `Background agent` card's `Version` row keeps showing the agent's descriptor.
A second row — `This window` — shows `BuildInfo.current.descriptor` for the UI process
itself. Both are single-line rows in the existing `Grid`; no new surface.

### 7 — The release pipeline

`scripts/check-release-version.sh <tag>`:

1. `VERSION` from the plist (the same read the workflow already does).
2. Fail unless the tag equals `v$VERSION`. **The `v` is the whole point** — the tags are
   `v0.1.0` and the plist is `0.1.0`, so an equality check between them can never pass.
3. Extract the CHANGELOG section with the workflow's existing awk and fail unless it has
   **at least one non-blank line** (`grep -q '[^[:space:]]'`). `test -s` is not enough:
   measured, an empty section extracts to a single newline and reads as non-empty.

In `release.yml`, call it as the first step after checkout, and apply the same non-blank
rule to the notes extraction so the fallback sentence fires when it is meant to.

### 8 — Tests

| Clause | Test |
|---|---|
| A1 | Run `git rev-parse --short=12 HEAD` in the package directory (located from `#filePath`) and assert it equals `BuildInfo.current.commit`; assert `dirty` matches `git status --porcelain`. Skipped, with a reason, when git cannot answer — so the suite is honest in a tarball rather than red. |
| A2 | Run the generator into a temp directory with no `.git` → `unknown`, `dirty = false`, real version. Then with a `.git` that git rejects → `unavailable`. Assert the output compiles as Swift by shape (the constants are present and quoted). |
| A3 | `descriptor` over constructed values: two commits differ; clean vs dirty differ; debug vs release differ; two identical release builds match. |
| A4 | `builtAt(ofExecutableAt:)` on a temp file returns its date; on a missing path returns nil. A stored snapshot built from that path keeps its value after the file is replaced. |
| A6 | `check-release-version.sh` against a fixture plist and CHANGELOG: right tag + real section passes; `0.1.0` instead of `v0.1.0` fails; missing section fails; **blank section fails**. |
| A8 | Run the generator twice into one directory; assert the output file's inode and modification time are unchanged by the second run. |
| A9 | The existing `BuildStamp` tests, unchanged and still green. |

Shell-script clauses run through `Process` from a Swift test, which is how A2, A6 and A8
become part of `swift test` rather than something a person remembers to check.

## Risks

| Risk | Handling |
|---|---|
| PlistBuddy denied by the plugin sandbox | Shell fallback in the generator; both paths exercised. |
| `status --porcelain` reports `.build`/`.worktrees` and the tree is always dirty | Verified during step 1 before anything is built on it. |
| `#if DEBUG` not set by SwiftPM | `_isDebugAssertConfiguration()` fallback; verified, not assumed. |
| A `swift test` that shells out to git is flaky in CI | It skips with a stated reason when git cannot answer, and never fails for the absence of a repository. |
| The plugin makes a downstream consumer's build fail | The generator never exits non-zero: every unresolvable input has a sentinel. |

## Definition of done

`swift build` clean with no new warnings; `swift test` green with the count read back
under a filter; every clause above has a test that was seen red before green; the
release check passes for the current tag/plist/CHANGELOG and fails each of the three
ways it is meant to; `CHANGELOG.md` updated under `## [Unreleased]`.
