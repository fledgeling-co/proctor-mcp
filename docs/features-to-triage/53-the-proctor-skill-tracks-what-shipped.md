---
sources: [REQ-091, REQ-092]
status: retired
validated-by: REQ-091, REQ-092 via CASE-0370, CASE-0371
validated-rungs: outcome
validated-provider: none
---
# The proctor skill tracks what actually shipped

**Read `docs/features-to-triage/00-WAVE-7-DIRECTION.md` first.** Sequence this last in the wave: it documents
the surface the other items build, so it cannot be written before they land.

## The problem

`~/Dev/fledgeling-plugins/plugins/proctor/skills/proctor/` is the instruction file a
model reads before driving Proctor. It is the product's real interface, more than the
tool schemas are, because it decides what a model attempts and what it believes a
result proves.

It is drifting. Measured 2026-08-15 against `main`, the skill and its `tools.md` do not
mention `agentBuild` (PRO-0030), the audit trail being signed rather than only sealed
(PRO-0032), the `surface` and `flags` fields on a browser handoff (PRO-0035), or
`AgentRecovery` replacing the removed Re-check row (PRO-0028). The tool count and the
newer assertion kinds are correct, so this is drift rather than rot.

Wave 7 will make it much worse: actuation moves to Cua, an iOS lane appears, and the
two-planes section stops describing how actuation works.

## What it should do

Bring the skill back in line with the shipped surface, and rewrite the sections wave 7
invalidates.

Specifically:

- **"Two planes, and why it matters" needs to become planes *and lanes*.** The
  process-directed and synthetic-event distinction still matters to a caller, because
  it still decides what a result proves. What changes is that Proctor is no longer the
  thing posting the events. Say who actuates, and keep the honesty rule that a
  synthetic-plane result proves the narrower claim.
- **A new iOS section.** Deep links via `simctl`, Maestro for flows, and above all the
  ceiling: an iOS target is not a window, the Mac's accessibility API does not reach
  into the simulator, and a model that assumes parity with the macOS lane will waste a
  campaign. State what cannot be done as clearly as what can.
- **"Before anything else" gets bigger.** `proctor_doctor` will report a toolchain
  rather than two grants, and the skill should say which missing pieces disable which
  lanes.
- **The observation half needs saying out loud.** It is now the product's centre and
  the skill barely mentions it: captures carry frame trustworthiness, and that is the
  reason a Proctor capture is worth more than a screenshot from anything else.

## How to write it

The runner writing this should load `/opus-5-guide` first, because Opus 5 executes this
file and its authoring rules differ from earlier models in ways that change the text:

- Give the complete task up front and let the reader finish; Opus 5 follows
  instructions literally and does not generalise a rule from one case to another, so
  state rules per case rather than relying on an example to carry them.
- Leave out verification scaffolding. Instructions like "double-check" or "verify with
  a subagent" compound with behaviour the model already has and cost tokens without
  improving results. The existing skill should be read for these and have them removed.
- Cap subagent spawning explicitly and say which scenarios warrant it. The skill
  already caps fan-out at four; keep an explicit cap and keep the reason with it.
- Calibrate length explicitly for the report the skill produces. Effort controls
  thinking, not visible length.
- Prefer calm trigger language and positive examples of what to do over lists of what
  to avoid.

## Not in scope

Changing the campaign's seven stages, which are the skill's actual method and are not
affected by what performs the clicking. Also not in scope: the plugin version bump and
any release of the plugin, which is the reader's call.
