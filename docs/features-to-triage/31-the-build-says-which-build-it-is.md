# The build says which build it is

## The problem

`AgentBuild.version` is a hardcoded `0.1.0` that has never been bumped. Two
things depend on it and both are degraded:

- `proctor_doctor` reports `agentVersion`, which tells a reader nothing. Two
  machines running builds three months apart report the same string.
- PRO-0027 wanted to detect a stale running agent after an install and could not
  use a version compare, so it fell back to comparing inode and size across three
  paths. That works and is shipped, but it works around a fact rather than fixing
  it.

## What it should do

Make the version a real identifier of the build that is running, so that
`agentVersion` distinguishes two builds and a staleness check can ask a direct
question.

## The hard parts, named

- **What the identifier should be** is the actual decision. A semantic version
  from a tag is meaningful to a person and stale between releases. A commit sha
  is exact and meaningless to a reader. A build timestamp orders correctly and
  says nothing about content. The likely answer is more than one field, and the
  spec should say which field answers which question.
- **It has to be generated at build time, in a way three paths agree on:**
  `swift build`, `scripts/install.sh`, and `.github/workflows/release.yml`. A
  version baked by the release workflow and absent from a local build gives every
  developer machine a null, which is the state we are in now wearing a different
  hat.
- **Do not break the release pipeline.** `release.yml` extracts the CHANGELOG
  section matching the tagged version. Anything here that touches how a version
  is named has to keep that match working.
- **PRO-0027's inode+size check should be reconsidered, not automatically
  replaced.** It answers "is the file on disk different from the file I am
  running", which a version compare answers only if the version genuinely changes
  every build. Say which is kept and why.

## Worth knowing

`docs/specs/spec-PRO-0027.md` and `spec-PRO-0028.md` both record this as child
work, from the staleness side and the `agentVersion` side respectively.
