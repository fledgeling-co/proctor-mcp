# PRO-0020: Route browser work to Obscura

**ID:** PRO-0020
**Status:** In Review
**Created:** 2026-08-14
**Last updated:** 2026-08-14
**Plan:** docs/plans/plan-PRO-0020.md
**Branch:** ai/pro-0020 (worktree `.worktrees/PRO-0020`)

## Feature description

Verbatim brief: `docs/features-to-triage/21-route-browser-work-to-obscura.md`. Proctor is
being used to drive web pages — attaching to Chrome or Safari, walking a flattened AX tree,
clicking at coordinates — and that trades the DOM, computed styles, the console, the network
log and a selector that survives a re-render for a worse instrument. The page should go to
Obscura (`obscura` on PATH, the operator's chosen browser tool). Proctor keeps the window, the
app and everything native around the page.

## Triage — 2026-08-14

### The decision the brief asked for: how much routing

**Recognise, disclose, hand off. No proxy, and no third actuation plane.** The brief floats a
fuller version in which page-level steps travel through Obscura and are presented as ordinary
Proctor steps on a third plane. That version is not merely bigger; it is wrong, for a reason
that is checkable rather than aesthetic.

`obscura --help` on this machine advertises `serve`, `fetch`, `scrape` and `mcp`. Every one of
them drives **Obscura's own engine**. None attaches to a running Chrome or Safari, and
`obscura serve` exposes CDP for Obscura's page, not for the browser window Proctor is attached
to. So "route this click to that window through Obscura" has no implementation: a routed step
would open a second, unrelated page at the same URL and report success against a window it
never touched. Its `stateHash` would not be comparable to the hashes either side of it, which
poisons `proctor_stability`; its `SettleReport` would be a conjunction of AX notifications and
dirty frames from a window that did not move. `docs/architecture.md` says a step's plane is on
every result and is never inferred, because what a result proves depends on how it travelled.
A fabricated third plane is the one failure that document exists to prevent.

The honest thing Proctor can do is stop the model in the moment it reaches for the wrong
instrument, tell it which instrument is right, and hand over everything needed to continue —
the URL, the tool, the commands, and the measured edges so they are not rediscovered.

**And the handoff has to disclose its own discontinuity, or it repeats the same lie one layer
out.** Obscura opens its own engine with its own cookie jar. Handing a model a URL eight steps
into an authenticated flow does not continue that flow; it restarts at a URL with no session,
no tab state and no SPA state. That is carried as a field of the handoff, in words, not left
for the model to discover at a login wall. (Out-of-family spec review, grok-4.6, called this
the sharpest defect in the first draft; it was right.)

### The decision the brief asked for: where the boundary sits

Two conditions, both required, for page-level disclosure:

1. The application is a **known browser**, matched on bundle identifier against a catalogue —
   not inferred from the tree. This follows `AXEngineImpl.isChromiumBased`, which identifies
   Chromium from the bundle precisely because the tree is what is missing.
2. The target is **inside an `AXWebArea`**.

A web view inside a native Mac app satisfies (2) and not (1), so it is never routed — it stays
Proctor's, exactly as the skill already tells the model. Native browser chrome (toolbar, tab
bar, address field, bookmarks, sheets, downloads popover, menu bar) satisfies (1) and not (2),
so it stays Proctor's too. Attaching to a browser at all discloses at the app level, because
attach is the moment the instrument is chosen.

### The decision the brief asked for: what a routed step's evidence looks like

Nothing is routed, so nothing changes. No new `ActuationPlane` case, no change to
`SettleReport`, no change to `Canonical` hashing, no change to what an `AuditRecord` means. A
step into page content executes exactly as it does today and reports the plane it really used;
it just arrives carrying a note that says the page is Obscura's.

## Scope

**In.** A pure browser catalogue and handoff payload in `ProctorCore`; disclosure on
`proctor_apps` (list and attach), `proctor_snapshot`, `proctor_find` and `proctor_act`; the
seven measured Obscura edges carried as data; README and CHANGELOG.

**Out.** Proxying steps; embedding a browser; a second browser backend; replacing Obscura; a
new enforcement mechanism; any change to settle, hashing, planes or the audit trail's meaning.

## Behaviour

A `browser` object on the result, at one of two detail levels.

**Full** (on `proctor_apps` action `attach` against a known browser) — `boundary`, `browser`,
`bundleId`, `use: "obscura"`, `continuity`, `evidence`, `url` **or** `urlUnavailable`,
`commands`, `caveats`.

**Brief** (everywhere else) — `boundary`, `browser`, `bundleId`, `use`, `continuity`, and
`url` or `urlUnavailable`. Full detail is emitted once, at the moment of choice; repeating
seven caveats on every step of a twenty-step flow is noise that gets skimmed.

`boundary` leads at both levels and is the same sentence at both: the page belongs to Obscura,
the native chrome around it — toolbar, tab bar, menus, sheets, downloads — stays Proctor's.
At app level that sentence is the whole point, because attaching to Chrome is not a reason to
leave Proctor; it is a reason to know which half of the window is whose.

`continuity` states that Obscura runs its own engine and its own cookie jar, so following this
advice restarts at a URL rather than continuing this window's session, and any authenticated
or multi-step state must be re-established there.

`evidence` states what a page-content step still proves: it travels the accessibility plane
like any other, but its `stateHash` is taken over a browser's render tree rather than an app's
view hierarchy, so a determinism score across page content measures the page's own churn as
much as the app's.

`caveats` carries the seven measured edges verbatim: the private-network block and
`--allow-private-network`; animations and transitions never executing; `setEmulatedMedia`
accepted and inert; web fonts never loading; an empty computed value meaning *not implemented*
rather than *not set* for `boxShadow`/`backgroundImage`/`textTransform`/`outline`/`flex`;
shorthand `padding`/`margin` resolving to `0px` while the layout is correct; and
`obscura fetch` rendering at a fixed 1280x720 and awaiting no promise.

`commands` carries **templates** with a literal `<url>` placeholder. The page's URL is
attacker-controlled text; interpolating it into a command string a model may paste into a
shell is a command-injection path, so the URL stays in its own field and is never composed
into prose or into a command.

### Where the URL comes from, and when there is none

`AXURL` on each web area in the window being asked about, falling back to `AXDocument`, which
is where some Chromium builds keep it. Not the application element and not a tab list, so it
describes the page in that window rather than whichever tab the app thinks is frontmost.

Only web areas **actually showing something** feed the URL decision: one with no frame, or one
collapsed to zero size, is discarded. A real browser tree carries more web areas than the page
a person is looking at (a docked DevTools pane, a preview, a collapsed area), and counting
those would make "several web areas" the answer nearly every time, which is a correct-sounding
way of never answering. Discarding an area with no extent is not picking between pages. When
**no** area reports a usable frame, none is discarded, because then the frames are what is
missing rather than the content.

Three cases then produce `urlUnavailable` with the reason instead of a guess: the attribute is
absent or empty; the read fails; or the window holds several rendered web areas whose URLs
differ, in which case Proctor does not pick one. Trailing slashes and fragments are normalised
before that comparison, so one page spelled two ways is one page.

### When Obscura cannot open the page

A readable URL whose scheme is not `http` or `https` (`chrome://`, `about:`, `devtools://`, an
extension page, the built-in PDF viewer) **keeps the disclosure and drops the recommendation**:
no `use`, no `url`, no `commands`, and `urlUnavailable` says why. Naming a tool that will fail
there is worse advice than naming none; staying silent would be worse still, because a model
would then drive that page believing Proctor had nothing to say about it. The first draft
suppressed the whole object, which handed the page back to the accessibility plane in silence;
the completeness critic caught it.

### Where the boundary is imprecise, and in which direction

Containment is geometric. Two consequences, stated rather than papered over:

- A browser that reports its web area as the **whole window** makes a toolbar target read as
  page content, so the advisory fires on a native control. The alternative is inventing a
  chrome inset, which would silently drop the disclosure on a real page instead. An advisory
  on a native control costs a line of JSON; a missing one costs the thing the feature is for.
- An **overlay drawn over the page** (a find bar, an autofill popover) sits inside the page's
  rectangle and reads as page content, for the same reason and at the same cost.

### Why the brief form is enough

The brief form omits the seven caveats, which would be a real gap if a caller could reach a
page-level result without having seen the full one. It cannot: `snapshot`, `find` and `act` all
resolve a window handle, and window handles only exist after `proctor_apps` action `attach`,
which is where the full form is emitted. Every session that sees a brief handoff has already
been given the full one. The two things that must not wait for that (`continuity`, and the
private-network caveat when the page is local) are on the brief form as well.

Where it appears:

| Surface | When |
|---|---|
| `proctor_apps` list | Brief, on each running row whose bundle id is a known browser. |
| `proctor_apps` attach | Full, when the attached app is a known browser. |
| `proctor_snapshot` | Brief, when the app is a known browser **and** the walked tree contains an `AXWebArea`. |
| `proctor_find` | Brief, when the app is a known browser **and** a matched node resolves inside an `AXWebArea`. |
| `proctor_act` | Brief, **once per call**, when the app is a known browser and any step targeted page content. |

## The catalogue

Exact bundle ids, plus a prefix rule for channel variants. Safari and Safari Technology
Preview; Chrome (stable, Beta, Dev, Canary) and Chromium; Edge and its channels; Brave and its
channels; Firefox, Developer Edition and Nightly; Arc; Orion; Vivaldi; Opera; Zen;
DuckDuckGo. Adding one is a line in a table, and the spec says that so an absent browser is a
known, cheap gap rather than a design flaw.

## Acceptance clauses

1. Known browser bundle ids classify, including channel variants (Chrome Canary/Beta/Dev,
   Edge, Brave, Firefox Nightly/Developer Edition, Safari Technology Preview); an unknown or
   absent bundle id classifies as nothing.
2. `proctor_apps` list marks a running known-browser row with a brief handoff and leaves every
   other row untouched.
3. `proctor_apps` attach on a known browser returns a full handoff carrying all seven caveats
   and the command templates; attach on a non-browser returns no `browser` key.
4. `proctor_snapshot` of a browser window whose tree contains an `AXWebArea` returns a brief
   handoff; **the same tree walked in a non-browser app returns none** (the WKWebView/Electron
   boundary).
5. `proctor_act` returns exactly one handoff for a batch of several page-content steps, and
   none for a batch confined to native chrome.
6. A URL containing shell metacharacters or quotes appears only in the `url` field; every
   command template still contains the literal `<url>` and no part of the URL.
7. Nothing is refused and no plane changes: an act into page content still executes and still
   reports the plane it actually used.
8. When the page URL cannot be read, the handoff carries `urlUnavailable` with the reason and
   no `url` key; a window holding two web areas with differing URLs is one such case.
9. A readable `chrome://`, `about:`, `devtools://` or other non-`http(s)` URL keeps `boundary`
   and `continuity` and drops `use`, `url` and `commands`.
10. Both detail levels carry the same `boundary` sentence and a `continuity` sentence; the
    brief level carries neither `caveats` nor `commands`.
11. A zero-sized or frameless web area beside a real one does not make the answer "several web
    areas"; a window in which *no* area reports a frame keeps every area in the comparison.
12. A page whose URL is loopback, `.local` or RFC1918 carries the `--allow-private-network`
    caveat in the brief form as well as the full one.
13. Every target a call addressed is considered, not a prefix of them: a batch that clicks the
    toolbar and then the page discloses, and a find whose first matches are chrome and whose
    later ones are page content discloses.

## Assumptions recorded in place of questions

- `[Behaviour]` **Advisory, never a refusal.** A refusal is a capability regression a caller
  cannot override, and driving native browser chrome is legitimate. Proctor's ethic is to
  report rather than to smooth over.
- `[Behaviour]` **There is no page-scoped enforcement, and the block list is not one.** An
  operator can put a browser's bundle id on the `proctor_policy` block list, but that refuses
  the whole application, chrome included — it cannot express the boundary this item draws. So
  an agent that ignores the disclosure keeps driving the page, and that is the accepted cost
  of choosing advisory. A page-scoped refusal is logged below as child work rather than
  claimed here.
- `[Scope]` **The catalogue is a list, not a heuristic.** A browser not in it discloses
  nothing. Inferring "browser" from an `AXWebArea` would sweep in every Electron app and break
  the boundary the brief drew.
- `[Scope]` **Firefox may not expose `AXWebArea`** on macOS in every configuration. App-level
  disclosure still fires on attach; page-level disclosure may not. Named, not solved.
- `[Behaviour]` **A point-based step** (`click`, `hover`, `dragPath` at coordinates) has no
  node to resolve, so in a browser window it gets the advisory without node precision. That is
  the case the brief calls out by name — a click at a point proves less than a DOM assertion —
  so imprecision errs toward disclosure.
- `[Cost]` `proctor_find` resolves ancestry for at most the first few matches and stops at the
  first hit, because a walk-up per result is an AX IPC round trip per level.
- `[Scope]` `proctor_doctor` gains nothing. It reports grants and health; which app is a
  browser is not a health fact.

## Child work found, not built here

- **Page-scoped refusal.** A policy rule that refuses actuation into an `AXWebArea` inside a
  known browser while leaving native chrome drivable. Needs `PolicyStore`, the `proctor_policy`
  schema and the tool catalogue, all contended surfaces; and it is a second authority over the
  same question, so it deserves its own spec.
- **`proctor_stability` over page content should disclose page churn.** A determinism score
  replayed across a browser page measures the page's render-tree churn as much as the app's.
  This item discloses it at `proctor_act`; the stability report does not know.

## What a test cannot reach here

Every clause above is machine-witnessable from `swift test` against the fake AX engine. What is
not: that a real Chrome window's `AXURL` reads back as expected, and that a real Safari page
node's ancestry contains an `AXWebArea`. Both need a window server and a running browser, so
they are code-complete-and-unverified rather than proven, and the report says so.

## Out-of-family review

Spec reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-14. It confirmed
the argument against proxying and found six defects; five are folded in above (the handoff's
own discontinuity; the block list not expressing this boundary; the app-level notice reading
as "leave Proctor"; unspecified URL provenance and the multi-web-area case; `chrome://` and
PDF-viewer false positives). The sixth — that page AX results still look like native ones and
contaminate determinism scoring — is answered by the `evidence` field here and logged as child
work for `proctor_stability`.

## Progress — 2026-08-14

Built on `ai/pro-0020` in `.worktrees/PRO-0020`. **418 tests / 51 suites green** (387/47 at
`deaa351`), `swift build` clean; the three warnings the build prints are pre-existing in
`ProctorUI`, which this change does not touch.

**What shipped.** `Sources/ProctorCore/BrowserTarget.swift` (catalogue, `WebArea`,
`WebContentProbe`, `BrowserHandoff`, the whole decision, pure). One seam,
`AXEngine.webContent(window:)`, implemented in `AXEngineImpl` as a single bounded downward walk
that stops at each `AXWebArea` and reads `AXURL` then `AXDocument`. Five call sites in
`Session` and `SessionAct`. `Snapshot` in `Wire.swift` gains a trailing `browser` field; the
four output schemas document it.

**Clause → test.** 1, 6, 8, 9, 10, 11, 12 → `Tests/ProctorCoreTests/BrowserTargetTests.swift`.
2, 3, 4, 5, 7, 13 → `Tests/ProctorAgentTests/BrowserRoutingTests.swift`, notably
`webViewInsideANativeAppIsNeverRouted`, which runs the same web-area probe under a browser
bundle id and a native one and requires opposite answers. That is the boundary in one test.

**Not machine-witnessable here.** That a real Chrome window answers `AXURL` (or `AXDocument`),
that a real Safari page element sits inside a real `AXWebArea`'s frame, and which browsers
report the web area as the content rect rather than the whole window. All need a window server
and a running browser; `swift test` has neither and Obscura is web-only, so it cannot see a
native surface either. Code-complete and unverified, not proven.

**Reviews.** Spec review and completeness critic both ran out-of-family on `grok-4.6`
(`--effort xhigh --sandbox read-only`), no downgrade needed. The spec review changed the design
five ways (see the section above); the critic changed it twice more: only rendered web areas
feed the URL decision, and every target is considered rather than the first three. Its claim
that a protocol-extension default would make the fake pass vacuously was answered by deleting
the default outright, so both conformances must implement the seam.
