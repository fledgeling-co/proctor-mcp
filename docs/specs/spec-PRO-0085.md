# PRO-0085: the skill that never mentions the guest lane, and a count that was wrong twice

**ID:** PRO-0085 · **Status:** To Do · **Created:** 2026-08-22
**Brief:** `docs/features-to-triage/78-the-skill-and-the-guest-lane.md` (Wave 12), which supersedes
the still-open `53-the-proctor-skill-tracks-what-shipped.md`
**Branch:** `ai/pro-0085` off `ai/wave-9` · **Lane:** headless, `./scripts/test.sh`
**Requirements:** REQ-091, REQ-092, REQ-093 · **Defects:** DEF-190..DEF-192 · **Cases:** CASE-0370..CASE-0374
**Ledger id:** allocated by the orchestrator. This item does not write `docs/feature-specs/LEDGER.md`.

**The deliverable lands outside this repository**, in
`~/Dev/fledgeling-plugins/plugins/proctor/skills/proctor/`. That skill is live for every project on
this machine, so a change to it reaches work this repository never sees. The repository-side change
is one test file, and it exists because the skill is about to assert an invariant nothing here
checks.

## Ready for implementation plan

**What an agent gets today.** A skill that documents 20 of the 21 tools the server ships, and the
one it omits is `proctor_guest` — the entire guest lane, absent from `SKILL.md`, from
`references/tools.md`, and from both other reference files. The only sentence in the skill that
mentions a virtual machine is `SKILL.md:802`, under `## Scale`, and it says a VM fleet is not the
answer. Every clause of it is true. An agent reading it concludes the lane is closed.

**What they get after this.** The guest lane named in the description, so the routing text an agent
matches against knows the lane exists; a short section saying when a guest is the right choice and
when the host is; the two-guest cap kept, with its citation, under the scale question it answers;
the native-versus-delegated tier stated plainly, so no campaign is planned against an accessibility
tree a Windows guest does not have; and the sentence that nothing provisions a guest, so an agent
asks for a provisioned machine at the start rather than discovering it halfway through a run.

### The brief's central measurement does not hold today, and the corrected one is smaller

The brief says the server ships 27 tools against the skill's 20, and names seven missing:
`proctor_guest`, `proctor_queue`, `proctor_hud`, `proctor_history`, `proctor_recent`,
`proctor_resource` and `proctor_actuation`. Re-measured on 2026-08-22 against
`Sources/ProctorCore/ToolCatalogue.swift`, which the brief itself names as the source of truth:

| | Count | Read from |
|---|---|---|
| Tools the server ships | 21 | `ToolCatalogue.all` |
| Tools `references/tools.md` names | 20 | every `proctor_*` token in the file |
| Genuinely missing | **1** | `proctor_guest` |

The other six are **internal agent verbs and belong in no tool list.** `AgentVerbs.swift:20-24`
states the boundary in its own words: *"The verbs below are internal. None is in `ToolCatalogue`, so
the shim — which gates `tools/call` on the catalogue — cannot reach them and no MCP host can put a
person's stop button away or read their activity feed through this path."* `MCPServer.swift:224`
is that gate: `guard ToolCatalogue.spec(named: name) != nil else { ... "no such tool: \(name)" }`.
Two of the six are not even spelled the way the brief spells them — the verb is
`proctor_recent_activity`, and `proctor_actuation` is a label on an audit record rather than a verb
at all.

Documenting the six as callable tools would tell every agent on this machine to make calls the shim
refuses. The skill instead states the boundary and why it exists, which is the useful version of
the same fact.

### Assumptions

**A1 — `ToolCatalogue.all` is the tool list, and the internal verbs are excluded deliberately.**
Grounded in `AgentVerbs.swift:20-24` and the `tools/call` gate above, and in the task brief's own
instruction to re-count against the catalogue. The alternative it beats was writing all 27 names
into `tools.md`, which the brief asked for on a measurement that has since moved.

**A2 — the repository-side change is one test file guarding that boundary.** The skill is about to
tell agents that internal verbs are unreachable through MCP; `AgentVerbs.swift` claims the same
thing in a comment; nothing tests it. A catalogue addition would make both statements false while
both still read as true. This is the narrowest change that gives the documentation something to
stand on, and it is the only repository-side code this item writes. The alternative it beats was a
skill-only change, which is smaller but leaves a security-relevant claim untested for the third
time in this file's history.

**A3 — the count is stated with the command that reproduces it.** `tools.md` carrying a bare "21
tools" drifts the moment the catalogue moves, which is how this brief came to be written twice. The
number is given with the file it is read from, so the next reader re-measures in one step.

### The open question this item records and does not answer

Whether `proctor_guest` should gain a `provision` action. Today it provisions nothing, because an
install must not happen as a side effect of a tool call and agent calls cannot raise the macOS
permission UI that Accessibility and Screen Recording need. Documenting that is a skill change;
changing it is a safety-posture change, and it belongs to the reader. The skill states the current
posture and its reason, and adds no `provision` action.

## The problem

### DEF-190 — the guest lane is absent from the skill that routes agents to it

`proctor_guest` shipped in wave 10 with eight actions — `list`, `status`, `start`, `stop`, `clone`,
`reach`, `attach`, `detach` — and was proved against a provisioned macOS guest
(`docs/specs/spec-PRO-0076.md`). A grep for `guest`, `lume`, `prlctl` or `tart` across `SKILL.md`,
`references/tools.md`, `references/methodology.md` and `references/evidence.md` returns no
description of the lane. The skill's `description`, which is the routing text a host matches
against, offers a macOS lane and an iOS Simulator lane and nothing else.

**Severity: medium.** The lane works and is unreachable from the instructions.

### DEF-191 — the only VM sentence in the skill answers a question nobody asked

`SKILL.md:802`, under `## Scale`: *"Apple silicon caps concurrent macOS guests at two, so a VM
fleet is not the answer, and more real parallelism past that is a hardware purchase rather than a
configuration change. Do not design a campaign that assumes otherwise."* The claim is correct about
throughput. The reasons to reach for a guest are isolation — a clean machine, a pinned OS version,
a discardable state, and not commandeering the desktop somebody is working on — and the cap speaks
to none of them. Positioned as the skill's only word on virtual machines, it reads as a
prohibition.

**Severity: medium.** A true fact filed under the wrong question, which is how a capability gets
talked out of existence.

### DEF-192 — `tools.md` states a tool count it no longer matches, and miscounts its own list

Line 11: *"The server ships **20 tools**"*, against 21 in `ToolCatalogue.all`. Line 31: *"Five more
exist and are named here rather than specified"*, followed by six names — `proctor_policy`,
`proctor_kill`, `proctor_dictionary`, `proctor_unlock`, `proctor_computer`,
`proctor_openai_computer`. The `full` profile row in the table reads 20 where
`ToolProfiles.swift:36` defines `full` as `all.map(\.name)`, which is 21.

**Severity: low.** Numbers a reader can check, all three currently wrong.

## The behaviour

### REQ-091 — the skill's tool documentation matches the shipped catalogue and excludes the internal verbs

`references/tools.md` names exactly the 21 tools in `ToolCatalogue.all` and no other `proctor_*`
identifier. The count is stated with the file it is read from. The profile table's `full` row reads
21 and lists `guest` among what `full` adds, matching `ToolProfiles.swift:33-38`. The page states
why `proctor_queue`, `proctor_hud`, `proctor_recent_activity` and `proctor_resource` are absent:
they are internal verbs, the shim gates `tools/call` on the catalogue, and a call to one is
refused with `no such tool`.

`proctor_guest` gets a specified section on the page, at the depth the other 14 specified tools
get: its eight actions, its arguments with types and defaults read from the catalogue's
`inputSchema`, and the `provider` enum with all three of `lume`, `prlctl` and `tart` — the third
added in PRO-0094, and its absence was why a consumer session reported the lane as lume/prlctl
only.

### REQ-092 — the skill routes to a guest on isolation grounds and states the delegated tier honestly

`SKILL.md` carries a section naming the choice between host and guest. The host is right when the
application under test is on this Mac and the person's desktop can be borrowed. A guest is right
when the campaign needs a machine whose state is clean or pinned, when it must not touch the
person's session, or when a run would otherwise leave state behind. The two-guest cap stays, with
its wording and its citation, under the scale question, and `## Scale` no longer carries the only
mention of virtual machines in the file.

The tier difference is stated: a macOS guest runs its own Proctor holding that machine's
Accessibility and Screen Recording grants, so it has a real accessibility tree, frame status and
the tri-observer check. A Linux or Windows guest is delegated — coordinates and screenshots, no
Proctor socket, no accessibility tree — and a tree-reading assertion against one is skipped with a
reason rather than passed.

The skill states that nothing provisions a guest: `list`, `status`, `start`, `stop` and `clone`
operate on a machine that already exists, and creating one, granting Accessibility and Screen
Recording inside its Aqua session, and cloning that granted image are things a person does with the
provider's CLI. The reason is given — an install must not happen as a side effect of a tool call,
and agent and daemon calls cannot raise macOS permission UI — so an agent asks for a provisioned
guest before planning a campaign around one. The skill records that provisioning one took most of a
session and four closed routes (`docs/specs/spec-PRO-0076.md`) rather than implying it is quick.

Where the skill mentions Tahoe rendering it states what was measured rather than asserting the bug,
matching `GuestNotes.TahoeRendering.sentence`, and it states that `proctor_guest --action status`
reports `osVersion` where it can be established and `unknown` with a reason where it cannot.

### REQ-093 — no internal agent verb is reachable through `tools/call`

`ToolCatalogue.spec(named:)` returns nil for every verb declared in `AgentVerbs` except
`proctor_doctor`, which is a catalogue tool and is named there because Proctor's own window calls it
by that name. The shim's `tools/call` gate refuses an unknown name with `no such tool` rather than
forwarding it to the agent.

This is the invariant REQ-091's documentation rests on, and it is asserted here rather than only
described in a comment: a later catalogue addition that exposed `proctor_hud` would let an MCP host
pause a person's run, and both `AgentVerbs.swift`'s comment and the skill would still read as true.

### Edge cases

- A verb spelled in the brief but absent from `AgentVerbs` (`proctor_actuation`, `proctor_history`)
  is not asserted against, because the test reads the declared verbs rather than a hand-copied list.
- `proctor_doctor` is the one `AgentVerbs` member that is a catalogue tool, and the test asserts it
  is present rather than skipping it.

### Failure modes

- **The catalogue grows a tool and `tools.md` is not updated.** The test does not catch this: it
  guards the internal-verb boundary, not the external document. The mitigation is REQ-091's
  stated command, not a test, and this is named as a known limit rather than claimed as covered.

## What this does not change

- No `provision` action on `proctor_guest`, per the open question above.
- No change to `ToolCatalogue`, `ToolProfiles`, the shim, or any guest source file.
- `docs/feature-specs/LEDGER.md` is not written by this item.
- `CHANGELOG.md` is not written: the repository-side change is one test, which is not user-facing,
  and the documentation change lands in a different repository.

## Acceptance

1. `references/tools.md` names 21 `proctor_*` tools and they are exactly `ToolCatalogue.all`.
2. `references/tools.md` has a `## \`proctor_guest\`` section carrying the eight actions and the
   three-provider enum.
3. The profile table's `full` row reads 21 and includes `guest`.
4. The skill's `description` names the guest lane and distinguishes native from delegated.
5. `SKILL.md` carries a host-versus-guest section; the two-guest cap survives verbatim under a
   scale heading.
6. The string "nothing provisions" or its equivalent appears with its reason, and no `provision`
   action is documented.
7. The new test file fails when `proctor_hud` is added to `ToolCatalogue.all`, and passes on the
   unmodified tree.
8. `./scripts/test.sh` prints a verdict line and exits 0.
9. `scripts/campaign/defect_gate.py` passes in both modes.

## What the resume found, 2026-08-22

The first attempt was killed by a stall detector partway through arming the
document instrument. Three things it left behind are recorded here because two of
them were wrong in a way a green run hid.

**The live skill was found mid-mutation.** Arming had been done by editing the
real files in `~/Dev/fledgeling-plugins`, and the kill landed between the mutation
and the revert. For roughly an hour every project on this machine read a skill
whose guest section was headed ``## `proctor_ARMING` ``, whose guest-lane heading
read `## The ARMING lane`, and whose two-guest cap paragraph was a placeholder
reading "A VM fleet is not the answer and the cap is not stated here at two". All
three are restored, the cap keeping the wording DEF-191 records. `skill_doc_arm.py`
now mutates scratch copies, so an interrupted arming run cannot leave the shared
skill broken.

**Three checks in the first instrument could not fail, and its 17/17 was read
over them.** `"tart" in tools` is satisfied by the word "start". The
`## The guest lane` check matched a backticked cross-reference to that heading
while the heading itself said something else, which is why it passed against the
mutated file. And nothing read the count the page states about itself, so
`The server ships **20 tools**` — the headline number DEF-192 exists to correct —
survived a green run of the instrument written to catch it. Providers are now
matched on a word boundary, headings are anchored to the start of a line, and the
stated count is compared to the catalogue. The instrument is 18 checks, and
`skill_doc_arm.py` watches each of the 18 go red under a mutation of its own.

**Two counts were still wrong and are now fixed**: `references/tools.md:11`
(20 → 21) and `SKILL.md:103` ("all twenty" → "all twenty-one"), which completes
the four sites DEF-192 names. A fifth, `gemini.md:21`, is recorded as DEF-193 and
deliberately left: it is outside the two files this item's plan scopes, and it is
notes on adapting the skill for Gemini rather than routing text a tool choice
rests on.
