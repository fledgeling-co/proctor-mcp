# Plan PRO-0052: The proctor skill tracks what actually shipped

**Spec:** `docs/specs/spec-PRO-0052.md`
**Tier:** Small — one artifact, no code, no test gate.
**Target repository:** `~/Dev/fledgeling-plugins` (edited in place, left uncommitted)

## Why this has no code stage

The skill is the product's real interface to a model, and it had drifted from
the surface it describes. Correcting it needs no change in `proctor-mcp`: the
code is right and the description of it was wrong. A plan that manufactured a
source change here would be inventing work to make a branch look busy.

## Stages, as executed

**1. Establish the truth, from the code rather than from the brief's list.**
The brief carries a map of what shipped and says plainly that it is a map and
not the territory. The authoritative sources, in the order they were read:

- `Sources/ProctorCore/ToolCatalogue.swift` — the tool set, every argument, every
  enum. This is what the shim advertises and what the agent dispatches on, so a
  claim the skill makes about an argument is checkable here and nowhere else.
- `Sources/ProctorCore/ToolProfiles.swift` — the four profiles and their exact
  membership.
- `Sources/ProctorCore/Wire.swift` — `ActuationPlane`, `ActuationBackendID`,
  `Actuation`, `StepResult`, `StabilityReport`, `DoctorReport` and its `Lane` and
  `Grant`.
- `Sources/ProctorCore/ToolchainLanes.swift` — how a lane's readiness is derived,
  and the note each lane carries.
- `Sources/ProctorCore/BrowserTarget.swift` — `BrowserHandoff`, `BrowserSurface`,
  `BrowserLaneFlags`, `HashSubject`.
- `Sources/ProctorCore/SwitchResolution.swift` — the two-part precedence rule.
- `docs/architecture.md` — the backend seam and the addressing rule.
- The wave 7 specs, read for what regressed rather than for what was built.

**2. Diff the skill against that, claim by claim.** This is where the six drifts
the brief did not predict were found, including two the brief's own list would
have preserved: the tool count and the `scripting` profile's membership.

**3. Rewrite, applying `/opus-5-guide`.** Loaded first, as the brief required.
The five rules it names were applied to the artifact.

**4. Check the regressions before promising anything.** A first draft of the
delegation section asserted that supervision holds intact under delegation,
which is what the direction file implies. PRO-0046 records otherwise in three
places. The section was rewritten against the spec rather than the direction.

## Verification

No `swift build` or `scripts/test.sh` run is meaningful for this item — the diff
in this repository is two markdown files under `docs/`. The check that matters
is that every tool, argument, field and enum value named in the skill exists in
the catalogue, which was done by reading each against its source while writing.

The one live check worth recording: `which cua-driver` returns nothing on this
machine, while `maestro` resolves to `/opt/homebrew/bin/maestro` and `simctl` to
Xcode's developer directory. That is the evidence behind the skill's caution
about the delegated lane and its absence of one about Maestro.

## Out of scope, per the brief

The campaign's seven stages, which are the skill's method and are unaffected by
what performs the clicking. They were left intact; the only addition is one
navigational sentence saying which stages have nothing to work with on an iOS
target. The plugin version bump and any release are the reader's call.
