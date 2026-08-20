# PRO-0076: the guest lane, capped at two, with a queue

**ID:** PRO-0076 · **Status:** Ready for Plan · **Created:** 2026-08-20
**PRD:** §9 (machines and witness tiers), §10 (lanes) · **Branch:** `ai/pro-0076` off `ai/wave-9`
**Depends on:** PRO-0058 (the guest seam), PRO-0060 (`reach`), PRO-0061 (the auto-route gate)
**Research:** `docs/research/2026-08-15-dossier-proctor-vs-cua.md`,
`docs/research/2026-08-15-proctor-vs-cua-driver.md`
**Live target:** `anvil-mac-node` under `tart` (reader's decision, 2026-08-20)

## The problem

Asked for directly: run the macOS applications under test inside macOS virtual machines rather
than on the operator's own Mac, up to the two Apple silicon allows, with a queue for when
several projects want them at once.

Two things stand between here and that, and only one of them is the queue.

**Nothing can execute inside a guest.** `GuestProvider` parses `lume` and `prlctl` and owns no
lifecycle policy. `proctor_guest reach` forwards the guest agent's Unix socket over SSH
`StreamLocal` and stops there. PRD §9 states the consequence in its own words: *"This process
cannot yet perform a step inside a guest — `reach` describes the tunnel, it does not attach."*
So `GuestRoute.decide` refuses rather than routes, which is the honest behaviour for a tunnel
nobody drives through and useless as a place to run a campaign.

**Nothing arbitrates the guests.** `RunQueue` has three lanes and every one of them is a mutex:
`.app(id)` and `.global` admit one holder. A guest needs two different answers at once — one
session per guest, because two campaigns cannot drive one VM, and at most two macOS guests
booted per host, because that is Apple's limit rather than a number anyone here chose. A mutex
lane can express the first and not the second.

A queue over slots nothing can use would be a queue for nothing, so the attach comes first.

## Scope

Deliver both halves at the scope below, plus the third provider that makes them measurable here.
If a better approach than the one described becomes apparent, say so in a sentence and build what
is specified rather than substituting it.

**Guest creation stays out.** Making a VM from scratch and granting Accessibility and Screen
Recording inside one are things a person does; the grant is the reader's hands and the run waits
for it rather than working around it.

### What the preflight measured, and what the reader settled

The machine has `lume` (no guests), `prlctl` (one Windows 11 guest, registration `invalid`) and
**`tart` 2.32.1 with a stopped macOS guest, `anvil-mac-node`**. The spec's original two providers
therefore had nothing live to attach to, which would have left A1 and A2 carried.

Asked which Done meant here, the reader chose to provision rather than carry, and to reuse the
existing node rather than download a fresh one. So:

- **`tart` becomes a third adapter**, beside `lume` and `prlctl`, on the same `GuestProvider`
  seam. Its surface, measured on this machine on 2026-08-20 rather than read from its docs:
  `list --format json` returns `Name`, `State`, `Running`, `Size`, `Disk`, `Source`, `Accessed`;
  `get <name> --format json` returns `OS`, `Running`, `Memory`, `Display`, `CPU`, `State`,
  `Disk`, `DiskFormat`; `run` starts, `stop` stops, `clone` clones, and `ip <name> --wait N`
  yields the address `reach` needs. `anvil-mac-node` reads `OS: "darwin"`, 8 CPU, 16384 MB,
  display 1024x768, 50 GB.
- **`OS` is read, not assumed.** `tart get` states the guest's platform, so A5's macOS-only cap
  is derived from what the provider says rather than from the guest's name or a default. Prefer
  the same treatment for the other two adapters wherever their output carries the platform.
- **`anvil-mac-node` belongs to another project.** Driving it is authorised; changing it is not.
  Never `delete`, `prune`, `rename` or `export` it, and stop it only under A10's rule, which
  already forbids stopping a guest this agent did not start.

## Acceptance criteria

### Attaching

1. **A1** — a session attached to a guest executes its steps inside that guest. The host agent
   routes tool calls over the socket `reach` forwards; the guest's own Proctor holds the guest's
   TCC grants and talks to the guest's window server. The host agent actuates nothing on behalf
   of a guest session. **Measured live** against `anvil-mac-node`, not carried.
1b. **A1b** — a Proctor reaches the guest. Build it for the guest, install it there, and record
   what the install needed: whether SSH was already reachable, whether the Tart Guest Agent is
   present (`tart exec` requires it), and how the agent is launched inside the guest. A guest
   build signed ad-hoc loses its TCC grants on every rebuild, so record which signing identity
   was used and what that costs the reader in re-grants.
2. **A2** — a run whose `Machine.kind` is `guest` never executed a step on the host. This is
   PRO-0051's rejected fallback and it fails closed: when the tunnel is down the batch is
   refused with the guest named, exactly as `GuestRoute.refuseHost` reads today. A verdict about
   the wrong machine is the one outcome this feature must not be able to produce.
3. **A3** — `Machine.tier` is derived from the guest's platform rather than supplied by the
   attach site: `macos` is native, `linux` and `windows` are delegated. `tier` keeps its absence
   of a default, for the reason PRD §9 gives.
4. **A4** — `gst-` handles resolve only within the session that attached them. A host window id
   handed to a guest session, or the reverse, is a refusal naming both machines rather than a
   lookup that happens to miss.

### The two slots

5. **A5** — `RunLane` gains a counted lane alongside its two mutex lanes, and the counted lane's
   capacity is a parameter. The macOS guest pool is that lane at capacity 2; a Linux or Windows
   guest pool is the same lane at whatever its provider allows, because the cap being honoured
   is Apple's rule about macOS guests and not a property of virtualisation. Which pool a guest
   joins comes from the platform its provider reports, so a guest is never counted against the
   macOS cap because of its name.
6. **A6** — one session per named guest. Two sessions naming the same guest serialise on it even
   when a slot is free, and the second one's wait says which session holds it.
7. **A7** — the third macOS guest waits. A run that would boot a third is queued against the pool
   rather than refused, and its wait carries position and depth the way `RunQueueError.timedOut`
   already does.
8. **A8** — waiting is bounded and reported. The pool honours the existing per-session waiting
   cap and timeout, so a project that keeps queueing cannot starve the others.

### Lifecycle, and what the queue may do to a machine

9. **A9** — admission to a slot may **start** the named guest, and release may stop a guest this
   agent started. Both are already `proctor_guest` actions and both stay gated and recorded.
10. **A10** — the queue never evicts. A guest a person started, or one another session holds, is
    waited for and never stopped to free a slot. Stopping a running VM discards its state, and a
    scheduler that may do that to reach a queued run can destroy work nobody asked it to risk.
11. **A11** — a guest that vanishes under a holder — stopped from outside, host slept, provider
    died — releases the slot and fails that run with the disappearance named, rather than
    leaving a slot held by nothing.

### Reporting

12. **A12** — `proctor_doctor`'s `guest` lane reports the pool: capacity, how many slots are
    held, by which sessions and guests, and how many runs are waiting. It continues to locate
    `lume` and `prlctl` by filesystem read and continues to execute neither, so a health check
    still costs no VM.

## Decisions taken at triage

- **Two is Apple's number.** macOS on Apple silicon permits at most two concurrently running
  macOS guests per host. It is recorded as a platform constant with that reason beside it, not
  as a tunable, and it constrains macOS guests only.
- **This revises PRD §9's "Proctor owns no VM lifecycle."** A9 lets the pool start and stop a
  guest it was pointed at, which that sentence currently reads as excluding. The part worth
  keeping is the part that was actually protecting something: Proctor creates nothing, installs
  nothing inside a guest, and grants nothing. Update §9 to say that in the same change, so the
  PRD and the code do not disagree about which is true.
- **The guest's Proctor is the actuator.** The alternative — the host agent driving the guest's
  UI through the provider's own screenshot and click surface — is the delegated tier, and using
  it for a macOS guest would throw away the accessibility tree and the frame-status channel that
  make a macOS guest worth having over a Linux one.
- **Three providers, one seam.** `tart` earns its place by being the only one with a working
  macOS guest on this machine, so it is what makes A1 measurable rather than carried. It goes on
  the existing protocol with no new abstraction, and its adapter creates a process only in the
  production type, exactly as the other two do.
- **The reader grants inside the guest.** Accessibility and Screen Recording cannot be granted
  from outside a macOS guest. The run stands the guest up, installs Proctor, and then stops and
  asks, rather than reporting the attach unverified or finding a way around a permission.
- **Contention is per host.** Two Macs each run two guests; nothing here coordinates across
  machines. A cross-host pool is a different feature and is not assumed by this design.

## Open questions, with the assumption taken to unblock

- **Where the queue lives when the projects are separate processes.** Several campaigns on one
  Mac reach one agent over one socket, so the existing in-agent queue already spans them.
  **Assumption:** no external broker; the pool is the agent's, and a second agent on the same
  Mac is out of scope for the same reason two agents already contend badly today.
- **Whether a slot survives a run ending.** Booting a macOS guest costs tens of seconds, so
  releasing the slot at the end of every batch would spend that repeatedly across a campaign.
  **Assumption:** the slot is held for the session's attachment rather than per batch, released
  on detach, on session end, or on the idle timeout in A8.
- **What a `clone` does to the count.** Cloning a stopped guest touches no slot; cloning a
  running one is not something the providers agree about. **Assumption:** refuse to clone a
  guest holding a slot, and say why.

## Notes for the runner

Read this spec, the two research documents named above, PRD §9 and §10, and the four files the
problem statement names, before changing anything. The on-disk artifacts are the memory: after a
compaction, re-read them rather than working from what is left in context.

Build the attach before the pool — the pool's tests need a guest session that can execute, and
writing them against a stub produces a queue proved only against itself.

Work directly rather than delegating. A subagent earns its cost here only for a wide read across
the guest, queue and session code that would otherwise fill this context, and one is enough;
nothing in this feature warrants several, and none should be spawned to check work already done.

Keep the changes to what these criteria describe. The queue, the session actor and the audit
trail are all touched by this feature and none of them is being redesigned by it.

Match the plan and progress notes to what the work needs: cover the substance and stop.

## Verification

Status: **Ready for Plan.** Nothing built.

A1 and A2 are measured against `anvil-mac-node` rather than carried, which is the reader's
decision of 2026-08-20 and the reason `tart` is in scope. Everything else is settled against the
injectable seam, as the other two adapters already are.
