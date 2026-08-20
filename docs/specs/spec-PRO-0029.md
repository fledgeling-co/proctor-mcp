# PRO-0029: A home for the PROCTOR_* switches

**ID:** PRO-0029
**Status:** Merged `153951b`
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/30-a-home-for-the-proctor-switches.md`
**Direction:** `docs/features-to-triage/00-WAVE-7-DIRECTION.md` (wave 7 architecture; nothing here contradicts it — this item gives the supervision surface's own switches a home, and the direction file keeps that surface)
**Builds on:** PRO-0036 `c9e42c9` — the card pattern and `StatusChecks.swift`, the testable-rules-in-Core precedent this extends; PRO-0050 `0ea6f88` — `DoctorReport.lanes`, per-lane availability; PRO-0051 `0f76c56` — lanes are deliberately selected, never automatic; PRO-0044 `d65dc1e` — `PROCTOR_ACTUATION`; PRO-0024 — the second lane's opt-in reasoning; PRO-0028 — the precedent for deleting a control that cannot do what its label says
**Consumes:** `DoctorReport`, `OverlaySwitch`, `Takeover`, `ContentionMonitor`, `BrowserUseTool.laneVariable`, `CuaDriverTool.laneEnv`, `Actions.restartAgent()`

## Feature description

> **REVISED for wave 7, 2026-08-15.** Still wanted, and the switch list changes. The UI switches (`PROCTOR_CURSOR`, `PROCTOR_HUD`, `PROCTOR_YIELD`, `PROCTOR_YIELD_INPUT`, `PROCTOR_TAKEOVER_INPUT`) survive because the supervision surface survives. `PROCTOR_SECOND_LANE` may not, since brief 45 hands browser work to Cua. Read `00-WAVE-7-DIRECTION.md` and enumerate the switches that actually exist when this is built rather than trusting the list below.
>
> # A home for the PROCTOR_* switches
>
> ## The problem
>
> Proctor's behaviour is configured by environment variables read at agent start:
> `PROCTOR_CURSOR`, `PROCTOR_HUD`, `PROCTOR_YIELD`, `PROCTOR_YIELD_INPUT`,
> `PROCTOR_TAKEOVER_INPUT`, `PROCTOR_SECOND_LANE`. That is six switches with no
> home. PRO-0026's review made the case plainly and it is true of all six rather
> than of the one it was raised against: an environment variable leaks to every
> child process the agent spawns, and it vanishes from a launchd plist the moment
> somebody reinstalls, so a person who turned something on has no way to see that
> it is on and no way to turn it off again except by editing a plist by hand.
>
> PRO-0024 logged the same gap from the other end: a status-window control for
> `PROCTOR_SECOND_LANE` was deliberately not built with the lane, because it needs
> a preference store and a way to write the agent's launchd environment.
>
> ## What it should do
>
> Give the switches one place to live that a person can see and change, and make
> the agent read that place rather than only its inherited environment.
>
> The status window is the surface: it already walks somebody through two
> permission grants and now offers agent recovery, so it is where a person goes
> when they want to know what Proctor is doing and change it.
>
> ## The hard parts, named
>
> - **Two sources of truth, and a precedence rule.** An environment variable set
>   by whoever launched the agent and a stored preference are both real inputs.
>   Say which wins and why, and make the surface show the effective value together
>   with where it came from, because a toggle that silently loses to an env var is
>   worse than no toggle.
> - **Changing a preference must reach a running agent.** The agent is long-lived
>   and launchd-started. Writing a plist changes what the *next* launch sees. A
>   switch that appears to take effect and does not until a relaunch is the same
>   class of defect PRO-0028 deleted a button for. Either apply live, or say
>   plainly that it applies on relaunch and offer the relaunch.
> - **`PROCTOR_SECOND_LANE` is a security control, not a preference.** PRO-0024
>   made it opt-in deliberately, on the reasoning that installing a CLI is not
>   consent to have it named to a model with a shell. A UI toggle is the right
>   place for that consent, and it is also a place somebody could flip without
>   reading what it means. Whatever the surface says next to it has to carry that.
> - **Writing a launchd environment from a GUI app** touches the agent's own
>   installation. Say what it writes, where, and what happens on the next
>   `install.sh`, which rewrites the plist.
>
> ## Not in scope
>
> New switches. This gives the existing six a home; it does not add a seventh.

---

## The enumeration, which the brief asks for first

The brief's list of six is out of date, and the header says so. Measured against
the tree at `c9e42c9` by grepping every `PROCTOR_*` literal in `Sources/` and
reading each call site. **32 distinct `PROCTOR_*` names exist. Eight are runtime
agent behaviour switches, and those eight are this item's scope.**

Two of the eight are not in the brief's list. One of the brief's six has changed
shape. Nothing in the brief's list has been deleted, so the wave-7 doubt about
`PROCTOR_SECOND_LANE` resolves as *survives* — brief 45 gave Cua the actuation
lane, not the browser lane, and `BrowserUseTool` is untouched by it.

### The eight that get a home

| Switch | Default | Shape | Where it is read | Read timing |
|---|---|---|---|---|
| `PROCTOR_HUD` | on | `OverlaySwitch` off-values | `SessionHUD.hudEnabledByDefault`, `RunHUDFeed.init` | seeded at start; **a live channel already exists** |
| `PROCTOR_CURSOR` | on | `OverlaySwitch` off-values | `CursorOverlay.isEnabled` | `static let` — once per process |
| `PROCTOR_TAKEOVER` | on | `OverlaySwitch` off-values | `TakeoverOverlay.isEnabled` | `static let` — once per process |
| `PROCTOR_YIELD` | on | `OverlaySwitch` off-values | `ContentionMonitor.enabled`, via `Session.yieldEnabled` | stored at session construction |
| `PROCTOR_YIELD_INPUT` | **off** | opt-in (set-and-not-an-off-value) | `ContentionMonitor.inputObserved` | stored at session construction |
| `PROCTOR_TAKEOVER_INPUT` | **off** | opt-in | `InputBlocker.isEnabled` | `static let` — once per process |
| `PROCTOR_SECOND_LANE` | **off** | **`=browser-use`, a tool name, not a boolean** | `BrowserUseTool.enabled` | resolved per doctor report from the process environment |
| `PROCTOR_ACTUATION` | **off** | **`=cua`, a lane name, not a boolean** | `CuaDriverTool.laneSelected`, `makeActuationBackend` | once at process start, documented as deliberate |

Three findings in that table are the reason the brief told us to re-enumerate:

- **`PROCTOR_TAKEOVER` exists and the brief never listed it.** PRO-0025 added it
  alongside `PROCTOR_TAKEOVER_INPUT` with the overlay/block asymmetry the other
  pairs have. A settings surface built from the brief's list would have shipped a
  card that silently omitted one of the two switches governing what appears over
  a person's screen while Proctor drives their Mac.
- **`PROCTOR_ACTUATION` is now first-class.** PRO-0044 added it and PRO-0051
  settled that lanes are deliberately selected and never automatic, native stays
  the default, and every run record names the lane. Its wrong setting is not a
  cosmetic difference: it is a run that measures the delegated path while its
  reader believes they measured the native one. It belongs in this card more
  than any of the drawing switches do.
- **`PROCTOR_SECOND_LANE` is not a boolean.** `BrowserUseTool.enabled` returns
  true only for the exact value `browser-use`; `PROCTOR_SECOND_LANE=1` is off.
  A checkbox that wrote `1` would read as enabled in the window and be off in the
  agent. This is the concrete form of the brief's warning about a toggle that
  silently loses.

### The 24 that deliberately do not get a home, with the reason

Recording these is half the deliverable: the next person to ask "why is this one
not in the window" should find the answer here rather than re-deriving it.

- **Numeric tuning** — `PROCTOR_HUD_PAUSE_LIMIT`, `PROCTOR_QUEUE_WAIT_LIMIT`,
  `PROCTOR_HISTORY_DAYS`, `PROCTOR_HISTORY_ENTRIES`. Not switches. Each has a
  working default and a bounded parse; a text field for each is a settings
  surface of a different kind, and the brief scopes this to the switches.
- **Security configuration that is not a toggle** — `PROCTOR_FS_ROOTS` (the
  filesystem jail's root list), `PROCTOR_MCP_TOKEN`, `PROCTOR_PROFILE`. These
  carry values a UI cannot sensibly compose, and two of them are secrets or
  near-secrets. `proctor_policy` is their surface.
- **Escape hatches that weaken a check** — `PROCTOR_CUA_ALLOW_UNSIGNED`,
  `PROCTOR_CUA_ALLOW_UNSUPPORTED`, `PROCTOR_CUA_TRANSPORT`. The first two
  disable a signature and a version gate in `CuaPreflight`. **Deliberately kept
  out of the window**, and this is a decision rather than an omission: putting a
  one-click bypass of a signature check in the same card as "show the pointer"
  makes the two look like the same kind of choice. Somebody who needs these can
  set them the way they set them today, having read what they do.
- **Plumbing** — `PROCTOR_SOCKET`. Where the socket is, not how Proctor behaves.
  Already reported in the Background agent card.
- **Build and install** — `PROCTOR_SKIP_NOTARIZE`, `PROCTOR_SIGN_IDENTITY`,
  `PROCTOR_NOTARY_PROFILE`, `PROCTOR_FORCE_BUILD`, `PROCTOR_PLIST`,
  `PROCTOR_CHANGELOG`, `PROCTOR_REGENERATE_TOOLCHAIN`, `PROCTOR_TEST_LOG`,
  `PROCTOR_TOOL_DIRECTORIES`, `PROCTOR_TOOL_NAMES`, `PROCTOR_TOOL_COMPANIONS`.
  Read by `scripts/*.sh` and the test suite, never by the running agent.
- **A compile flag, not an environment variable** — `PROCTOR_REFLECTOR` is a
  Swift `#if` condition. Nothing at runtime can change it, so a control for it
  would be inert by construction.

## The four hard parts, answered

### 1. Precedence: the environment wins, **except that off always wins for a capability switch**

**Rule, in two parts.**

- **The six ordinary switches** — the four drawing switches `PROCTOR_HUD`,
  `PROCTOR_CURSOR`, `PROCTOR_TAKEOVER` and `PROCTOR_YIELD`, plus the two lane
  selectors `PROCTOR_SECOND_LANE` and `PROCTOR_ACTUATION`: **environment >
  saved preference > built-in default.** A switch whose source is the environment
  renders its control disabled and names the variable.
- **The two input-capture opt-ins** — `PROCTOR_YIELD_INPUT` and
  `PROCTOR_TAKEOVER_INPUT`: **off wins from either source.** The environment can
  turn them on; a saved preference of off turns them back off, and their control
  is **never disabled**. Effectively `environment AND saved`.

The first part's reasoning is unchanged: the environment is set by whoever started
this particular agent and applies to this launch only, so a preference set months
ago must not silently override a deliberate `PROCTOR_ACTUATION=cua` and leave a run
measuring a path its reader did not choose.

**The second part exists because the out-of-family gate found the first draft
failing unsafely, and it was right.** With one blanket rule,
`PROCTOR_TAKEOVER_INPUT=1` in the agent's launch environment creates the
`CGEventTap` that swallows the person's keyboard, and the "locked when sourced
from the environment" rule then disables the only control that could turn it off.
The person whose keyboard is being eaten is shown a switch they cannot press, and
their remedy is to find an environment variable and restart a background process.
That inverts the reasoning the switch was built on: `InputBlocker` reads its
value once precisely so a tap can never appear without somebody asking, and
`Takeover`'s own comment refuses to make the stronger capability a default while
the weaker one stays opt-in. A locked-on off-switch is the same mistake in a new
place.

The asymmetry costs the first part nothing. A capability escalation that anyone
can decline is not a lane selector whose whole value is that it cannot be
silently cancelled.

**Coupling rule.** `PROCTOR_TAKEOVER_INPUT` on with `PROCTOR_TAKEOVER` off means
input is held while nothing on screen says so. The window states that pairing as
a warning on the row, and the run record already carries `TakeoverReport.shown`
and `.blocked` separately, so the combination is visible after the fact as well.
The same holds for `PROCTOR_YIELD_INPUT` with `PROCTOR_YIELD` off.

**The surface shows four things per switch, never just the toggle:** the value the
agent is running with, the value that is saved, the source of the effective value
(`environment` / `saved` / `default`), and — when the source is the environment —
the variable's name plus the fact that the agent *inherited* it. That last word is
load-bearing: `install.sh` writes no `EnvironmentVariables`, so an environment
value almost always arrives from `launchctl setenv` or a wrapper, which survives
every reinstall and is otherwise invisible. A row that only said "set by the
environment" would leave a person with nowhere to look.

### 2. Reaching a running agent: **seven of the eight** are relaunch-scoped, said plainly

**Seven of the eight apply at the next agent start.** (The first draft said six,
which is arithmetic the gate caught: eight switches minus the one live switch is
seven.) The window says so on the row and offers `Restart agent` inline.

This is not a shortcut around live-apply. The code's own reasoning says live-apply
would be a defect for the switches that matter most. `InputBlocker.isEnabled` is a
`static let` and carries the comment *"Read once: a tap that could switch itself
on mid-process would be a tap nobody agreed to."* `CuaDriverTool.laneEnv` is
documented as read once at process start because *"per call would let one run mix
lanes, which is what makes a determinism score measure the plumbing."* Making
those live would reverse two settled decisions to win a nicety.

`PROCTOR_HUD` is the exception and keeps its existing live behaviour: the run
panel already has a show/hide control channel from this window
(`AgentModel.setPanel(visible:)`), and PRO-0036's window already drives it. The
new preference sets the *default* the agent seeds from at start; the live channel
is unchanged. The row says both, because "shown now" and "shown at the next start"
are genuinely two facts about that switch.

**Running and saved are two fields, never collapsed into one.** The gate found the
window able to show a wrong effective value, and the fix is structural rather than
a matter of timing. A row shows what the agent *is running with* — from its report,
which is the only party that knows — beside what is *saved and will apply*. When
they differ the row shows a pending marker and the restart button. There is no
moment at which one number stands for both, so there is no window in which the
window quietly lies.

Before the first report of a given agent process arrives, the running value reads
**not yet known**. It is never guessed from the window's own environment (a
different process's environment), from the saved file (which is a request, not a
fact), or from the previous process's last report (which describes a process that
has exited). `PROCTOR_HUD` shows both its live state and its saved start-up
default, because those are genuinely two facts and the live channel can be set the
other way.

### 3. Two controls are consent gates, not checkboxes

`PROCTOR_SECOND_LANE=browser-use` names an autonomous LLM agent to a model with a
shell, attaching to a real browser with the person's real cookies and logins, and
nothing it does reaches Proctor's audit trail. `BrowserUseTool` already carries
that disclosure and PRO-0036 already renders it beside the tool row.

**`PROCTOR_TAKEOVER_INPUT` gets the same treatment, and the gate was right that
the first draft's omission was the wrong way round.** It creates a `CGEventTap`
that swallows the person's own keyboard and mouse. Measured against the second
lane it is the more dangerous of the two — it needs no additional software, no
credential and no network, and it takes the machine away from the person sitting
at it — so a design giving the second lane a confirmation and this one a bare
checkbox had the ordering backwards.

**Both are off by default, both are a two-step enable with the disclosure above
the control rather than behind a disclosure triangle, and both are one click to
disable with no confirmation.** The asymmetry is the point, and it is the same
asymmetry the switches' own defaults have.

The second lane's control writes the literal `browser-use`, never `1` or `true`,
so the saved value and the value `BrowserUseTool.enabled` accepts are the same
string by construction. The plan's test list pins this.

**An environment-set lane bypasses the confirmation, by design, and the disclosure
stays on screen anyway.** Somebody who exported `PROCTOR_SECOND_LANE=browser-use`
made that choice deliberately and does not need to re-consent through a window
they may never open. What they do get is the row, the disclosure, and the word
`environment` beside it — so the consent is visible even where it was not
collected here.

### 4. What is written, where, and what `install.sh` does to it

**Nothing writes the launchd plist. That is the design, and it is the answer to
the brief's fourth hard part rather than an evasion of it.**

Measured at `c9e42c9`: `scripts/install.sh` writes
`~/Library/LaunchAgents/app.fledgeling.procter.agent.plist` with a `cat >` heredoc
that **has no `EnvironmentVariables` key at all** and overwrites the file
unconditionally on every run. So a plist-written preference would be destroyed by
the next `install.sh` — silently, on an upgrade, taking a person's saved settings
with it. That is precisely the disappearance the brief's problem statement
describes, and writing to the plist would reproduce it rather than fix it.
Applying a plist change also needs a `bootout` + `bootstrap` cycle, which is
strictly heavier than the `kickstart` the window already uses.

**Instead: a preference file the agent reads at start, beside its other state.**

- **Path:** `~/Library/Application Support/app.fledgeling.procter/settings/settings.json`,
  derived from `Wire.bundleIdentifier` exactly as `PolicyStore` and `FlowStore`
  derive theirs, never a hardcoded string and never a directory called `Proctor`.
  **The out-of-family gate caught the first draft naming
  `~/Library/Application Support/Proctor/`, which does not exist on any Mac** —
  `install.sh` sets `SUPPORT_DIR="$HOME/Library/Application Support/$BUNDLE_ID"`,
  and every store in the tree agrees with it.
- **Created by:** the window, on first write, `0700` on the directory, following
  `PolicyStore`. `install.sh` already does `mkdir -p "$SUPPORT_DIR"` for the
  parent and never removes it, so the file survives every reinstall and upgrade.
- **Written by:** the status window's own process, atomically.
- **Read by:** the agent at process start, and by the window to show the saved
  value beside the effective one.
- **Contents:** the eight switch names and their saved values, nothing else. No
  secrets, no paths, no policy. File mode `0600`, directory `0700`.
- **On the next `install.sh`:** untouched. This is the substantive improvement
  over the plist and the reason the design went this way.

**`procter` is not a typo.** `Wire.bundleIdentifier` is the string
`app.fledgeling.procter`, and every store, socket and log path in the tree is
derived from it. The out-of-family gate flagged it as a misspelling; it is the
real bundle identifier, and "correcting" it would point the window at a directory
the agent does not use. Named here so the next reader does not fix it.

**The parse table, so two processes cannot disagree about a string.** The saved
value and the environment value go through the same reader.

| Switch | On | Off | Anything else |
|---|---|---|---|
| The four `OverlaySwitch` switches (`HUD`, `CURSOR`, `TAKEOVER`, `YIELD`) | anything not an off-value, including unset | `0`, `off`, `false`, `no` (trimmed, lowercased) | reads **on** — this is `OverlaySwitch`'s existing rule and is not changed here |
| The two opt-ins (`YIELD_INPUT`, `TAKEOVER_INPUT`) | set, non-empty, not an off-value | unset, empty, or an off-value | reads **off** |
| `SECOND_LANE` | exactly `browser-use` | anything else, including `1` and `true` | reads **off** |
| `ACTUATION` | exactly `cua` (case-insensitive) | anything else | reads **off** |

**A corrupt, unreadable or partially-written file falls back to the built-in
defaults, never to "on".** Unknown keys are ignored rather than rejected, so an
older agent reading a newer window's file still starts. Writes are atomic
(write-temp-then-rename), so a reader never sees a torn file.

### settings.json is not a trust boundary, and the spec says so

The gate's sharpest finding, accepted in full. The file lives in the user's own
home directory: **any process running as this user can write it**, and `0600`
keeps out other users rather than other programs. The agent — which holds
Accessibility and Screen Recording — reads it at start and honours it.

So the honest claim is narrow, and it is the only one made: **this file is a
convenience for a person, not a control that constrains a program.** Anything
already running as this user can rewrite Proctor's switches, and could equally
rewrite the plist, the shim's configuration, or Proctor's own bundle. This
feature does not widen that; it makes the resulting state visible in a window
where it previously was not visible anywhere.

Three things follow, and they are the proportionate response rather than an
unenforceable claim of protection:

- **Off wins for the two capability switches** (part two of the precedence rule),
  so the file can always *decline* a tap and can never be the sole reason one
  exists that a person cannot cancel.
- **The effective value and its source are carried in the agent's report and the
  run record**, so a run driven with a tap or a second lane says so in the
  evidence, whatever set it. This is the same reasoning PRO-0051 applied to the
  actuation lane.
- **No self-bootstrap.** The one shell-holding party this design could hand
  something to — the second lane's `browser-use` agent — exists only once the
  second lane is already on, so it cannot write the file to turn itself on. The
  residual is malware already running as the user, which has better targets.

The agent's report gains the effective values, because **the window's own
environment is not the agent's**. The window is launched by Finder or LaunchServices;
the agent is launched by launchd. Reading `ProcessInfo` in the window would report
the wrong process's environment, and would do so plausibly. The effective value and
its source are therefore computed in the agent and carried on `DoctorReport` as a
new optional field, following `lanes` and `policy` — optional so an older agent's
report still decodes against a newer window.

## Acceptance criteria

Each clause names the test that proves it. Clauses marked **(eye)** cannot be
witnessed by `swift test` — `Package.swift` declares no `ProctorUI` test target
and there is no window server under test — and are verified by a person looking at
a running build.

1. **The catalogue names exactly the eight runtime switches**, with each one's
   default, shape and read timing. Test: a table-driven test over the catalogue.
2. **The catalogue cannot drift from the code.** A test asserts each catalogue
   entry's variable name equals the real constant or literal at its call site
   (`CuaDriverTool.laneEnv`, `BrowserUseTool.laneVariable`, and the literals in
   `Takeover`, `ContentionMonitor`, `SessionHUD`, `CursorOverlay`). This is the
   guard against the exact failure that created this item — a list that moved
   while a document did not. Follows PRO-0036's drift test.
3. **Precedence resolves environment > saved > default for the six ordinary
   switches**, including the two non-boolean ones. Test: resolution over a supplied
   environment dictionary and a supplied saved store.
4. **Off wins from either source for `PROCTOR_YIELD_INPUT` and
   `PROCTOR_TAKEOVER_INPUT`.** With the environment on and the preference off, the
   resolved value is **off**, and the control reports itself **not locked**. This is
   the gate's finding and is the single most important test in the list. Test: the
   four combinations of environment and saved, per capability switch.
5. **The source is reported, not inferred.** Resolution returns the value *and*
   which of the three sources produced it. Test: all three sources per switch.
6. **An off-value in the environment beats an on preference for an ordinary
   switch.** Test: `PROCTOR_CURSOR=0` with cursor saved on resolves off, source
   `environment`.
7. **`PROCTOR_SECOND_LANE` saves the literal `browser-use`.** A saved value of
   `1`, `true` or `on` resolves the lane **off**, matching `BrowserUseTool.enabled`.
   Test: round-trip plus the rejected spellings.
8. **`PROCTOR_ACTUATION` saves the literal `cua`**, same shape, same test.
9. **The parse table holds for every switch**, including that an unrecognised value
   reads on for the four `OverlaySwitch` switches and off for the other four. Test:
   table-driven over the parse table in this spec.
10. **An ordinary switch sourced from the environment reports its control as
    locked, with the variable's name; a capability switch never does.** Test: a pure
    function returning the control state.
11. **Every switch reports whether it applies live or at the next agent start**, and
    `PROCTOR_HUD` is the only one reporting live — so exactly seven report
    relaunch-scoped. Test: table-driven, asserting the count.
12. **`TAKEOVER_INPUT` on with `TAKEOVER` off is reported as a warned pairing**, and
    likewise `YIELD_INPUT` with `YIELD`. Test: the pairing function over all four
    combinations.
13. **The store round-trips**, and a missing, unreadable, corrupt or
    partially-written file resolves to the **built-in defaults** — specifically, the
    two capability switches and the two lane selectors resolve **off** — without
    throwing. An unknown key is ignored, not rejected. No key outside the eight is
    ever written. Test: encode/decode plus the four malformed cases.
14. **The store's path derives from `Wire.bundleIdentifier`**, never a literal.
    Test: the resolved path contains `app.fledgeling.procter` and is asserted equal
    to the `PolicyStore`-shaped construction.
15. **The report's new field is optional and an older report still decodes.** Test:
    decode a `DoctorReport` JSON with the field absent.
16. **(eye)** The window shows a Switches card in the established `Card` /
    `SectionTitle` idiom, with each row's running value, saved value, source, and
    lock state.
17. **(eye)** A locked row's control is visibly disabled and names the variable and
    the fact that the agent inherited it.
18. **(eye)** Before the first report of an agent process, rows read *not yet known*
    rather than a guess.
19. **(eye)** Changing a relaunch-scoped switch shows the pending marker and the
    `Restart agent` button, and the marker clears after the restart when the
    agent's report comes back with the new running value.
20. **(eye)** Both consent gates — the second lane and the takeover input block —
    show their disclosure above the control, require the confirmation to enable, and
    disable in one click.

## Out-of-family review gate

Ran on **grok-4.6**, effort `xhigh`, per the fleet contract (Codex is off on this
repo). Two attempts: the first died mid-reasoning after going off to read repo
files — the contract's documented failure mode — but produced one finding before
it did. The second, with the evidence inlined and file reading forbidden,
completed.

| # | Finding | Disposition |
|---|---|---|
| 1 | The Application Support path names a directory that does not exist | **Accepted.** Corrected to the `Wire.bundleIdentifier` form; clause 14 now pins it. From the failed first attempt. |
| 2 | Precedence fails unsafely for both opt-ins: env can turn the keyboard-swallowing tap on and the lock rule then disables the only control that could turn it off | **Accepted, and it reshaped the design.** Precedence is now two-part; clause 4 is its test. |
| 3 | The window can show a wrong effective value, and for a relaunch-scoped switch the lie can last the rest of the agent process | **Accepted.** Running and saved are now two fields that are never collapsed; clauses 18 and 19. |
| 4 | `settings.json` is writable by any process running as the user; the agent honours it with no consent check on the read path | **Accepted.** Stated plainly as a non-boundary, with the three proportionate responses. No claim of protection is made. |
| 5 | "Six of eight apply at next start" and "HUD alone is live" cannot both be true | **Accepted.** Arithmetic error; it is seven. Clause 11 asserts the count so it cannot drift again. |
| 6 | `TAKEOVER_INPUT` is more dangerous than `SECOND_LANE` and had no two-step | **Accepted.** Both are consent gates now. |
| 7 | No parse table, no corrupt-file behaviour, no file mode, no coupling rule for the `_INPUT` pairs | **Accepted.** All four added; clauses 9, 12, 13. |
| 8 | `procter` is a typo | **Rejected, with the reason recorded in the spec.** It is the real bundle identifier. |
| 9 | An env-set `SECOND_LANE` skips the consent gate | **Accepted as a documented deliberate choice**, not a change: an operator who exported it consented already, and the disclosure stays on screen with `environment` beside it. |

## Not in scope, restated against the enumeration

No new switch is added. The 24 names in the second table above stay exactly as
they are, reachable exactly as they are today. In particular the two Cua preflight
bypasses are deliberately absent from the window, for the reason given there.

## Child work found

- **`PROCTOR_HUD_PAUSE_LIMIT`, `PROCTOR_QUEUE_WAIT_LIMIT`, `PROCTOR_HISTORY_DAYS`
  and `PROCTOR_HISTORY_ENTRIES` have no home either**, and are a different shape
  of problem (bounded numbers with defaults, not switches). Worth an item; not
  specced here.
- **`TakeoverWiringTests.swift:317` is still flaky on main, after PRO-0053.**
  Measured during this item's gate rather than inferred. The test is *a run that
  cannot post does not close a posting run's in-flight window*, and the failing
  assertion is `#expect(post.inFlight)`.

  | Tree | Full-suite runs | Failures |
  |---|---|---|
  | `main` at `6263c94`, unmodified | 30 | 2 |
  | `ai/pro-0029` | 15 | 2 |

  Same test, same line, indistinguishable rates, so it is not this item's. It
  reddens the gate roughly one run in ten, which is exactly the cost PRO-0053 was
  raised about and is high enough that a real finding will eventually be
  dismissed as "that flake again". Worth its own item; not fixed here, because
  the fix is in the takeover wiring rather than in anything this change touches.

- **`scripts/install.sh` rewrites the plist wholesale.** Harmless once this item
  lands, because nothing depends on the plist carrying an environment. Recorded
  because anyone who later decides to write `EnvironmentVariables` there will hit
  it.
