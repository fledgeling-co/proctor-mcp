# The skill advertises 20 tools of 27, and talks an agent out of the guest lane

**Wave 12, brief 2 of 2.** Independent of `77`. This is the instruction file at
`~/Dev/fledgeling-plugins/plugins/proctor/skills/proctor/`, not the repo — the work lands there and
this brief lives here because the repo is what it is meant to describe.

Supersedes the still-open `53-the-proctor-skill-tracks-what-shipped.md`, which found the same drift
on 2026-08-15 and named a smaller version of it. Fold that brief in rather than running both.

## The measurement, taken 2026-08-21

**Seven shipped tools are absent from the skill.** `references/tools.md` advertises 20; the server
ships 27. Missing: `proctor_guest`, `proctor_queue`, `proctor_hud`, `proctor_history`,
`proctor_recent`, `proctor_resource`, `proctor_actuation`. An agent working from the skill cannot
reach a lane it does not know exists.

**`proctor_guest` appears nowhere in the skill at all** — not in `SKILL.md`, not in `tools.md`, not
in either reference file. The guest lane shipped in wave 10 and was proved live against a
provisioned macOS guest; the instruction file has never mentioned it.

**The one thing the skill says about VMs is a discouragement, and it answers a different question
than the one an agent is asking.** `SKILL.md:802`:

> Apple silicon caps concurrent macOS guests at two, so a VM fleet is not the answer, and more real
> parallelism past that is a hardware purchase rather than a configuration change. Do not design a
> campaign that assumes otherwise.

Every clause is true, and it is a correct answer about **scale**. An agent reads it as a
prohibition. The reasons to use a guest are isolation rather than throughput: a clean machine, a
pinned OS version, a state you can discard, and not commandeering the desktop the person is using.
The two-guest cap says nothing about any of those.

**The skill's description offers two lanes** — native macOS, and a narrow iOS Simulator lane. The
description is the routing text, so it shapes what an agent believes the skill can do. No guest
lane, no Windows.

## What to write

**Bring `tools.md` back in line with the 27 shipped tools**, each described from the shipped
catalogue rather than from memory. `Sources/ProctorCore/ToolCatalogue.swift` is the source of truth
and already carries prose written for a model to read.

**Add a "when a guest is the right lane" section**, and let it be short. The decision is: use the
host when the app under test is here and the person's desktop can be borrowed; use a guest when the
test needs a clean or pinned machine, when it must not touch the person's session, or when a run
would otherwise leave state behind. Then the cap, in its correct place — as the answer to "can I
run twelve of these at once", which is no.

**Rewrite `SKILL.md:802` so the cap stops reading as a prohibition.** Keep the fact, keep the
citation, and move it under the scale question it answers.

**Extend the description to name the guest lane, and be honest about Windows.** macOS guests get the
native tier: the guest runs its own Proctor holding its own TCC grants, with a real accessibility
tree and the tri-observer check. Linux and Windows guests are **delegated** — the catalogue already
says so — with no Proctor socket, no accessibility tree, coordinates and screenshots only. A skill
that implies parity there will produce campaigns that assume an element tree that does not exist.

**Say plainly that nothing provisions a guest.** `proctor_guest`'s own description is the wording to
follow: list, status, start, stop and clone operate on a machine that already exists, and creating
one, granting Accessibility and Screen Recording inside its Aqua session, and cloning that granted
image are things a person does with the provider's CLI. An install must never happen as a side
effect of a tool call. An agent that knows this asks for a provisioned guest instead of failing
halfway through a campaign.

## Write it to the guidance the repo already follows

`/opus-5-guide` before editing, because Opus 5 runners execute this file. Give the complete spec up
front and let the runner finish; leave out verification scaffolding, which compounds into
over-verification; cap subagent spawning explicitly; calibrate length in countable units, since
effort controls thinking rather than output; use calm trigger language rather than "CRITICAL: you
MUST"; and say what to do rather than what to avoid, with the reason attached. Brief `53` recorded
that the existing skill still carries verification scaffolding to remove.

Route the prose through `/agent-voice` at its `skill` register.

## What this brief does not do

It does not add a `provision` action to `proctor_guest`. That would change a safety posture the
current design took deliberately, and whether to change it is the reader's call rather than a
documentation decision. Record the question; do not answer it in the skill.

It does not claim the guest lane is easy. Provisioning one took most of a session and four closed
routes, recorded in `docs/specs/spec-PRO-0076.md`. The skill should set that expectation rather
than hide it.
