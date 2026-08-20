# PRO-0044: Cua becomes the actuation backend

**ID:** PRO-0044
**Status:** Merged `d65dc1e`
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/45-cua-becomes-the-actuation-backend.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` — wins over any earlier spec
**Evidence:** `docs/research/2026-08-15-dossier-proctor-vs-cua.md`,
`docs/research/2026-08-15-proctor-vs-cua-driver.md`
**Builds on:** PRO-0001 (the CUA *schema façade* — an unrelated meaning of the same
three letters, see naming below), PRO-0005/0013/0032 (the gate and the sealed trail),
PRO-0016 (the multi-session queue, whose lanes are per-app), PRO-0019/0025 (the
foreground report and the background preference), PRO-0023 (Proctor never installs
anything and never executes a detected binary)
**Depended on by:** PRO-0045, PRO-0046, PRO-0050, PRO-0051

## Feature description

<!-- Verbatim from docs/features-to-triage/45-cua-becomes-the-actuation-backend.md -->

# Cua becomes the actuation backend

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

Proctor reimplements, for macOS only and with one maintainer, what Cua Driver does
across three platforms with a hundred contributors and 130+ commits a week. Every hour
spent on the actuation planes is spent losing ground.

## What it should do

Put Cua behind Proctor's existing actuation seam, so a `proctor_act` step is performed
by `cua-driver` while everything a caller sees stays the same.

## The hard parts, named

- **Choose the transport and defend it.** Cua ships one binary that runs as an MCP
  stdio server, a long-running daemon, or a one-shot CLI call. Proctor is Swift and
  already runs a long-lived agent. A daemon plus a client is the obvious fit and also
  the one that introduces a second process to supervise, restart and version-check.
  A one-shot call per step is simpler and pays process spawn on every click. Measure
  before choosing: a step budget that doubles is a determinism problem, not just a
  latency one.
- **The seam already exists and should be used rather than replaced.** Proctor has an
  actuator abstraction with fake implementations behind the test suite. Adding a Cua
  implementation beside the native one is the whole shape of this change; if it turns
  into a rewrite, stop and say why.
- **Version pinning.** Cua moves fast enough that "whatever is installed" is not a
  dependency, it is a variable. Decide the supported range, detect it, and refuse
  clearly rather than failing at the first call with a schema error.
- **Element addressing does not survive the boundary.** Cua's element handle is
  per-snapshot and returns a stale error once a newer snapshot supersedes it. Proctor's
  flows record the selector each step resolved through, which is what makes a replay
  meaningful. Say how a Proctor selector becomes a Cua target on each call, and what
  happens when the snapshot moved underneath.
- **Plane reporting is a wire contract.** Every step result says which plane it
  travelled and callers depend on it. Cua reports its own delivery mode. Map them
  honestly rather than flattening everything to one value.

## Not in scope

Deleting the native planes. That is its own item, deliberately, so this one can land
and be measured against the thing it replaces.

---

## What it is

One new actuation backend beside the native one, chosen explicitly, reporting honestly
what it did. Nothing a caller sees changes shape; two things a caller sees gain values,
because Cua can deliver a step in a way Proctor's four-value plane enum cannot express
and pretending otherwise would be the flattening the brief forbids.

The change is an extraction, not a rewrite. Today one line in `SessionAct.runSteps`
calls `ax.perform(step:window:foreground:)` — the single actuation call site in the
whole agent. That line starts calling an injected `ActuationBackend` instead. The
native backend forwards to exactly the code that runs today, so every existing test
passes unchanged. That is the proof this is not a rewrite, and it is checkable rather
than asserted: the branch diff contains no change to
**`Sources/ProctorAgent/AX/Actuator.swift`**.

### Naming, before it causes an incident

`CUA` in this repo already means the **computer-use-agent schema façade** from PRO-0001
— `CUAFacade`, `CUATranslator`, `SessionCUA`, `proctor_computer`. That is the
OpenAI/Anthropic tool schema and has nothing to do with `trycua/cua`.

Everything this feature adds is spelled **`Cua`** (mixed case), or **`CuaDriver`** where
a bare word would be ambiguous. No new symbol is spelled `CUA`. The existing façade
symbols are not renamed: renaming shipped surface to make room for a new dependency is
exactly the drive-by this pipeline forbids.

## Why observation does not move, restated because it is the load-bearing reversal

The research's counter-review reversed the report's own recommendation. Section 1
concluded Cua's surface is an adequate substrate because it returns tree and pixels
together; sections 2 and 3 established that the tree "lies on some surfaces", that
off-Space SwiftUI windows return only a menu bar, and that Cua's screenshots carry no
frame-status metadata while Apple defines six `SCFrameStatus` values and makes checking
them a precondition of trusting a frame. A verification layer needs one channel it can
trust. So Proctor keeps its own ScreenCaptureKit path and its own trustworthiness
reporting, and **only actuation is delegated.**

That reversal is what makes the design below possible rather than merely permitted.
Because Proctor still observes, Proctor is the thing that knows what an element *is*
and what the machine looked like afterwards. The backend is told what to hit and is
asked what it did; it is never the authority on either. Every consequence below — the
addressing chain, the effect check, what the trail attests to — follows from keeping
that half.

## What is unverified, and how the design survives being wrong about it

`cua-driver` is **not installed on this machine**, and PRO-0023's shipped decision is
that Proctor never installs anything and an install never happens as a side effect of a
tool call. No install was performed to obtain a number or read a schema. Everything
below about Cua's wire — the reported path vocabulary, the effect values, the snapshot
caps, whether every client mode mediates through the app-hosted daemon — is read from
its documentation and from a cross-family review, not from the shipped binary. The
research's own recommendation 6 says exactly this: verify the absences against the
binary, not the docs.

So the design is arranged so that **being wrong about Cua's vocabulary produces a clear
refusal rather than a wrong answer**:

- The mapping from Cua's reported values to Proctor's is a **table, not control flow**.
- A **capability probe at lane start** reads the vocabulary the installed build actually
  uses and compares it to the table.
- A value not in the table is **refused at lane start**, and if one appears mid-run the
  step reports `unknown` rather than guessing.

Everything in this spec is current to 2026-08-15 and to nothing later. The research's
own perishability note applies with full force: Cua ships 130+ commits a week.

## The five hard parts, answered

### 1. Transport: speak to the long-lived driver; the framing of the question was wrong

**Decision: talk to a long-lived `cua-driver` endpoint, not a CLI spawn per step.**

Two corrections to the reasoning first, because the original argument for this did not
survive review.

**The determinism argument was false and is withdrawn.** The brief warns that a doubled
step budget is a determinism problem, and the first draft of this spec built on that:
spawn-time variance would land in the score. It does not. `StabilityScore.fold` folds
`perRun: [[String]]` — per-step **AX state hashes** — and computes instability and
`firstDivergence` from those alone. No timing enters the score at any point. A slower
step costs wall-clock across an N-run sweep and nothing else. The honest claim is a cost
claim, not a determinism claim, and it is made as one.

**The choice may not be the one the brief describes.** Cua's macOS TCC identity belongs
to `CuaDriver.app` (`com.trycua.driver`), and the app-hosted daemon exists precisely to
own that identity. On the review's reading, `mcp` and `call` are both **clients of that
app** rather than independent actuators, so a "one-shot call" does not avoid a daemon —
it spawns a CLI that talks to the daemon that was going to exist anyway. If that is
right, the real variable is client overhead per step, and a per-step process spawn buys
nothing at all. **Unverified**: it is the single most valuable thing to check the moment
the binary is on a machine, because it decides whether this section had a decision to
make.

What ships, given that:

- One `CuaTransport` protocol. The long-lived endpoint client is the default.
- `PROCTOR_CUA_TRANSPORT=oneshot` selects a per-step CLI client, so the comparison is
  runnable rather than argued.
- Every delegated step records its transport round-trip on the step artifact.
- **The threshold that reverses the default, written now:** if the per-step CLI's median
  round trip is within 25% of the endpoint client's and its p95/median spread is no
  wider, the endpoint client's supervision cost is not being paid for and the default
  should move. Re-run before PRO-0051 decides the native planes' fate.

A per-step CLI is **never an automatic fallback** when the endpoint client fails. The
direction file is explicit that a fallback is a decision and not a safety net; a run that
silently changes actuation path mid-flight is unscoreable. Endpoint failure refuses the
step and is recorded.

### 2. The seam: extract the one method, do not touch the actuator

`AXEngine` bundles observation (list, attach, snapshot, find, node, notifications, web
content) with the single actuation method `perform`. Observation stays exactly where it
is. `perform` moves out into its own protocol:

```
protocol ActuationBackend: AnyObject, Sendable {
    var id: ActuationBackendID { get }                  // .native | .cua
    func backgroundCapability(for kind: ActionStep.Kind) -> BackgroundCapability
    func preflight() async throws                        // version + capability gate
    func perform(step: ActionStep, target: StepTarget,
                 foreground: Bool) async throws -> Actuation
}
```

**`backgroundCapability` is the part the dependent items most need to be right**, and the
first draft of this spec did not have it. `Session.refusal(for:foreground:)` refuses
`.click`, `.key`, `.hover` and `.dragPath` whenever `foreground` is false, before any
backend is consulted; `foregroundDemand` and the queue's `lanes(for:)` derive from the same
two static kind sets. Those rules are correct *about Proctor's native plane* — they are
true because Proctor can only express those kinds as CGEventPost into the shared stream.
They are false about Cua, which delivers them to one process without the front.

Left alone, that would ship a Cua lane in which **background clicks are unreachable** —
which is the whole reason for adopting Cua — while a batch that never touches the
foreground still takes the exclusive lane and reports that it took the machine. So the
kind→plane prediction becomes a question asked of the backend. The native backend's answers
reproduce the existing kind sets exactly, so nothing about the native lane changes.

`AXEngine.perform` is **kept and unchanged**, because the native backend is a small
adapter that forwards to it. Nothing in `Actuator.swift` moves, changes, or is copied.
`Session` gains one injected property whose default wraps the `ax` it was already given,
so every existing test that builds `Session(ax:capture:)` compiles and passes untouched.
That zero-churn property is what "beside the native one" means in practice.

`StepTarget` is the backend-neutral description of what to hit, computed by `Session`
**before** the call, from Proctor's own observation:

```
struct StepTarget: Sendable {
    var window: WindowHandle
    var app: AppHandle?
    var nodeId: String?
    var identity: ElementIdentity?     // nil when the step names no element
}
```

The native backend ignores `identity` — it already holds a retained `AXUIElement`, which
is strictly better than any re-resolution, and that advantage is preserved rather than
levelled down. The Cua backend uses `identity` and nothing else.

The call becomes `async`. It already sits inside an `async` function one line below an
`await`, so this costs no restructuring; `Session` is a reentrant actor and isolation
already drops at that point, so nothing new is held across the suspension.

### 3. Version pinning, the rule it collides with, and the second TCC identity

**Supported range: `>= 0.13.0, < 0.14.0`.** Cua is pre-1.0 at 0.13 with a nightly
channel, so a minor is the compatibility unit; a wider range on a project shipping 130+
commits a week is a wish, not a dependency. The version gate is paired with the
capability probe above: a supported version number whose vocabulary does not match the
table still refuses, because the number is a claim and the probe is evidence.

**The collision.** `ToolPresence` ships an explicit, reasoned decision that detection
reads the filesystem and **never runs the binary**, because the directories that make a
launchd agent's lookup work (`~/.local/bin`, `~/.cargo/bin`, `/opt/homebrew/bin`) are
user-writable, and executing whatever answers to a filename there, inside a process
holding Accessibility, is a code-execution path opened on Proctor's own initiative. Its
stated cost is that Proctor learns no version. Version pinning needs a version.

Both survive, because the rule is about *side effects of unrelated calls*, not the lane:

1. **Presence probing is unchanged.** `cua-driver` joins the existing read-only search;
   no binary is executed to answer "is it there".
2. **Execution requires the lane to be selected.** Running the driver is not a side
   effect of a probe — it is the whole of what the Cua lane does, chosen by an operator.
3. **Before the first execution, the binary at the resolved path is signature-checked**
   via the Security framework (`SecStaticCodeCreateWithPath` +
   `SecStaticCodeCheckValidity`). This closes the planted-file hole that made the
   never-execute rule right, and it is why this spec may reverse the "learns no version"
   cost without reversing the reasoning behind it.

   **"Is signed" is not a policy, and the anchor is an external fact.** Accepting any
   valid Developer ID signature accepts every notarised binary on the machine, which is
   not a check. The requirement must pin Cua's *own* identity — and which anchor that is,
   and whether Cua's builds are Developer ID signed at all rather than ad-hoc (a source or
   Homebrew build is ad-hoc signed and would fail any anchored requirement), cannot be
   defaulted from this repo. The research reads `com.trycua.driver` as a signing identity;
   this spec does not promote that to a team identifier it has not seen.

   So the anchor is **configuration with a fail-closed default**, not a hardcoded guess.
   The requirement string is a constant in one place, the check refuses on any mismatch
   *and* on an unsigned or ad-hoc binary with a message naming which of the two it was,
   and an operator who has satisfied themselves about a source build accepts it with
   `PROCTOR_CUA_ALLOW_UNSIGNED=1`, which stamps every record exactly as the version
   override does. An operator resolving a refusal is strictly better than Proctor guessing
   an anchor, and it keeps the failure visible instead of silently trusting whatever is on
   the path.

**The second TCC identity, which is a bigger fact than the version gate.** When Cua
actuates, the Accessibility grant doing the work belongs to `com.trycua.driver`, not to
Proctor. Proctor's own grant no longer describes whether actuation will succeed. Two
consequences, both stated here so PRO-0050 inherits them rather than rediscovering them:

- **Preflight reads Cua's own health and permission report** rather than inferring from
  Proctor's grants. **The mechanism matters, because the obvious alternatives are worse.**
  macOS does not expose another process's TCC grants to a plain filesystem read: reading
  `TCC.db` would need Full Disk Access, a new grant and a scope widening this wave has no
  business asking for. So Proctor **asks the driver**, which already ships `doctor`,
  `health_report` and `check_permissions` — and by this point the lane is selected and the
  binary is signature-checked, so executing it is the lane rather than a side effect. This
  is a second process's opinion arriving as text, not something Proctor verified, and it
  is reported in exactly those terms. PRO-0050's brief already frames Cua's doctor that
  way, so this is consistent with a decision the wave has made rather than a new one.
- **Proctor's health report must stop implying it speaks for the whole machine** when the
  Cua lane is selected. The report gains the lane's own grant state beside Proctor's.
  Reporting only Proctor's would be a green light for a lane that cannot move a mouse.

Detection and refusal happen at **lane selection and again at endpoint start**, never at
the first schema error. The refusal names the found version, the supported range and a
remedy. An unsupported version can be forced with `PROCTOR_CUA_ALLOW_UNSUPPORTED=1`,
which stamps `unsupportedVersionForced` on every run record and audit row it touches — an
escape hatch that cannot be taken quietly.

### 4. Element addressing: two trees that must agree before anything is struck

This decides whether a delegated replay still means anything, and the first draft of it
was wrong in three ways that review caught.

**The join key cannot be `AXIdentifier`.** Cua's per-element record is `role`, `label`,
`value`, `frame`, `parent_index` and `depth`. There is no identifier field. So the
attribute Apple documents as the one meant for testing — developer-set, invisible to the
user — exists on Proctor's side of the boundary and not on Cua's. A cascade that starts
with it collapses to role, then a label like "OK", then a rectangle; and matching on a
rectangle **is** coordinate addressing wearing a different hat, which is the thing this
section exists to refuse.

**The key is structural.** `parent_index` and `depth` are the disambiguator Cua actually
provides, and the first draft dropped them. The identity Proctor computes is therefore a
**chain**, not a leaf: the target's `(role, label)` plus the `(role, label)` of its
ancestors, to the window. Two "OK" buttons in one window differ by their chain; two that
do not differ by their chain are genuinely ambiguous and are refused as such.
`AXIdentifier` is still read — it is the best thing Proctor has for picking the right
element *on its own side*, and it is recorded in the flow so a replay keeps it — but it
is never the join key, and the spec says so rather than implying a durability the
boundary cannot carry.

**Frame corroborates; it never decides alone.** A candidate whose chain matches and whose
frame is wildly different is rejected. A set of candidates distinguishable *only* by frame
is ambiguous and refuses.

**Verification happens before the strike, not only after a stale error.** The first draft
retried on `stale_element_token` and refused if the re-match had a different identity.
Review found the hole: a token only goes stale when a *newer snapshot supersedes it*. If
the tree mutates while the current snapshot is still current, index N simply has a new
occupant — the first attempt acts, and no stale error is ever raised. Retrying correctly
protects the second attempt and not the one that did the damage.

The answer is the product's own premise applied to addressing: **two independently
obtained trees must agree about the target at the moment of acting.** In the same step,
Proctor reads the element through its own retained reference and the backend reads Cua's
snapshot, and the step proceeds only when both describe the same thing — same role, same
label, and frames that overlap by more than half. A disagreement is not a retry; it is
the finding. This is the tri-observer check, in miniature, on the addressing path, and it
is the one mechanism that covers the first attempt.

The rest of the failure table:

- **`stale_element_token` → re-snapshot, re-match, retry once**, and record
  `retriedOnStale` on the step. A step whose target was moving is a determinism signal,
  not an implementation detail.
- **Re-match with a different identity → refuse** (`targetMoved`). Acting on whatever
  moved into place is how a delegated run corrupts the thing it verifies.
- **No match → refuse** (`targetUnresolved`), carrying what Proctor's own tree says is
  there. Expected rather than hypothetical, see off-Space below.
- **Cua's snapshot was truncated → refuse as `targetAmbiguous`, not `targetUnresolved`.**
  Cua caps a snapshot by node count and depth. In a truncated tree a namesake can match
  while the real target was cut, and uniqueness cannot be established at all. "I could not
  finish looking" must never be reported as "it is not there".
- **Cua reports the window off-Space → refuse with that reason named.** Cua's documented
  limit is that an off-Space SwiftUI window returns only its menu bar; Proctor's retained
  references keep resolving there. So the Cua lane **cannot drive windows the native lane
  can**, and this is a capability regression rather than a corner case. It is recorded
  here because it is one of the strongest arguments against deleting the native planes,
  and PRO-0051 should inherit it as evidence rather than find it in production.

**The never-coordinates promise, stated at the right width.** The first draft said
coordinates are never used. That overclaims: Cua's own `click(token)` pixel-clicks at an
element's centre for some gestures, and Proctor cannot forbid a third party its
internals. The accurate promise: **Proctor never substitutes a coordinate for an element
resolution that failed.** What Cua does internally is Cua's, and it is reported — a step
whose path came back `pixel` is flagged, because a coordinate strike is the least durable
evidence a step can produce and a replay built on it re-clicks absolute positions, which
is exactly what a layout change breaks.

### 5. Plane reporting: map what happened, not what was asked for

`ActuationPlane` has four values, and `.syntheticEvent` means CGEventPost into the single
WindowServer stream, foreground-only. `ForegroundReport.measured` counts exactly that
value, and `ActResult.foreground` is how a caller decides whether a suite runs unattended.

**Map the reported path, never the requested mode.** Cua takes a requested
`delivery_mode` of `background` or `foreground` and reports the path it actually took —
on the review's reading, one of `ax`, `cgevent`, `cgevent_fg`, `key_events`,
`key_events_fg`, `pixel`. The request is an intention and the path is an outcome; the
first draft mapped the request, which is the same flattening the brief forbids, made in
the other direction. Worse, an unrecognised `delivery_mode` is reported to fall back to
`background` silently, so a request is not even reliable evidence of what was asked.

The table, marked unverified and enforced by the capability probe:

| Cua path | Proctor plane | Why |
|---|---|---|
| `ax` | `.accessibility` | the same plane Proctor's own AX route uses |
| `cgevent`, `key_events` | `.routedEvent` | injected, delivered to one process, needs no front |
| `cgevent_fg`, `key_events_fg` | `.syntheticEvent` | the shared stream; the app had to be in front |
| `pixel` | `.routedEvent`, flagged | a coordinate strike; least durable evidence |
| anything else | `.unknown` | this build cannot say, and says so |

Two new values, and the reason each has to exist:

- **`routedEvent`** — an injected event delivered to a specific process rather than the
  shared stream. Background-safe, and not the accessibility plane. Mapping it to
  `.accessibility` would lie about the mechanism; mapping it to `.syntheticEvent` would
  report every such run as having taken the machine. Not counted by
  `ForegroundReport.measured`, and visible to PRO-0046, which has to decide what event
  discrimination means when another process posts.
- **`unknown`** — the step was performed and the build does not recognise the reported
  path. One value rather than two for "new path" and "decode failed", because the
  consequence is identical: this build cannot say how the machine was driven. The raw
  string is carried in `reportedMode`, so the two remain distinguishable to a reader
  without splitting the enum.

`Actuation` gains `backend` and `reportedMode` (Cua's own word, verbatim), so a reader can
audit the mapping rather than trust it.

**The guard-arming consequence, which is the sharpest thing in this section.** Proctor's
foreground guards — the panel's mouse gate, the contention watch, the takeover statement
— arm *before* a post, from `SyntheticPost.declare()` inside `Actuator`, because Proctor
is the one posting. A delegated step is posted by another process, so there is nothing to
declare and the guards would arm only after the fact. Proctor cannot fix that by
inspecting Cua. It can fix it by **asking**:

- Proctor requests `background` explicitly for every step unless the batch itself asked
  for the foreground, in which case it requests `foreground` and arms the guards before
  the call exactly as it does today.
- A step that comes back on a `_fg` path when `background` was requested is a **contract
  violation**: the machine was taken without warning. The step reports `.syntheticEvent`
  and is flagged `unrequestedForeground`, and the run's foreground note says so.

That is the honest shape available from outside another process, and it hands PRO-0046 a
named condition rather than a surprise.

**An unproven plane never reads as safe.** `ForegroundReport` gains `unproven`, the count
of `unknown` planes. Critically, `note` — whose being `nil` is today's wire signal for
"nothing to disclose" — is **non-nil whenever `unproven > 0`**. A new field that existing
readers do not read would leave the lie in place for every one of them; changing the
signal they already read is what actually closes it.

`.appleEvents` and `.declared` stay native-only. Cua has no equivalent of the Apple
Events plane, which is the fact that most argues against deletion in PRO-0051.

### 6. The effect field, because a driver that reports success is not a machine that moved

This was absent from the first draft and it is the failure mode the whole product exists
to catch. Cua returns an `effect` per action — `confirmed`, `unverifiable`, or
`suspected_noop` — and documents its own silent failures: minimized-window keyboard
commits that report success without committing, canvas surfaces that no-op, hotkeys that
are always `unverifiable`. A backend call that returns without an error is not evidence
that anything happened, and folding it straight into `ok: true` reproduces exactly the
defect Proctor is meant to detect.

So the effect is carried onto the step result and crossed with the one instrument Proctor
still owns:

- `confirmed` → an ordinary success.
- `unverifiable` → success, marked. The driver did the thing and cannot prove it landed.
- **`suspected_noop` with an unchanged post-state hash → the step does not read as a
  plain success.** It is reported with the effect and the hash comparison beside it.

The post-state hash is Proctor's own accessibility walk after the step, computed by code
that already runs on this path today. Crossing an external claim with an independent
measurement is the tri-observer premise, and it is available here only because
observation did not move.

## What the audit trail now attests to

The direction file asks for this plainly. PRO-0045 implements the trail changes; this
seam ships the facts they need and states the claim.

**Before:** Proctor recorded the action it performed. One process, one claim, no
independent confirmation of the effect.

**After, with a delegated backend:** each row carries three facts of different strength —
the request Proctor made (intent, Proctor's own knowledge), the effect the driver
reported (an external claim: confirmed, unverifiable, suspected no-op), and the
post-state hash Proctor computed from its **own** accessibility walk after the step.

The third is why the trail does not develop a hole, and it exists only because
observation did not move. The record is not "what Proctor asked for": it is what Proctor
asked for, what the driver said happened, and what Proctor independently observed
afterwards — a stronger claim than the trail carries today, which has no independent
confirmation at all.

Two limits stated rather than glossed. The gate is not a sandbox: a model with a shell
can call `cua-driver` directly and never pass through Proctor, and no design here
prevents that. And nothing about what is recorded concerning the target widens — PRO-0032
decided that a URL in an audit entry is a person's browsing history in a file Proctor
keeps, and delegation is not a reason to revisit it.

## Acceptance clauses

**A1 — The native path is untouched and provably so.** A `Session` built without an explicit
backend actuates through the native one, which forwards to `AXEngine.perform`. Every
existing agent test compiles and passes with **no edit** to its `Session(...)` construction,
and the branch diff against `main` contains no change to
`Sources/ProctorAgent/AX/Actuator.swift` — checked at the finalize gate, because a unit test
cannot certify what a change set did not touch.

**A2 — The backend is chosen explicitly and never changes mid-run.** Default native;
`PROCTOR_ACTUATION=cua` selects the Cua lane. The backend is stamped on every step result.
A kind the selected backend cannot perform — `appleScript` and `shortcut` have no Cua
equivalent — is **refused**, never quietly run on the other backend. A flow replayed on a
different backend from the one that recorded it is refused rather than scored, which is the
mixed-backend case that actually corrupts a determinism number.

**A2b — A kind's plane is predicted from the backend, not from a static list.** The
refusal, the foreground demand and the queue's lane demand all ask the selected backend what
a kind can do. Native answers exactly as today's kind sets do; the Cua lane can therefore
run a background `click`, and a batch that stays in the background neither takes the
exclusive lane nor reports that it took the machine.

**A3 — The join key is structural, and ambiguity refuses.** An element is matched across
the boundary by its `(role, label)` chain through its ancestors. `AXIdentifier` is
recorded but never used as the join key. Candidates separable only by frame are
`targetAmbiguous`, not a match.

**A4 — Two trees agree before anything is struck.** Proctor's own reading of the target
and the backend's must describe the same element — role, label, and frames overlapping by
more than half — or the step refuses. This check runs on the first attempt, not only
after a stale error.

**A5 — The moved-target failure table holds.** Stale token retries once and records
`retriedOnStale`; a re-match with a different identity fails `targetMoved`; no match fails
`targetUnresolved`; a truncated snapshot fails `targetAmbiguous`; an off-Space window
fails with that reason named. Proctor never substitutes a coordinate for a failed
resolution.

**A6 — Unsupported versions and unknown vocabularies refuse before the first step.** A
version outside `>= 0.13.0, < 0.14.0`, or a capability probe returning a value outside the
mapping table, refuses at lane selection with what was found, what is supported, and a
remedy — not at the first schema error. Forcing it stamps every record.

**A7 — The binary is signature-checked against a pinned identity before it is ever
executed, and presence probing still executes nothing.** A `cua-driver` that is unsigned,
ad-hoc signed, or signed by an identity other than the configured one is refused and not
run, with a message naming which of the three it was. Accepting one anyway requires an
override that stamps every record. The presence probe reads the filesystem only.

**A8 — The lane reports the driver's own grants, not Proctor's.** Preflight asks the
driver for its health and permission report — no `TCC.db` read, no Full Disk Access — and
the answer is carried as the driver's own claim, labelled as such rather than as something
Proctor verified. Surfacing it beside Proctor's grants in the health report is PRO-0050's.

**A9 — A dead endpoint is a recorded refusal, never a silent change of plane.** An
endpoint that cannot start, dies mid-step, or answers after the deadline fails the step
with a distinct error. Nothing retries on the native backend automatically.

**A10 — The reported path is mapped, not the requested mode.** The table in §5 holds;
Cua's own word is carried verbatim beside the mapped value; an unrecognised path is
`.unknown`.

**A11 — An unrequested foreground escalation is reported as one.** A step returning a
foreground path when background was requested reports `.syntheticEvent`, is flagged
`unrequestedForeground`, and the run's foreground note says the machine was taken without
warning.

**A12 — An unproven plane never reads as background-safe.** `ForegroundReport.unproven`
counts `unknown` planes, and `note` is non-nil whenever `unproven > 0`.

**A13 — A suspected no-op does not read as a plain success.** The reported effect is on
every delegated step result. When Cua reports `suspected_noop` **and** Proctor's own
post-state hash is unchanged, the two independent observers agree nothing happened and the
step reports `ok: false` with `actionNoOp`. When they disagree — Cua suspects a no-op but
Proctor's hash moved — the step stays `ok: true` and carries the effect beside it, following
the existing precedent for a step whose post-state read failed. Adding the effect while
leaving `ok` true would reproduce exactly the defect A12 fixes: every existing reader still
sees a success.

**A14 — Every delegated step records what it cost**, so the transport decision is
re-settleable by measurement on a machine that has the binary.

**A15 — The whole Cua lane is exercised without the binary.** A fake transport drives the
happy path, cross-tree disagreement, the stale retry, `targetMoved`, `targetUnresolved`,
`targetAmbiguous` from truncation, off-Space refusal, the version refusal, the unknown
path, the unrequested foreground escalation, `suspected_noop`, and an endpoint that dies
mid-step.

## Not in scope

- **Deleting or disabling the native planes** — PRO-0051, which this must land before.
- **The audit row shape, sealing and signing** — PRO-0045. This ships the facts it needs.
- **Stop, yield, event discrimination, the cursor, the HUD under delegation** — PRO-0046.
  This ships `.routedEvent` and `unrequestedForeground` so that item can branch on them.
- **Doctor's toolchain reporting** — PRO-0050. This ships the presence, version and
  grant probes it will read.
- **iOS / Maestro** — PRO-0048 and PRO-0049.
- **Consuming Cua's screenshots, tree or verification as observation** — forbidden by the
  direction file. Cua's tree is read for one purpose: to find the handle for an element
  Proctor has already identified, and to be disagreed with.
- **Routing browser work through Cua's CDP lane** — see below.

## Child work found

- **Cua's browser lane may reverse PRO-0020's conclusion.** Cua binds an exact native
  window to its tab and drives it over CDP in the background. PRO-0020 and PRO-0024
  concluded Proctor should recommend a browser tool and never proxy, because such tools
  drive their own engine rather than the attached window. That premise does not hold for
  Cua. Not specced here.
- **A Maestro lane does not fit this seam as-is.** PRO-0048/0049 treat iOS as a peer lane
  behind the same surface, but a Maestro flow is a file executed by another binary, not a
  step list driven call by call. It binds at the flow level, not the step level, so
  `ActuationBackend` does not extend to it without a second, flow-level seam. Worth
  knowing before PRO-0049 assumes otherwise.
- **Two Proctor sessions share one driver.** PRO-0016's lanes are per-app, so two sessions
  on different apps run concurrently — and both would talk to one `CuaDriver.app`, sharing
  its snapshot map, so one session's snapshot can invalidate another's handle. The
  per-step snapshot-and-act window makes this small rather than absent. If it bites, it
  belongs with the queue, not here.

## Triage — 2026-08-15 — Ready for Implementation Plan

**Sentinel verdict:** S3 (governance-adjacent: the audit trail's meaning, the policy
gate's reach, a second TCC identity, and a decision to execute a third-party binary from
a process holding Accessibility all move here). No essential gaps: every open question was
resolvable from the direction file, the research, a shipped decision in this repo, or the
out-of-family review, and each is recorded as an assumption rather than asked.

### UI & logic preview

**Where it shows up:** nothing customer-facing changes. The run panel, the menu bar and
the status window are untouched by this item — behaving correctly under delegation is
PRO-0046's. *(behind the scenes — nothing visible changes)*

**What users will see:** nothing visible. A run driven through the new lane looks
identical; what changes is what a finished run can honestly say about itself.

**Behaviour changes:**
- A run can be pointed at the new driver, off by default, chosen deliberately.
- A step whose target moved between the look and the strike stops, rather than acting on
  whatever moved into place.
- A driver that is present but too new, too old, or speaking an unrecognised vocabulary
  refuses at the start of the run with a reason, instead of failing partway.
- A step the driver itself suspects did nothing no longer reads as a plain success.

### Assumptions

- `[Data & scope]` The new lane is off by default; existing runs are unaffected (*the item that decides the default is PRO-0051*).
- `[Operations]` **Default:** talk to one long-lived driver process (*a per-action spawn buys nothing if every mode talks to the same helper anyway*).
- `[Operations]` Timing was not measured and the driver is not installed; installing it as a side effect is forbidden (*PRO-0023's shipped decision*).
- `[Operations]` **Both ways of talking to the driver are available** and every run records its own timing, so the default above is falsifiable (*the choice is untested, not unmeasurable*).
- `[Operations]` The earlier claim that speed affects the repeatability score was withdrawn (*checked: the score folds state, never time*).
- `[Compliance]` The driver's signature is checked before it is ever run, pinned to a configured identity, refusing an unsigned or ad-hoc build (*"is signed" accepts every notarised binary on the machine, which is not a check*).
- `[Compliance]` A source or Homebrew build refuses with that reason named and is accepted only by an override that stamps the record (*the anchor is an external fact this repo cannot default, so an operator resolves it visibly*).
- `[Compliance]` Supported range is one minor version, refused clearly outside it (*a pre-1.0 dependency shipping daily is not a range*).
- `[Compliance]` The range is a documentary reading, confirmed on first contact by the vocabulary probe (*chosen without ever running the driver, so the probe is what makes it real*).
- `[Compliance]` An unsupported version can be forced, and doing so is stamped on the record (*an escape hatch that hides itself is worse than none*).
- `[Compliance]` The lane asks the driver for its own permissions rather than reading them (*another process's grants are not readable without Full Disk Access, which this wave will not ask for*).
- `[Experience]` Both sides must agree about the target before anything is struck (*a handle that went stale silently is the failure that corrupts a run*).
- `[Experience]` A target that moved, is ambiguous, or cannot be seen refuses rather than acting (*a wrong click that replays green is the worst outcome available*).
- `[Experience]` Windows on another desktop cannot be driven through the new lane at all (*the driver reports only a menu bar there; Proctor can still see them, which is evidence for PRO-0051*).
- `[Operations]` No automatic fall back to the old path when the new one fails (*the direction file: a fallback is a decision, not a safety net*).
- `[Operations]` What the driver did is mapped, never what it was asked to do (*the request can be silently ignored, so it is not evidence*).
- `[Operations]` Two new delivery descriptions are added rather than reusing the four existing ones (*one of the driver's modes is background-safe and still an injected event; neither existing word is true*).
- `[Compliance]` An unknown delivery description never reads as safe to run unattended, and it changes the sentence existing readers already read (*a new field nobody reads leaves the lie in place*).
- `[Compliance]` A step the driver suspects did nothing is reported with that suspicion (*a driver reporting success is not a machine that moved*).
- `[Data & scope]` Nothing about what is recorded concerning the target widens (*PRO-0032 decided that, and delegation is not a reason to revisit it*).

*If any of these are wrong, edit the answer inline (or correct an assumption) in this file and re-run `/triage PRO-0044` before the planner picks this up.*

### Out-of-family review — grok-4.6, xhigh, read-only

Ran on the three load-bearing decisions with the evidence inlined. Codex is off for this
repo by instruction, so grok is the out-of-family lane. Nine findings; **six accepted,
three narrowed**. It changed this spec more than any other input.

Accepted and now in the spec:

1. **The effect field was ignored** — the highest-severity finding. A no-error call
   becoming `ok: true` is precisely the silent-success defect this product exists to
   detect. New §6 and clause A13.
2. **`AXIdentifier` does not exist on Cua's side of the boundary**, so the durability
   cascade collapsed to a rectangle. Rewritten around a structural `(role, label)` chain
   using `parent_index`/`depth`. Clause A3.
3. **The stale-token retry does not protect the first attempt** — a mutation under a
   still-current snapshot raises no stale error at all. Answered with the cross-tree
   agreement check before the strike. Clause A4.
4. **The determinism argument for the transport was false.** Verified directly against
   `StabilityScore.fold`, which folds state hashes and never time. Withdrawn and restated
   as a cost claim.
5. **Mapping `delivery_mode` mapped the request, not the outcome**, and an unrecognised
   mode falls back to `background` silently. Now maps the reported path, with the
   unrequested-escalation flag as clause A11.
6. **`unproven` alone would leave `note == nil` reading as safe** for every existing
   reader. `note` now changes. Clause A12.

Narrowed rather than accepted whole:

- **"You cannot keep never-coordinates and call those tools."** Correct about Cua's
  internals; the promise is now stated at the right width — Proctor never substitutes a
  coordinate for a failed resolution — and a `pixel` path is flagged.
- **"One-shot without a daemon fails closed; every mode talks to `CuaDriver.app`."**
  Plausible and consistent with the research, and it would mean the transport question is
  smaller than the brief supposes. Recorded as the highest-value thing to verify against
  the binary, not adopted as fact.
- **Snapshot caps of 2000 nodes / depth 25.** The specific numbers are unverified, but the
  failure they imply is real and is handled as `targetAmbiguous` on any truncation the
  driver reports, whatever the cap turns out to be.

The vocabulary grok supplied for paths and effects is **not verified against the shipped
binary** and is treated throughout as an unverified reading enforced by a capability probe
— see "What is unverified" above. No key material or gate code was sent; the review was
scoped to design prose.

### Assumptions review gate — fable-5, high effort, fresh reviewer

Run against the Assumptions block with this repo's locked decisions inlined (PRO-0023's
never-install and never-execute rule, PRO-0032's no-widening rule, the direction file's
fallback rule, PRO-0051's ownership of the native-planes decision). Four findings, all
accepted, none escalated to an Essential Question:

1. **"The signature is checked" hid a question: checked against what?** Accepting any
   valid Developer ID accepts every notarised binary on the machine. Pinning is the actual
   decision, and the anchor — plus whether Cua's builds are Developer ID signed at all
   rather than ad-hoc, as a source or Homebrew build would be — is an external fact this
   repo cannot default. Resolved by making the requirement a configured constant with a
   fail-closed default and a stamped override, rather than by asking: an operator
   resolving a visible refusal beats Proctor guessing an anchor.
2. **Reading another process's grants has no benign mechanism.** `TCC.db` needs Full Disk
   Access — a new grant and a scope widening — and the alternative is to ask the driver and
   trust its answer. Resolved by asking, and by labelling the answer as the driver's own
   claim, which is how PRO-0050's brief already frames it.
3. **Assumptions 2 and 4 contradicted each other** — one committed to a single long-lived
   process, the other said both transports ship. Reworded to default versus available.
4. **The version range was chosen from documentation, never from contact.** True, and
   noted as such; the capability probe is what converts it from a reading into a check.

Everything else was found aligned with the locked decisions, with the no-automatic-fallback
assumption singled out as correctly encoding the direction file's rule.

## Plan — 2026-08-15

Implementation plan: `docs/plans/plan-PRO-0044.md` (Plan size: Large).

The plan's out-of-family gate found seven material defects and three of them changed this
spec rather than only the plan: the backend-aware plane prediction (A2b, without which the
Cua lane could not perform a background click at all), the two-observer no-op rule (A13,
which otherwise reproduced the defect A12 fixes), and A1's proof moving from a unit test to
a finalize-gate diff check. Nothing in the plan narrows a triage assumption.

## Progress — 2026-08-15

**Status:** In Review. Branch `ai/pro-0044`, worktree `.worktrees/PRO-0044`. Not merged;
finalization is the orchestrator's.

### Acceptance clauses, and what proves each

| Clause | Proof | Result |
|---|---|---|
| A1 native untouched | `git diff main...HEAD -- Sources/ProctorAgent/AX/Actuator.swift` is empty; whole existing agent suite green with no edit to any `Session(...)` construction | pass |
| A2 explicit backend, no mid-run change | `ActuationSeamTests.defaultsToNative`; `CuaBackendTests.nativeOnlyKindsRefuse`; `SessionFlow.requireSameBackend` | pass |
| A2b plane predicted from the backend | `ActuationSeamTests.delegatedBackgroundClickIsNotRefused` and `.nativeStillRefusesBackgroundClick` | pass |
| A3 structural join key | `ElementMatchTests` chain, disambiguation and ambiguity cases | pass |
| A4 two trees agree before the strike | `ElementMatchTests.agreementHolds` / `.labelDisagreementRefuses`; `CuaBackendTests.mutationUnderACurrentSnapshotRefuses` | pass |
| A5 moved-target table | six `CuaBackendTests` refusals, `truncated` explicit | pass |
| A6 version + vocabulary refuse first | `CuaBackendTests.versionRefusesFirst`, `.unmappableVocabularyRefuses`; `CuaVersionTests` | pass |
| A7 signature pinned, probe executes nothing | `CuaBackendTests.unsignedBinaryRefuses`, `.signatureVerdictsReadDifferently` | pass |
| A8 driver's own grants | `CuaBackendTests.unhealthyDriverRefuses` | pass |
| A9 dead endpoint refuses | `CuaBackendTests.deadDriverRefuses` | pass |
| A10 map path not request | `CuaBackendTests` mapping cases incl. `unknownPathIsNotGuessed` | pass |
| A11 unrequested escalation flagged | `CuaBackendTests.unrequestedEscalationIsFlagged`; `ActuationSeamTests.escalationIsReported` | pass |
| A12 unproven never reads safe | `ActuationWireTests.unprovenChangesTheNote`; `ActuationSeamTests.unprovenRunDiscloses` | pass |
| A13 suspected no-op ≠ success | `ActuationSeamTests.agreedNoOpFailsTheStep` and `.contradictedNoOpStaysOK` | pass |
| A14 cost recorded | `transportMs` asserted in `CuaBackendTests.accessibilityPath` | pass |
| A15 whole lane without the binary | 24 `CuaBackendTests`, all behind `FakeCuaTransport` | pass |

### What could not be measured, and why

`cua-driver` is not installed on this machine and PRO-0023 forbids installing it as a side
effect, so **nothing here has spoken to the real binary**. Every claim about its wire — the
delivery-path vocabulary, the effect values, snapshot truncation, whether every client mode
mediates through the app bundle — is a documentary reading enforced by a capability probe
rather than a verified fact. The design is arranged so that being wrong produces a refusal
at lane start instead of a wrong plane on a step result. The ordered first-contact checklist
is in the plan; items 1 and 2 can invalidate design decisions and should be run first.

The transport decision is therefore **argued, not measured**. The determinism argument the
first draft rested on was checked against `StabilityScore.fold` and withdrawn: the score
folds state hashes and never time. Both transports ship, every step records `transportMs`,
and the threshold that reverses the default is written into the spec.

### Two defects found by my own tests, worth recording

- **The version gate admitted `0.14.0-nightly`.** Semver sorts a pre-release below its own
  release, so an upper bound of `< 0.14.0` *matched* a build of the next minor — the one
  thing that bound exists to exclude. Pre-releases are now refused outright, which also
  catches `0.13.0-rc1` at the floor.
- **A no-op step counted itself as completed and let the batch continue**, unlike every
  other failure path in the loop. It now stops the batch as they do.

### Child work found

Recorded in the spec's `Child work found` section: Cua's CDP browser lane may reverse
PRO-0020's conclusion; a Maestro lane binds at flow level and does not fit this step-level
seam; and two concurrent sessions would share one driver's snapshot map.
