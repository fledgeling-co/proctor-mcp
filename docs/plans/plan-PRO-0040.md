# Plan — PRO-0040: `open -a Proctor` cannot launch Proctor while the agent is running

**Spec:** `docs/specs/spec-PRO-0040.md`
**Branch / worktree:** `ai/pro-0040` in `.worktrees/PRO-0040`
**Tier:** Small. Six files, one new plist, two new tests, one build gate.
**Baseline before any change:** `swift build` clean, `swift test` = **937 tests in 105 suites**, passing.

The design decision is settled in the spec and was measured before it was written. This
plan does not revisit it; it sequences the edits and names the evidence each acceptance
clause is closed by.

## Step 1 — `Apps/Proctor/AgentInfo.plist` (new)

Three keys, no version keys (spec: "Version keys are deliberately absent").

```xml
<key>CFBundleIdentifier</key><string>app.fledgeling.procter.agent</string>
<key>CFBundleName</key><string>Proctor Agent</string>
<key>LSUIElement</key><true/>
```

It sits beside `Apps/Proctor/Info.plist` because that is where the bundle's other plist
already lives and where `scripts/build-app.sh` and `scripts/check-release-version.sh`
already look for bundle metadata.

The file gets a comment block in the same register as `Info.plist`'s, saying what it is
for: this is a section linked into `proctor-agent`, not a bundle's `Info.plist`, and it
exists so LaunchServices does not answer `open -a Proctor` with a process that has no
window.

## Step 2 — `Package.swift`: link the section into the agent

On the `ProctorAgent` executable target only:

```swift
linkerSettings: [.unsafeFlags([
    "-Xlinker", "-sectcreate",
    "-Xlinker", "__TEXT",
    "-Xlinker", "__info_plist",
    "-Xlinker", "Apps/Proctor/AgentInfo.plist",
])]
```

Two things to verify at build time rather than assume:

- **The path resolves.** It is relative to the linker's working directory. If SwiftPM
  does not run the linker from the package root the build fails loudly, and Step 6's
  gate catches a section that silently did not land. If it does not resolve, fall back
  to a path derived from `#filePath` at manifest evaluation, which is deterministic and
  needs no environment.
- **`ProctorReflector` still consumes cleanly.** Already measured (spec, Risks): a
  throwaway package depending on this one by URL at `from: "1.0.0"` and importing
  `ProctorReflector` builds clean with these flags present. Re-run that check after the
  edit, because it is the one failure that would only appear in someone else's repo.

## Step 3 — `Sources/ProctorCore`: name Proctor's identities

`Wire.bundleIdentifier` already exists and is the app's identity. Add the agent's beside
it, derived from it so the two cannot drift, plus the predicate the contention monitor
needs:

```swift
/// The agent's own LaunchServices identity, since PRO-0040. The agent binary
/// carries this in a `__TEXT,__info_plist` section so that `open -a Proctor` is
/// not answered by a process with no window. It is NOT the signing identifier:
/// every nested binary is still signed `-i app.fledgeling.procter`, which is what
/// the TCC grants match on.
public static let agentBundleIdentifier = bundleIdentifier + ".agent"

/// Whether a running application is one of Proctor's own.
public static func isProctor(bundleIdentifier id: String?) -> Bool
```

`isProctor` accepts both identities and rejects nil. Accepting the agent's identity is
not strictly needed — the monitor adds its own pid directly — but it is the honest
predicate and it keeps the answer right if the agent is ever enumerated rather than
assumed.

## Step 4 — `ContentionMonitor.ourOwnPids()`: stop inferring the identity

`Sources/ProctorAgent/Session/ContentionMonitor.swift:229` currently reads
`Bundle.main.bundleIdentifier`, which after Step 2 is the agent's, matching no running
application. Replace the `if let id = Bundle.main.bundleIdentifier` guard with a filter
on `Wire.isProctor(bundleIdentifier:)`.

This is the clause that stops the change from weakening supervision: without it, someone
opening Proctor's own menu to release a held run reads as a person taking the machine,
and the run holds itself again on the way out. The cache and the one-second refresh are
untouched.

## Step 5 — Tests

Two, both in existing targets, both red before the change and green after.

**T1 — `Wire.isProctor` recognises Proctor's own processes** (`ProctorCoreTests`).
The app's identifier and the agent's are both Proctor; an unrelated identifier and nil
are not; and the agent's identifier is the app's plus `.agent`, so the derivation is
pinned. Closes **AC4**'s logic half.

**T2 — the shipped agent plist matches the identity the code assumes** (`ProctorCoreTests`).
Reads `Apps/Proctor/AgentInfo.plist` from the repo root, located from `#filePath`.
Asserts it parses; `CFBundleIdentifier` equals `Wire.agentBundleIdentifier`; that this
differs from `Apps/Proctor/Info.plist`'s `CFBundleIdentifier`, which must equal
`Wire.bundleIdentifier`; and that `LSUIElement` is `true`. Closes **AC5**'s contract
half — if anyone edits either plist so the agent stops having its own identity, or so
the app's identity drifts from the constant, this fails.

`swift test --filter` matches the Swift function name, not the `@Test` display string,
so read the `with N tests` count back before believing any filtered green. Full-suite
count must go 937 → 941 (T1 and T2 are parameterised across their cases) or whatever
the actual added count is, read back rather than predicted.

## Step 6 — `scripts/build-app.sh`: gate the section and the signing identifier

Two assertions, both after the agent binary is signed, because the second one can only
be read from a signature.

**6a — the section is present.** `otool -s __TEXT __info_plist` on the agent binary must
report a non-empty section. Without it the agent registers as an instance of the app and
`open -a Proctor` stops working, silently.

**6b — the signing identifier is still the app's.** `codesign -dv` on the agent must
report `Identifier=app.fledgeling.procter`. This one came out of the out-of-family
review and is the more valuable of the two: a later `codesign` run that omits `-i` would
take the embedded `CFBundleIdentifier` as the signing identifier, rewrite the designated
requirement, and lose a person's Accessibility and Screen Recording grants one release
later with nothing failing in between. Now it fails the build.

Both messages say what the failure costs, not just what it is.

This is the whole of the three-scripts-move-together obligation for this change. The
installed layout does not change, so `scripts/install.sh`, `scripts/notarize.sh`,
`scripts/doctor.sh` and `.github/workflows/release.yml` need no path edits — and
`release.yml` calls `scripts/build-app.sh`, so the release path inherits both gates
without being taught anything. Closes **AC5**.

## Step 7 — Docs and changelog

- `docs/architecture.md`: a short note that the agent carries its own LaunchServices
  identity, that this is not its signing identity, and why both facts matter.
- `CHANGELOG.md` `## [Unreleased]` only, prose written through `/create-luke-content`
  (format `marketing`) per this repo's convention.

## Step 8 — End-to-end verification on this machine

The three acceptance clauses that no `swift test` can reach. Run in this order, because
the grant check is only meaningful against a pre-existing grant.

1. Record the before state: `codesign -d -r-` on the installed agent, and the agent's
   own doctor report for Accessibility and Screen Recording.
2. `PROCTOR_SKIP_NOTARIZE=1 scripts/install.sh` from the worktree. Developer ID signed,
   not notarised, nothing leaves this machine.
3. **AC1:** with the agent up, `lsappinfo find bundleid=app.fledgeling.procter` names
   the UI app or nothing, never the agent. Confirm by pid.
4. **AC2:** quit the UI app, leave the agent running, `open -a Proctor`, and confirm the
   UI process starts. Then `open -a Proctor` again with both up and confirm the window
   comes back rather than nothing happening.
5. **AC3:** `codesign -d -r-` on the newly installed agent is byte-identical to step 1,
   and the agent still reports both grants, with no consent dialog shown.
6. **AC6** is a review clause, not a runtime one: confirm by diff that nothing added
   stops or restarts the agent, and that `install.sh` still ends in `open`.

## Risks carried into work

- The linker path (Step 2) is the only genuinely unknown mechanic. Everything else was
  measured on a probe before the spec was written.
- The out-of-family gate is degraded. Recorded in the spec's review section rather than
  passed over.

## Out of scope

Any bundle-layout change, any signing or notarisation change, any UI change, and
anything in the Wave 7 Cua/iOS direction.
