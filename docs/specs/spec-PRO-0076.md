# PRO-0076: the guest lane, capped at two, with a queue

**ID:** PRO-0076 · **Status:** Ready for AI · **Created:** 2026-08-20
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

## Implementation plan

Implementation plan: `docs/plans/plan-PRO-0076.md` (committed: `cdaeea0`, tier: Large).
Out-of-family plan review: grok `grok-4.6` `xhigh`, verdict ACCEPT WITH CHANGES, folded in.

---

## Progress (2026-08-20)

Built on `ai/pro-0076` off `ai/wave-9`. **1,788 tests in 210 suites green**, whole suite, via
`./scripts/test.sh`.

**Ten of twelve criteria settled. A1 is settled at the seam and BLOCKED live. A1b is BLOCKED.**
Both stop at the same place and it is the manual gate this wave recorded in advance: Accessibility
and Screen Recording cannot be granted from outside a macOS guest, and installing Proctor inside
`anvil-mac-node` needs a login this agent does not hold. What was measured on the way is recorded
below; what a person must do is listed after it.

An earlier draft of this note claimed A1b settled. It was not: the guest was booted and probed, and
no Proctor was built for it, copied into it or launched inside it, which is what the clause asks
for. Corrected here rather than left standing.

### Per clause

| Clause | State | Evidence |
|---|---|---|
| A1 | **settled (seam) · BLOCKED (live)** | `GuestAttachWiringTests` — an attached session's calls reach the link and `FakeAX.performed` is empty. That proves the routing and the host actuating nothing; it stands on a fake link, so it is **not** the live measurement the clause asks for. Blocked at the TCC grant. |
| A1b | **BLOCKED** | No Proctor was built for the guest, copied into it, or launched there. What the install needs is measured and recorded below; the install itself needs a guest login. |
| A2 | settled | `GuestAttachWiringTests` — a failing link refuses naming the guest, no host step; a source guard asserts the fallback branch does not exist. |
| A3 | settled | `GuestAttachmentTests` — tier derived both directions; `darwin` → `.macos` → `.native`. |
| A4 | settled | `GuestAttachmentTests` + `GuestAttachWiringTests` — all three cases, including one identity's handle under another's guest session. |
| A5 | settled | `GuestPoolLaneTests` — capacity 1/2/3 admit 1/2/3; one scan cannot admit three into two; a linux guest is not counted against the macOS pool. |
| A6 | settled | `GuestPoolLaneTests` + `GuestPoolWiringTests` — two sessions on one guest serialise with a slot free. |
| A7 | settled | `GuestPoolWiringTests` — the third queues rather than being refused; the timeout carries position and depth. |
| A8 | settled | `GuestPoolWiringTests` — the per-session cap binds the attach path; the holder's idle ceiling is separate from the wait limit. |
| A9 | settled | `GuestAttachWiringTests` — a stopped guest is started through the audited path, with `guestStart` and `guestAttach` rows; release stops only what this agent started. |
| A10 | settled | `GuestPoolWiringTests` + `GuestPoolLaneTests` — a full pool queues for a person-started guest and for one another session holds; no `stop` in the provider log. |
| A11 | settled | `GuestPoolWiringTests` — a vanished guest releases the slot and names the disappearance; concurrent releases decrement once. |
| A12 | settled | `GuestPoolWiringTests` — capacity, held, holders and waiting each asserted; the provider call count is unchanged across two reports. |

### Which tests were armed, and against what

Ten mutations were applied to the delivered code one at a time, the named suite run, and the
mutation reverted. Every one was caught, so these tests fail when the behaviour they name is
broken rather than merely passing beside it. Recorded here because "armed" is otherwise an
assertion about work nobody can see.

| Mutation applied to production code | Suite | Caught |
|---|---|---|
| `forwardToGuestIfAttached` returns nil always (never forwards) | `GuestAttachWiringTests` | yes, 5 issues |
| the link-failure path returns nil instead of refusing (a host fallback) | `GuestAttachWiringTests` | yes |
| `poolsHaveRoom` ignores capacity | `GuestPoolLaneTests` | yes, 7 issues |
| the guest mutex lane is dropped from the admission set | `GuestPoolLaneTests` | yes |
| tier derivation returns `.native` for every platform | `GuestAttachmentTests` | yes, 3 issues |
| the vanish path leaves the slot held | `GuestPoolWiringTests` | yes |
| `reclaimAbandonedAttachments` never reclaims | `GuestPoolWiringTests` | yes, 2 issues |
| the `slotHeld` idempotence latch is removed | `GuestPoolWiringTests` | yes |
| `poolStatus` asks a provider for a listing | `GuestPoolWiringTests` | yes |
| the forward stops checking for a vanished guest | `GuestPoolWiringTests` | yes |
| a failed attach stops leaving the guest it started | `GuestPoolWiringTests` | yes |

Two of those took a second attempt, and both were the test being weaker than it read. The
idempotence test first covered only sequential releases, where removing the attachment already
guards, so the latch mutant survived; the case that distinguishes them is two releases racing
across an `await`, since `Session` is a reentrant actor. That race was still unreachable because
the fake link's `close()` never suspended, so the fake was under-modelling a real socket close and
the test would have passed with the latch removed.

### The completeness critic, and what it changed

The out-of-family critic (grok `grok-4.6`, `xhigh`) returned **INCOMPLETE** on the first pass and
found five real defects plus two overstated claims in this note. All are fixed above or corrected
here:

- `guestVanishedError` returned nil when the provider adapter could not be resolved, so "the
  provider died" — a case A11 names — reported all-well and left the slot held. It is now a vanish.
- `detach` reported `guestStopped` from `startedByThisAgent` before the stop ran, so a stop that
  failed still said it had stopped while the VM kept running uncounted. It now reports the measured
  outcome, and the failed stop is recorded on the trail.
- the release-path stop called the adapter directly rather than the audited `guestMutate` A9 keeps.
- `grantable` defaulted an unstated pool capacity to 1, turning any pool the caller did not
  describe into a mutex, which contradicts the spec for the linux and windows pools. Unstated is
  now unbounded, and a test fails if a platform is ever added without a capacity, so the macOS cap
  cannot go missing by omission.
- an attached session calling only host-only tools never touched its attachment, so a session
  driving through `proctor_doctor` looked idle and could have its slot reclaimed.
- A1b was claimed settled and is not; A1's live half was under-qualified. Both corrected above.

A second pass over the fixes returned three more, two of them defects the first round of fixes
introduced or left standing. All three are fixed:

- **`stopGuestAfterFailedAttach` kept the shape that was being removed elsewhere**: a missing
  adapter returned silently, `try?` swallowed the failure, and the audit row said `ok` regardless.
  An attach that started a guest and then failed its probe could therefore leave a macOS guest
  running, uncounted, with its slot already given back — the A11 hole on the single path that had
  just consumed Apple's cap. It now goes through the same audited stop and records honestly when
  the guest could not be stopped.
- **The stop outcome was stored on one field of a `Session` shared by every identity**, which the
  reporting fix introduced. A concurrent release of another attachment could overwrite it between
  this stop and `detach` reading it, reporting a guest this call had just stopped as still running:
  the inverse of the lie it was added to fix. The outcome is returned from the release now.
- **`grantable`'s `capacities` parameter defaulted to an empty map**, so a caller who omitted it got
  unbounded pools and Apple's two would not bind. It defaults to `GuestPool.capacities`.

Two findings were **not** acted on, with reasons. The critic could not see `GuestHandleScope` or
`Session.windowHandle` (they were outside the excerpt sent) and read A4's resolver as missing; it
is present and tested. And `peerIsAlive` treating an unparseable identity key as alive is
deliberate: reclaiming a slot on the strength of a string this build could not read would be worse
than holding it, and it is commented as such.

### A1b — what the guest-side install actually needs

Measured against `anvil-mac-node` on 2026-08-20. It was started for this and stopped again; it is
back in the `stopped` state it was found in, and nothing about it was changed.

- **It boots headless.** `tart run anvil-mac-node --no-graphics`, `State: running` within ~20s,
  `OS: darwin`, 8 CPU, 16384 MB.
- **The Tart Guest Agent is ABSENT.** `tart exec` fails with *"Failed to connect to the VM using
  its control socket … is the Tart Guest Agent running?"*. So `tart exec` is not a route into this
  guest, and the install has to go over SSH.
- **SSH is reachable and needs a credential this agent does not have.** The guest takes
  `192.168.65.2` from the dhcp resolver, port 22 is open and `sshd` answers, offering
  `publickey,password,keyboard-interactive`. No key on this host authenticates as `admin`. No
  password was attempted: the guest belongs to another project, and guessing a credential against
  somebody else's machine is not something to do unasked.
- **Signing, and what it costs the reader.** A guest build signed ad-hoc keys its TCC grants to the
  exact bytes, so Accessibility and Screen Recording are thrown away on every rebuild and must be
  re-granted by hand each time. A Developer ID signature keys them to the team-scoped identity
  instead and survives a rebuild, which is why this repo's `scripts/install.sh` notarises by
  default. Use the Developer ID path for the guest too; the ad-hoc build is only worth it for a
  throwaway you will run once.

### A1 — the manual gate, and exactly what a person must do

Accessibility and Screen Recording cannot be granted from outside a macOS guest, so the live half
of A1 stops here rather than being reported as verified. In order:

1. **Start the guest and open a display.** `tart run anvil-mac-node` (without `--no-graphics`, so
   there is a screen to click in). It boots to the login window in about 20 seconds.
2. **Get in.** Log in at the console, or install an SSH key for the guest's admin user. Nothing
   below can be done over `tart exec`, because the guest has no Tart Guest Agent.
3. **Put a Proctor inside it.** Build with `scripts/install.sh` and copy the notarised
   `Proctor.app` into the guest's `~/Applications`, then run its installer inside the guest so
   launchd owns the agent. Ad-hoc signing works and costs a re-grant on every rebuild.
4. **Grant the two permissions, inside the guest, in its own GUI session.** System Settings >
   Privacy & Security > **Accessibility**, add `Proctor.app`, switch it on. Then System Settings >
   Privacy & Security > **Screen Recording**, same bundle, same switch. An SSH session cannot do
   this: it is not the foreground Aqua session that owns the desktop, and neither an agent nor a
   daemon can raise the TCC prompt.
5. **Forward the socket.** On this Mac, open the tunnel `proctor_guest reach` describes:
   `ssh -L <localSocket>:<remoteSocket> admin@192.168.65.2`, with `remoteSocket`
   `~/Library/Application Support/app.fledgeling.procter/agent.sock` for a standard install.
   Proctor does not open this and does not install `ssh`.
6. **Then run the proof.** `proctor guest --action attach --guest anvil-mac-node`, followed by any
   actuating call, and confirm the result's `machine` names the guest. The clause is settled when a
   step performed through that session changes something inside the guest and nothing on this Mac.

### Discovered, and reported rather than minted

- **A defect in PRO-0058's code, fixed here because it blocks A3 and A5.**
  `GuestPlatform.infer` tested `hay.contains("win")` for Windows, and dar-**win** contains it. Every
  macOS guest whose provider named its platform `darwin` was classified Windows: delegated tier, no
  accessibility tree, no frame-status channel, and refused by `GuestReach` as a machine with no
  Proctor inside. Latent since PRO-0058; it surfaced now because `tart` is the first provider here
  that says `darwin` rather than `macOS`. Matching is now on a token that starts with "win".
- **A question for the reader, not decided here: the pool counts attachments, not VMs.** A guest
  booted by a bare `proctor_guest start`, or by a person typing `tart run`, is running and is not
  in Proctor's count, so three macOS guests can be up while the pool reports two slots.

  This was nearly built out and deliberately was not. Making `start` take a slot only means
  anything if the slot is held for as long as the VM runs, and `start` is a one-shot call that
  returns immediately, so it would need a per-guest lifetime registry with its own release rules.
  The spec's model is narrower and coherent: the pool gates **attachment**, A9 lets admission start
  a guest, and A10 already says a guest a person started is waited for rather than evicted.
  Counting VMs instead of attachments would also mean polling a provider on a schedule, which is
  precisely what A12's discipline refuses. So the doctor states the limit rather than implying the
  count is the whole truth, and widening it is a scope call for the reader rather than an
  implementation detail to settle here.

---

## Gap-fix pass (2026-08-20)

The fresh-context verifier returned NEEDS MORE WORK on six findings. All six are closed.
**1,794 tests in 211 suites green**, whole suite, twice, via `./scripts/test.sh`.

### Two production lines nobody was testing

The verifier deleted `Dispatch.swift:80` and `Dispatch.swift:443` one at a time and the whole
suite stayed green both times. The seam functions were tested directly; nothing drove them
through the dispatcher, which is the layer that decides whether a call reaches the seam at all.
`DoctorReplyWiringTests` exists in this repo for exactly that reason and both fixes follow it.

`GuestDispatchWiringTests` (new) drives an attached session through `Dispatcher.handle` and
asserts the call lands on the guest link, the guest's answer comes back verbatim, and
`FakeAX.performed` is empty. Armed by deleting the funnel: three issues, the first reading
`(response → AgentResponse(id: "1", ok: false, … message: "proctor_act requires steps as an
array")).ok → false` — a guest session doing host work, which is A2's failure exactly.

`DoctorReplyWiringTests` gains two cases for A12: the macOS pool's capacity, held and waiting
in the reply a caller receives, and a real attachment showing up as a held slot named by guest.
Armed by deleting `report["guestPool"] = await session.poolStatus()`: two issues, both
`(reply["guestPool"] → nil).objectValue → nil`.

### A7's second half now stands on a refusal the queue produced

`theWaitSaysWhereItStood` used to construct the `RunQueueRefusal` itself, so it would have
passed if a queued attach never produced one. It now holds Apple's two, queues three more
attaches, and opens the scheduler's give-up timer through the injected `sleep` — the same seam
that exists so a wait limit is provable in milliseconds. The depths are read back out of the
three messages and asserted as 3, 2 and 1, which is what three waiters giving up one after
another produces and what a literal could not.

### Three defects the builder did not report

**A socket leak on the attach guard.** The "already attached" check sits four suspension points
ahead of the write, and `Session` is a reentrant actor, so two attaches on one identity both
passed it; the second overwrote `guestLinks[key]` and left a `GuestLink` holding an unclosed
socket with nothing left to close it. The per-guest mutex lane hid it, because the same-guest
case never raced. Asking again immediately before the write, with no await in between, makes
the guard binding; the loser takes the existing failure path, which now also closes the link it
opened. Armed: without the re-check both attaches succeed and both links stay open.

**An unaudited stop.** `TartProvider.start` ran a bare `tart stop` when a boot never came up.
That is a lifecycle change on somebody's machine with no row on the trail, and A9 says a stop
stays gated and recorded. It is the third time this shape has been found in this feature, so
there is now one function rather than three fixes: `stopGuestThroughAuditedPath` is what the
release path, the failed-attach cleanup and the boot timeout all call, and the boot timeout is
handled in `Session.guestMutate` because that is where the audit sink is. The adapter reports
the timeout and stops nothing; `guestMutate` is its only production caller, so nothing is
orphaned.

**A doc comment on the wrong type.** `TartTool` was inserted between `PrlctlTool`'s doc comment
and `PrlctlTool`, so the symlink paragraph documented tart. Each paragraph is back on the type
it describes.

### Left as it stands, with the reason

A5's mutant produced a hang rather than a red assertion, and `scripts/test.sh`'s absent-verdict
rule caught it. Nothing cheap converts the hang into an assertion without contorting tests that
already prove the arithmetic, so it is left and recorded here rather than worked around.

A1's live half and A1b are unchanged and still BLOCKED at the in-guest TCC grant. Nothing in
this pass touched `anvil-mac-node`.
