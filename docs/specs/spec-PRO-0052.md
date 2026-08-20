# PRO-0052: The proctor skill tracks what actually shipped

**ID:** PRO-0052
**Status:** Merged `d6cf947`
**Created:** 2026-08-16
**Last updated:** 2026-08-16
**Brief:** `docs/features-to-triage/53-the-proctor-skill-tracks-what-shipped.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` — wins over any earlier spec
**Plan:** `docs/plans/plan-PRO-0052.md`
**Branch:** `ai/pro-0052` (worktree `.worktrees/PRO-0052`)
**Sequenced last in wave 7 on purpose:** it documents the surface every other item built.

## The deliverable lives in another repository

The artifact is `~/Dev/fledgeling-plugins/plugins/proctor/skills/proctor/` —
`SKILL.md` and `references/tools.md`. Both were edited in place and left
uncommitted for the reader. **This branch contains no source change**, and that
is the correct outcome rather than an unfinished one: nothing in `proctor-mcp`
needed to change for the skill to become true, because the skill was the thing
that was false.

`references/methodology.md` and `references/evidence.md` were read and
deliberately not rewritten. `methodology.md` describes the macOS lane's method,
which wave 7 did not change; `evidence.md` is a dated research record whose
claims remain accurate about the native lane. Both are now flagged for what they
are in `SKILL.md`'s Depth section rather than silently left to read as current
across all lanes.

## What was wrong, measured against `main` at `01f823c`

Drift the brief predicted:

- `agentBuild` (PRO-0030), the signed trail (PRO-0032), `surface` and `flags` on
  a browser handoff (PRO-0035), and `AgentRecovery` (PRO-0028) were absent.
- The two-planes section described actuation as something Proctor performs.

Drift the brief did not predict, found while checking every claim against the
catalogue rather than against the brief's list:

| Claim in the skill | Truth on `main` |
|---|---|
| "The server ships 19 tools" | 20, since `proctor_ios`. |
| `scripting` = core + `flow` `stability` `dictionary` `policy` | `policy` is **not** in `scripting`; it is `full`-only. |
| No `ax` profile documented | `ax` exists and is the smallest, at 8 tools. |
| "sixteen distinct assertion kinds" | Seventeen. `horizontalAlignment` (PRO-0042) was in the prose but not in the count or in `tools.md`'s enum. |
| `proctor_snapshot` `maxNodes` default 2000 | 600, plus an undocumented wall-clock bound on the walk. |
| A synthetic-plane step means "the server fell back" | Only for `type` and `scroll`, which try every accessibility route and concede. An outright refusal fails the step. |

The last one mattered most: it told a reader to interpret a refusal as a silent
downgrade, which is the opposite of the guarantee the code makes.

## What the skill now says

Four rewrites the brief asked for, plus one it did not.

1. **"Two planes" became "Planes and lanes: what a step proves, and who
   performed it."** The plane vocabulary is stated at its shipped width — six
   values, with `routedEvent` and `unknown` explained by what a reader may
   conclude from each. The honesty rule that a synthetic-plane result proves the
   narrower claim is kept and sharpened. Beside it, the lane says who actuated:
   `native` as the deliberately-selected maintained default, `cua` behind
   `PROCTOR_ACTUATION=cua`, never automatic and never a fallback. The five
   delegated-only fields are tabulated with what to do about each.

2. **A new iOS section**, leading with the ceiling rather than the capability: a
   device handle is not a window handle, five tools refuse one by name, and there
   is no tree, no elements, no geometry and no `agree`. The four `open` verdicts
   are given with what each supports, and the sentence "none of them claims the
   app reached a particular screen" is stated outright, because that is the
   inference a model will otherwise write into a report. The Maestro half says
   `flowPassed` means the driver reported success and Proctor observed nothing.

3. **"Before anything else" grew from two grants to five questions** — is the
   server here, which grants (three-state), which toolchain, which lanes, and
   what the gate will do next — with a table mapping each lane to what its
   absence disables.

4. **A new second section, "What Proctor observes, and why that is the whole
   point"**, naming the three channels that stay Proctor's and why frame
   trustworthiness is the difference between a Proctor capture and a screenshot.

5. **Not asked for, and load-bearing: the delegated lane's capability
   regressions.** PRO-0046 and PRO-0044 recorded three that a reader planning an
   unattended campaign would otherwise discover in production — an off-Space
   window is refused on the Cua lane and reachable on the native one; the
   takeover statement goes up *after* an unrequested escalation rather than
   before; and a batch whose driver cannot be identified arms no input block, so
   click-to-Stop is not consulted and the person keeps Escape, the menu bar and
   the gaps between steps. A first draft of this section claimed supervision
   holds intact. Reading PRO-0046 rather than trusting the direction file
   corrected it.

## Written for Opus 5, per the brief

The brief made loading `/opus-5-guide` non-optional and named five rules. All
five were applied to the file rather than to the process of writing it:

- **Complete task up front, rules stated per case.** The lane table, the verdict
  table and the refusal table state each case rather than relying on one example
  to carry the rest.
- **Verification scaffolding removed.** The file was scanned for it. There was
  none of the "double-check" or "verify with a subagent" kind, and the one
  instance of aggressive framing — a "Mandatory Rule for Visual Proof" built
  around "Never rely on…" — was rewritten as a positive instruction carrying its
  reason (a headless renderer has no window server, so it emits placeholder
  glyphs without saying so).
- **Subagent cap kept explicit with its reason**, and extended with the two
  cases the guide names: one agent rather than several where one will do, and no
  subagent for re-checking a result already in hand.
- **Length calibrated explicitly** for the report the skill produces — cover the
  substance, no filler sections, no restated summary, no closing reflection.
- **Calm trigger language throughout**, with the reason kept beside each rule so
  a reader can generalise from it.

## Honesty carried into the text

Nothing in wave 7 was exercised against a live `cua-driver`, which is not
installed on this machine (`which cua-driver` → not found, checked
2026-08-16). The skill says so where a reader would act on it, and tells anyone
selecting that lane to treat the first delegated step as a probe. The Maestro
lane was verified live and is described without that caveat; `maestro` and
`simctl` are both present here.

## Acceptance

Every claim in `SKILL.md` and `references/tools.md` traces to
`Sources/ProctorCore/ToolCatalogue.swift`, `Sources/ProctorCore/ToolProfiles.swift`,
`Sources/ProctorCore/Wire.swift`, `Sources/ProctorCore/ToolchainLanes.swift`,
`Sources/ProctorCore/BrowserTarget.swift`, `Sources/ProctorCore/SwitchResolution.swift`,
`docs/architecture.md`, or a wave 7 spec. There is no build or test gate for
this item, because it changes no code in this repository; the gate is that the
skill does not name a tool, argument, field or enum value the catalogue does not
have.

## Child work found

None requiring a new id. Two observations for the reader:

- `Sources/ProctorShim/Install.swift` prints "advertises all nineteen (~11.3k)"
  in its post-install help. That count is now 20. One line, in this repo, and
  outside this item's diff since this branch carries no source change.
- The plugin version bump and any release of `fledgeling-plugins` are the
  reader's call and were deliberately not made.
