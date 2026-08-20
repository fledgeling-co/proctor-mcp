# PRO-0047: The run has a history you can read

**ID:** PRO-0047
**Status:** Merged `9756282`
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0047.md`
**Branch:** `ai/pro-0047` (worktree `.worktrees/PRO-0047`)

## Feature description

# The run has a history you can read

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

Proctor records a great deal and shows almost none of it. The audit trail is sealed and
signed and readable only by a tool. The HUD shows the step in flight and forgets it.
The queue bar shows what is waiting. When a run ends, a person who wants to know what
just happened to their machine has nowhere to look.

The reader asked for action logs and history alongside the overlay, and they are the
part that does not exist yet.

## What it should do

A readable record of what Proctor did, reachable from the menu bar and the status
window: the runs, their steps, what each step targeted, which plane it travelled, what
came back, and what it cost in time.

## The hard parts, named

- **This is a second reader of the audit trail, and the trail is sealed.** Decryption
  happens in the agent, which holds the key. A window that renders history is therefore
  asking the agent for plaintext it deliberately made unreadable at rest. Say what
  crosses that boundary and in what form, and keep the answer as narrow as the feature
  needs.
- **A history view is a place a person reads attacker-controlled text.** Step
  descriptions carry an application's own accessibility labels, which is why PRO-0014
  fences every object in quotes and sanitises both supplied and derived names. A list
  view renders far more of that text than a one-line HUD ever did, so the fencing has
  to hold at this size.
- **Retention is a decision, not a default.** An unbounded history of everything an
  agent did on somebody's Mac is a surveillance artifact sitting in their home
  directory. Say how much is kept, how it ages out, and how a person clears it.
- **Do not build a log viewer when a run summary is what people want.** The unit a
  person thinks in is "that thing it just did", not a line-per-event stream. Design for
  the run, and let a step list live inside it.

## Not in scope

Exporting history, or any second copy of the trail outside the sealed one. PRO-0013
chose no recovery path deliberately and this feature does not reopen it.

---

## Triage — 2026-08-15

**Ready for Implementation Plan**

**Sentinel review:** S2 — Approve with assumptions. Two risks carry this item and both
are answered in scope rather than deferred. The first is that a window rendering
history is a decryption request against a trail PRO-0013 deliberately made unreadable
at rest, so the boundary has to be drawn explicitly and narrowly. The second is that
this is the first Proctor surface to render pages of application-authored text at
once, which is a phishing surface if the fence PRO-0014 built for one line does not
hold at list size. Not S3: nothing here is investor-facing or price-sensitive, and no
new capability, grant or network path is acquired.

### Where the direction file changes an earlier decision

Wave 7 moves actuation to Cua. This feature reads what a run **recorded** and never
asks who performed the step, so nothing here is built against a Cua-specific shape.
One consequence is worth stating rather than discovering: `plane` is today an
`ActuationPlane` written by Proctor's own actuator, and a delegated step will need a
value for it. History renders whatever the trail holds and treats an unrecognised
plane as an opaque label rather than failing to draw the row — which is the whole of
this feature's dependency on PRO-0044. Recorded under **Child work found** rather than
coupled to an unmerged branch.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** a new **History** window in Proctor's own app *(customer-facing
  — new surface)*, opened from the menu bar and from a button on the status window's
  Activity card. Nothing on the run HUD changes; nothing over another app changes.
- **What users will see:** a list of the things Proctor did, newest first, one row per
  **run** rather than one row per event. A row says when it happened, which tool it
  was, which application it touched, how it ended and how long it took. Opening a row
  shows the steps inside it — what each one acted on, which way the action travelled,
  what came back, and its own time. Above the list: how many entries Proctor is
  holding, when the record next clears itself, and a Clear button.
- **Behaviour changes:** the record Proctor already keeps becomes readable by the
  person whose machine it is, without a tool and without a terminal. Two things change
  underneath: each recorded action now carries which run it belonged to, how long it
  took and how it travelled, so it can be grouped and read; and the record stops
  growing forever — it holds a bounded window and clears itself past that.
- **Design reference:** the **status window's** own language — system cards on the
  window background, the monospaced uppercase section titles, system tints — not the
  run HUD's graphite. The reason is in the Assumptions below.

### The look, and why it is not the HUD's

The HUD's neutral graphite `rgba(24,25,28,.74)` on neutral white with vermilion as the
only colour exists to solve one problem: a panel floating over somebody else's
application must not borrow that application's palette, and the warm porcelain from
`mocks/onboarding-and-menu.html` was tried and rejected for reading as brown mud in
exactly that position.

**A History window has neither problem.** It is Proctor's own window, on its own
background, next to the status window a person opened it from. Adopting the HUD's
graphite there would make Proctor look like two applications; adopting the rejected
porcelain would fail for the reason it already failed. So History is built in the
status window's existing language, which is already in the tree and already native:
`Card` on `controlBackgroundColor` with a `separatorColor` stroke, `SectionTitle`
uppercase monospaced at 10pt, system green and orange for outcome, and the system tint
for anything live. The only new visual idea is the **fence** below, which is a
containment device rather than a decoration.

Neither settled decision is reopened: the HUD keeps its palette, and porcelain stays
rejected.

**Assumptions**

*What crosses the sealed boundary*

- `[Compliance]` The window never sees a sealed line, a key, a key id, or a raw trail
  record. The agent opens the trail and hands back a **projection** already reduced to
  the fields the surface draws. *(the narrowest thing that renders a history; a raw
  record hands the window fields it has no use for and would then be holding.)*
- `[Compliance]` What crosses: the time, the tool, the outcome, the application's
  **bundle identifier**, the step kind, Proctor's own past-tense verb phrase, the
  object that phrase acted on, the plane, the elapsed milliseconds, the refusal or
  failure reason, the lane recommendation's `{lane, rule, scheme}` where there is one,
  the run identifier and the step number. *(each is on the face of the surface; nothing
  crosses that is not drawn.)*
- `[Compliance]` The application is identified by its **bundle id**, never by a display
  name, and the window is not identified at all. *(what the record actually holds in
  `app` and `window` is a session handle id — `app-3`, `win-7` — which is meaningless
  after a restart and would have been drawn as if it named something. The bundle id is
  the durable identity the policy gate already judges on, it is the one an operator can
  act on, and preferring it removes a whole class of application-authored display text
  from the surface rather than fencing it.)*
- `[Compliance]` What does **not** cross, and is not asked for: the redacted `value`
  and `script` fields — the length-and-hash of typed text and script bodies — the
  post-state hash, the sealing and signing key identifiers, the session handle ids, and
  the record's own JSON. *(a hash of a password is still a thing about a password: it
  belongs in one place, and a history surface has no use for it. PRO-0014 already
  refuses to put typed text on a line; this refuses to put its fingerprint on one
  either.)*
- `[Compliance]` **Stated boundary, and the honest correction to an earlier draft of
  this spec.** Keeping the new verb out of `ToolCatalogue` stops a model reaching *this
  surface*; it does not make the trail unreadable to a model, because
  `proctor_policy` action `audit` is already a catalogue tool that opens the trail and
  returns whole records — redaction hashes, post-state hashes and key ids included — to
  any MCP host. This feature adds no reach that path does not already have, and the
  projection is strictly narrower than it. That existing tool takes an unbounded
  `limit`; capping it belongs to PRO-0005 and is recorded under **Child work found**.
- `[Compliance]` The trail is opened **only when a person asks for history**, never on
  the half-second activity poll and never on the two-second doctor poll. A history call
  is answered from a bounded read of the trail's tail and is capped in what it returns.
  *(a timer that decrypts the trail continuously would make the sealed-at-rest property
  true only of the file, which is not the property PRO-0013 bought.)*
- `[Compliance]` The channel is the agent's existing unix socket, and the verb is
  **internal** — never in `ToolCatalogue`, exactly as `proctor_recent_activity` and
  `proctor_hud` are — so no MCP host and no model can read a person's history. *(the
  shim gates `tools/call` on the catalogue; that is what keeps this a person's surface
  rather than a model's.)*
- `[Compliance]` This does not widen PRO-0013's stated boundary. That spec already
  named what it does not claim: "a program already running as this same user, which can
  reach the key exactly as the tool does". The socket is 0700 in this user's directory
  and is the same one the doctor and activity polls already use. *(honest statement of
  what is and is not new: the answer is nothing.)*
- `[Compliance]` Reading history is **not** itself recorded in the trail. Clearing it
  is. *(a read is an attended, local, read-only act by the machine's owner, and
  recording it would grow the record every time somebody looked at it — a privacy
  feature that produces more surveillance each time it is used. A clear is destructive
  and is attested.)*
- `[Operations]` An entry the agent cannot open comes back as a marked unreadable
  placeholder and is drawn as one, counted, never silently dropped. *(`AuditLog.Entry`
  already carries exactly this state and PRO-0013 chose it deliberately.)*
- `[Operations]` When the key cannot be reached at all, History says so in the agent's
  own words and shows nothing rather than an empty list. *(an empty list and an
  unreadable trail are different facts and must not look alike.)*

*The fence, at list size*

- `[Compliance]` Every string that originated outside Proctor — an element's
  accessibility label, a caller-supplied step name, a menu path component, the text
  inside a failure reason — is **sanitised in the agent before it is written**,
  through the same routine PRO-0014 already applies: collapsed to one line, control,
  bidi and markup characters removed, hard-capped, no ellipsis. That routine gains a
  caller-supplied cap so history can hold a longer object than the HUD's 48 while
  staying one implementation. *(the cap belongs at the source; PRO-0014 settled that.
  A second sanitiser would drift from the first, and a fence whose contents were
  cleaned by a different routine is theatre.)*
- `[Experience]` **The verb and the object are stored separately, and only the object
  is fenced.** `StepDescription` today returns one string containing both — `Pressed
  "Send invoice"` — which a list cannot fence without fencing Proctor's own words too.
  The record therefore holds Proctor's past-tense verb phrase and the object as two
  fields, and the row draws the first plainly and the second inside the fence. *(the
  whole point of the fence is that the boundary between Proctor's words and an
  application's is structural; a single blended string makes that boundary
  punctuation again.)*
- `[Experience]` The fence is a bordered, tinted run with a fixed maximum width, on
  its own, never flowing into Proctor's words. *(PRO-0014's own after-merge decision
  said punctuation "is not the best the HUD can do" and that a text run "no character
  can escape" is the better fence. A page of rows is where that matters: quotation
  marks that work on one line stop working when there are forty of them and a row can
  be made to look like the row above it.)*
- `[Experience]` Proctor's own words lead every row and never sit adjacent to
  unfenced foreign text. Row structure is fixed and identical for every row: outcome
  mark, Proctor's verb, the fenced object, the plane, the time. *(a row whose shape
  depends on its content is a row an application can reshape.)*
- `[Compliance]` Foreign text is rendered through SwiftUI's verbatim text initialiser,
  never the localisation-key one. *(`Text("literal")` takes a `LocalizedStringKey` and
  renders Markdown; the `String` overload does not, but the two differ by one edit
  nobody would flag in review. `Text(verbatim:)` cannot be turned into the other by
  accident.)*
- `[Compliance]` **Stated boundary on the reason.** A refusal's reason is Proctor's
  own sentence. A *failure's* reason is an error message, and an error message can in
  principle quote text a step carried — which is the one field the `value` and
  `script` exclusions above are there to keep out. The reason is kept, because a
  history that cannot say why something failed is most of the value gone, and it is
  sanitised and capped like any other foreign string and fenced when it is not
  Proctor's own. Auditing the agent's error messages for payload echo is real work and
  is recorded under **Child work found** rather than claimed here.
- `[Experience]` The object is capped longer for history than for the HUD, and the
  fence truncates visually when it still does not fit, so two long window titles that
  differ late are visibly truncated rather than silently identical. *(the HUD caps at
  48 because its line must never ellipse; a list row has room and a forensic surface
  must not make two different things look like one.)*
- `[Compliance]` Nothing drawn from the trail is a link, a button title, a menu title
  or a tooltip, and no row is clickable other than to expand its own steps. Text is
  selectable and copyable. *(a history row is a place to read, and a control whose
  title comes from an application under test is a control an application under test
  chose.)*
- `[Compliance]` The History window sets its sharing type to none, so it is excluded
  from screen capture — Proctor's own `proctor_capture` included. *(the run HUD already
  does this. A window holding opened history is exactly the window a model driving this
  Mac should not be able to photograph, and this is one line.)*
- `[Experience]` A step with no fenceable object draws the action alone rather than an
  empty fence. *(PRO-0014's rule that a nameless step reads as the action alone.)*

*The unit is a run, not an event*

- `[Behaviour]` One **run** is one tool call: a `proctor_act` batch and its steps, a
  replayed flow, one repeat of a stability sweep, a single capture, a policy decision.
  The steps inside a batch are that run's steps. *(this is the unit a person means by
  "that thing it just did", and it is already the unit the agent's dispatch choke point
  begins and ends.)*
- `[Behaviour]` The run identifier is minted at that choke point and carried for the
  length of the call, so every record written during a call — a gate refusal, each
  step, a recommendation — lands in the same run. *(one place, so a new audited call
  site is grouped without anybody remembering to group it.)*
- `[Behaviour]` A recorded step gains the facts it does not carry today: which run,
  which position in it, how long it took, which plane it travelled, Proctor's own
  past-tense verb phrase, and the object that phrase acted on. *(the brief asks history
  to show the plane and the time, and neither is in the record today. The wording is
  persisted rather than derived on read because it cannot be derived on read: PRO-0014's
  derivation needs the live `ActionStep` and the resolved `AXNode`, and the record keeps
  only the kind and a node selector. PRO-0014 deferred exactly this field — "`AuditRecord`
  gains no description field" — and this is the item that adds it.)*
- `[Behaviour]` A record written outside a tool call — a person's Stop, a hold, a
  panel decision — carries no run identifier and is drawn as its own single-record
  run, in its right place in time. *(that is what those events are: a person's own act,
  not a step of somebody's run. The same is true of every record written before this
  ships.)*
- `[Behaviour]` A run's headline outcome is derived from its records: ok when every one
  is ok, refused when the gate turned it down, stopped when a person halted it, failed
  otherwise. Its time is the span from its first record to its last. *(the summary is
  the row; the steps are what opening it reveals.)*
- `[Data & scope]` The projection records **what the run recorded**, never who
  performed the step. *(wave 7's direction: no Cua-specific shape here.)*

*Retention*

- `[Data & scope]` The trail holds at most **14 days** or **10,000 entries**, whichever
  is reached first. Both are adjustable through the agent's environment in the shape
  the other switches use, and both are clamped to a bounded range — 1 to 90 days, 100
  to 100,000 entries — so there is no setting that means "keep everything" and none
  that means "keep almost nothing". *(an unbounded record is the artifact the brief
  names; an off switch for the bound would reinstate it, and a floor of zero would let
  anything that can write the agent's environment shred the trail on the next append.
  Anyone who can rewrite that environment can already replace the agent, so the clamp
  is a floor against accident rather than a claim against that attacker.)*
- `[Data & scope]` Passing either cap **rotates the trail in whole**: the file is
  replaced, a fresh trail identity and end-mark are started, and the first record of
  the new trail attests the rotation — how many entries went, the time span they
  covered, the discarded trail's identifier, and **the hash of its final entry**.
  *(the trail is hash-chained from a genesis over its own prefix and anchored by a
  count and a head hash held in the key store, so removing entries from the front is
  not representable: the first survivor still points at a record that is gone, and the
  verifier is right to call that a broken link. Two alternatives were live — a retired
  segment with its own anchor, and a signed truncation record that makes front-removal
  legal. A second-opinion pass by another model picked rotation, on the ground that two
  anchors introduce new mismatch states and either grow the verifier or silently narrow
  its coverage, and that a legal signed truncation converts "removing history is
  unrepresentable" into "removing history is permitted when signed". The head hash in
  the rotation record is what stops the discarded history being merely gone: it is
  committed to, so a copy taken beforehand can still be checked against it.)*
- `[Data & scope]` The cap is checked **at run boundaries only** — as a tool call
  begins, never between the steps of a batch. *(a rotation in the middle of a run would
  discard that run's own first half while the HUD was still showing it.)*
- `[Operations]` A rotation is loud on stderr the way the one-time conversion already
  is, and the trail's status carries that it happened, with the counts. *(PRO-0013's
  precedent: a step that destroys history says so.)*
- `[Experience]` The consequence is stated rather than hidden: history is **not** a
  sliding window. It fills to the cap and then starts again. The window therefore shows
  how many entries are held and how much of the window remains, so the moment is never
  a surprise. *(the honest cost of the mechanism above; the mitigation is a generous cap
  and telling people.)*
- `[Experience]` **Clear** is the same operation, on demand and immediate: the trail is
  rotated now, and the rotation record says a person asked rather than a cap being
  reached. It asks first, in words that say the record cannot be brought back. *(one
  mechanism for both, so there is one thing to get right.)*
- `[Compliance]` **Stated boundary on Clear.** The confirmation is in the window; the
  verb is in the agent, so any process running as this user can call it without seeing
  a dialog. That is PRO-0013's already-stated boundary, with one difference worth
  naming: deleting the trail file by hand is *detected* by the anchor, where an
  agent-mediated clear is legitimate. What closes the gap is that a clear is not
  silent — it is attested in the new trail's first record, with the discarded count and
  head hash — so a shred leaves a mark rather than an empty file. The clear verb is not
  in `ToolCatalogue`, so no MCP host can reach it. *(a capability handshake was
  considered and rejected: it stops accidents, and the threat it would be sold against
  is a same-user process that can already replace the agent.)*
- `[Compliance]` A rotation — by cap or by hand — leaves no readable copy, no backup, no
  sidecar and no export, exactly as PRO-0013's conversion does not. *(the same rule,
  and this feature is where somebody would be tempted to add one.)*
- `[Operations]` Rotation is all-or-nothing under the trail's existing cross-process
  lock, and it records its intent before it starts. An interrupted rotation is
  **completed** on the next append rather than reported as tampering — the marker names
  the new trail identity and the discard summary, so a crash mid-rotation resolves to
  the state the rotation was heading for. *(without this the window between replacing
  the file and writing the new end-mark reads as `wrongTrail` or `missingFromEnd`,
  which is an accusation for what was in fact a crash.)*
- `[Compliance]` The age cap is judged on the wall clock, which is the clock the
  records are stamped with. A clock moved backwards delays rotation and a clock moved
  forwards brings it on; the entry cap is the backstop for the first and the attested
  rotation record is the evidence for the second. *(named because a wall-clock trigger
  has no better answer available, and a silent one would be worse.)*
- `[Compliance]` This makes the audit trail a bounded record rather than a permanent
  one, and that is a real change to what PRO-0005 and PRO-0032 built. Anyone who needs a
  longer accounting raises the cap. *(named because it is a genuine trade and should
  not be discovered later: tamper-evidence still holds over what is held, and what has
  rotated away is committed to by the rotation record rather than merely forgotten.)*
- `[Operations]` The trail's verdict — clean, entry count, first fault — is unchanged
  by this and remains what `proctor_policy status` reports. A rotated trail verifies
  clean as a short trail, not as a damaged one. *(the point of doing it this way.)*

*The surface*

- `[Layout]` History is its own window in Proctor's app, opened from a menu-bar item
  and from a button on the status window's Activity card. *(browsing is not what the
  status window is for, and a scrolling list inside a status dashboard fights it.)*
- `[Layout]` It follows the system appearance, reduced motion and reduced transparency
  the way the rest of the app already does. *(nothing here needs a rule of its own.)*
- `[Experience]` The list is newest first, one row per run, with the steps folded away
  until a person opens a row. *(the brief: design for the run and let the step list
  live inside it.)*
- `[Experience]` Empty, unreadable and unreachable are three different states with
  three different sentences: nothing recorded yet, the record cannot be opened on this
  Mac, and the agent is not answering. *(they have three different remedies.)*
- `[Operations]` The window's header carries the **trail's own verdict** beside the
  entry count: whether it verifies clean, the first fault if it does not, how many
  entries this run could not write, and how many entries in view could not be opened.
  *(without it a rolled-back, key-mismatched or partly unreadable trail renders as
  "nothing happened", or as a list with silent holes in it. A history surface that
  cannot tell an empty record from a broken one is the wrong surface to have built.)*
- `[Experience]` The window reads a fresh projection when it opens and when a person
  asks it to; it does not poll. *(it is a record of the past; a live surface for the
  present already exists, twice.)*
- `[Data & scope]` No export, no reveal-in-Finder, no copy-all button, no second file.
  Individual text stays selectable. *(scope; PRO-0013's decision is not reopened by a
  convenience button.)*
- `[Operations]` The projection is capped by default at a bounded number of runs, and
  the window holds it only while it is open — closing the window drops it. *(the
  opened trail is the plaintext PRO-0013 made unreadable at rest; a second process
  keeping thousands of records of it alive indefinitely is a copy in all but name.)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and
re-run `/triage PRO-0047` before the planner picks this up.*

**Grounding note.** Everything this builds on is in the tree today. `AuditLog`
(`Sources/ProctorAgent/Session/PolicyStore.swift`) already seals, signs, chains,
converts and reads the trail, and `openedTail(_:)` already returns opened entries with a
marked placeholder for one it cannot open. `AuditRecord` (`Sources/ProctorCore/Policy.swift`)
is a `Codable` struct inside the sealed ciphertext, so new optional fields are
backward-compatible on read and change neither the signed material nor the chain.
`Dispatcher.handle` (`Sources/ProctorAgent/Dispatch.swift`) is a single choke point
around every tool call and already begins and ends the activity feed there.
`SessionAct` has the plane, the elapsed milliseconds, the step index and the resolved
node in scope at the point it calls `auditStep`. `StepDescription`
(`Sources/ProctorCore/StepDescription.swift`) already derives the line and already
sanitises supplied and derived names alike. `proctor_recent_activity` and `proctor_hud`
are the precedent for an internal socket verb outside `ToolCatalogue`, and
`AgentModel` already speaks that socket from the window process.
`ProctorUIApp` already has a `Window` scene and a `MenuBarExtra`, so a second window is
a scene and a menu item. This is Swift/macOS work: the gate is `swift build` +
`swift test`; the Playwright acceptance stage does not apply. What is not machine
witnessable here is the rendering itself — `swift test` has no window server — so the
fence, the sanitisation, the grouping, the projection and the rotation are all specified
to live outside the views, in pure code that tests can reach, which is the shape
`PointerMarker`, `StepDescription` and `RunHUDState` already use.

**Assumptions review gate.** An independent pass over the defaults above failed two and
they were fixed here rather than escalated. First, the projection originally carried the
`value` and `script` redactions because they were already in the record; a
length-and-hash of a typed password crossing into a second process for no reason the
surface needs is a widening, and it is now explicitly excluded. Second, reading history
was originally audited for symmetry with clearing it; that makes the trail grow every
time a person looks at it, which is a privacy feature producing more record each time it
is used, so the read is not recorded and the clear is.

**Out-of-family spec review:** grok `grok-4.6` (xhigh, read-only) ran on the design and
returned **22 findings**. The lane ran; no downgrade. Dispositions:

**14 accepted and folded into the Assumptions above.** The sharpest was that the trail
holds *session handle ids* in `app` and `window`, not names, so the row this spec
described could not have been drawn — the projection now identifies an application by
its bundle id and does not identify a window at all, which removes foreign display text
rather than fencing it. Next sharpest: the derived description cannot be derived at read
time, because PRO-0014's derivation needs the live step and the resolved node, so the
wording is persisted at write; and it must be persisted as *two* fields, because a single
blended `Pressed "Send invoice"` cannot be fenced without fencing Proctor's own verb —
which is precisely what the chip was for. It found the over-claim about model reach:
`proctor_policy` action `audit` is already a catalogue tool returning whole opened
records to any host, so "not in the catalogue" was never isolation of the trail, and the
spec now says so. It found that whole-trail rotation discards signed history while
attesting only a count, so the rotation record now commits to the discarded trail's
final head hash; that a mid-batch rotation would eat its own run's first half, so the
cap is checked at run boundaries; that the crash window across a rotation turns the
verifier's honest states into an accusation, so rotation records its intent and an
interrupted one is completed rather than reported; that the environment clamp had no
stated floor; that a failure reason can echo the payload the `value` and `script`
exclusions exist to keep out; that the window never surfaced the trail's own verdict, so
a broken trail would read as "nothing happened"; that the projection dropped the lane
recommendation, which is the one act PRO-0032 exists to record; that a second sanitiser
would drift from PRO-0014's; that a hard cap with no ellipsis makes two long titles
collide on a forensic list; that the window process would cache the opened plaintext
indefinitely; and that a model can attach to Proctor's own app and photograph the open
window, which `sharingType = .none` now prevents.

**Three rejected, with reasons.** It read whole-trail rotation as *forced* by the chain
and the rationale as misstating the alternatives; the rationale named both alternatives
and the choice was made on verifier complexity, not on impossibility — the wording is
sharpened above rather than the decision changed. It expected Cua-delegated clicks to
bypass `Dispatcher.handle`; delegation happens *inside* `proctor_act`, so the outer call
is still the dispatch call and the step records are still written on this side of it.
It read the `RunHUDPanel` audit sink's records as mis-grouped singletons; a person's Stop
*is* its own event, and that is now stated as intended behaviour with a test rather than
treated as a defect.

**Five recorded as stated boundaries or child work** rather than changed here: the
same-user socket remains PRO-0013's already-named boundary; `proctor_policy audit` needs
a cap, which is PRO-0005's surface; error-message payload echo needs its own audit; the
policy gate does not refuse Proctor's own bundle id; and a wall-clock retention trigger
has no better available answer, so it is named instead of hidden.

## Child work found

- **A plane name for a delegated step (PRO-0044).** When actuation moves to Cua, the
  `plane` a record carries needs a value for a step Proctor did not post. History draws
  an unrecognised plane as an opaque label rather than failing, so nothing breaks — but
  the vocabulary is that item's to settle, not this one's.
- **`proctor_policy` action `audit` takes an unbounded `limit`.** It is a catalogue tool
  that opens the trail, so a model can pull all of it in one call. Capping it belongs
  with PRO-0005, which owns that tool.
- **Audit the agent's error messages for payload echo.** A failure reason is the one
  field that could carry text the `value` and `script` redactions exclude. Nothing found
  here says one does; nothing here proves one does not.
- **The policy gate does not refuse Proctor's own bundle id.** A model can attach to the
  status app and read its accessibility tree. The History window is excluded from
  capture, which does not close the accessibility half.
- **Segmented retention, so history slides rather than empties.** Rejected here for the
  reason in the Assumptions. If the cliff bites in use, the shape is a retired segment
  with its own anchor and a verifier that reports on both.
- **A `policy` block in `proctor_doctor`.** PRO-0013 recorded this as missing and it
  still is; the trail's state is visible through `proctor_policy status` alone. Left
  with PRO-0005 where PRO-0013 left it.

---

## Progress — 2026-08-15

**In Review.** Branch `ai/pro-0047`, worktree `.worktrees/PRO-0047`. Stopped before
merge per the fleet rule. Plan: `docs/plans/plan-PRO-0047.md`.

**Gate:** `swift build` clean. `swift test` **921 tests in 103 suites passed** against a
HEAD baseline of **849 in 98** — plus 72 tests and 5 suites, nothing changed, nothing
removed.

Both numbers are measured with four suites skipped — `BrowserLaneWiringTests`,
`ObscuraPresenceWiringTests`, `HoldAttributionWiringTests`, `TakeoverWiringTests` — and
the reason is worth stating plainly rather than burying, because a skipped suite is a
gap in a gate. Those four hang, and they hang **at HEAD as well as on this branch**:
the first run of this session, taken before a line was changed, stalled on exactly the
same tests, and the HEAD baseline above was produced with the same skip set to make the
two numbers comparable. They depend on `proctor_doctor`, which waits indefinitely, and
that is the subject of PRO-0041, in flight in another worktree. Nothing in this feature
touches them. With those four included, a full run reached 1,065 passing tests with
**zero** recorded issues before stalling, and all six of the suites this feature owns or
touches passed inside that run.

### What was built

`AuditRecord` gains six optional fields inside the sealed ciphertext — `run`, `seq`,
`ms`, `plane`, `act`, `obj` — so a record can be grouped and read. They change neither
the signed material nor the chain link, both of which are computed over the ciphertext,
and an entry sealed before this decodes with all six nil. `RunIdentity` mints a task
local at the dispatcher's existing choke point, so a gate refusal, every step of a batch
and a lane recommendation share one run without any call site knowing about it.
`StepDescription` gained a verb/object split and a caller-supplied cap, because a
blended `Pressed "Send invoice"` cannot be fenced without fencing Proctor's own verb.

`RunHistory` and `HistoryRetention` in Core are pure and carry every decision: the
grouping, the outcome reduction, the caps, the clamps and the rotation wording.
`AuditLog` gained rotation, which is both the retention cap and Clear.
`SessionHistory` projects opened records into runs behind two internal verbs that are
not in `ToolCatalogue`. `HistoryWindow` draws it in the status window's own language,
with one `Fence` view that is the only place foreign text is rendered.

### Acceptance

| Clause | Test |
|---|---|
| A run's records group into one run, in order | `groupsByRun`, `ordersStepsBySeq` |
| A record outside a call is its own run | `recordWithNoRunIsARunOfOne`, `standaloneRecordsDoNotMerge` |
| Records written before this still read | `recordsWithoutRunFieldsStillRender` |
| An application is named by bundle id, never a handle | `runNamesTheApplicationByBundleId` |
| A gate refusal lands on the run | `gateRefusalIsTheRunsOwnReason` |
| The outcome is reduced, not guessed | `outcomeAllOk`, `outcomeAllFailed`, `outcomeHaltWins`, `outcomeRefusalWins`, `outcomeMixed`, `outcomeRecommended`, `outcomeEmpty`, `haltIsNotTheGate` |
| An application cannot fake a person's Stop | `haltTestIgnoresForeignText` |
| An unopenable entry is counted, never dropped | `unreadableIsCounted` |
| A recommendation carries the scheme and no address | `laneCarriesSchemeOnly` |
| The projection carries nothing it does not draw | `projectionOmitsSecrets` |
| Neither history verb is reachable as a tool | `historyIsNotInTheCatalogue` |
| One call is one run; two calls are two | `oneCallOneRun`, `taskLocalCrossesTheActorHop` |
| A step's record carries position, cost, plane, wording | `stepRecordCarriesTheFacts` |
| An app's own name is cleaned before it is stored | `derivedNamesAreCleanedBeforeTheyAreStored` |
| Verb and object recompose to the blended line | `verbPlusObjectEqualsCompletedLine` |
| The verb is Proctor's, never the kind's raw value | `verbIsAlwaysWritten` |
| One sanitiser, two caps | `historyCapUsesTheSameSanitiser`, `longerCapStillCleans`, `quotesAreFoldedAtEveryCap`, `longerCapIsGraphemeSafe` |
| Typed text never reaches the wording | `typedTextNeverBecomesAnObject` |
| Each cap fires on its own | `entryCapRotates`, `ageCapRotates`, `entryCap`, `ageCap` |
| A backwards clock does not rotate | `clockMovedBack` |
| Caps are clamped, with no unbounded value | `clampDays`, `clampEntries`, `noUnboundedSetting`, `defaults`, `honoursEnvironment` |
| Rotation attests what it discarded | `rotationRecordCommitsToTheHead`, `noteCommitsToTheHead`, `rotationNamesTheCap` |
| A rotated trail verifies clean | `rotatedTrailVerifiesClean`, `rotationStartsAFreshTrail`, `appendingAfterRotationStaysClean` |
| Rotation leaves no readable copy | `rotationLeavesNoSidecar` |
| A trail that cannot be signed is not rotated | `unsignableTrailIsLeftAlone` |
| Clear is the same operation | `clearRotatesNow`, `clearingEmptyIsANoOp` |
| An interrupted rotation completes | `interruptedRotationIsCompleted` |
| A planted or corrupt marker cannot drive a wipe | `plantedGarbageMarkerIsIgnored`, `plantedMarkerCannotForgeASummary` |
| A finished rotation is not run twice | `completedRotationIsNotRepeated` |
| Two agents cannot double-rotate | `capIsRetestedUnderTheLock` |
| The cap survives an unrecordable end-mark | `capSurvivesAnUnrecordableAnchor` |

### Gates

**Spec review: grok `grok-4.6` (xhigh, read-only), lane ran, no downgrade.** 22 findings;
14 accepted, 3 rejected, 5 recorded as boundaries or child work. Dispositions in full
above.

**Completeness critic: grok `grok-4.6`, lane ran on the second attempt, no downgrade.**
The first attempt died on the deadline after going off to read the repository itself
rather than answering from the description; the retry, explicitly told to answer from
the description alone, returned 19 findings. **Five were real defects in the shipped
code and are now fixed, each with a test:**

1. A **planted rotation marker** would have had Proctor sign a discard summary that
   never happened — a forgery carrying Proctor's own signature, which is strictly worse
   than the deletion the same person could already perform. The attestation is now
   recomputed from the trail at the moment of truncation and the marker's numbers are
   never signed; where the trail is already empty the record says the summary could not
   be established rather than repeating an unverifiable claim.
2. A **corrupt or truncated marker** drove a rotation. It is now removed and ignored.
3. A crash **after the attestation was written but before the marker was deleted** would
   have re-run the rotation and destroyed the genesis entry it had just written, and on
   a loop, everything appended since. Recovery now recognises a finished rotation and
   only clears the marker.
4. The cap decision was taken **outside the cross-process lock**, so two agents could
   both rotate and the second would wipe the first's attestation. The caps now travel
   into `rotate` and the decision is made again under the lock.
5. The cap counted from the end-mark alone, so a **key store that stopped recording new
   marks** would freeze the count while the file grew — the trail growing without limit
   while reporting that it was bounded, which is this feature's own failure arrived at
   quietly. The count is now the larger of the mark and what the last append actually
   saw in the file, which the append reads anyway.

Rejected with reasons: it read the whole-trail wipe as forced by the chain (the spec
names both alternatives and chose on verifier complexity); it assumed appends,
migration and rotation do not share the cross-process lock (they do, and always have);
and it expected the rotation record to be attributed to the triggering call (the cap
check runs deliberately *before* the run identity is minted, so a rotation reads as its
own event, which is what it is).

**Egress note, worth recording.** The contract warns that a grok call transmits the
artifact and every source file it opens. No key-handling code was pasted into either
prompt, but the first invocation went and read the worktree on its own initiative,
including the audit and key-store sources, before dying on the deadline. A future gate
on this area should say "do not read any files" in the prompt itself, which is what the
retry did.

### A defect found in the existing tests, and fixed

Two suites that each redirect the process-wide trail seams ran in parallel and stamped
on each other: `.serialized` only orders the tests *inside* one suite. It presented as
entries appearing in another suite's file and a key mismatch against a public key a
different suite had cached. `Tests/ProctorAgentTests/TrailIsolation.swift` now carries
one lock that every trail-touching suite takes, `AuditChainWiringTests` included.

The same work needed a seam for the sealing pair (`AuditSealKeys`), because reading the
trail was not previously testable at all: the unsealing half comes from the login
Keychain, which a test process must never touch, so a suite could prove the trail was
written and never that it could be opened. The live implementation and its default are
unchanged.

### Not machine-witnessable here

The window's rendering, the fence as drawn, the Clear confirmation, light and dark, and
the exclusion from screen capture. `swift test` has no window server. Everything those
views decide — the grouping, the outcome, the sanitisation, the caps, the projection —
is in Core or the agent and is tested there; what the views own is arrangement. It needs
a human glance.

### Deliberately not built

No export, no reveal-in-Finder, no copy-all, no second file: PRO-0013's decision is not
reopened by a convenience button. No segmented retention, so history empties rather than
slides; the reasoning and the shape it would take if the cliff bites are in the
Assumptions and in Child work. No cap on `proctor_policy` action `audit`, which is
PRO-0005's tool.
