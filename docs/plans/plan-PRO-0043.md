# Plan — PRO-0043: The build-identity tests fail whenever HEAD moves without a source change

**Spec:** `docs/specs/spec-PRO-0043.md`
**Tier:** Small — one test file, one comment, no production code paths.
**Branch / worktree:** `ai/pro-0043` in `.worktrees/PRO-0043`
**Gate:** `swift build` + `swift test`

## Files

| File | Change |
|---|---|
| `Tests/ProctorCoreTests/BuildInfoTests.swift` | Rewrite two tests, add two, extend one helper |
| `Plugins/BuildIdentity/plugin.swift` | Correct the doc comment's claim about prebuild scheduling |
| `CHANGELOG.md` | One line under `## [Unreleased]`, prose via `/create-luke-content` |

Nothing under `Sources/` changes. `scripts/gen-build-identity.sh` is not touched: it is the
thing under test and its behaviour is correct.

## Step 1 — Give the test helpers a sealed git environment

The existing `run(_:_:environment:status:)` helper already merges an environment dictionary
over the process's own, but merging cannot *remove* an inherited variable. Add a single
constant the git-touching call sites pass:

```swift
/// Everything that lets an inherited environment redirect a git call away from the
/// directory it was given. `GIT_DIR` and friends override `-C`, so a test process that
/// inherited one would have both the test and the generator reading a different
/// repository than the path says.
private static let sealedGitRemovals = ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"]
private static let sealedGitOverrides = ["GIT_CONFIG_GLOBAL": "/dev/null",
                                         "GIT_CONFIG_SYSTEM": "/dev/null"]
```

**Measured before writing it, and it corrected the first draft.** Setting `GIT_DIR` to the
empty string does *not* read as unset — `GIT_DIR= git -C <repo> rev-parse HEAD` fails with
`fatal: not a git repository: ''`, so an empty-string override would break every git call
instead of sealing it. The three redirect variables have to be **removed** from the child
environment, which the existing merge-only helper cannot express, so `run` gains an
`unsetting: [String] = []` parameter. The two config variables do work as overrides: with
`GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_SYSTEM=/dev/null`, a `config --get user.email`
exits non-zero, so inherited hooks, signing and identity are genuinely out of reach.

`generator(outputDirectory:packageDirectory:)` gains matching parameters, defaulting to the
existing behaviour so current call sites are unchanged. The script inherits whatever the test
process hands it, so sealing only the test's own git calls would seal nothing.

## Step 2 — Rewrite the two live-checkout tests

**`compiledCommitMatchesGit`** keeps its name's intent but drops the equality. It becomes: get
the live short sha; when that fails, skip as it already does for the tarball case; when it
succeeds, use it only as proof that git answers here, then assert the *compiled* value is
twelve-or-more lowercase hex and neither sentinel. The message on the shape assertion names
`.build/plugins`, because the residual case that can still fire it is a stale generated file.

Rename it to something that does not promise the equality it no longer makes —
`compiledCommitIsARealCommit`. Note for step 4: `swift test --filter` matches the Swift
function name, so the rename changes the filter string.

**`compiledDirtyMatchesGit`** loses its comparison against the working tree and becomes
`sentinelCommitIsNeverDirty`: if the compiled commit is `unknown` or `unavailable`, then
`dirty` is `false`. No git call at all, so nothing about the machine can move it.

## Step 3 — Add the two hermetic generator tests

Both build their own repository under `NSTemporaryDirectory()`, with the generator's output
directory a **sibling** of that repository rather than a child — the review's sharpest finding,
because output written inside the repo makes the tree dirty before the clean case is observed.

```
root/
  repo/          <- git init here, plist here, the tree under measurement
  out/           <- generator output, outside repo/
```

**`generatorReadsTheCommitOfItsCheckout`** — `git init` in `repo/`, set `user.email` and
`user.name` locally on it (needed for a commit, and the global config is sealed off), one
`--allow-empty` commit, read its `rev-parse --short=12 HEAD`, run the generator with
`packageDirectory: repo`, assert the written file contains that exact commit and
`dirty = false`.

**`generatorSeesADirtyTree`** — continue from the same shape: write an untracked file inside
`repo/`, run the generator again, assert `dirty = true` and the commit unchanged. Assert the
clean case first in the same test so the flip is what is being measured, not two independent
observations.

Both use `#require` on the git steps rather than a silent `guard ... else { return }`: a
machine that cannot run `git init` cannot build this package, so a quiet skip there would be
the silence the suite exists to reject. This matches `brokenRepositoryIsUnavailable`, which
already calls `git init` unconditionally.

## Step 4 — Prove it, including the failure that started this

Red-then-green is available for the two new tests but not for the two rewrites, whose point is
that they *stop* going red. So the evidence for those is the reproduction:

1. `swift test --filter 'compiledCommitIsARealCommit|sentinelCommitIsNeverDirty|generatorReadsTheCommitOfItsCheckout|generatorSeesADirtyTree'` — read the `with N tests` count back, because a filter that matches nothing reports green.
2. `git commit --allow-empty` to move HEAD, then re-run the same filter with the build plan warm. Before this change that is the exact command that produced the reported failure; after it, green.
3. `touch` an untracked file, re-run. Before: red on the dirty assertion. After: green.
4. Full `swift test` for the sweep, on a dirty tree, with no `rm -rf .build/plugins`.

Record the before/after counts. The pre-existing skips named in the brief
(`ObscuraPresenceWiringTests`, `BrowserLaneWiringTests`, PRO-0041) stay skipped and are not
this id's business.

## Step 5 — The plugin comment

Replace the sentence claiming prebuild commands "run every time with no up-to-date check"
with what was measured: they are scheduled every build, but a build llbuild considers fully up
to date runs no commands at all, so the generated identity can lag the checkout. Point at
`docs/specs/spec-PRO-0043.md` for the measurement. No code change — `createBuildCommands` is
untouched.

## Out of scope, deliberately

- Making the plugin re-run on a HEAD move. Child work in the spec; a prebuild command has no
  declared inputs, so this needs a different mechanism.
- Adding a CI job that runs `swift test`. Child work in the spec.
- Any change to `scripts/gen-build-identity.sh`.

## Plan review

Out-of-family review ran at the spec stage on `grok-4.6` at `xhigh` and its findings are
folded into the decisions this plan implements — five accepted, two rejected with reasons, one
promoted to child work; the record is in the spec's Out-of-family review section. The plan
adds no design decisions beyond those, so it is not re-gated. One assumption this plan
introduces on its own — that git reads an empty `GIT_DIR` as unset — is marked above as
something to verify during step 4 rather than to rely on.
