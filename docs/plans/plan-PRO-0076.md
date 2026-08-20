# Plan — PRO-0076: The guest lane, capped at two, with a queue

**Spec:** `docs/specs/spec-PRO-0076.md`
**Plan size:** Large
**Branch:** `ai/pro-0076` (worktree `.worktrees/PRO-0076`, from `ai/wave-9` @ `492a8a1`)
**Gate:** `swift build` + `./scripts/test.sh` (never bare `swift test` — the pipe eats the exit code)

Revised once against the out-of-family gate; the gate's findings and their dispositions are at the
foot of this file.

## What was measured, and what it changed

Five findings from reading the code and running the CLI. Each moved the design, so each is
recorded before the slices rather than discovered inside one.

### M1 — There is exactly one `Session`, so an attachment cannot be a field on it

`Sources/ProctorAgent/main.swift:125` builds one `Session` for the whole agent. Callers are told
apart by `SessionIdentity.current`, a task-local set per request from the peer process
(`Sources/ProctorAgent/SessionIdentity.swift:47`). `Session.machine` is today a single stored
field defaulting to `.host` (`Session.swift:199`), and the only writers are five test sites —
production never calls `setMachine`.

So an attach that wrote that field would move **every** connected client onto the guest. The
attachment is therefore a map keyed by `RunSessionIdentity.key`, and `machine` becomes a computed
lookup falling back to the existing stored field. That keeps all five existing `setMachine` sites
working unchanged.

M1 also decides the holder lifetime, and that is the harder half — see D4.

### M2 — `tart list` does not carry the platform; `tart get` does

Measured on this machine 2026-08-20, tart 2.32.1:

```
tart list --format json  -> [{Size, State, Source, Name, Running, Accessed, Disk}]   no OS
tart get anvil-mac-node --format json
                         -> {OS: "darwin", CPU: 8, Size, State, Display: "1024x768",
                             Memory: 16384, DiskFormat, Disk: 50, Running: false}
```

The spec requires `OS` to be read rather than assumed, and A5 derives the macOS cap from the
platform the provider reports. A listing with no `OS` cannot answer A5, so `TartProvider.list()`
enriches each row with a `get`.

`GuestPlatform.infer(os: "darwin", name: nil)` returns `.macos` — read at
`Sources/ProctorCore/GuestInventory.swift:113`, where the macOS branch tests `hay.contains("darwin")`.
This is the only live target's classification, so it gets a test rather than a reading.

Name inference is deliberately **not** used for tart. `infer` would read `anvil-mac-node` as macOS
and `anvil-linux-node` as linux, and both would be right, which is what makes it a trap: a guest
named `build-box` would be counted against Apple's cap, or excused from it, by its name.

### M3 — `Dispatch.handle` is the single funnel, so the forward has one seam

`Sources/ProctorAgent/Dispatch.swift:73` switches every tool in one place. A1 says the host agent
routes tool calls over the socket `reach` forwards, so the intercept sits there, ahead of every
local path.

### M4 — `RunQueuePlan.grantable` is mutex-only by construction

`isDisjoint(with: taken)` is the whole admission rule (`RunQueue.swift:270`). It can express "one
session per guest" and cannot express "at most two macOS guests". Adding a `.pool` case to
`RunLane` while leaving `isDisjoint` in place produces a **mutex of capacity one**, not a counted
lane — so the counted admission is a genuine rewrite of that function, and capacity 1 is the
specific wrong answer to watch for.

### M5 — Proctor does not open the tunnel, so `attach` consumes one that exists

`GuestReach` is a *recipe*: `SessionGuest.guestReach` returns `localSocket` / `remoteSocket` /
`host` and never a shell line, because a tool result carrying `ssh -L` is an instruction a model
with a shell would run. PRD §9 and the catalogue both state that a person opens the tunnel.

So `attach` does not create the forward. It takes a `localSocket` — defaulting to
`GuestReach.defaultLocalSocket(handle:home:)`, the same path `reach` already names — and connects
to it. A socket nothing is listening on is A2's refusal, not an attempt to open one. This is why
the tunnel is a step in the manual gate rather than a slice here.

## Design decisions

- **D1 — Two new lane cases, one mutex and one counted.** `RunLane.guest(String)` is a mutex lane
  keyed by `provider:name` and gives A6 on the existing machinery. `RunLane.pool(String)` is the
  counted lane keyed by **platform**, because the cap is a platform rule. Capacity is not part of
  the case: two demands for the same pool must hash equal, so capacity travels beside the lanes as
  a parameter, which is what A5 asks for.

  **Occupancy is a count, and this is the part that decides whether A5 is true.** `grantable` gets
  a `[String: Int]` occupancy built from `active`, and inside the scan every grant **increments**
  that count before the next waiter is considered. Both other shapes are wrong and each fails a
  different way: putting `.pool` into the `taken` set caps the pool at one, and counting only
  `active` without the in-scan increment lets a single scan admit three. Both get a test.

- **D2 — A full pool marks, it does not break.** `.global` stays a barrier. A full pool marks
  itself for the rest of the scan and the walk continues, so FIFO holds within the pool while host
  runs behind it still start. A pool that broke the scan would let a busy guest lane starve every
  Mac run on the machine.

- **D3 — Two is a platform constant with its reason attached, and it binds macOS only.**
  `GuestPool.capacity(for:)` returns 2 for `.macos`. No platform rule is known for Linux or
  Windows and the spec names no number, so those pools are **unbounded by Proctor and bounded by
  their provider** — which is what "whatever its provider allows" means when the provider states
  no number. Recorded as an assumption, not presented as a measurement.

- **D4 — The slot is held for the attachment, and the holder needs its own release rule.** The
  spec's assumption is taken as written: acquired at attach, released at detach or session end,
  because booting a macOS guest costs tens of seconds and re-paying that per batch would dominate
  a campaign.

  **"Session end" is undefined under M1, and that is a leak, not a detail.** There is one
  `Session`; identity is a task-local per request; a peer that attaches and then dies calls no
  detach. A8's timeout expires *waiters*, not *holders*, so two dead attachments would occupy
  Apple's two forever. So the holder gets its own rule, kept distinct from A8:

  1. **The peer going away releases.** `SessionIdentity` already reads the peer pid and its start
     time (`SessionIdentity.swift:52-60`). A holder whose peer process is gone is released on the
     next pool decision. This is the primary rule and it needs no timer.
  2. **An idle ceiling backs it up**, `PROCTOR_GUEST_ATTACH_IDLE`, defaulting to a value stated in
     the code with its reason. This is A8's *spirit* ("waiting is bounded and reported") applied to
     holders; it is deliberately **not** the same constant, because a wait ceiling of 45 seconds
     would tear down a healthy attachment mid-campaign.

- **D5 — A2 fails closed at the link, never at the step.** A guest session whose link is down is
  refused before anything runs, with the guest named. There is no host fallback to disable because
  none is written, and a test asserts the host actuator recorded nothing.

- **D6 — The forward is a denylist, so a new tool fails closed.** Host-only tools are named:
  `proctor_guest`, `proctor_doctor`, `proctor_policy`, `proctor_history`, `proctor_history_clear`,
  `proctor_queue`, `proctor_hud`, `proctor_recent_activity`. **Everything else forwards.** An
  allowlist of "machine-facing" tools would silently run a newly-added actuation tool on the host
  under a guest session, which is precisely A2's failure; a denylist makes the new tool forward by
  default and the mistake visible instead.

- **D7 — `proctor_guest start` for a macOS guest is admitted through the pool.** Otherwise Apple's
  two is bypassed by the one action whose entire job is booting a macOS VM, and A5 would cap only
  attachments rather than guests. A guest a *person* started outside Proctor is still never
  evicted (A10) and is not in Proctor's count; the doctor says so rather than implying the count
  is the whole truth.

## Slices

Reordered so nothing forward-references: the pure pool lands before the attach that consumes it,
and the attach is built and tested once without a slot and then wrapped in one.

### Slice 1 — `tart` as a third adapter (A5's platform source, A1's live target)

`Sources/ProctorCore/GuestInventory.swift` · `Sources/ProctorAgent/Guest/GuestProvider.swift`

- `TartTool` beside `LumeTool` / `PrlctlTool`: binary `tart`, docs URL,
  `extraDirectories = ToolLocator.commonToolDirectories`. Detection stays a filesystem read.
- `TartInventory.parse(_:)` — pure, decodes the measured `list` array. `Running` is a real bool,
  so `running` comes from it and `state` keeps the provider's own word. Platform is nil from a
  listing, by M2.
- `TartInventory.platform(fromGet:)` — pure, reads `OS` through `GuestPlatform.infer(os:name:)`
  with `name` nil, so only the provider's word is consulted.
- `TartProvider: GuestProvider` on the existing seam, injectable `run` closure, production type the
  only one that creates a process. `list` enriches per row with `get`; `status` is `get` plus the
  row; `start`/`stop`/`clone` map to `run`/`stop`/`clone <src> <dst>`.
- `Session.resolvedGuestProviders()` gains the tart branch; the "neither lume nor prlctl" refusal
  becomes three-way.

**`tart run` is a foreground, long-lived process**, unlike `lume run`, so `start` launches detached
and polls `get` for `Running: true` under the adapter's timeout. **On timeout it stops the guest it
just launched, then reports `timedOut`.** Reporting a timeout while leaving the VM running would
orphan a macOS guest that is up, uncounted and unowned — which would make A5, A9 and A10 all false
at once. Stopping is permitted here precisely because this agent started it (A10's rule).

**Never against `anvil-mac-node`:** `delete`, `prune`, `rename`, `export`. Not on the protocol, so
there is no path to them.

### Slice 2 — The attachment, keyed by session (A3, A4)

`Sources/ProctorCore/GuestAttachment.swift` (new, pure) · `Sources/ProctorAgent/Session/Session.swift`

- `GuestAttachment`: the guest's `Machine`, its handle, the local socket path, whether this agent
  started the guest, an idempotent `slotHeld` bit (D4/slice 6), and when it attached.
- `Machine.tier` is derived from the platform and never supplied by the attach site (A3): `.macos`
  → `.native`, everything else → `.delegated`. `tier` keeps its absent default; the derivation is a
  function, not a parameter with a fallback, so there is no attach site that *could* supply one.
- `Session.attachments: [String: GuestAttachment]` keyed by `RunSessionIdentity.key`; `machine`
  becomes a computed lookup with the stored field as fallback.
- **A4 is per-identity handle scoping, not only a machine mismatch.** Three cases, each its own
  refusal naming both machines rather than `windowNotFound`:
  a host window id under a guest session; a guest-minted id under a host session; and an id minted
  under *another identity's* attachment. The third is what "resolve only within the session that
  attached them" actually says, and it is the case two guest sessions hit — where a machine-only
  check would find both sides are guests and let it through. So guest-minted ids are recorded per
  identity, and `Session.windowHandle(_:)` consults the scope before `windowsByID`.

### Slice 3 — The link, and the forward (A1, A2)

`Sources/ProctorAgent/Guest/GuestLink.swift` (new) · `Sources/ProctorAgent/Dispatch.swift`

- `protocol GuestLink` — `send(AgentRequest) async throws -> AgentResponse`, plus `probe()`. One
  production type over `SocketClient` pointed at the forwarded local socket (M5), one fake for
  tests. Same seam shape as `GuestProvider` and `ActuationBackend`.
- `GuestForwarding.isHostOnly(tool:)` — pure, the D6 denylist. Everything not named forwards.
- `Dispatch.handle` consults the current identity's attachment first; attached plus a forwarding
  tool sends the request over the link verbatim and returns the guest's response.
- **A2 is this slice's point.** A link that will not connect, or a send that fails, is an
  `AgentError` naming the guest and stating nothing ran on this Mac, in the shape
  `GuestRoute.refuseHost` already reads. No branch falls back to the host.

### Slice 4 — The counted lane, pure (A5, A6, A10)

`Sources/ProctorCore/RunQueue.swift`

- `RunLane.guest(String)` and `RunLane.pool(String)` with their `description` cases
  (`guest:tart:anvil-mac-node`, `pool:macos`).
- `GuestPool`: pool id from a platform, `capacity(for:)` carrying the two-is-Apple's-number
  comment, and `LaneDemand.forGuest(provider:name:platform:)` building `[.guest(…), .pool(…)]`.
- `RunQueuePlan.grantable` gains `capacities: [String: Int]` and counts pool lanes per D1, with the
  in-scan increment. Mutex behaviour for `.app` and `.global` is unchanged, and the existing
  `RunLaneTests` are the regression proof.
- A10 needs no code — `grantable` has no eviction path — but it gets its test here and in slice 7.

Pure and provable with no guest, which is why it precedes the attach rather than following it.

### Slice 5 — `proctor_guest action "attach"` / `"detach"`, without the slot (A1, A9's start)

`Sources/ProctorAgent/Session/SessionGuest.swift` · `Sources/ProctorCore/ToolCatalogue.swift`

- Two actions on the existing tool. `attach` resolves the guest, refuses a non-macOS or delegated
  one through `GuestReach.cannotReach`, **refuses a guest whose platform is unknown** (see below),
  may start it, opens the link at the `localSocket` a person forwarded (M5), probes it, records the
  attachment. `detach` drops it and, when this agent started the guest, stops it (A9) — never
  otherwise (A10).
- **Starting goes through the existing gated `guestMutate` path**, not a raw `adapter.start`, so
  A9's "both stay gated and recorded" is true by construction. Audited under `AuditTool.guestAttach`
  / `.guestDetach` beside the existing `guestStart` / `guestStop` / `guestClone` rows.
- **An unknown platform is refused, because nil is fail-open for the cap.** A `get` that fails
  leaves `platform` nil, which maps to `.delegated` — fail-closed for *actuation*, and fail-**open**
  for A5, since a delegated guest is not counted against the macOS pool and a macOS VM could boot
  uncounted. So attach refuses rather than admitting it, and says the platform could not be read.
- **Cloning a guest that holds a slot is refused with the reason** (the spec's third assumption),
  and it gets a row in the test table rather than a sentence here.
- Catalogue entry, schema enum and description updated in the same change; `capabilities` stops
  listing attach as unavailable.

### Slice 6 — The scheduler holds slots (A6, A7, A8, A9, D4)

`Sources/ProctorAgent/Session/RunScheduler.swift` · `SessionQueue.swift` · `SessionGuest.swift`

- The scheduler learns pool capacities and passes them to `grantable`; occupancy is counted from
  `active`, which it already holds.
- Slice 5's attach is wrapped in `acquire`, and D7's `start` for a macOS guest with it.
- **Release is one idempotent path that always re-scans.** Detach, A11's vanish, peer death, idle
  ceiling and start-timeout all funnel through it, guarded by the attachment's `slotHeld` bit. Two
  of them firing on one attachment must decrement once: a second decrement underflows the count and
  admits two waiters where one slot freed, and on the waiter side a double resume traps the
  process. Every release re-examines the whole waiting list, because a decrement that skipped the
  scan parks A7's third guest until its timeout.
- A6 comes from `.guest(…)` being mutex; the wait names the holding session from
  `RunTicketInfo.identity.label`. A7's wait carries position and depth as `RunQueueRefusal.timedOut`
  already does. A8's per-session cap and wait limit bind the attach path because it goes through
  the same `acquire`.
- **Acquire before start, never the reverse.** Booting first and counting after lets a reentrant
  acquire during the boot poll start a third macOS guest before either is counted.

### Slice 7 — A guest that vanishes releases its slot (A11)

`Sources/ProctorAgent/Guest/GuestLink.swift` · `SessionGuest.swift`

A link that fails, or a `status` reporting the guest no longer running, drops the attachment,
releases the slot through slice 6's single path, and **names the disappearance** — stopped from
outside, host slept, provider died. Where a run is in flight it fails that run; where the
attachment was idle there is no run to fail, so the release is recorded and the next call gets the
named refusal. A slot held by nothing is what this closes.

### Slice 8 — The doctor reports the pool (A12)

`Sources/ProctorCore/ToolchainLanes.swift` · `SessionDoctor.swift` · `SessionQueue.swift`

- The `guest` lane row gains `tart` to `requires` and to the either-is-enough rule.
- The pool report — capacity, slots held, by which sessions and guests, how many waiting — built
  from the scheduler snapshot, which is host state and costs no VM. It also states that guests
  started outside Proctor are not in the count (D7).
- A12's second half is a guard: a test asserts the doctor path executes no provider.

### Slice 9 — The documents

- **`docs/PRD.md` §9** — A9 revises "Proctor owns no VM lifecycle." The sentence is replaced by
  what it was protecting: Proctor creates nothing, installs nothing inside a guest, and grants
  nothing. §9's "cannot yet perform a step inside a guest" and §10's `guest` lane row are updated
  in the same change, since both are now false.
- **`CHANGELOG.md`** — `[Unreleased]`, prose through `/create-luke-content` at format `marketing`.
- **`docs/specs/spec-PRO-0076.md`** — the `## Progress` note, including A1b's install record.

## A1b — the guest-side install, and the manual gate

A1b is a **record of findings, not a checklist with blanks**. Build Proctor for the guest, install
it there, and write down what the install actually needed: whether SSH was reachable, whether the
Tart Guest Agent is present (`tart exec` requires it — this is findable now and must be found, not
recorded as unknown), how the agent is launched inside the guest, and which signing identity was
used with what re-grant cost. An ad-hoc signed guest build loses its TCC grants on every rebuild,
which is a real cost to the reader.

**The run stops before the grant.** Accessibility and Screen Recording cannot be granted from
outside a macOS guest, and this runner cannot ask anyone. So the build stands the guest up, takes
the attach as far as it goes, and hands back an ordered list of what a person must do inside the
guest — the exact panes, the exact bundle, the exact command to run afterwards, and the SSH
StreamLocal forward from M5. A1 reported verified without that grant would be a verdict about the
wrong thing.

`anvil-mac-node` belongs to another project. Start and stop only, and stop only under A10's rule.

## Test strategy

**Seam:** the existing injectable ones. `GuestProvider` takes an injected `run` closure, so tart's
argv and parsing are provable with no `tart`; `GuestLink` is a protocol with a fake; `RunQueuePlan`
is pure; `RunScheduler` takes an injected clock **and sleeper** — never a wall-clock wait in a queue
test, which is the PRO-0053/0054 flake lesson.

**Falsifiability at the base commit.** Every clause fails at `492a8a1`, but most fail at *compile*,
which is a weak red. Where a behavioural red exists it is taken as well, and the honest one for the
counted lane is this: add the `.pool` case, leave `isDisjoint` in place, and the capacity-2
assertion fails at one holder. (The earlier draft claimed `grantable` "admits an unbounded number
of pool holders today"; that was wrong — `.pool` does not exist at base, and the mutex it degrades
to caps at one, not at infinity.)

Each kill below is written to fail for the reason the clause names, not merely to differ.

| Clause | Test | Where | The observation that kills it |
|---|---|---|---|
| A1 | a batch on an attached session reaches the link; the host actuator log is empty | `GuestAttachWiringTests` | any host step recorded, or the link not called |
| A1 live | against `anvil-mac-node` — **blocked at the TCC grant, reported as remaining work, never claimed as settled** | handback | — |
| A1b | the record answers SSH, guest agent, launch and signing identity **with findings** | handback + Progress | any of the four recorded as "unknown" |
| A2 | a failing link refuses, names the guest, and no step ran on the host; the refusal matches `refuseHost`'s shape; a tool absent from the denylist forwards rather than running locally | `GuestAttachWiringTests` | a step result exists; the guest is unnamed; an unlisted tool runs on the host |
| A3 | `darwin` → `.native`; `linux`/`windows` → `.delegated`; **and a darwin guest classified delegated fails**; no attach site can supply a tier | `GuestAttachmentTests` | either direction misclassified |
| A4 | host id under a guest session, guest id under a host session, **and one identity's guest id under another identity's guest session** — each a two-machine refusal | `GuestAttachmentTests` | any of the three returns `windowNotFound`, or the cross-identity case resolves |
| A5 | capacity 2 admits two and queues the third; **capacity 1 admits one** (capacity is a parameter); a linux guest is not counted against the macOS pool; a single scan cannot admit three | `RunQueueTests` | a third admitted; capacity ignored; one scan over-grants |
| A6 | two sessions on one guest serialise with a slot free | `RunQueueTests` | both admitted |
| A6 msg | the wait names the holding session | `RunQueueWiringTests` | the message carries no session label |
| A7 | the third macOS guest waits rather than being refused, **and its wait carries position and depth** | `RunQueueWiringTests` | a refusal, or a wait missing either field |
| A8 | a session's fourth waiting attach is refused by the cap, **and a wait past the limit times out** on the injected clock | `RunQueueWiringTests` | a fourth queues, or the ceiling never fires |
| A8b | a holder whose peer is gone releases; the idle ceiling releases; **neither uses the wait limit** | `GuestPoolWiringTests` | a dead holder keeps its slot, or a healthy attachment is torn down at the wait limit |
| A9 | attach of a **stopped** guest records a `start` through the gated path and an audit row | `GuestPoolWiringTests` | no `start` in the provider log, or no audit row |
| A9b | release stops only a guest this agent started | `GuestPoolWiringTests` | a `stop` for a guest found already running |
| A10 | a full pool queues rather than stopping anything, for both a person-started guest **and one another session holds**; the provider log has no `stop` | `GuestPoolWiringTests` | any `stop` recorded |
| A11 | a vanished guest releases the slot, **names the disappearance**, and does so when idle as well as mid-run; a double release decrements once | `GuestPoolWiringTests` | pool count stays at 1; the error does not name the vanish; occupancy underflows |
| A12 | the doctor reports capacity, slots held, holders, and waiting count — **each asserted** — and executes no provider | `ToolchainDoctorTests` | any field absent; the provider log is non-empty |
| clone | cloning a guest that holds a slot is refused with the reason | `GuestPoolWiringTests` | the clone proceeds |
| tart | `list` carries no platform; `get` supplies `darwin` → `.macos`; a failed `get` leaves nil; a start timeout stops what it launched | `GuestProviderTests` | platform invented from the name; an orphaned VM after timeout |

**Regression sweep:** `RunQueueTests`, `RunQueueWiringTests`, `GuestRouteTests`,
`GuestRouteWiringTests`, `GuestProviderTests`, `GuestToolTests`, `GuestInventoryTests`,
`WitnessTierTests`, `MachineDisclosureWiringTests`, `ToolchainDoctorTests`,
`SessionIsolationWiringTests`. The `machine` change in slice 2 and the `grantable` change in slice
4 are the two that reach beyond this feature.

Full `./scripts/test.sh` green, twice, before the handback.

## Parity inventory

Slice 4 routes an existing decision through a widened function. Every behaviour of the old
`grantable` is **kept**, proved by the existing `RunLaneTests` / `RunQueueTests`: FIFO within a
lane; every release re-examines the whole list; `.global` at the head is a barrier; a held queue
starts nothing; the local `taken` mark never becomes scheduler state. Nothing is dropped. The
addition is counted admission for `.pool`, which no existing caller reaches.

Slice 2 routes `Session.machine` from a stored field to a computed lookup. The stored field is
**kept** as the fallback, specifically so the five `setMachine` sites keep their meaning; deleting
it would silently revert four suites' guest coverage to the host.

## Scope: what is out, and the one thing that is narrowed

Out, each traced to the spec: guest creation and granting TCC inside one (excluded explicitly); a
cross-host pool ("contention is per host"); an external broker (recorded assumption); redesigning
the run queue, the session actor or the audit trail (the spec's closing instruction — all three are
touched, none reshaped).

**Narrowed, and reported rather than absorbed: A1's live half.** The spec says A1 is measured live
against `anvil-mac-node` and not carried. This plan builds all of it and takes the live attach as
far as a machine can, then stops at the TCC grant, because Accessibility and Screen Recording
cannot be granted from outside a macOS guest and this runner cannot ask anyone. That is the manual
gate the wave recorded, so the narrowing is expected — but it is a narrowing, and A1 is handed back
as **blocked at the grant with a handover**, never as settled. Every other clause is carried in
full.

## Out-of-family gate

**Lane:** grok `grok-4.6` at `xhigh`, read-only, evidence inline (per this repo's ORCHESTRATOR.md —
codex is off and is not a fallback). Ran clean; verdict **ACCEPT WITH CHANGES**. Not downgraded.

Findings accepted and folded in above: the `grantable` occupancy shape (D1) and its two wrong
answers; nil platform being fail-**open** for the cap (slice 5 refuses); slice 4's forward reference
to the pool (slices reordered, attach split from slot); the D4 holder leak under M1 (peer-death
release plus an idle ceiling, kept distinct from A8); double-release and continuation double-resume
(one idempotent path, `slotHeld`); the `tart run` start-timeout orphan (stop what it launched); D6
allowlist → denylist; A9's start going through the gated path; `reach` never being established by
the plan (M5); `proctor_guest start` bypassing the cap (D7); A4's cross-identity case; and fourteen
falsifiers that would not have killed their clause. The claim that `grantable` "admits an unbounded
number of pool holders today" was wrong and is corrected; the claim that nothing was narrowed was
also wrong and is corrected above.

Disputed on evidence, one: the gate flagged `GuestPlatform.infer(os: "darwin")` → `.macos` as
unproven. It is correct — `GuestInventory.swift:113` tests `hay.contains("darwin")` in the macOS
branch — and it now carries a test rather than a reading.

Left open deliberately, one: whether guests started outside Proctor should count against Apple's
two. Counting them means executing a provider on a schedule, which is exactly what A12's discipline
refuses. D7 closes the bypass inside Proctor and the doctor states the limit; widening further is a
question for the reader, not a decision for this plan.
