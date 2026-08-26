# CLAUDE.md — proctor-mcp

Proctor is a macOS agent that gives any MCP-speaking model computer use on a Mac and doubles as a UI-testing harness. `ORCHESTRATOR.md` at the repo root is the memory of what has shipped and what is open; read it before planning work. This file covers two release conventions that are easy to get wrong and that every change is expected to honour.

## Releases are notarised Developer ID, never ad-hoc

Every build that leaves this machine (a GitHub release asset, anything handed to another Mac) is Developer ID signed, notarised with Apple, and stapled. This is what makes it work for other people: the TCC grants (Accessibility, Screen Recording) key on the team-scoped Developer ID signature, so a signed build keeps its grants across upgrades, and Gatekeeper accepts a stapled build without a fight. Ad-hoc signing ties the grants to the exact bytes and throws them away on the next rebuild, so use it only for a throwaway build you will run once on this machine.

The paths that already do this, so match them rather than re-inventing:

- `scripts/install.sh` auto-detects the Developer ID identity and notarises a fresh build by default (keychain profile `proctor`; `PROCTOR_SKIP_NOTARIZE=1` to skip a local-only build).
- `scripts/notarize.sh` submits and staples, taking either a local keychain profile or an App Store Connect API key from the environment.
- `.github/workflows/release.yml` builds, signs, notarises, staples and publishes the release on a `v*` tag, using the six repo secrets documented in its header.

When you change how the app is built, signed, or packaged, keep all three of these in step, because a release that skips notarisation reaches users as a Gatekeeper block.

## Keep CHANGELOG.md current, and write its prose through create-luke-content

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Semantic Versioning. Add user-facing changes to the `## [Unreleased]` section in the same change that makes them, so the log never drifts behind the code. On release, rename `## [Unreleased]` to `## [x.y.z] - YYYY-MM-DD` and open a fresh `## [Unreleased]`. The heading format is load-bearing: `.github/workflows/release.yml` extracts the section matching the tagged version for the GitHub release notes, so a heading it cannot match ships empty notes.

Write the entry prose through the create-luke-content skill (`/create-luke-content`, format `marketing`) rather than by hand. It carries Luke's voice and a deterministic lint that hard-fails on an em dash and on AI-cliché phrasing, which is the difference between a changelog Luke ships as written and one that reads as generated. Route the copy through it before assembling the file; editing the voice back in afterwards means rewriting and re-linting, which is the expensive order.
