# PRO-0045: A delegated call is still gated and recorded

**ID:** PRO-0045
**Brief:** `docs/features-to-triage/46-a-delegated-call-is-still-gated-and-recorded.md` (brief 46)
**Status:** Merged `1bff5c2`
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0045.md`
**Branch:** `ai/pro-0045` (worktree `.worktrees/PRO-0045`)

## Feature description

# A delegated call is still gated and recorded

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

PRO-0005 built a fail-closed policy gate. PRO-0013 sealed the audit trail at rest.
PRO-0032 signed it and recorded the browser lane recommendation. All three assume the
process writing the record is the process performing the action.

Move actuation into `cua-driver` and that stops being true. Unless this is designed,
Proctor's trail quietly becomes a record of **what Proctor asked for**, which is a
weaker claim than **what happened to the machine**, written in the same words.

## What it should do

Keep the gate in front of every delegated call, keep the trail describing reality, and
say precisely what the trail now attests to.

## The hard parts, named

- **Intent and outcome are now two facts, and the trail should carry both.** Cua
  returns an effect for an action (confirmed, unverifiable, suspected no-op). A trail
  recording only the request is the hole described above; a trail recording the
  request and the reported effect is stronger than what Proctor has today, because
  today's record has no independent confirmation at all.
- **A subprocess can fail in ways an in-process call cannot.** It can die mid-step,
  answer late, or be a different build than the one whose grants were checked. Each is
  an audit event, not just an error return.
- **Do not widen what is recorded about the target.** PRO-0032 decided a URL in an
  audit entry is a person's browsing history in a file Proctor keeps, and defaulted to
  less. Delegation is not a reason to revisit that.
- **The gate must not be bypassable by talking to Cua directly.** If `cua-driver` is
  installed and running on the machine, a model with a shell can call it without
  passing through Proctor at all. Proctor cannot prevent that and should not pretend
  to; say so plainly in the spec so nobody mistakes the gate for a sandbox.

## Worth knowing

The interlock that stops `swift test` writing to the operator's real trail
(`PolicyStore.isTestProcess`) has already been inert once. Verify it fires before
running any suite that appends.

## What it is

PRO-0044 moved actuation behind `ActuationBackend` and shipped the facts a delegated
step produces: which backend acted, the driver's own delivery mode, its claimed effect,
whether the element handle was re-resolved, whether the machine was taken without being
asked. Those facts reach the *step result*. **None of them reach the trail.** `auditStep`
today records the tool, the target, the kind, the plane, the outcome and the post-state
hash, and nothing on that row can distinguish a step Proctor performed itself from one it
asked another process to perform.

That is the hole, stated precisely: the trail is not yet wrong, because until an operator
sets `PROCTOR_ACTUATION=cua` every step is still native. It becomes wrong the moment the
lane is selected, and it becomes wrong *silently*, because the record keeps its shape and
its words while the thing behind the words changes.

This item closes it in four moves:

1. every delegated step's row carries **who acted, what they claimed, and what Proctor
   independently observed** — three facts of different strength, kept apart;
2. a subprocess failure that leaves the outcome genuinely unknown stops claiming the step
   **failed**, because "failed" asserts the action did not happen and Proctor cannot know
   that;
3. the lane itself becomes an audited object — opened, refused, identity changed, died,
   timed out — rather than a set of error returns that surface only as step failures;
4. the claim the trail makes is written down in one paragraph, in the spec and in the
   code, so the next person to change this can tell whether they weakened it.

Nothing is added about the target. No new field carries an address, a document title, a
window title or caller text.

## What the trail attests to

This is the deliverable as much as the code is, so it is stated once, plainly, and the
same words go in the header comment of `SessionPolicy.auditStep`.

> **Every row of the trail is a claim Proctor makes about a request it made.** For a step
> Proctor performed itself, that claim covers the action too: one process asked and acted,
> so intent and act are the same event, and the post-state hash is Proctor reading back its
> own work.
>
> **For a delegated step the row carries three facts, of three different strengths, and
> never merges them.** *Proctor's own knowledge:* the gate allowed this application, and
> Proctor sent this request to this backend at this time. *An external claim:* the driver
> reported it delivered the action by this path, with this confidence that it landed
> — Proctor did not witness it and does not vouch for it. *Proctor's own observation:*
> Proctor walked the window's accessibility tree before and after, on its own capture and
> its own tree, and the state either changed or did not.
>
> The third is what stops the trail becoming a record of intent. It is weaker than having
> performed the action and stronger than taking the driver's word: a delegated row is
> **corroborated**, where a native row is merely **self-reported**. Where the two disagree
> — the driver claims success and nothing moved, or the driver suspects a no-op and the
> window changed — the trail records the disagreement rather than resolving it.
>
> **Where Proctor cannot say, the row says it cannot say.** A driver that dies mid-step or
> answers after the deadline may have delivered the action before it went. That row is
> `indeterminate`, not `failed`, and it carries Proctor's own before/after reading as the
> only evidence left.
>
> **The gate is not a sandbox.** It stands in front of every call Proctor makes and in
> front of nothing else. `cua-driver` is an ordinary binary on the machine, and any model
> holding a shell can drive it directly, unlogged and ungated, without Proctor being aware.
> Proctor cannot prevent that, does not try to, and the trail's completeness is a claim
> about Proctor's own actions, never about the machine.

## The hard parts, answered

### 1. Intent and outcome are two facts, and so is Proctor's own reading — three, not two

The brief frames it as two facts. It is three, and separating the third is what makes the
feature worth building. PRO-0044's `Actuation` already carries the driver's claim; PRO-0044
also introduced the no-op verdict, which crosses that claim with a before/after reading
Proctor takes from its own tree. So the second observer already exists in the code — it
simply stops at the step result and never reaches the trail.

Five fields go on `AuditRecord`, all optional, all appended after PRO-0047's six, so a row
sealed by an earlier build still decodes with them nil. As with PRO-0047 they change neither
the signed material nor the chain link, both of which are computed over the sealed
ciphertext rather than over the record's fields.

| Field | What it is | Whose claim |
|---|---|---|
| `by` | the backend that performed it — `native`, `cua` | Proctor's |
| `mode` | the driver's own word for how it delivered the step, verbatim | the driver's |
| `eff` | the driver's confidence it landed — `confirmed`, `unverifiable`, `suspectedNoOp` | the driver's |
| `obs` | Proctor's own before/after reading — `changed`, `unchanged`, `unread` | Proctor's |
| `lane` | which lane instance acted, tying the row to a lane-opened record | Proctor's |

`obs` is the load-bearing one and the reason this is not simply "log the reply". It is
computed from the hash Proctor takes before the step and the hash it takes after, both from
its **own** accessibility walk. `unread` is a real answer rather than a failure: a `close`
step ends with no window to walk, and claiming `unchanged` there would be a fabrication.

**What `obs` is, stated narrowly, because the tempting reading is wrong.** It is the
*window's accessibility state as Proctor read it*, and nothing larger. It is not "the
machine changed". A canvas surface repaints without moving the tree, a scroll can leave the
tree identical, another process can change the tree without the step touching it, and an
animation or a clock can change it for no reason at all. So `changed` is evidence the step
landed and not proof, `unchanged` is evidence it did not and not proof, and the spec says
so wherever the field is described. What it *is* good for is exactly the case this item
cares about: an independent reading, taken by a different observer from the one making the
claim, at the moment that matters.

Three deliberate nils, all meaningful:

- **`eff` and `mode` are nil for a native step**, because the native backend has no such
  concept — it judges a write by reading it back rather than by reporting a confidence.
  A nil here says *this backend does not make claims about itself*, which is different from
  a backend that claimed nothing.
- **`obs` is nil for a native step**, and this was argued rather than inherited. Native does
  have a hash lying around — the *previous* step's post-state — and could populate the field
  from it. It should not. A reading taken one step earlier is separated from this step by a
  settle, an application's own repaints and anything else on the machine, so it would measure
  a different interval while wearing the same field name. A weaker measurement in a field
  readers trust is worse than an absent one, and `SessionAct` deliberately reads a before-hash
  only when `actuator.id != .native` so the native path pays nothing for a delegated concern.

**The crossing is written once, into `outcome`, and is not left to the reader.** This is
PRO-0044's `noOpVerdict`, which already computes it and hands the result to `auditStep` as
`ok:` — every existing reader checks the outcome, so that is the slot the answer belongs in.
What this item adds is the *inputs*, persisted beside the verdict, so a reader can audit the
crossing instead of trusting it. There is no `verdict` field precisely because there is
already exactly one place the rule lives.

All nine cells, so none is left implied:

| `eff` \ `obs` | `changed` | `unchanged` | `unread` |
|---|---|---|---|
| `confirmed` | `ok` | `ok`, disagreement on the row | `ok` |
| `unverifiable` | `ok` | `ok`, weakest row in the trail | `ok` |
| `suspectedNoOp` | `ok`, disagreement on the row | **`failed`** — two observers agree | `ok` |

The two `unchanged` cells in the first two rows carry a sentence as well as the two fields.
The completeness gate found the reason: a driver that over-claims would otherwise write a
clean row whose disagreement was reachable only by crossing two fields, and the outcome a
person actually filters on would say nothing at all. The step still passes, because a step
can legitimately move nothing; the row says the observers do not agree.

Only the one cell fails, and that is PRO-0044's shipped rule, unchanged. The reason the
other two `unchanged` cells do not fail is that an unchanged tree is a routine outcome of a
step that worked — `hover` moves nothing, a `focus` onto an already-focused element moves
nothing — so failing on it would turn a weak signal into a false negative across the whole
step vocabulary. Those rows are not silent about it: both fields are on the record, so
"the driver said it worked and Proctor saw nothing move" is readable, and it is the query a
person investigating a flaky run wants.

### 2. A subprocess fails in ways an in-process call cannot

The brief names three. Each gets an answer, and the first one changes the vocabulary of the
trail.

**It can die mid-step — and this is why `failed` had to stop being the answer.** When
`AXEngine.perform` throws, nothing was posted: the step demonstrably did not happen, and
`outcome: failed` is true. When the driver's stdio closes mid-call, Proctor knows only that
it stopped hearing back. The request may have been written, delivered, and performed before
the process went. Recording that as `failed` asserts something Proctor cannot know, and it
is precisely the direction file's "a weaker claim wearing the same words" — running in the
opposite direction. So:

- `AuditRecord.Outcome.indeterminate` is added, meaning **Proctor asked and cannot say
  whether it happened**;
- a delegated step whose backend became unreachable mid-call records `indeterminate`;
- **Proctor takes its post-state reading anyway.** The before-hash was already taken, the
  window can still be walked, and with the driver gone Proctor's own observation is the
  *only* evidence about what the machine did. `obs: changed` after a driver death is a
  strong signal the action landed; `obs: unchanged` is a strong signal it did not. This is
  the single most useful thing in the feature and it costs one walk on a path that has
  already failed.
- The batch still stops, exactly as it does today. Nothing about control flow changes; only
  the claim does. Continuing a plan when Proctor cannot say what state the machine is in is
  what PRO-0044's no-op verdict already refuses to do.
- **An indeterminate step is never retried automatically**, and this is the one place the new
  outcome has teeth beyond wording. Replaying a step that may already have been delivered is
  how a single click becomes two, and a "failed" step is exactly the kind of thing a retry
  loop feels entitled to re-run. Nothing in the agent auto-retries a step today; the clause
  exists so that the next thing which does has to decide about this case explicitly rather
  than inherit a wrong default.

**What the reading after a death cannot prove, stated because the tempting reading is wrong
again.** Proctor terminates the child and then walks the window. An event the driver had
already posted can land *after* that walk — the post is in the window server's stream and
killing the client does not recall it. So `obs: unchanged` on an indeterminate row means
"nothing had changed when Proctor looked", not "nothing happened". This is why the row is
`indeterminate` in both directions rather than being resolved by the reading, and it is why
the lane is closed for the rest of the run rather than reused: a second child striking the
same target after a late event landed is how an indeterminate step becomes a doubled one.

`indeterminate` reaches history as its own outcome rather than degrading to a fault:
`RunHistory.Outcome.indeterminate`, drawn with its own glyph and wording. An older build
reading a newer trail maps it through `RunHistory.outcome(of:)`'s existing `default:` to
`.failed`, which is a safe degradation and does not need a migration.

**It can answer late — and today it cannot, which is a defect this item has to fix first.**
`CuaEndpointTransport.callTimeout` is declared at 30 seconds and **never read**: `exchange`
does an unbounded blocking read, so a driver that stops answering hangs the step, the batch,
the run panel and the lane forever. Auditing an event that cannot occur would be theatre, so
the deadline is implemented as part of this item and recorded as a defect found in PRO-0044.

The implementation has one non-obvious consequence that has to be designed rather than
discovered. The line protocol has **no request ids**: replies are matched to requests by
position. If a call times out and the transport keeps the process, the reply that eventually
arrives is read as the *next* call's reply, and every subsequent step in the run acts on an
answer to a question it did not ask. So a timeout **poisons the lane**: the child is
terminated, the transport refuses every later call with a reason, and the run does not
silently start a fresh driver mid-flight — which is the rule `CuaClients` already states for
a death and which a naive timeout would have quietly broken.

A timed-out step is `indeterminate` for a second reason beyond the first: the driver may
still act *after* Proctor stopped waiting. The row cannot claim the action did not happen,
and it cannot claim it happened before the step ended either.

**It can be a different build than the one whose grants were checked — and the obvious fix
is a false attestation.** Preflight runs once per lane and establishes signature, version,
vocabulary and health by checking the binary **at a path**. The first draft of this spec then
re-checked that path per batch on the transport that re-execs, and the out-of-family review
was right to call it: verifying a path and then spawning that path is a time-of-check /
time-of-use gap, and the resulting lane record would attest identity A while build B ran.
An audit feature that writes a confident, wrong attestation is worse than one that writes
none — it is the only failure here that manufactures evidence rather than losing it.

So identity is established **against the running process, after the spawn, before the first
request**, using `SecCodeCopyGuestWithAttributes` with the child's pid and the same
requirement `CuaPreflight` already builds. That check has no gap: it interrogates the process
that is going to act, not a filename that may since have changed. The cdhash is read back
from the same signing information and recorded, so the lane record commits to a specific
build rather than to a version string the driver reported about itself.

The two transports then differ in what can honestly be claimed, which is a real property
rather than an implementation detail:

- `CuaEndpointTransport` holds one child for the lane's life. It is verified by pid at spawn,
  and a process cannot change its own code after `exec`, so the attestation holds for every
  step the lane performs. `identityPinned: true`, cdhash recorded, one lane record covers the
  run.
- `CuaOneShotTransport` re-execs per call. Each call is a different process, so a lane record
  cannot attest an identity for the lane at all. `identityPinned: false`, **no cdhash, and no
  identity claim** — the record says the transport cannot support one. The per-batch re-check
  is kept, but is described and named as **detection, not prevention**: it notices a build
  that moved between batches and refuses, and it cannot stop one that moves between the check
  and the next `exec`. Naming it correctly is the point; a reader must not take
  `lane.identityChanged` as a guarantee that unchanged means unchanged.

The honest summary, which goes in the lane record rather than only in this spec: on the
long-lived transport the trail names the build that acted; on the per-call transport it names
the build that answered a question, and says that is all it names.

**Where lane events go.** They are records of their own, not fields smuggled onto a step. Tool
`proctor_act`-adjacent naming would be wrong — these are the lane's events, so they carry tool
`proctor_actuation` and a kind-less shape, which `RunHistory` already treats correctly: a
record with no step kind belongs to the run rather than to its step list. They inherit
`RunIdentity.current` like everything else, so a lane opened inside a call is read as part of
that call, and a lane that dies outside one is its own event.

| Event | Outcome | When |
|---|---|---|
| `lane.opened` | `ok` | first delegated step of a lane: path, version, overrides, transport, `identityPinned` |
| `lane.refused` | `refused` | preflight refused: which stage, and why |
| `lane.identityChanged` | `refused` | unpinned lane whose build moved between batches |
| `lane.died` | `indeterminate` | the driver stopped answering mid-call |
| `lane.timedOut` | `indeterminate` | the deadline expired and the lane was poisoned |

### 3. The wording has to stop asserting, too

The review that read this spec found the sharpest defect in it, and it is not in a new field
— it is in one PRO-0047 already ships. `AuditRecord.act` holds **Proctor's own past-tense
wording**: "Pressed", "Chose", "Set". Every step row carries it, and it is the phrase a person
reads in the history list. On an indeterminate row, `act: "Pressed"` asserts the press
happened, in Proctor's own voice, on the very row whose entire purpose is to say Proctor
cannot tell. The five new fields would have been correct and the sentence beside them would
have been a lie.

Two changes close it, both small:

- **An indeterminate row is written with the noun form, not the past form.**
  `StepDescription.Wording` already carries `noun` ("Press", "Menu choice", "Set value")
  beside `past` ("Pressed", "Chose", "Set"), so the honest phrasing already exists and only
  has to be selected. `act: "Press"` asserts nothing; the outcome on the same row supplies
  the rest.
- **`StepDescription.Outcome` gains `indeterminate`**, because today it has exactly two cases,
  `refused` and `failed`, and the after-the-fact line renders "Press \"Send invoice\" failed"
  — the same false claim in the surface a person actually reads. The new case renders a line
  that says the outcome is unknown rather than negative.

This is the difference between recording honesty and displaying it. A trail that carries an
`indeterminate` outcome behind a sentence that reads "Pressed … failed" has not told anybody
anything.

### 4. Nothing recorded about the target widens

PRO-0032's decision stands untouched, and the design makes it structurally hard to breach
rather than merely intending to honour it. Of the five new step fields, four are drawn from
**closed vocabularies Proctor owns**: `by` is an `ActuationBackendID`, `eff` is an
`ActuationEffect`, `obs` is a three-valued enum this item defines, `lane` is a short
Proctor-minted identifier. None can carry foreign text because none is a free string.

`mode` is the one exception and is handled rather than waved past. It is the driver's own
word (`ax`, `cgevent_fg`, `pixel`), not the application's, so it is not browsing history and
not app content — but it is still foreign text entering a file Proctor keeps, and the same
discipline applies. It is written through `StepDescription.sanitised`, the bound already used
for `obj`, so it is length-capped and control characters are stripped. A driver that returned
a megabyte of prose in its `path` field would put a bounded token in the trail, not the prose.

The guard is a test rather than a promise: a redaction test walks every field this item adds
and asserts each is either enum-derived or sanitised, and the lane records are asserted to
carry the driver's *path* and *version* but no window title, no URL, no argument values and
no element labels beyond what a native row already carries.

Two things that would have widened it and are deliberately not built: the step's arguments as
sent to the driver (they contain typed text, which is what `Redaction` exists to keep out),
and the driver's `message` on a failure (application-authored strings reach it, and the
existing `reason` already carries Proctor's own sentence).

### 5. The gate is not a sandbox, and the spec says so

The gate's *placement* needs no change and this was checked rather than assumed. `runSteps`
takes an `AuditContext` that only exists once `enforcePolicy` or `policyGate` has run, and
delegation happens strictly inside `runSteps`, below that point. Preflight — which is the
thing that spawns the subprocess — is reached only from `CuaActuationBackend.perform`, which
is reached only from the actuation call site inside the loop. So **the gate already stands in
front of every delegated call, including the spawn**, and an acceptance clause pins that
ordering so a later refactor cannot quietly invert it.

What changes is not the gate's position but what a refusal now means, and the honest statement
of its reach:

> The gate governs what Proctor does. It does not govern the machine. `cua-driver` is an
> ordinary executable, and any process that can run a shell can drive it directly — without
> Proctor's policy, without a row in Proctor's trail, and without Proctor being able to
> observe that it happened. Nothing in this design prevents that, and nothing here should be
> read as claiming otherwise. A complete trail means every action *Proctor* took is recorded.
> It has never meant, and after this item still does not mean, that every action taken on the
> machine is recorded.

This is not a limitation introduced by delegation. A model with a shell could already move a
window with `osascript`. Delegation makes it *conspicuous*, because the driver is a
purpose-built actuation binary sitting on the machine with its own Accessibility grant — which
is precisely why saying it plainly matters more now than it did before.

## Acceptance clauses

**A1 — The gate stands in front of every delegated call, including the spawn.** A batch whose
application is blocked by policy writes a `refused` row and reaches neither `preflight` nor
`perform`; a test with a recording backend asserts zero backend calls and one refusal row. The
ordering is asserted structurally, not by reading the code.

**A2 — A delegated step's row carries who acted, what they claimed, and what Proctor observed.**
A successful delegated step produces a row with `by: cua`, the driver's `mode` and `eff`, and an
`obs` derived from Proctor's own before/after hashes. The equivalent native step produces `by:
native` with `mode`, `eff` and `obs` all nil.

**A3 — The two observers are recorded separately, including when they disagree.** A driver
reporting `suspectedNoOp` where Proctor's tree changed records `eff: suspectedNoOp`, `obs:
changed` and `outcome: ok`. A driver reporting `suspectedNoOp` where the tree did not change
records `obs: unchanged` and `outcome: failed`, matching PRO-0044's existing verdict.

**A4 — A driver that dies mid-step records `indeterminate`, not `failed`, and still carries
Proctor's own reading.** A transport that throws mid-call produces a step row with `outcome:
indeterminate` and a populated `obs`, plus a `lane.died` record. The batch stops.

**A5 — A call that exceeds the deadline is bounded, poisons the lane, and is recorded.** A read
that produces no reply returns within the deadline rather than hanging; the child is terminated;
subsequent calls on that transport refuse with a reason naming the timeout; the step row is
`indeterminate` and a `lane.timedOut` record is written.

**A6 — Lane identity is verified against the running process, and an unpinned lane attests
nothing.** The long-lived transport verifies its child by pid after spawn and before the first
request; the lane-opened record carries path, version, cdhash, overrides, transport and
`identityPinned: true`. The per-call transport records `identityPinned: false` with **no**
cdhash and no identity claim. A per-call lane whose reported version changes between batches
writes `lane.identityChanged` and refuses the batch before any step runs; a pinned lane does
not re-preflight.

**A7 — Nothing recorded about the target widens.** A redaction test asserts every field this
item adds is enum-derived or sanitised, that `mode` is length-bounded, and that no lane or step
row carries a URL, a window title, an argument value or a typed string.

**A8 — `indeterminate` reads as its own thing.** `RunHistory` maps it to
`Outcome.indeterminate` rather than to `.failed`, a run containing one is not reported as `ok`,
and the status window draws it with its own glyph and wording.

**A9 — The wording on an indeterminate row asserts nothing.** Such a row carries the noun form
of the verb ("Press") rather than the past form ("Pressed"), and
`StepDescription.line(for:node:outcome:)` renders an `indeterminate` outcome as unknown rather
than as failed. A test walks every `ActionStep.Kind` and asserts no indeterminate line contains
that kind's past-tense verb.

**A10 — An indeterminate step is never retried automatically.** The batch stops at it, and no
path in the agent re-runs it without an explicit new call.

**A11 — The native path is unchanged.** A native step's row is byte-identical to what it was
before this item, which is what the nils above are for, and no existing test's *assertion*
changes. `auditStep`'s signature does change (`ok: Bool` becomes `outcome: String`, because a
boolean cannot express a third outcome), so its two direct callers in the test suite are
updated mechanically; both are listed in the progress note.

**A12 — The attestation paragraph is in the code.** The sentence this spec leads with is the
header comment on `auditStep`, so the next person to change the trail's meaning has to read
what it currently claims.

## Not in scope

- **Preventing direct calls to `cua-driver`.** Impossible from here, and claiming otherwise is
  the failure mode the brief names. Stated as a limit instead.
- **Recording the driver's arguments or its failure messages.** Both carry application or
  caller text; the existing `reason` and `Redaction` cover what a reader needs.
- **Any change to sealing, signing, key handling or rotation.** This item appends optional
  fields and one outcome value; it does not touch the chain, the signed material, the key
  store or `AuditChain`.
- **Stop under delegation** — PRO-0046's, and named by the direction file as its own problem.
- **Whether the native planes survive as a fallback** — PRO-0051's.
- **Deciding the transport default.** PRO-0044 ships both and this item records which one acted;
  the measurement that would move the default still needs a machine with the binary.

## Child work found

- **`CuaEndpointTransport` has no request ids.** The timeout poisons the lane as a consequence.
  A protocol with correlation ids would let a late reply be discarded and the lane survive, which
  is a better answer than poisoning and is a driver-wire change rather than a Proctor one.
- **Two concurrent sessions share one driver process.** PRO-0044 recorded this for the snapshot
  map; it applies to the line protocol too, and the poisoning rule makes it sharper — one
  session's timeout closes the other session's lane.
- **`proctor_doctor` does not report the lane's identity.** The trail will carry it after this
  item and the doctor will not, which is the wrong way round for something an operator checks
  before a run.

## Triage — 2026-08-15 — Ready for Implementation Plan

**Sentinel verdict:** S3 (governance: this item defines what the audit trail's rows mean, adds a
value to the outcome vocabulary, and states the boundary of the policy gate in the operator-facing
record). No essential gaps: every open question was answerable from the direction file, PRO-0044's
shipped seam, PRO-0047's record shape, or the code itself, and each is recorded as an assumption
below rather than asked.

### UI & logic preview

**Where it shows up:** the status window's history list (`Sources/ProctorUI/HistoryWindow.swift`)
gains one outcome state. The run HUD, the menu bar and the queue are untouched. *(mostly behind
the scenes)*

**What users will see:** a run driven through the delegated lane looks identical while it runs.
Afterwards, a step whose driver died or timed out is drawn as its own state — neither a success
nor a failure — with wording that says Proctor cannot tell whether it happened.

**Behaviour changes:**
- A delegated call that stops answering now gives up on a deadline instead of hanging the run.
- After such a timeout the lane closes for the rest of the run rather than silently restarting.
- A delegated lane that re-execs the driver per call re-checks the build between batches and
  refuses if it moved.
- Nothing changes for a run on Proctor's own planes, which is still the default.

### Assumptions

- `[Data & scope]` **The gate needs no move**; it already precedes delegation and the spawn (*checked against the call graph: `AuditContext` gates entry to `runSteps`, `preflight` is reachable only from `perform`*).
- `[Data & scope]` The five new record fields are optional and appended, so older sealed rows decode unchanged (*PRO-0047 set this precedent and the signed material is computed over ciphertext*).
- `[Data & scope]` No field carries application or caller text; `mode` is sanitised because it is foreign text even though it is not app content (*PRO-0032's decision, applied conservatively*).
- `[Operations]` **A timeout poisons the lane** rather than restarting the driver (*the line protocol has no request ids, so a late reply would be read as the next call's answer*).
- `[Operations]` `callTimeout`'s declared 30 seconds is adopted as the deadline rather than re-derived (*PRO-0044 chose it; this item makes it real, and changing the number is a separate argument*).
- `[Operations]` **Identity is verified against the running child by pid, after spawn**, not against a path before it (*a path check followed by an exec is a time-of-check gap, and the resulting lane record would attest the wrong build*).
- `[Operations]` The per-call transport **attests no identity**; its per-batch re-check is detection, not prevention (*each call is a different process, so no lane-wide claim is true*).
- `[Risk]` `indeterminate` degrades to `failed` in an older reader via the existing `default:` arm, so no migration is needed (*checked in `RunHistory.outcome(of:)`*).
- `[Risk]` The driver is still not installed on this machine, so every claim about its wire remains PRO-0044's documentary reading; this item adds no new dependency on it (*PRO-0023 forbids installing it as a side effect*).

### Out-of-family review — grok-4.6, xhigh, read-only

Ran on the design only; no key-handling code, no sealing pair and no `AuditKeyStore` was
shown. Five findings, all dispositioned, three of which changed the design:

1. **Accepted, and it is the most serious.** Verifying the driver at a path and then spawning
   that path is a time-of-check / time-of-use gap, so the lane record would attest one build
   while another ran — an audit feature manufacturing evidence rather than losing it.
   Identity is now established against the **running process by pid after spawn**, the cdhash
   is recorded, and the per-call transport attests **no** identity at all rather than a
   plausible-looking one. Its per-batch re-check is renamed detection, not prevention.
2. **Accepted.** `AuditRecord.act` is past tense ("Pressed") and `StepDescription.Outcome` has
   only `refused` and `failed`, so an indeterminate row would have read "Pressed … failed" in
   the one surface a person actually looks at. Hard part 3 was added for this: the noun form on
   an indeterminate row, and a third outcome case in the wording table. Checked in the code
   before accepting.
3. **Accepted as clarification.** The reviewer read "the verdict gets no field" as leaving the
   crossing to every reader. The intent was the opposite and the design already agreed with it
   — `noOpVerdict` computes it once into `outcome` — so the section was rewritten to say so and
   to specify all nine cells rather than the two it had implied.
4. **Accepted.** `obs` was described as what Proctor observed of the machine; it is an
   accessibility-tree hash, which a canvas repaint, a scroll, another process or an animation
   can all move or fail to move. Narrowed to evidence rather than proof wherever it appears, and
   the post-death reading is now explicitly unable to rule out an event landing after the walk.
5. **Rejected, with the reason recorded.** Draining the stream to resynchronise instead of
   poisoning the lane. A drain cannot distinguish the late reply from the next one without
   request ids, which is the very thing the protocol lacks; the reviewer's own better answer —
   add correlation ids — is a change to the driver's wire rather than to Proctor, and is
   recorded as child work. Poisoning stays.

The reviewer also asserted the five fields "do not change `act`, `outcome`, or the History
projector". That was true of the draft it read and finding 2 is what fixes it; `outcome` was
already being changed by this item.

### Defect found in the foundation

`CuaEndpointTransport.callTimeout` is declared and never read. `exchange` performs an unbounded
blocking read, so a driver that accepts a request and never replies hangs the step, the batch and
the run panel indefinitely. It is fixed here because A5 cannot otherwise be true, and it is
recorded against PRO-0044 rather than silently absorbed.

## Plan — 2026-08-15

`docs/plans/plan-PRO-0045.md`. Six slices, gated out of family on grok-4.6 after the design
was. The plan review changed the design in three places; they are recorded there.

## Progress — 2026-08-15

Built on `ai/pro-0045` in `.worktrees/PRO-0045`, rebased onto `main` at `ca54833`.

**Test counts, via `./scripts/test.sh`** — never a bare or piped `swift test`, per the repo's
gate rule: **1105 → 1134 tests, 118 → 121 suites, exit 0.** Twenty-nine new tests.

### Acceptance clauses, and what proves each

| Clause | Proof |
|---|---|
| A1 gate precedes the spawn | `gatePrecedesTheBackend` — a blocked app costs zero backend calls and writes one refusal |
| A2 three facts on a delegated row | `delegatedRowCarriesThreeFacts`, `nativeRowCarriesNoDelegatedFields` |
| A3 disagreement recorded, not resolved | `disagreementIsRecordedRatherThanResolved`, `agreementOnNothingHappeningFails` |
| A4 a death is indeterminate, with Proctor's reading | `aDeadDriverIsNotAFailure`, `nativeFailureIsNotIndeterminate` |
| A5 the deadline is real and bounded | seven tests in `CuaLineReaderTests`, one per bug the review found |
| A6 lane identity and lane events | `laneEventsBelongToTheRun`, `laneEventsStayWithTheRunThatProducedThem` |
| A7 nothing widens | `delegatedFieldsCarryNoForeignText` |
| A8 indeterminate reads as its own thing | `indeterminateIsItsOwnThing`, `oneUnknownStepContaminatesTheRun`, `aPersonsStopStillWins` |
| A9 the wording asserts nothing | `indeterminateRowsUseTheNounForm`, `noIndeterminateWordingIsPastTense` (walks every kind) |
| A10 never auto-retried | `indeterminateStopsTheBatchWithoutRetrying` |
| A11 the native path is unchanged | the whole prior suite, green with two mechanical call-site edits |
| A12 the attestation is in the code | `theAttestationIsInTheCode` |

### Two deviations from the plan, both recorded rather than absorbed

**The audit token is not reachable, so the pid is used and the residual window is named.**
The plan review was right that `kSecGuestAttributePid` names a slot rather than an
incarnation and that a recycled pid would be attested with confidence. `PROC_PIDAUDITTOKEN`
turns out to be absent from the public SDK — it is in neither `sys/proc_info.h` nor
`libproc.h` — and the alternatives are restricted under the hardened runtime, so
`kSecGuestAttributePid` is the documented public route and is what shipped. What that costs
is written into `CuaProcessCheck` rather than hidden, and it is far smaller than what it
replaces: a path check followed by a spawn leaves a window an attacker chooses, while this
leaves only the child dying and its pid being reused in the microseconds between the spawn
and the check.

**The typed failure became two fields on `AgentError` rather than a wrapper type.** The
review's requirement was that the step loop must not infer "indeterminate" from an error
*code*, and `AgentError.indeterminate` — set by the backend that failed — satisfies it
exactly: the loop reads the backend's judgment, never a number. A separate `ActuationFailure`
wrapper was built first and withdrawn, because it forced eleven unrelated PRO-0044 tests to
be rewritten and needed an unwrap layer at the wire where a `remedy` could quietly be
dropped. `AgentError.lane` carries the event on the same principle the review established:
it travels with the thing that caused it, so there is no gap between producing and taking.

### Defect found in the foundation, fixed here

`CuaEndpointTransport.callTimeout` was declared in PRO-0044 at 30 seconds and never read.
`exchange` did an unbounded blocking read, so a driver that accepted a request and never
replied hung the step, the batch, the run panel and the lane for the agent's life. A5 could
not be true while that held, so the deadline was implemented, and implementing it surfaced
the poison rule: the line protocol has no request ids, so a reply arriving after Proctor
stopped waiting would be read as the answer to the next call.

### Five bugs the plan review found in the line reader before it shipped

Polling ahead of a line already in the buffer; discarding the residual on expiry; reading EOF
as a timeout; millisecond truncation turning a sub-millisecond budget into `poll(…, 0)`; and
a wall clock that jumps when the machine sleeps. Each would have poisoned a healthy lane and
each has a test.

### What could not be measured

`cua-driver` is still not installed and PRO-0023 forbids installing it as a side effect, so
nothing here has spoken to the real binary — the same limit PRO-0044 recorded. The deadline,
the residual buffer and the EOF handling are exercised against a bare `Pipe()`, which is why
`CuaLineReader` takes a file descriptor rather than a process. `CuaProcessCheck`'s success
branch cannot be exercised end to end without a signed driver on the machine.

### Out-of-family completeness gate — grok-4.6, xhigh, read-only

Design only. It confirmed the framing rather than the implementation: its lead finding is
that the trail is an honest record of the agent's own session and not of actuation, which is
what the attestation paragraph already says in as many words, so it reads as agreement about
where the limit sits rather than an unmet claim.

One finding was actionable and changed the code. `confirmed` (or `unverifiable`) crossed with
`obs: unchanged` left a passing row whose disagreement was reconstructable from two fields but
absent from the outcome anyone filters on, so an over-claiming driver wrote a clean-looking
row. Those rows now carry a sentence saying the observers do not agree, without changing the
pass/fail rule; two tests cover it and the native path is asserted to gain no such sentence,
since it has no second observer.

Its remaining points are documented limits rather than gaps: identity is established at spawn
and cannot prove nobody else spoke to the driver in between (the shell limitation, stated);
`obs: unread` is honest about a `close` step that leaves no window to walk; native rows carry
nils by argued design; and lane events riding the return value have exactly one caller, which
writes them on both the success and the failure path.

### The interlock

`PolicyStore.isTestProcess` was verified firing before any suite was run and again at the
end: the operator's trail at `~/Library/Application Support/app.fledgeling.procter/audit/`
is byte-identical across every run of this session — 577 lines, md5 `d2e2ad29…`.
