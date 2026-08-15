# PRO-0036: The status window's checks say what they can check

**ID:** PRO-0036
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/37-the-status-windows-checks-say-what-they-can-check.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` (wave 7 architecture; nothing here contradicts it)
**Builds on:** PRO-0028 `(merged)` — the precedent and the constraint; PRO-0041 `0545219` — the three-state grant and `AgentRecovery`; PRO-0050 `0ea6f88` — the toolchain report shape this window renders
**Consumes:** `DoctorReport.tools`, `ToolPresence.usability` / `.evidence` / `.version` / `.detail`, `AgentRecovery.Offer`

## Feature description

> **REVISED for wave 7, 2026-08-15.** Still wanted, and now larger. The window will also be reporting on `cua-driver`, `xcrun simctl` and `maestro`, so the rule this brief is about (a check must say what it can actually establish) applies to more rows than it did. Sequence after brief 51, which decides what the health report knows.
>
> ## The problem
>
> Two pre-existing defects in the status window, both logged by features that
> declined to widen their scope.
>
> - **Three `Re-check` buttons carry the limitation PRO-0028 deleted a menu row
>   for.** macOS caches the Screen Recording answer through `SCShareableContent`
>   per process for that process's life, so none of these buttons can clear a stale
>   denial. Nothing is broken, because a working `Restart Agent` now sits beside
>   them, but the buttons still promise a check that cannot reach that grant.
> - **The Shortcuts CLI row renders under "Optional — asked for per app"**, which
>   is text belonging to the Automation grant and wrong for a CLI. PRO-0023 did not
>   add to it, reporting Obscura as a tool rather than appending to `grants`, so
>   the row is now the odd one out in its own section.
>
> ## What it should do
>
> Make each check in the window say what it can actually establish, and put the
> tool rows under a heading that describes tools.
>
> ## The hard parts, named
>
> - **PRO-0028 is the precedent and its reasoning is the constraint.** It removed a
>   control rather than relabelling one, on the grounds that a label naming an
>   object the control cannot read is worse than no control. The same test applies
>   to each of these three buttons individually: for each one, name what it reads,
>   whether that read is cached, and whether a person pressing it can change the
>   answer. Some of them may be fine.
> - **`Restart Agent` beside them is the working path** and the window should make
>   that legible rather than leaving a person to discover which of four buttons is
>   the one that works.
> - **Grants and tools are different kinds of thing.** A grant is a decision macOS
>   holds about Proctor; a tool is a file on the machine. They currently share a
>   section and a subtitle. Separating them is the smaller half of this item and
>   probably the more valuable one.
>
> ## Not in scope
>
> Adding new checks. This is about the ones already on screen telling the truth.

---

## The per-button verdict, which is the deliverable the brief asks for

The brief asks for one thing per button: what it reads, whether that read is cached, and
whether a person pressing it can change the answer. Read at the source on 2026-08-15.

| # | Button | What it reads | Cached? | Can a press change the answer? | Verdict |
|---|---|---|---|---|---|
| A | `Re-check` beside **Start the agent**, in the agent-not-answering state | whether the agent's socket answers, over a connection opened fresh for the call | **No** | **Yes.** A person who has since started the agent gets a different answer — and a restarted agent is a *new process*, so its grant cache is empty too | **Honest. Keep unchanged.** |
| B | `Re-check` in the **Obscura is not installed** callout, directly under the install commands | a fresh stat of every path Proctor searches for the tool | **No.** The agent re-probes on every health call, and the comment over that line names this button as the reason | **Yes.** Run the commands printed above it, press it, the row changes | **Honest. Keep unchanged, and it is the working path for its own callout.** |
| C | `Re-check` in the **footer** | the whole report | **Partly.** Accessibility reads live. Every tool row is re-stat'd. Screen Recording is answered from a cache macOS holds per process for the life of that process — a *definite* answer, granted or denied, is frozen there until the agent restarts. An *unconfirmed* answer is never cached and is re-asked on a backoff | **No — nothing a press produces is unobtainable by waiting two seconds, and the one row a person presses it for cannot move at all** | **Delete it.** |

Two of the three are fine, which is what the brief left room for. The third is the item, and
the answer for it is the precedent's answer.

### The two measurements that decide button C

Both read from the source on 2026-08-15, and together they are the whole argument.

**The poll never stops.** It starts when the window's model is created and there is no code
path anywhere that stops it — the function that would exists and is called by nothing. So
the report is re-fetched every two seconds for the application's entire life, window open or
closed.

**The timestamp beside button C already advances on its own.** The `Checked 14:32:01` line
is stamped every time a report lands, which is every two seconds. A person watching the
footer sees the clock tick without touching anything.

So button C sits beside a clock that advances without it, refreshing rows that refresh
without it. Its entire contribution is up to two seconds of latency, and that contribution
is invisible because the clock was going to move anyway. Meanwhile the one row a person has
a reason to press it for — the frozen permission — does not move at all.

### Reconciling this with PRO-0028, which already ruled on these buttons

PRO-0028 did not merely leave these three alone; it reasoned about them and said they stay:
*"each has its object from context, which is exactly what the menu row lacked."* Its
completeness critic disagreed as finding 8, that finding was rejected for that item and
logged as child work, and this item is that log.

**PRO-0028 was right about two of them and wrong about the third, and the reason is what
counts as context.** Buttons A and B sit inside a remediation block — a statement of what is
wrong, an instruction, and a control that confirms the instruction worked. Their object is
the thing the block is about, a press genuinely re-reads it, and neither is anywhere near the
frozen permission. Button C sits beside a clock. "Everything in this window" is not an object;
it is the absence of one, which is exactly what the deleted menu row had.

Both of PRO-0028's own legs for deleting that row apply to button C unchanged: **the poll
already does everything it does**, and **the press a person is motivated to make is the one
it cannot serve.** The right question is not how many rows the button refreshes but why
anybody reaches for it, and the answer is that something looks wrong and they want it
re-read. The thing that looks wrong and will not move is the frozen row.

Counting live rows instead of counting motivations is how a control that does nothing keeps
its place. Deleting it also leaves `Restart agent` as the only action beside the timestamp,
which is the second thing the brief asked for.

### The claim beside it is false too, and separately

`Re-check` names no object; the line next to it makes a claim. **`Checked 14:32:01`** is one
freshness statement placed under the whole window. It is true of the report, of every tool
row and of Accessibility. It is false of exactly one row, whose answer macOS established when
the agent launched and may be hours old.

That is the trap, and an ordinary person reaches it in four steps: see *Screen Recording —
Required, not granted yet*, press **Open Settings**, grant it, come back, look at the footer.
The clock says a second ago. The row still says not granted. The natural reading is that the
grant did not take.

**Freshness is a property of an answer, not of a window.** PRO-0050 reached the same
conclusion from the other side and put a checked-at stamp on every tool row. Deleting the
button does not fix the sentence, and fixing the sentence would not have justified keeping
the button; they are two defects that happen to be adjacent.

## What this feature is

Four changes, none of which adds a check.

### 1. The footer's ornamental `Re-check` goes, and its claim is corrected

The button is deleted, for PRO-0028's own two reasons applied to it. `Open log` and
`Restart agent` stay, which leaves the footer with one maintenance action, one real remedy,
and a clock — and makes `Restart agent` the only thing there a person can press when
something looks wrong.

The clock's blanket claim is scoped to what it is actually about: the report was **asked
for** at that time, which is true of every report, rather than every answer in it having
been **established** then, which is not.

Buttons A and B are untouched, down to their labels.

### 2. Each check says what moves it, attached to its state and never to the permission

Every check gains a plain sentence about what would change its answer. The sentence belongs
to **the state a check is in**, not to the check itself — flattening Screen Recording into
one line is a defect, because two of its three states move by entirely different means:

| Check and state | What moves it | What the row says |
|---|---|---|
| Accessibility, denied | read live on every poll | Proctor notices a grant made in Settings on its own, within a couple of seconds |
| Screen Recording, **denied** | only a fresh agent process | macOS settled this answer when the agent started and will not revisit it; granting it in Settings will not change this row until the agent restarts |
| Screen Recording, **unconfirmed** | the probe being asked again, which happens by itself | macOS did not answer in time; Proctor asks again on its own, and this is not a refusal — **and it must never claim a restart is required, because none is** |
| Screen Recording, **granted** | nothing said | unchanged, and deliberately silent — see the asymmetry below |
| Automation | the target application's own prompt, at first use | unchanged — *Optional — asked for per app* is correct here, and this is the only check it was ever correct for |

**The asymmetry, named rather than hidden.** The same cache freezes a *revocation*: a person
who turns Screen Recording off in Settings leaves the agent reporting it granted until the
agent restarts, so a green row can outlive the permission it describes. The row stays silent
about this on purpose. A caveat under every healthy permission on every working Mac is the
permanent-nag failure PRO-0028's critic forced out of the menu, and the two errors are not
symmetric in cost: a stale denial is silent and traps a person into thinking their grant
failed, while a stale grant fails loudly and immediately the first time anything tries to
capture. The fact is recorded here and as child work rather than pretended away.

### 3. `Restart Agent` becomes legible as the remedy for the one answer that is stuck

The sentence that says this is already written, already tested and already gated — and the
status window does not show it. `AgentRecovery.decide` is a pure function from PRO-0041; it
produces a reason and an action title, and it offers the restart **only when this window's
own independent read of the permission says the grant is there**. That gate is not
decoration: PRO-0028's critic forced it precisely so that a Mac which has never granted
Screen Recording does not carry a permanent row whose button cannot create a permission. The
offer is rendered in the menu today and nowhere in the window.

So the window renders the offer it already computes, beside the grant it is about, with the
reason and the button together rather than a paragraph a person has to finish before finding
the action. Nothing new is decided, the gate survives unchanged, and no nag is added.

**When the offer does not appear, the row still has to be useful.** That window read may
itself be answering from a per-process cache — a limitation recorded knowingly in
`AgentRecovery` and in PRO-0028's assumptions, and independently rediscovered by this item's
own review. It is not reopened here, but it has a consequence that is this item's: the row's
sentence has to name the restart on its own, so that a person whose offer never appears still
learns what to do. The footer's `Restart agent` is where they do it.

### 4. Grants and tools stop sharing a section

They are different kinds of claim and the window currently makes them in one voice. After
this there are three sections, each answering one question:

- **Permissions** — decisions macOS holds about Proctor. Accessibility, Screen Recording,
  Automation. Nothing else.
- **Tools** *(new)* — files on this machine that Proctor does not ship. The Shortcuts CLI
  moves here, which is what the brief asked for; Obscura and the second browser lane move
  here from the agent card; and the rows PRO-0050 already puts on the wire and this window
  has never drawn — `simctl` with its Xcode version, `cua-driver`, `maestro` — are drawn
  from the same array rather than from a second opinion.
- **Background agent** — facts about the running process. Version, this window's build,
  macOS, socket, attached apps, live observers, signature, and the Secure Event Input
  notice.

Each tool row shows what PRO-0050 established about it: whether it is usable, what that
verdict rests on, a version when a route that runs nothing produced one, and — behind the
same show-and-hide the grant rows already use — Proctor's own sentence and the paths it
searched. The searched paths matter: an agent started by the system inherits none of a
terminal's lookup settings, so *"but it is installed"* is diagnosable only by comparing
where each side looked.

The window's own hand-written summary of Obscura goes. It is a second verdict about a row
the report already decided, and two verdicts about one fact eventually disagree.

## Why this stays inside "no new checks"

The brief rules out adding checks and this adds none. Nothing here probes anything: no new
call, no new tool, no change to the agent, no change to what goes over the wire. Every row
in the new section is an answer the agent already computes and this window already receives
every two seconds and currently throws away. Drawing an answer that is already in hand is
not a new check.

The line falls the other side of two things that would be. `proctor_doctor` also carries a
per-lane readiness block and a policy posture block, both real, both unrendered. They answer
questions this window does not ask today — *what can this machine actually do*, and *will the
gate refuse the next call* — and each is a new surface with its own design. Both are recorded
as child work rather than smuggled in here.

## Acceptance criteria

Each is one thing that must be true. Every clause marked **(machine)** is provable by a
Swift test; every clause marked **(eye)** needs a person to look at the rendered window,
because this repo has no test target for the UI and no window server under `swift test`.

1. **(machine)** **Every check knows what moves it.** Each name the health report can put in
   its permissions list resolves to exactly one kind: a permission read live, a permission
   answered once per agent process, a permission that can only be settled by the target
   application's own prompt, or a tool. No name resolves to none, and a test fails if the
   agent emits a name this does not cover.
2. **(machine)** **A tool never appears among the permissions.** Given a report whose
   permissions list carries the Shortcuts CLI, the permissions section excludes it and the
   tools section includes it.
3. **(machine)** **"Optional — asked for per app" is only ever said about Automation.** It
   still renders for Automation, and no other check can produce that sentence.
4. **(machine)** **The remedy sentence belongs to the state, not to the permission.** A denied
   Accessibility grant says Proctor will notice a grant on its own. A denied Screen Recording
   grant says the answer was settled when the agent started and needs a restart. An unconfirmed
   one says macOS did not answer and that Proctor asks again by itself — and **never** claims a
   restart is required or names a settings pane, because neither is true of that state.
5. **(machine)** **The unconfirmed state is not dressed as a denial.** No remedy, sentence or
   control produced for an unconfirmed grant claims a refusal or names a switch to flip —
   holding PRO-0041's rule at the surface this item touches.
6. **(machine, in part)** **The restart offer is the existing decision, unchanged.** The window
   shows whatever `AgentRecovery.decide` already returned for the same five inputs, and no
   second decision is written — that much is provable. With this window's own read of the
   permission absent or negative there is no offer, so no permanent row appears on a Mac that
   has not granted it, and the row's own sentence still names the restart, so a person whose
   offer never appears is not left without the answer. **That the offer then draws beside the
   right grant is (eye).**
7. **(machine)** **Every tool row is a rendering of a row the report sent.** For each entry in
   the report's tools array there is one row, in the report's order, whose usability, evidence,
   version and detail are the ones the report carried. The window computes no second verdict
   about a tool, and the hand-written Obscura summary is gone from the source.
8. **(machine)** **A tool row's short line is derived, not authored twice.** The one-line
   status a row shows follows from its usability and evidence alone, and the full sentence the
   report supplied is shown unedited behind the disclosure.
9. **(machine)** **The second browser lane keeps its gate.** With the operator's second-lane
   switch off, that tool's name appears nowhere in the window's rendered content — the
   invariant PRO-0035 and PRO-0050 both hold, now also true of the UI.
10. **(machine)** **Freshness is claimed only where it is true.** The footer's line says the
    report was asked for at that time rather than that every answer was established then.
11. **(machine)** **The footer's `Re-check` is gone and the other two are untouched.** No
    control in the footer calls the refresh; `Open log` and `Restart agent` remain. Buttons A
    and B keep their labels and their actions byte-for-byte, and a test pins the verdict table
    above so a later change to any of the three has to argue with a recorded finding rather
    than with nobody.
12. **(machine)** **Nothing is decided in a view.** Every rule in clauses 1 to 10 is a pure
    function in the shared library with a test; no new conditional logic about what a check
    means lives in the window's own code.
13. **(machine)** **The agent and the wire are untouched.** No file under the agent changes,
    the health report's shape is unchanged, and the existing suite stays green.
14. **(eye)** **The three sections read as three kinds of thing.** A person opening the window
    sees permissions, tools and process facts under headings that describe themselves, with the
    tool rows no longer in the permissions list.
15. **(eye)** **The trap is closed.** With Screen Recording denied and then granted in
    Settings, the window says in advance that the row will not move until the agent restarts,
    and offers the restart once it can see the grant for itself.
16. **(eye)** **Nothing is stranded by the deletion.** With the footer button gone, the clock
    still advances on its own while the window is open, so a person can see the window is live
    without a control to prove it.

## Non-goals

- **No new probe, no new call, no new tool, no change to the agent or the wire.** The brief
  rules out new checks and this item adds none.
- **Not rendering the per-lane readiness block or the policy posture block.** Both are on the
  wire and unrendered; both are new surfaces answering new questions. Child work.
- **Not touching the first-run walkthrough**, including its "Already allowed? Open System
  Settings" line — still-open child work from PRO-0041, and a different surface.
- **Not changing what `ready` means**, the menu bar, the character, the run panel, or the
  history window.
- **Not re-deriving anything PRO-0050 decided.** Its verdicts are rendered, not recomputed.
- **Not deleting buttons A or B.** Each has a real object and completes the block it sits in.
- **Not reopening whether this window's own permission read is itself cached.** Recorded
  knowingly in PRO-0028 and unchanged here; this item only makes sure the row is useful when
  the offer it gates does not appear.
- **Not warning about a stale *granted* row.** The asymmetry is real and named above; a
  caveat under every healthy permission is the nag PRO-0028 removed. Child work.
- **Not redesigning the window's look.** Existing components, existing type scale, one new
  section.

## Assumptions recorded in place of questions

- `[Experience]` The footer's `Re-check` is deleted rather than relabelled. *(the clock beside it already advances every 2s and the poll never stops, so it changes nothing a person can see)*
- `[Experience]` Buttons A and B stay exactly as they are. *(each completes a remediation block, names a real object, and a press genuinely re-reads it)*
- `[Experience]` The Screen Recording row states the restart requirement whether or not the restart is offered. *(the offer is gated on independent evidence that may not arrive; the fact is true either way)*
- `[Experience]` The restart offer appears in the permissions section, reason and button together. *(a remedy belongs next to what it remedies, and not behind a paragraph)*
- `[Experience]` A stale *granted* row carries no caveat. *(a warning on every healthy Mac is a nag; a stale grant fails loudly at first capture, where a stale denial traps silently)*
- `[Layout]` Tools become their own section between permissions and activity. *(the two "what does this machine have" questions sit together, then the run's story)*
- `[Layout]` A tool row shows a short derived line, with Proctor's full sentence behind the existing show-and-hide. *(the supplied sentences run to two or three lines and would swamp a row)*
- `[Data & scope]` The Shortcuts CLI is filtered into the tools section by the window, not removed from the report. *(changing what the health report calls it is an agent change this item is scoped out of; recorded as child work)*
- `[Data & scope]` Rows the report already sends and this window has never drawn are drawn. *(an answer already in hand is not a new check)*
- `[Operations]` Every rule lands in the shared library with a test; the window renders. *(there is no test target for the UI and no window server under `swift test`, so a rule written in a view is a rule this repo cannot prove)*
- `[Operations]` The stale mock of this window is left alone and its drift recorded. *(it predates the toolchain report and still shows a menu row PRO-0028 deleted; nothing tests it)*

*If any of these are wrong, correct it inline in this file and re-run `/triage PRO-0036` before the planner picks this up.*

## Out-of-family review — grok-4.6, 2026-08-15

Codex is off for this repo, so the gate ran on grok, read-only, with the evidence inlined.
**The first attempt at `xhigh` was a lane failure** — it exited zero having printed only its
reasoning preamble with no answer body — and is recorded rather than counted as a pass. The
retry at `high` with a shorter prompt answered in full. It did not rubber-stamp: **it
reversed the central decision of the draft.**

| # | Finding | Disposition |
|---|---|---|
| 1 | The draft flattened Screen Recording into "macOS answers once at start", which is false for a timed-out probe — that state is not cached and can flip without any restart | **Accepted.** The sentence now belongs to the state rather than to the permission, and clause 4 forbids an unconfirmed row claiming a restart is needed. |
| 2 | Refusing to delete button C protects impatience, not capability: the 2s poll already updates everything it updates, and the motivated press is the frozen row — the same failure the deleted menu item was killed for | **Accepted, and it reversed the design.** Verified before acting: the poll-stopping function is called by nothing, and the timestamp is re-stamped on every poll. The button is deleted. The draft was counting live rows instead of counting why anyone reaches for it. |
| 3 | Fixing the caption while keeping the verb makes the label honest and leaves the button lying; and explaining before acting inserts a reading assignment in front of the action | **Accepted.** The verb is gone with the button, and the offer now puts its reason and its button together. |
| 4a | If the timestamp only moves on a press you are hiding the poll; if it moves every 2s the button is visibly ornamental | **Accepted as the deciding measurement** for finding 2. It moves every 2s. |
| 4b | The window's "independent" permission read may be the same per-process cache, so the restart offer may never appear after a grant | **Rejected as out of scope, and it confirms an assumption.** Already recorded knowingly in `AgentRecovery` and PRO-0028; reopening it is not this item's. Its consequence *is* this item's, and clause 6 now requires the row to name the restart on its own. |
| 4c | A revocation is frozen the same way, and the copy only addresses granting | **Accepted as a fact, declined as a warning.** Named in the spec as an asymmetry with its reason and logged as child work; a caveat under every healthy permission is the nag PRO-0028 removed. |

## What a test cannot reach here

`swift test` has no window server and there is no test target for the UI. Stated plainly so
the report does not overclaim:

**Machine-witnessed:** every rule in clauses 1 to 13 — the kind of each check, the
partition, the remedy sentences, the tri-state handling, the offer's inputs and gate, the
derivation of each tool row's short line from the report's own values, the second lane's
gate, the footer's wording, and the agent and wire being untouched. These are pure
functions with tests, and the window's job is to call them.

**Not machine-witnessed, needs a person to look:** that the window draws at all; that the
three sections read as three kinds of thing; that a row's disclosure opens; that the tool
rows are legible at the window's real width; that the restart offer appears where it should
on a Mac in the state that produces it; and the end-to-end trap in clause 15, which needs a
real Mac, a real permission and a real agent restart. The plan should end with a build,
install and look, as PRO-0040 did, and the progress note should say which of these a person
actually saw rather than implying the suite covered them.

## Child work found

1. **The health report calls the Shortcuts CLI a permission.** It is appended to the report's
   permissions list, and only when it is missing. This item corrects the window; any other
   reader of that report still sees a tool in the permissions list. Moving it belongs with
   whoever owns that report's shape.
2. **The per-lane readiness block is on the wire and nothing renders it.** Deliberately out of
   scope here; it is the natural next question this window could answer.
3. **The policy posture block is on the wire and nothing renders it.** Same reasoning. Note
   that PRO-0050 recorded its own child work about the policy tool answering freely, which
   bears on how much a window should show.
4. **The first-run walkthrough's "Already allowed? Open System Settings" line** carries the
   misdirection PRO-0041 fixed on the grant row. Still open, still a different surface.
5. **The window mock has drifted.** It shows this window before the toolchain report existed
   and still carries a menu row that was deleted. Either it is maintained or it is marked as a
   record of a past state.
6. **A revoked Screen Recording permission is frozen the same way a denial is**, so the agent
   can report a permission granted after a person has taken it away, until it restarts. Raised
   by this item's out-of-family review and new as far as the specs go. Deliberately not warned
   about here — see the assumption and its reason — but somebody should decide whether the
   agent should re-probe on a revocation signal rather than the window paper over it.

## Plan — 2026-08-15

Implementation plan: `docs/plans/plan-PRO-0036.md` (Plan size: Standard).

Its out-of-family gate changed the shape once more: an unrecognised check name falls to the
**tools** side, not the permissions side. The permission names are a closed set macOS fixes;
tools are the half that grows, so defaulting an unknown name into Permissions would have
re-created the very defect clause 2 exists to remove. A set-equality tripwire between the
agent's grant-name literals and the names the shared library carries makes the fallback
close to unreachable — the build goes red before a machine ever meets it.

## Progress — 2026-08-15

**In Review.** Branch `ai/pro-0036`, worktree `.worktrees/PRO-0036`. Three commits.
`swift build` clean with no warning in any file this item touches.

**Rebased twice while in flight**, because two siblings merged underneath it: onto `107cdbb`
after PRO-0045, then onto `183546d` after PRO-0051. The second carried one conflict, in
`CHANGELOG.md`, where both items had added to `## [Unreleased]`; both entries were kept.

**`./scripts/test.sh`: 1193 tests in 131 suites → 1242 in 136, all green**, re-run in full
after the rebase rather than inferred from a clean apply. 26 of those tests are this item's;
the rest arrived with the two siblings. Every count was read back rather than assumed. Two clauses were proved red before green by
perturbation, and so was the guard the out-of-family critic asked for.

### Clause → evidence

| # | Clause | Evidence |
|---|---|---|
| 1 | Every check knows what moves it | `everyKnownNameClassifies`, `everyKindIsUsed`, `unknownFallsToTools`, and `grantNamesMatchTheMap` (set equality against the agent's own literals) |
| 2 | No tool among the permissions | `shortcutsIsATool`, `partitionIgnoresRequired` (every name × every state × both values of `required`) · **and seen**: the rendered Permissions card holds Accessibility, Screen Recording and Automation only |
| 3 | "Optional — asked for per app" is Automation's alone | `perAppTextIsAutomationsAlone` · **and seen** on the Automation row |
| 4 | The sentence belongs to the state, not the permission | `mobilityMatrixIsComplete`, plus the three named cases. **Proved red** by returning nil from `mobility` |
| 5 | Unconfirmed is never dressed as a denial | `unconfirmedIsNotADenial` |
| 6 | The restart offer is the existing decision | `theViewActuallyCallsTheLibrary` asserts the window reads `model.recovery` and re-derives neither `AgentRecovery.decide` nor its evidence gate. **The offer drawing in place is not witnessed** |
| 7, 8 | Tool rows render the report's verdicts, short line derived from usability and evidence alone | `rowsMirrorTheReport`, `statusIgnoresPathAndVersion`, `rowsSurviveAReportWithoutTheUsabilityAxis` |
| 9 | The second lane's gate holds at this surface | `secondLaneStaysBehindItsSwitch` (every field of every row) · **and seen**: no such row in the rendered Tools card |
| 10 | Freshness claimed only where true | `freshnessNamesTheAsking` · **and seen**: the footer reads `Asked the agent 10:56:35 pm` |
| 11 | The right `Re-check` went | `theRightRecheckWasDeleted` — the footer region carries none, exactly two remain, and each survivor is asserted inside its own block. **Proved red** by restoring the button · **and seen**: the footer is `Open log`, `Restart agent`, timestamp |
| 12 | Nothing decided in a view | `theViewActuallyCallsTheLibrary`. **Proved red** by pointing one call at nil |
| 13 | The agent and the wire untouched | **Not held. See below** |
| 14 | Three sections read as three kinds of thing | **Seen** |
| 15 | The trap closed | **Not witnessed** |
| 16 | Nothing stranded by the deletion | **Seen in part** |

### The clause that broke, and why breaking it was right

**Clause 13 said the agent and the wire were untouched. They are not, and the reason is the
whole value of having looked.** `Dispatch.swift` assembled `proctor_doctor`'s reply by
encoding `DoctorReport` and then **overwriting** `report["policy"]` with the full ungated
`policyStatus()`. That shipped on `main` with PRO-0050 and cost two separate things:

- **The status window was broken outright.** The replacement carries none of `PolicyPosture`'s
  keys, and an optional field that is *present but wrong-shaped* still throws, so
  `DoctorReport` could not decode its own agent's reply. The window reported a completely
  healthy agent as "The background agent is not answering" and never recovered. Confirmed at
  the exact error, both by removing the line and by putting it back:
  `DecodingError.keyNotFound`, key `mode`, path `policy`.
- **PRO-0050's clause 12 was true of the type and false on the wire.** Every allow, block and
  sensitive entry, the filesystem roots, the trail's path and its key id were in the first
  call the Proctor skill tells a model to make.

Deleting the overwrite restores exactly what PRO-0050 specified and already tested for, and
`proctor_policy` action `status` is untouched and still answers in full. Three new tests in
`DoctorReplyWiringTests` hold it **where a caller actually reads it** rather than where the
type is encoded, which is the gap that let it ship.

No test in either item could have caught this. It was found by building the app and looking
at it, which is the step the plan insisted on.

### Seen by a person, and how

Built the bundle and ran it **without installing**: three sibling runners were in flight and
replacing `/Applications/Proctor.app` would have restarted the shared agent under them. The
build ran against a private agent on `PROCTOR_SOCKET=/tmp/pro0036-agent.sock`, so nothing
installed was touched; the launchd job was confirmed present and answering at the end.

Witnessed: the window drawing; the Permissions card with its new subtitle and only the three
permissions; `Optional — asked for per app` on Automation and nowhere else; both granted rows
correctly silent; the Tools card with its own subtitle and five rows — `obscura` *Usable,
found*, `simctl` *Usable, version read from where it is installed* with **26.6 (17F113)**,
`cua-driver` *Not found*, `maestro` **2.4.0**, and **`Shortcuts CLI` — *Usable, part of
macOS***, which is the row the brief is named for; no `browser-use` row with the lane off; the
Background agent card reduced to process facts with no tool rows left in it; the footer as
`Open log`, `Restart agent`, `Asked the agent 10:56:35 pm` and **no `Re-check`**; and the
agent-down branch still carrying `Start the agent` beside its own untouched `Re-check`, with
the Tools card correctly absent when there is no report.

### Not witnessed, and not implied

- **The denied and unconfirmed permission sentences, and the restart offer.** Both grants are
  granted on this Mac. Seeing them needs a permission revoked on the reader's own machine,
  which was not done. The sentences are proved as strings; their placement is not.
- **Clause 15 end to end.** Same reason.
- **A `Details` disclosure opening.** SwiftUI exposes neither the scroll view nor these
  buttons to System Events, and driving Proctor's own window *through Proctor* twice knocked
  the installed agent over, so it was stopped rather than pushed. The rows and their contents
  are witnessed; the toggle's behaviour is not.
- **Clause 16 in full.** The footer was seen without its button; that the clock keeps
  advancing was not timed across two captures.
- **Anything about `cua-driver` beyond absence.** It is not on this machine.

### Child work found

1. **An older agent still breaks a current window, and nothing says so.** A report from a
   pre-PRO-0050 agent fails the same decode for the same reason, and the window blames the
   agent. The installed app on this Mac was three merges behind and presented exactly that.
   Worth a version-aware message, or a lenient decode, rather than "not answering".
2. **Driving Proctor's own UI through Proctor destabilises the agent.** Two `proctor_act`
   scroll steps against a Proctor window left the installed agent unreachable until launchd
   restarted it. Same bundle id on both ends is the obvious suspect.
3. **The health report still calls the Shortcuts CLI a permission.** Corrected at the window;
   any other reader of that report still sees a tool in the grants list.
4. **The per-lane readiness block and the policy posture block are on the wire and unrendered.**
   Deliberately out of scope here.
5. **A revoked Screen Recording permission is frozen the same way a denial is**, so the agent
   can report it granted after a person has taken it away.
6. **The first-run walkthrough's "Already allowed?" line**, still open from PRO-0041.
7. **The window mock has drifted** and predates both the toolchain report and PRO-0028.
