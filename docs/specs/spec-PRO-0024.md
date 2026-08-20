# PRO-0024: A second browser lane for what Obscura cannot do

**ID:** PRO-0024
**Status:** Merged
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** docs/plans/plan-PRO-0024.md
**Branch:** ai/pro-0024 (worktree `.worktrees/PRO-0024`)

## Feature description

Verbatim brief: `docs/features-to-triage/25-second-browser-lane-for-obscuras-limits.md`.
PRO-0020 hands every browser page to Obscura and carries seven measured edges as data.
Some of those edges stop a job rather than degrading it, so naming one tool for every page
sometimes hands over work that tool cannot finish, and the failure reads as the page's
fault. Add a second lane — the `browser-use` CLI — and make the interesting half the
*choosing*, with the limit that drove the choice stated so the advice is checkable.

This extends PRO-0020's and PRO-0023's object rather than adding a second one.

## Triage — 2026-08-15

### The conflict the brief said to settle: detection **and** an explicit opt-in, defaulting to Obscura-only

**Proctor names `browser-use` only when it is on this machine *and* the operator has turned
the lane on by name. Unset means Obscura-only, which is the standing instruction as
written.** The capability limits stay disclosed either way; only the tool name is gated.

This is the brief's third reading, and the first draft of this spec took the second
(detection alone) on the argument that installing browser-use *is* the operator's consent
materialised. The out-of-family review took that apart, and it was right:

> Installing a CLI is consent to have a file. It is not consent for an Accessibility-holding
> agent to name that file to a model that has a shell.

The asymmetry that argument turns on is the one that matters here and that detection cannot
see. Obscura is a bounded reader: `fetch`, `eval`, `screenshot`. `browser-use` is an
**autonomous LLM agent**, and its default local mode attaches to the operator's running
Chrome over CDP with their cookies, extensions and logins. Naming it is not choosing a
better instrument for a page; it is starting a second agent that can act as that person on
every origin they are signed in to, and whose actions appear nowhere in Proctor's audit
trail. A standing rule that says a tool is *removed* is also exactly the situation in which
a leftover binary is the normal state — so "the file is there" is the weakest possible
evidence that somebody meant it.

The other two readings fail for the reasons already argued, and the first one fails hardest:

**Capability-gated regardless — rejected, and not on taste.** A model holding a shell that is
told "use browser-use" on a machine that has none does not stop; it runs `uvx browser-use`
or `pip install browser-use`, both of which fetch and execute from PyPI. That is PRO-0023's
finding arriving through a different door: a recommendation for an absent tool is an
*install* instruction wearing a recommendation's clothes, and the person who would have
hesitated is not in the loop.

**Detection alone — rejected on the argument above.** It survives as one half of the gate,
because PRO-0023's rule still binds: never name a tool that is not there.

**The opt-in is one environment variable, `PROCTOR_SECOND_LANE`.** Unset or empty is off; the
value is the tool's own name, `browser-use`. It matches `PROCTOR_HUD`, which is how this repo
already spells an operator preference, and it lives in the launchd plist rather than anywhere
a tool result can reach. It names the specific tool rather than being a boolean, so a future
third lane is a value rather than a second variable, and so the operator's act says what they
are consenting to. It is read once at agent start: a model that wanted to flip it would have
to rewrite the plist and reload the agent, which is a much louder act than the one this gate
exists to prevent — and that is the honest limit of the gate rather than a claim it is
tamper-proof.

**The two halves do different jobs, and collapsing them into one boolean hides a state.** The
plan review caught this. The **variable** decides whether the name may appear at all: it is
the operator's consent, and once given, a reader who set it and sees no lane has to be told
why. The **binary** decides whether the lane is usable. Three states, and each behaves
differently:

| `PROCTOR_SECOND_LANE` | on disk | behaviour |
|---|---|---|
| unset | either | `off` — the name appears nowhere, on any surface, in any field |
| set | present | `enabled` — the routing table below applies |
| set | absent | `unavailable` — the routing table does not apply, and a handoff that would have named the lane carries a `ToolAbsence` for it instead, so an operator who enabled a lane that is not there finds out from the thing that would have used it |

The `unavailable` absence names the project page and carries **no install commands**, which
`ToolAbsence` cannot hold by construction. Proctor still asks nobody to install browser-use;
it answers a question the operator already asked by setting the variable.

**What it costs, recorded.** On the reader's own machine this feature is inert until they set
the variable, which means the lane they asked for arrives switched off. That is deliberate and
it is the brief's own third option: a lane this heavy should start from a person's decision,
and the routing below is what makes that decision worth making. The limits Obscura cannot
clear are disclosed exactly as they are today, gate or no gate.

### What Proctor can actually know about the job — and two of the brief's three inputs do not carry

The brief names three inputs. Answering it honestly means saying which ones survive contact.

**The URL's scheme — carries, and is the only routing signal in this spec.** It is fully
determined: no inference, no probability, and not authored by the caller. A `chrome://`,
`chrome-extension://` or `devtools://` page does not exist in Obscura's engine at all, which
is why PRO-0020 drops the recommendation for it. It does exist in a real Chromium. This rule
converts PRO-0020's "no recommendation, here is why" into a real answer.

But **"not `http(s)`" is the wrong cut**, and the review caught it. `file:` and `data:` are
also not `http(s)`, and they are not browser-internal pages — pointing an autonomous agent
holding a live profile at a local file is a worse answer than no answer, and the useful advice
for a local file names no browser at all. So the rule fires on an **explicit list of
browser-internal schemes** and nothing else (below).

**The kind of step being asked for — does not carry. This is a finding, and it reverses this
spec's first draft.** The draft routed a `hover` step to the second lane, on the grounds that
a hover state is transition-gated and Obscura never executes transitions. The review took the
premise apart: `:hover` is a pseudo-class and a style recalculation, not a transition, and
`getAnimations() == 0` is a measurement about animations. A hover that swaps a colour works.
Worse, **the caller authors the step list**, so routing on a step kind lets a model win the
heavier lane for a whole page by adding one step — which is the same class of signal this
spec rejects `dragPath` and `scroll` for. Routing on a step kind is out entirely.

**The page's accessibility shape — does not carry either.** The obvious candidate was a web
area with no accessible children: a page whose content is not in the accessibility tree. It
discriminates nothing, because Obscura reads the **DOM**, not the AX tree, and a page
invisible to accessibility can have a complete DOM. "Proctor cannot drive this page" is
already why the handoff exists; it says nothing about which lane should. PRO-0020's
several-web-areas case fails the same way, since both lanes need a URL.

**And the fact Proctor holds that is not on the brief's list is deliberately not used.**
browser-use can attach to a running Chrome and keep its session, which is exactly the
discontinuity PRO-0020 discloses and cannot fix. Proctor cannot see whether the flow in hand
depends on being signed in, and the first draft handed that question to the caller as a note
beside a handoff that had already named Obscura. The review named that correctly as the
"try one, then the other" the brief forbids, dressed as honesty — a payload that picks a
winner and then tells the model the winner may be wrong has three readings, two of which
make the stated default a fiction. **The note is gone.** PRO-0020's `continuity` sentence
already states the cost of the Obscura lane; a caller who knows their flow is signed in, and
whose operator has enabled the lane, can ask for it.

### The routing table

Evaluated in order, conditions complete and non-overlapping. `why` is a full sentence naming
the rule that fired — never a token. "**lane on**" means the state table above says `enabled`.
**Every transition to the second lane also requires a Chromium-family browser**, for the
reason under rule 4.

| # | Condition | Lane | `why` says |
|---|---|---|---|
| 0 | no URL was read (no window named, `AXURL` absent, or **any** rendered area silent) | fall to 4-5 | — |
| 1 | **every** rendered area reported a URL and every one is a browser-internal scheme, the page is not on the deny list, browser is Chromium-family, lane on | `browser-use` | this page has no equivalent in Obscura's engine; a real Chromium is where it exists |
| 1a | the same, but the page **is** on the deny list | **none** | this is the browser's own credential, extension or history surface, and no lane is pointed at it |
| 2 | every distinct URL is browser-internal, otherwise | **none** | PRO-0020's `notOpenable`, unchanged |
| 3 | a URL is present and is neither `http(s)` nor browser-internal | **none** | `file:` and `data:` get a reason naming neither tool — read the file, decode the payload; anything else keeps PRO-0020's `notOpenable` |
| 4 | `http(s)` or no URL, Obscura **present** | `obscura` | the default: no measured Obscura limit applies to this page |
| 5 | `http(s)` or no URL, Obscura absent | **none** | PRO-0023's `toolUnavailable`, unchanged |

Rule 1 additionally carries a `ToolAbsence` for browser-use, and no lane, when the state is
`unavailable`.

**The second lane is never a fallback for an ordinary page, and that reverses a rule this spec
had.** An earlier draft routed any `http(s)` page to it whenever Obscura was missing. The
completeness critic took it apart: that makes a credentialed autonomous agent the *default* for
every web page on a machine without Obscura — the opposite of the brief's "keep Obscura as the
default" — and it does it on exactly the pages most likely to be hostile, because that agent's
loop ingests the page it is reading, so a page can instruct it. Obscura being uninstalled is a
fact about the machine rather than a capability fact about the page, and it is not a reason to
change instrument. PRO-0023's answer — say Obscura is missing — is the honest one and is
already built.

**The deny list**, which is rule 1a and the critic's sharpest single finding. `chrome://`
covers the browser's own configuration, credential store, extension list and history:
`settings`, `password-manager`, `passwords`, `extensions`, `flags`, `history`,
`net-internals`, `wallet`, `signin`, `sync-internals`, `policy`, `management`, `credits`,
`profile-internals`, matched on the host so `chrome://settings/passwords` is covered by
`settings`; and `devtools:` wholesale, because driving DevTools drives the page it is
inspecting. Handing an agent that acts as this person the page where their saved passwords
live, on the grounds that Obscura cannot open it, is a worse answer than the honest one. The
check runs **inside** the enabled branch, so with the lane off this whole path is byte-for-byte
what PRO-0020 emitted: the list exists to stop a lane firing, not to reword a refusal that was
already happening.

**Rule 0's silent-area guard**, the critic's other structural find. `AXURL` comes back nil on
real trees more often than a clean model suggests, and the URL set is built by dropping the
silent areas. One extension frame beside a signed-in tab whose URL never arrived would then
read as "every URL here is internal" and route a bank to the second lane. So the internal-page
rule requires that **every** rendered area spoke; a window Proctor has only partly read is one
it will not route on what it did read.

**Rule 1 needs *every* URL, not one.** It is PRO-0020's existing `notOpenable` branch with two
conditions added, so no new URL selection is invented: a window holding a `chrome://` page and
an `https` iframe already resolves to the `https` one and goes to Obscura, which is right.
Mixed schemes were the review's worry and the existing code already answers them.

**Why the second lane is Chromium-only.** Its advertised value is that it drives a real
Chromium — the engine in which that page exists. The claim does not survive a Safari, Firefox,
Orion, DuckDuckGo or Zen window: browser-use would drive a *different* browser with a
different session, which is PRO-0020's "success against a window it never touched" one level
out.

The **browser-internal schemes** are `chrome:`, `chrome-extension:`, `chrome-untrusted:`,
`chrome-search:`, `chrome-native:`, `chrome-error:`, `isolated-app:`, `devtools:`, `edge:`,
`brave:`, `vivaldi:`, `opera:` and `arc:`. A list rather than a "not http(s)" negation, for the
same reason `BrowserCatalogue` is a list: a negation sweeps in everything nobody thought about,
and here the things nobody thought about are the ones that would point an agent holding a live
profile somewhere it should not go. **`about:` is deliberately not on it** — `about:blank` is
the empty tab every browser opens, and starting an autonomous agent for one is absurd; it keeps
PRO-0020's behaviour exactly. Adding a scheme is a line in a table; a missing one costs a
no-recommendation, which fails visibly.

Rule 1 promises the page is **reachable** in that lane, not that it is drivable — several
Chrome internal pages are shadow-DOM WebUI and hostile to automation, and an extension page
needs that extension loaded in that profile. Both are said in `why` rather than discovered.

Rule 3 is new advice rather than a lane, and it is better advice than the recommendation
PRO-0020 would otherwise withhold in silence.

**`use` stays singular**, and its value is the binary's own name — `obscura` or `browser-use`,
never a Swift spelling. PRO-0023 left `toolUnavailable` singular because a handoff names one
lane at a time; the same holds for the recommendation. Naming both lanes with their trade-offs
hands the decision back to the caller, which is the thing the brief objects to.

### The second lane discloses what it is, at both detail levels

The review's sharpest structural point: rules 1 and 4 justify the lane with an *engine* fact
("this page does not exist in Obscura"), while what the caller actually gets is an autonomous
agent with a far larger blast radius than the step that won the route. A `why` about a scheme
cannot carry that.

So for the browser-use lane, `boundary` and `continuity` — both of which are on the **brief**
form, by PRO-0020's rule that what must not wait does not wait — say what the lane is:

- it is an **autonomous agent** rather than a command that does one thing, so what it does
  between the ask and the answer is not enumerated in advance;
- in its default local mode it drives a **real browser with real credentials**, so an action
  it takes is an action taken as that person, on every origin they are signed in to;
- **nothing it does reaches Proctor's audit trail.** PRO-0005's trail records what Proctor
  did; a lane Proctor recommends and does not execute leaves no record, and a reader who
  assumed the trail was complete would be wrong.

`caveats`, at full detail, adds the operational edges: attaching to a running browser needs
the remote-debugging prompt approved; the browser it attaches to is **its own choice of
Chrome and not necessarily the window Proctor is attached to**, so a Brave window driven here
may hand work to a different browser with a different jar; it needs a model credential and the
run costs whatever that model costs.

### What goes on the wire for the second lane: a name, a reason, and a mode — never a command

**The browser-use lane carries no `commands`, at any detail level.** PRO-0020 ships templates
for Obscura and this spec does not re-open that. It states the criterion that separates them,
so the difference is a rule rather than an exception:

> A command template belongs in a tool result only when running it does exactly one bounded,
> read-shaped thing.

`obscura fetch <url> --dump markdown` meets it: one page, one read, no credential, no
autonomy, and the tool is already installed. `browser-use` fails it three ways — its
documented ephemeral invocation installs from PyPI as it runs, it needs a model credential,
and it starts an agent on a live profile.

The review's counter is fair and is answered rather than dismissed: withholding the template
leaves the model to invent one from its weights, and what it will invent is `uvx browser-use`
in default local mode — the three properties the criterion refused. So the lane carries **mode
guidance in prose**, which is not a pasteable command: run it from an installed entry point
rather than an installer that runs it, and give it an isolated browser profile unless
continuing this person's session is the actual point of the job. That is a constraint on the
invocation without composing one, and `docs` points at the project for the rest.

### The two questions PRO-0023 left

**Version: no probe, and the need for one is removed rather than deferred.** PRO-0023 refused
to execute a binary found in a user-writable directory from a process holding Accessibility.
That argument is not weaker here — a `browser-use` on `PATH` is a Python console-script shim
in exactly such a directory, and running it may bootstrap an environment, which is not a cheap
read. It costs nothing because **no rule above depends on a version**: "drives a real
Chromium" is true of every release with a CLI. If a future rule needs one, PRO-0023's
disposition stands — behind an explicit operator opt-in, never on by default.

**Two booleans versus an array: the array is the right shape, and the booleans are
grandfathered rather than broken.** `proctor_doctor` gains `tools: [ToolPresence]`, carrying
every *located* tool — obscura then browser-use — and that is where a fourth would go.
`obscuraAvailable` and `obscura` stay, documented as the compatibility spelling of the obscura
entry, with an assertion that they agree. **No third boolean is added.**
`shortcutsCLIAvailable` stays out of the array on merit rather than for compatibility:
`/usr/bin/shortcuts` is an OS component at a fixed absolute path, with no search list, no
candidates and no companions, so a `ToolPresence` for it would be a shape with three empty
fields. The duplication is a stated cost with a named exit: the booleans go when something
else justifies a protocol change, not before.

### Where browser-use is reported, and where it is not

**`proctor_doctor` reports presence and lane state as facts. Nothing volunteers the name when
the lane is off, and nothing anywhere offers to install it.** Doctor answers a question that
was asked; a handoff volunteers advice. PRO-0023's `searched` precedent says a diagnosable
absence is worth the field, since "installed but Proctor cannot see it" is the failure a
launchd agent actually produces — and here it is also how an operator who set the variable and
sees no lane finds out why.

`secondLane` on the report carries three states — `off` (not enabled), `enabled` (enabled and
found), `unavailable` (enabled and not found) — so the two halves of the gate are
distinguishable rather than collapsed into one boolean.

There is therefore **no `ToolAbsence` for browser-use**, no install commands anywhere, and no
status-window callout. The status window gains one row **whenever browser-use is present**,
saying whether the lane is on, so an operator can see that a tool their own rule removed has
become an active lane. That asymmetry against Obscura's "not installed / here is how" callout
is the gate decision made visible: Proctor asks for Obscura and merely notices browser-use.

The install commands remain, as PRO-0023 built them, **in the status window only** — computed
in `MainWindow` from `ObscuraTool.installCommands` and never on `DoctorReport`. That is what
keeps the callout coherent with the no-commands-in-a-tool-result rule, and it is asserted.

## Scope

**In.** A `chromiumFamily` flag on `KnownBrowser`; a browser-internal scheme list; a
`BrowserUseTool` catalogue entry (binary, docs, lane text, no install commands, no absence);
a second `ToolLocator.locate` call behind a `ToolProbes` container on `Session`; the
`PROCTOR_SECOND_LANE` read; the lane decision and `why` in `BrowserTarget`; `note` → `notes`;
two notes; `tools: [ToolPresence]` and `secondLane` on `DoctorReport`; a present-only row in
the status window; the `proctor_doctor` output schema; README and CHANGELOG.

**Out.** Proxying steps through either tool (PRO-0020's reasoning, unchanged: both drive their
own engine, so a routed step would report success against a window it never touched). Any new
tool verb. Any new actuation plane. A version probe. Install commands, an absence object or a
callout for browser-use. A UI control that writes the preference. Routing on a step kind or on
the accessibility shape. Any change to settling, hashing, planes or the audit trail. Removing
`obscuraAvailable`.

## Behaviour

### Detection

`ToolLocator.locate(binary: "browser-use", companions: [], …)` over the same candidate
directories PRO-0023 built, which already cover where a Python console script lands
(`~/.local/bin` for pipx and `uv tool`, `/opt/homebrew/bin`, `/usr/local/bin`). No companions:
browser-use is one console script, and what it needs — a Chromium, a model credential — is not
a sibling file and is not checkable by stat.

A **project-local virtualenv is invisible** to this, exactly as PRO-0023's launchd sentence
describes. That is a false absence, diagnosable from `searched`, and its consequence here is
that Proctor stays quiet — the safe direction for a gated recommendation.

**Two probes, one container, one predicate.** `Session` holds `ToolProbes` with an `obscura`
and a `browserUse` probe rather than two ad-hoc fields: the same argument that sends the doctor
report to an array, one layer down. **The environment read, the two presences and the three
lane states are combined in exactly one pure function**, `BrowserLanes.make(obscura:
browserUse: environment:)`, which the handoff path, `proctor_doctor` and the status row all
read from. The plan review's sharpest structural finding was that three readers each
interpreting an environment variable and two stat results is three partial copies of one
predicate, and they will disagree — a doctor report saying `enabled` beside a handoff that
names Obscura. There is one copy.

**The `lanes` argument has no default.** A default of "Obscura present, second lane off" would
make every call site that forgot to pass one claim Obscura is installed — reintroducing the
exact bug PRO-0023's `withTool` existed to fix, with the compiler silent. Every call site
passes it, and PRO-0020's existing suite is updated rather than shielded.

**The clock and the environment are injected**, both, at `ToolProbes`. `setenv` after launch
does not reach a process's cached environment and the first test to read a real one wins the
process, so a suite that reads `ProcessInfo` directly is a suite that leaks.

**The TTLs differ, and the difference falls out of the gate.** PRO-0023 made an absent Obscura
expire in 15 seconds because Proctor is what provokes somebody to install it. Proctor never
asks anyone to install browser-use, so there is nothing to poll for: **browser-use is cached
for 300 seconds either way.** Somebody who installs it mid-session gets the lane at the next
`proctor_doctor`, which re-probes and writes through, exactly as PRO-0023 defined.

### The handoff

One new field, `why: String`, at both detail levels, on every handoff that names a lane. It is
what makes the choice checkable, and it names the rule that fired — including rule 5, the
default, because "no measured limit applies here" is a claim Proctor is making and should
stand behind.

`boundary` and `continuity` become functions of the lane rather than constants. `boundary`
still leads at both levels and is still the same sentence within one handoff.

`note: String?` becomes `notes: [String]?`, because a page can be several of these at once.
The rename is safe: `note` arrived in PRO-0020, which merged after the only release
(`v0.1.0`, 2026-08-13), so it has never reached a reader. **Every note is gated on the Obscura
lane**, because every one of them is a fact about Obscura; the plan review found the first
draft warning a browser-use handoff about an SSRF block that lane does not have. Two entries,
in a fixed order:

- **Private network** — PRO-0020's, unchanged, now `lane == obscura` only.
- **A `.pdf` URL over `http(s)`** — PDF structure is a documented divergence and neither lane
  reads it; the useful advice names no tool: fetch the file and parse it, because rendering it
  in a browser measures the viewer rather than the document. Matched on `URL.path`, lowercased,
  so a query string or a fragment does not hide it.

**The viewport note was designed and then cut.** It would have said that this window's page is
a different size from `obscura fetch`'s fixed 1280x720. The review pointed out that on any real
Mac window the delta is large, so the note would fire on nearly every Obscura handoff and
become noise — the same "correct-sounding way of never answering" this repo already rejects,
inverted. The generic caveat already states the fixed viewport.

### `proctor_doctor`

`tools: [ToolPresence]` — obscura then browser-use, always both, present or absent — plus
`secondLane` with its three states. `obscuraAvailable`, `obscura` and `obscuraUnavailable` are
unchanged and must agree with the obscura entry. `ready` and `blockers` are untouched by
either tool, for PRO-0023's reason: `ready` means Proctor can do its own job, and Proctor
drives native applications without any browser tool.

### The status window

One row in the *Background agent* card, below Obscura's, **rendered whenever the lane is not
`off`** — that is, whenever browser-use is present or the variable is set: `browser-use —
second lane on`, `— found, lane off`, or `— lane set, not installed`, with one line saying what
the lane does and that it is set by `PROCTOR_SECOND_LANE`. No callout, no buttons, no install
text. `off` with nothing on disk means no row, so a machine that removed the tool and never
enabled the lane sees nothing.

## Acceptance clauses

1. `BrowserCatalogue` reports `chromiumFamily` correctly: Chrome, Chromium, Edge, Brave, Arc,
   Vivaldi and Opera are Chromium-family; Safari, Safari Technology Preview, Orion, DuckDuckGo,
   Firefox, Firefox Developer Edition, Firefox Nightly and Zen are not. Channel variants
   inherit their prefix rule's answer.
2. **The gate, and it is total.** With `PROCTOR_SECOND_LANE` unset, the string `browser-use`
   appears in **no tool result at all** — not in a handoff at any detail level, not in a
   snapshot, not in `proctor_doctor`'s `tools`, and not as a status-window row — across every
   combination of scheme, browser, Obscura state and browser-use presence. Unset behaves
   exactly as absent.
3. **The three states.** `BrowserLanes.make` returns `off` when the variable is unset whatever
   is on disk, `enabled` when it is set and the tool is present, `unavailable` when it is set
   and the tool is absent — and it is the only place any of the three is computed.
4. Rule 1: a `chrome://settings` page in Chrome with the lane enabled returns
   `use: "browser-use"` and a `why` naming the scheme; the same page in **Firefox** falls to
   rule 2 and returns PRO-0020's no-recommendation handoff; a window holding both a `chrome://`
   page and an `https` page still resolves to the `https` one and the Obscura lane.
5. Rule 2 with the lane off is byte-identical to PRO-0020's `notOpenable` handoff; so is
   `about:blank`, which is not a browser-internal scheme here.
6. Rule 3: `file:///Users/x/page.html` and `data:text/html,…` return no recommendation and a
   reason naming neither tool, in Chrome, with the lane enabled.
7. **The second lane is never a fallback.** Obscura absent, lane enabled, any browser, an
   `https` page or no page at all → no lane and `toolUnavailable` for Obscura. `proctor_apps`
   attach, which has no URL by construction, can never reach the second lane.
8. Rule 4: both present, nothing matching → PRO-0020's Obscura handoff plus `why`, `use` is
   `"obscura"`.
9. Rule 5, and the whole ladder's completeness: for all combinations of (Obscura present /
   absent) x (lane off / enabled / unavailable) x (Chromium / not) against an `https` page and
   against a no-URL app-level handoff, the handoff either names Obscura when Obscura is there
   or names nothing — an ordinary page never reaches the second lane.
9a. **The deny list**: `chrome://settings`, `chrome://settings/passwords`,
   `chrome://password-manager/...`, `chrome://extensions`, `chrome://flags`,
   `chrome://history`, `chrome://net-internals/#dns`, `brave://wallet`,
   `edge://settings/profiles` and any `devtools:` URL return no lane with the deny reason, in
   Chrome, with the lane enabled — while `chrome://settings-guide` and
   `https://example.com/settings` are untouched.
9b. **A partly read window is not routed**: one `chrome-extension://` area beside an area whose
   `AXURL` was nil returns no lane and says the window was only partly read.
10. `unavailable`: the lane is set and the tool is absent, on a Chromium `chrome://` page →
    no lane, and a `ToolAbsence` for browser-use naming the project page, with **no** install
    command text in any of its fields.
11. The browser-use lane's `boundary` and `continuity` state the autonomy, the real-credential
    default mode and that nothing it does reaches the audit trail — **at the brief detail level
    as well as the full one**; its `caveats` at full detail add the remote-debugging prompt, the
    it-may-drive-a-different-browser edge, and the model credential and its cost.
12. The browser-use lane carries **no `commands` key** at either detail level — absent, not
    empty — and no field of any handoff on that lane contains `uvx`, `pip `, `pipx` or `curl`,
    or any Obscura flag such as `--allow-private-network`.
13. `boundary` and `continuity` differ between the two lanes and are identical across the two
    detail levels of one handoff; `why` is a sentence, present at both levels whenever a lane is
    named, and `use` is the binary name (`browser-use`, never `browserUse`).
14. `notes` fire only on the Obscura lane, carry several entries at once in a stable order, and
    appear at both detail levels: `http://192.168.1.4:3000/report.pdf?t=1` carries the
    private-network and PDF notes; the same URL on the browser-use lane carries neither.
15. `proctor_doctor` reports `tools` containing obscura, and browser-use **only when the
    operator named the lane**; the obscura
    entry equals the `obscura` field and its `available` equals `obscuraAvailable`; `secondLane`
    is the same three-state value `BrowserLanes.make` computed; `ready` and `blockers` are
    identical across every combination.
16. The two probes are independent and cached independently: browser-use's absent answer
    survives past `ToolProbe.absentTTL` and expires at 300s under an injected clock, while
    Obscura's does not; a `proctor_doctor` call re-probes **both** and writes through, so a
    handoff taken immediately after reflects both answers.
17. `proctor_apps` attach on a Chromium browser with the lane enabled carries `why` and the
    lane through the encoded JSON, end to end, from an injected environment rather than the
    process's own.
18. `DoctorReport` — the whole encoded tool result — contains no install command text for
    either tool: no `curl`, no `tar`, no `mv`. The Obscura install commands exist only where
    `MainWindow` computes them.
19. The advertised tool surface gains no verb, and the `proctor_doctor` output schema documents
    `tools` and `secondLane`.

## Assumptions recorded in place of questions

- `[Decision]` **The gate is detection AND `PROCTOR_SECOND_LANE`, default off.** Argued above,
  after the out-of-family review rejected detection alone. If the reader wants presence to be
  enough, one predicate is deleted and nothing else changes.
- `[Decision]` **The second lane carries no command text**, under the stated criterion, and
  carries mode guidance in prose instead. This extends PRO-0023's rule rather than excepting it.
- `[Behaviour]` **Routing is on the URL's scheme only.** The step kind and the accessibility
  shape were examined and rejected with reasons, which answers two of the brief's three inputs
  rather than leaving them out.
- `[Behaviour]` **The binary is `browser-use`**, the official package's console script,
  verified absent from this machine — consistent with the standing instruction. A third-party
  fork with a `browser-use run …` surface exists; Proctor names the tool and never composes a
  command, so the fork changes nothing on the wire.
- `[Behaviour]` **No version probe**, because no rule needs one.
- `[Behaviour]` **Detection is presence of a name at a path**, inheriting PRO-0023's limitation
  in full: a planted file reads as present, a project-local venv reads as absent, and Proctor
  never executes either.
- `[Behaviour]` **The opt-in is not tamper-proof.** A model with a shell could rewrite the
  launchd plist and reload the agent. That is louder than `uvx browser-use` by orders of
  magnitude, which is the whole of the claim; it is stated rather than defended as a boundary.
- `[Behaviour]` **`ready` stays true** whatever either tool's state.
- `[Scope]` **`tools` is the growth surface; `obscuraAvailable` is grandfathered.** No third
  boolean, and the duplication is deliberate.
- `[Scope]` **No UI control writes the preference.** The status window reports it; setting it
  is a plist edit, as `PROCTOR_HUD` already is.
- `[Cost]` **browser-use caches at 300s both ways**; PRO-0023's asymmetry exists to catch an
  install Proctor asked for, and Proctor asks for nothing here.

## Child work found, not built here

- **Proctor could record that it recommended a lane**, and does not. Nothing either tool does
  reaches the audit trail — this spec discloses that on the wire — but the recommendation
  itself is Proctor's own act and is auditable. It touches `PolicyStore` and the audit schema,
  so it is a separate item.
- **`proctor_stability` still does not know a page is page content** (PRO-0020's child, now
  larger): a score replayed through a lane Proctor does not execute measures nothing it claims
  to.
- **A status-window control for `PROCTOR_SECOND_LANE`**, which needs a preference store and a
  way to write the agent's launchd environment. Deliberately not built with the lane.
- **`scripts/doctor.sh` knows about neither tool.** PRO-0023 logged this for Obscura; a second
  tool does not change the shape of the item.
- **`why` names the rule, not the risk, and nothing on the object is machine-readable.** A
  host that wanted to gate on "this lane is unaudited" or "this lane needs a live profile" has
  to read prose. A small flag set would be a real improvement and is a separate change.
- **A PWA or "open as app" window** (`com.google.Chrome.app.*`) inherits Chrome's catalogue row
  through the prefix rule, so it is treated as Chrome. Inherited from PRO-0020 rather than
  introduced here, and worth its own look.
- **`chromiumFamily` is a second fact per browser that can drift**, since a browser can change
  engine (Opera and Edge both have). It is a line in a table, and a wrong answer costs one lane
  recommendation for an internal page, which fails visibly.

## Out-of-family review

Spec reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15, no
downgrade. Nine defects; **four changed the design** and are folded in above:

1. **Presence is not consent for this tool.** The strongest finding and the one that reversed
   the central decision: installing a CLI is consent to have a file, not consent for an
   Accessibility-holding agent to name it to a model with a shell — and a "removed" rule makes
   a leftover binary the normal state. The gate became detection **and** an explicit opt-in.
2. **The session note was try-then-the-other in disguise.** A payload that names Obscura and
   then says the other lane keeps the session has three readings, two of which make the stated
   default a fiction. Deleted.
3. **`hover` was the same inference the spec rejected elsewhere**, with a story attached:
   `:hover` is a pseudo-class, not a transition, and the caller authors the step list, so a
   model could win the heavier lane by adding one step. Routing on step kind is out entirely.
4. **"Not `http(s)`" pointed the dangerous lane at the dangerous URLs.** `file:` and `data:`
   are not browser-internal pages. Replaced with an explicit scheme list, and `file:`/`data:`
   got their own no-recommendation.

Two more were adopted as strengthening rather than redesign: the engine-fact `why` cannot
carry what the lane actually is, so the lane's nature moved onto the brief form; and
withholding a command template leaves the model to invent the worst invocation, so the lane
carries mode guidance in prose.

Three were answered rather than adopted, with the answer written in:

- *Disclosing the limit hands the model the gap, and its weights supply the tool name.* The
  limits are PRO-0020's `caveats` and already ship today; un-disclosing them is a regression,
  and gating the name does not change what a model could infer.
- *The catch-all rule recommends Obscura when it is absent.* The conditions were already
  disjoint, but the table read as ambiguous; it is now complete and non-overlapping, and
  clause 8 asserts all four availability combinations.
- *The Obscura install callout is only coherent if the status window is human-only.* It is —
  the commands are computed in `MainWindow` and are not on `DoctorReport` — and clause 18 pins
  it.

## Plan review, out of family

Plan reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15, no downgrade.
Fourteen defects; **nine changed the design before any code was written**, which is more than
the spec review changed:

1. **Rule 4 was a cross-browser hijack** — it did not test `chromiumFamily`, so a Safari window
   with Obscura missing would have recommended an agent driving somebody's Chrome. Every
   transition to the second lane now requires a Chromium-family browser.
2. **A two-state `BrowserLanes` could not express a three-state gate**, so "you enabled a lane
   that is not installed" had nowhere to go. Three states, and the `unavailable` one is now
   visible in the handoff and in the window.
3. **Three readers of one predicate.** The environment read and the two presences are combined
   in one pure function that the handoff, the doctor and the window all use.
4. **The ladder had no step for a missing URL** and hid it in prose. Rule 0 is explicit.
5. **`lanes` had a default argument**, which would have made a forgotten call site claim
   Obscura is installed — PRO-0023's bug, re-introduced with the compiler silent. Removed.
6. **`about:` was on the internal-scheme list**, so an empty tab would have started an
   autonomous agent. Removed; `chrome-search:`, `chrome-native:`, `chrome-error:` and
   `isolated-app:` added, which are the internal pages people actually land on.
7. **The private-network note was not lane-gated**, so a browser-use handoff would have warned
   about an SSRF block that lane does not have. Every note is now Obscura-only.
8. **The viewport note would have fired on nearly every handoff**, since no real Mac window is
   1280x720. Cut rather than tuned.
9. **`why` was a token for rule 1 and a sentence elsewhere**, and the PDF match was on the whole
   URL rather than its path. Both fixed, and `use` is pinned to the binary's own spelling.

Answered rather than adopted: that rule 4 makes browser-use read as an Obscura substitute — it
now carries Obscura's absence alongside the recommendation, which says the true thing instead;
and that a `python -m browser_use` install or a project-local virtualenv is unreachable, which
is PRO-0023's stated false-absence limitation inherited in full.

## Completeness critic, out of family

Reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15, no downgrade,
against the built change. **Four findings changed the feature after it was working:**

1. **Rule 1 was handing an agent the browser's password manager.** `chrome://password-manager`,
   `chrome://settings`, `chrome://extensions`, `chrome://flags`, `chrome://history` and
   `brave://wallet` are all-internal, Chromium-family, and have no `http(s)` sibling, so they
   matched perfectly. The deny list exists because of this, and `devtools:` went with it.
2. **The second lane as a fallback was the largest surface in the feature and the least
   justified.** Deleted; the reasoning is in the routing section.
3. **A window with a nil `AXURL` on one area would have read as all-internal**, because the
   URL set is built by dropping the silent ones. Rule 1 now requires that every rendered area
   spoke.
4. **The gate was an invariant about handoffs, not about tool results.** `proctor_doctor`
   listed browser-use unconditionally and the status window showed a row on presence alone, so
   a machine that never enabled the lane still saw the name. Both now follow the variable, and
   clause 2 asserts the whole result rather than the handoff.

Also adopted: attaching to a running browser is a **latch** rather than a one-off — the
remote-debugging port stays open to every local process until that browser quits — which is now
a caveat.

Answered rather than adopted:

- *The notes are Obscura-only, so a private-network page on the second lane loses its warning.*
  True of the earlier draft; with the fallback gone the second lane only ever fires on a
  browser-internal page, which is neither private-network nor a PDF.
- *`ToolAbsence` is inconsistent between the two paths.* It follows PRO-0023's rule, which is
  that a page the missing tool would not have helped anyway gains no absence.
- *An empty-string `AXURL` behaves differently from nil.* It does not: `distinctURLs` already
  skips empty strings, so both fall through the same branch.
- *`note` → `notes` breaks an old decoder.* `note` shipped in PRO-0020, which merged after the
  only release, so no decoder has ever seen it.

Recorded as limitations rather than fixed: Chrome's built-in PDF viewer presents as a
`chrome-extension://` URL, so a PDF opened in Chrome reads as a browser-internal page and gets
the lane rather than the read-the-file advice — useless rather than dangerous, and the deny
list bounds it; `view-source:`, `blob:` and `filesystem:` fall to `notOpenable` without their
inner URL being unwrapped, which is fail-closed; a torn read is possible if a `proctor_doctor`
call lands between the two independent caches during a handoff, costing one call a stale lane;
and a leftover `PROCTOR_SECOND_LANE` in a launchd plist stays in force until the agent
restarts, which is what an operator preference is.

## What a test cannot reach here

Machine-witnessable from `swift test`: every clause above, against an injected predicate,
injected clock, injected environment and the existing fake AX engine.

**Not witnessable, and reported as code-complete rather than proven:** that the status window
renders the browser-use row; that `browser-use` is the console script's name on a machine that
has one; that browser-use can in fact open a `chrome://` page, or attach to a running Chrome
over CDP. The first needs a window server. **The rest would need browser-use installed here,
which the reader's standing instruction forbids** — the one experiment that would settle them
is the one this feature exists to avoid provoking. Stated rather than worked around: the claims
come from the project's own documentation, and `why` names reachability rather than promising a
page will drive.

## Progress — 2026-08-15

Built on `ai/pro-0024` in `.worktrees/PRO-0024`. **637 tests / 80 suites green** (610/78 at
`5fe12e9`), `swift build` clean, no new warnings; the three the build prints are pre-existing
in `ProctorUI` and are not in the code this change touches. The suite was run six times, three
before the critic's changes and three after, with the same count each time.

**What shipped.** `Sources/ProctorCore/BrowserUseTool.swift` (the catalogue entry, the lane
variable, the absence for the enabled-but-missing state, and the status row's text). In
`BrowserTarget.swift`: `chromiumFamily` on `KnownBrowser`, the browser-internal scheme list and
its deny list, `BrowserLane` / `SecondLaneState` / `BrowserLanes.make`, lane-dependent
`boundary` / `continuity` / `caveats` / `commands`, the `decide` ladder, `why`, `notes`.
`ToolLocator.commonToolDirectories`, so both tools share one search list rather than two that
drift. `ToolProbes` in the agent, holding two independently cached probes and the injected
environment. `tools` and `secondLane` on `DoctorReport`, filled from one `refreshBoth`. One
conditional row plus a caption in `MainWindow`. Schema, README, CHANGELOG.

`BrowserTarget.withTool` is **deleted**: the lane now decides the boundary text, the continuity
text, the caveats and the commands together, and a post-hoc patch cannot express that. Its
clauses are unchanged and its tests moved onto the `lanes` argument.

**Clause → test.** 1-14 and the status row → `Tests/ProctorCoreTests/BrowserLaneTests.swift`,
notably `theNameNeverAppearsUnlessTheOperatorNamedIt`, which walks 5 schemes x 3 browsers x 2
Obscura states x 2 presences x 2 detail levels and asserts the encoded JSON never contains the
string. 15-19 → `Tests/ProctorAgentTests/BrowserLaneWiringTests.swift`, notably
`theGateHoldsAtTheWire`, which extends that invariant from the handoff to the snapshot and the
health report, and `aDoctorCallWritesThroughBothCaches`. PRO-0023's
`BrowserHandoffToolAvailabilityTests` and `ObscuraPresenceWiringTests`, and PRO-0020's
`BrowserRoutingTests`, all now pass a `lanes` value and an empty environment, so none of them
depends on what happens to be installed or exported on the machine running the suite.

**Not machine-witnessable here.** The status window's browser-use row. That `browser-use` is
the console script's name on a machine that has one. That browser-use can open a `chrome://`
page or attach to a running Chrome. The first needs a window server; **the rest would need
browser-use installed on this machine, which the reader's standing instruction forbids**, so
the one experiment that would settle them is the one this feature exists to avoid provoking.
Code-complete and unverified, not proven. The claims come from the project's own documentation,
and `why` names reachability rather than promising a page will drive.

**Reviews.** Spec review, plan review and completeness critic all ran out of family on
`grok-4.6` (`--effort xhigh --sandbox read-only`), no downgrade. All three changed the feature,
and the second and third changed it most:

- the **spec review** reversed the gate from detection alone to detection plus an opt-in,
  deleted the session note, deleted the `hover` routing rule and replaced "not http(s)" with an
  explicit scheme list;
- the **plan review** found nine defects before a line was written, including a rule 4 that did
  not check the browser family and a `lanes` default argument that would have re-introduced
  PRO-0023's bug with the compiler silent;
- the **completeness critic** found that the feature as built would hand an autonomous agent
  `chrome://password-manager`, and that the second lane as a fallback was the largest and least
  justified surface in it. Both are gone.

**A note on how much the reviews moved this.** Between the first draft and what shipped, the
gate changed, two of the four routing rules were deleted, one was narrowed twice and a deny
list was added. That is the point of running them; it is also worth saying plainly that the
first draft of this spec would have been a bad thing to ship.
