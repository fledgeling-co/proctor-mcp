# PRO-0035: The browser catalogue stops guessing, and the handoff is machine-readable

**ID:** PRO-0035
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** docs/plans/plan-PRO-0035.md
**Branch:** ai/pro-0035 (worktree `.worktrees/PRO-0035`)

## Feature description

Verbatim brief: `docs/features-to-triage/36-the-browser-catalogue-stops-guessing.md`.

PRO-0024 logged three related weaknesses in how Proctor decides what a browser is and how it
tells a model what it decided.

- **A PWA or "open as app" window is treated as Chrome.** A bundle id like
  `com.google.Chrome.app.<hash>` inherits Chrome's catalogue row through the prefix rule.
  Inherited from PRO-0020 rather than introduced by PRO-0024, and wrong in a way that matters:
  a PWA window is an application window whose whole content is one page, and handing it off as
  a browser tab is not obviously right or obviously wrong.
- **`chromiumFamily` is a second fact per browser that can drift.** A browser can change
  engine; Opera and Edge both have. A wrong answer costs one lane recommendation for an
  internal page, which at least fails visibly.
- **`why` names the rule, not the risk, and nothing on the handoff object is machine-readable.**
  A host that wanted to gate on "this lane is unaudited" or "this lane needs a live profile"
  has to read prose written for a person.

Decide what a PWA window is, stop carrying a fact that can drift where it can be derived or
checked, and give the handoff object a small machine-readable flag set beside the prose.

**Do not re-litigate the routing rule.** PRO-0024 settled that routing is on the URL's scheme
alone, with a deny list, after rejecting the accessibility shape (Obscura reads the DOM, not
the AX tree, so an AX-empty page discriminates nothing) and the kind of step (the caller
authors the step list, so a model could win the heavier lane by adding one step). Both
rejections still hold. This item improves what is reported and how a browser is identified; it
does not reopen how a lane is chosen.

## Triage — 2026-08-15

### The product decision: an installed web app is an application window, and Proctor drives it

**A `com.google.Chrome.app.<hash>` window is an application window. Proctor drives it, names
no browser lane for it, says why, and still reports its address.** Not a browser tab, and not
ambiguous.

The brief warns that the third reading is not automatically the honest one, and it is right:
an object that says "this might be a browser window and might be an app window" moves the
decision to a model holding strictly less information than Proctor has. Proctor knows the
bundle id and knows what that form means. It should answer.

**The argument that settles it is consistency with a boundary this repo already drew.**
PRO-0020's whole point is that a web view inside a native Mac application is never routed —
that is the WKWebView/Electron boundary, and `webViewInsideANativeAppIsNeverRouted` is the
test that pins it. Slack, VS Code and Discord are Chromium rendering one origin's web content
in a window with its own bundle id, its own dock icon and its own session, and Proctor drives
all three natively without a word about a browser tool. An installed web app is the same
shape from different tooling. Routing the Chrome-installed Slack to a browser tool while
driving the Electron Slack natively is an inconsistency the boundary cannot justify.

**And the recommendation it replaces is confidently useless.** Handing the window's address to
Obscura opens that site in a different engine with no cookie jar. A site is installed as an
app precisely because somebody uses it signed in, so the discontinuity `continuity` discloses
is not an edge case here; it is the normal case, and the advice fails at a login wall.

**What was checked and did not survive.** The first draft of this decision rested on a second
pillar — that a web app window has no toolbar, tab bar or address field, so the boundary
sentence describes nothing and the whole window is page content. The out-of-family review
falsified it: Safari web apps show a navigation toolbar by default, Chrome and Edge have a
tabbed application mode, and window-controls-overlay puts web content *in* the title bar. So
**the boundary is unchanged for a web app**: inside an `AXWebArea` is the page, and a web app's
own toolbar or tab strip stays Proctor's, exactly as in a browser window. `evidence` stays at
full detail only, where it already is. The decision rests on the Electron argument and the
cold-jar argument, both of which hold on their own.

**What Proctor says, and why it says anything at all.** The purest form of "drive it natively"
is to identify nothing, exactly as an Electron app gets nothing. That is rejected for the
reason PRO-0020 rejected silence for `chrome://`: a model that reads the bundle id
`com.google.Chrome.app.abc123` will conclude *Chrome*, and Proctor staying quiet leaves it
acting on that conclusion. It is also not a change into silence — today this window gets
Chrome's full handoff, `use: "obscura"`, a URL and command templates.

So a web app window carries a handoff that names **no lane**: no `use`, no `commands`, no
`notes` about Obscura. It keeps `url`, because the address is readable and withholding it
forces a model that disagrees back onto guessing — that was a second review finding, and
suppressing the URL was copied from PRO-0024's not-a-page rule where the URL genuinely leads
nowhere. `why` carries the reason, `continuity` gets its own sentence that does not mention a
tool Proctor is not naming, and `flags` describe what driving it here commits the caller to.

**Naming the live-session lane here was argued and is out of scope.** The review's strongest
counter is that the second lane exists because it can continue a live session, and an
installed web app is where session continuity matters most — so a Chromium web app with the
lane on should name it. The argument is good and the answer is no, twice over. PRO-0024's
completeness critic deleted "the second lane as a fallback for ordinary web content" as the
largest and least justified surface in that feature; a web app is an ordinary `https` page in
application clothing, so naming the lane here resurrects the deleted rule for a subclass. And
this item's own terms are that it improves what is reported and how a browser is identified,
not which windows reach a lane. Logged as child work with the argument attached, because it
deserves a decision rather than a silence.

### The identification bug is the prefix rule treating a hash as a release channel

`identify` matches `com.google.Chrome` and accepts **any** remainder as a channel variant,
which is how `.canary`, `.beta` and `.dev` are covered without enumerating them. A per-site
app's remainder is `app.<hash>`, so it reads as a channel of Chrome.

Two out-of-family passes were needed to get the fix right, and the first draft of it was wrong
in three ways.

**Match on a path component, not a prefix of the remainder.** Chromium builds a shim id as the
base bundle id plus `.app.` plus the app id, and the base of a channel build is the channel's
own id — so a real Canary web app is `com.google.Chrome.canary.app.<hash>`, whose remainder is
`canary.app.<hash>` and does not begin with `app.`. Testing the start of the remainder would
have missed every web app on Canary, Beta, Dev, Edge Dev and Brave Beta, which is to say on
the builds a person doing this work actually runs. Any dot-separated component equal to `app`
or `webapp`, compared case-insensitively, marks a per-site application. `WebApp` may be the
**final** component — Safari's template id is `com.apple.Safari.WebApp` with nothing after it —
and it is never the **first**, because `app.zen-browser.zen` opens with one.

**Truncate at the marker and then look up, rather than looking up and then inspecting.** The
first draft merged the exact table and the prefix table into one longest-prefix-first table, so
that `com.apple.Safari.WebApp.<uuid>` could match Safari at all — Safari, Chromium, Vivaldi and
both Opera rows are exact-match entries today, and nothing extending them matches anything. The
plan review found what that costs: promoting an exact row to a prefix identifies **every**
descendant of it, so `com.apple.Safari.SafeBrowsing.Service` and its siblings would start
resolving to Safari, which is a change to a non-web-app window and this item promised not to
make one.

So the lookup is untouched. Identification first splits the id at its web-app marker, then runs
**today's** exact-then-prefix lookup on the part before it:
`com.apple.Safari.WebApp.site.<uuid>` looks up `com.apple.Safari` and hits the exact row;
`com.google.Chrome.canary.app.<hash>` looks up `com.google.Chrome.canary` and hits the prefix
rule; `com.operasoftware.OperaGX.app.<hash>` looks up `com.operasoftware.OperaGX` and hits its
own exact row rather than being read as an Opera channel. Every id with no marker takes exactly
the path it takes today, which is the cheapest possible proof that non-web-app identification
did not move.

**What this cannot see.** Chrome's `--app=<url>` windows, opened without installing anything,
run in the main browser process and carry the plain `com.google.Chrome` id. They are
indistinguishable from a tab by bundle id and keep today's behaviour. A false negative in the
safe direction, named rather than papered over.

A **closed list of channel words was considered and rejected**: a channel Chrome ships next
year would then identify as nothing at all and lose PRO-0020's disclosure entirely, which
trades a known bug for an unknown one. `app` is never a channel name, so the targeted marker
regresses nothing.

Safari's forms are **documented rather than measured** — no web apps are installed on this
machine, so nothing here verified them. Including them is upside-only: a Safari web app
identifies as nothing today and discloses nothing.

### The shim, and the two limits of "Proctor drives it"

A Chrome app shim is a loader that dlopens the framework out of Chrome's own bundle, so its
`Contents/Frameworks` directory is empty. `AXEngineImpl.isChromiumBased` lists exactly that
directory, so it answers **false** for every web app shim, and the manual-accessibility flag
Chromium needs before it exposes anything might then rest on the emptiness heuristics alone.
So the flag is applied when the bundle id identifies as an installed web app: a shim's empty
framework directory is a fact about how shims are built, not evidence that the process is not
Chromium.

Two limits are stated rather than solved, because neither is reachable from `swift test` and
no web app is installed here to measure. A shim may hand off and self-terminate, in which case
the window belongs to `com.google.Chrome` and identification never sees the web-app form —
today's behaviour, unchanged. And that a web app window's tree contains a web area at all is
an assumption; if it does not, the page-level handoff does not fire and the app-level one does,
which is the safe direction.

### `chromiumFamily`: one declared fact per row, and an honest claim about what that fixes

**The obvious answer — measure the engine from the app bundle — was tried against real bundles
and fails.** `AXEngineImpl.isChromiumBased` reads `Contents/Frameworks` and looks natural as an
authority: an app shipping a Chromium framework is Chromium whatever a table written in August
2026 says. Measured here: Chrome ships `Google Chrome Framework.framework` and Safari ships no
`Frameworks` directory, so both answer correctly. But the function decides on a **brand-name
heuristic** — a framework name containing `Chrom`, `Edge` or `Brave` — and Vivaldi, Opera and
Arc name their frameworks after themselves. None of the three is installed here to check.
Adopting the measurement would demote three browsers the table currently gets right, on the
strength of a second guess this machine cannot settle. The out-of-family review agreed and
would not reverse the call.

**So the fact is derived from one per-row fact rather than measured, and the claim is
narrowed.** `chromiumFamily` was always a proxy for one question — does the page in front of
Proctor exist in the browser the second lane drives — and the per-row fact behind it is which
internal scheme namespace that browser owns. Chrome and Chromium own `chrome`, Edge `edge`,
Brave `brave`, Vivaldi `vivaldi`, Opera `opera`, Arc `arc`; Safari, Safari Technology Preview,
Orion, DuckDuckGo, Firefox, Firefox Developer Edition, Firefox Nightly and Zen own none,
because their internal pages are `about:` pages and `about:` is deliberately not routed.

So `KnownBrowser` carries `internalScheme: String?` in place of `chromiumFamily: Bool`, and
`chromiumFamily` becomes computed — `internalScheme != nil`. **What that buys, precisely: one
fact per row where there were two, so the two can no longer disagree, and adding a browser
answers both questions in one line. What it does not buy: immunity from drift.** Opera changing
engine still needs somebody to edit that row. The review was right to call the stronger claim
false, and a real engine probe — Info.plist or loaded images, verified against Vivaldi, Opera,
Arc and a shim — is logged as child work rather than claimed here.

The routable scheme list is derived the same way but in **two parts**, because the first draft's
single rule was self-contradictory: `chrome-extension`, `chrome-untrusted`, `devtools` and
`isolated-app` have no browser whose own scheme they are. So there is a shared Chromium set
that needs no owner, and a per-row set where every entry has exactly one, and the list is their
union.

**Routing behaviour is identical for every browser in the table**, before and after, and a
clause asserts it.

### The flag set: five booleans, uniform polarity, and a stated limit

`why` names the rule that fired — a fact about a scheme — while what the caller is being handed
is an instrument with a blast radius, and a host that wants to refuse an unaudited or
credential-holding one has to read English written for a person.

`flags` is an object carrying all five keys every time. An object rather than an array of set
names, because a host reading `flags.autonomous` must be able to tell `false` from "this
Proctor does not know that flag"; an array collapses the two. Polarity is uniform — **true
means the fact is present and is one to weigh** — so a host's rule is "refuse if any flag I
care about is true".

**The flags describe the instrument the handoff points at**, which the review's sharpest
finding forced. The first draft put them only on a named lane, so the one path that acts in
the person's live signed-in session — Proctor driving their installed Gmail window — carried
no flags at all, and a host refusing `canActAsThisPerson` would have blocked the autonomous
lane and waved that through. There are three instruments, not two:

| Flag | obscura | browser-use | Proctor, on a web app |
|---|---|---|---|
| `actsOutsideThisWindow` | true | true | false |
| `autonomous` | false | true | false |
| `canActAsThisPerson` | false | true | true |
| `outsideTheAuditTrail` | true | true | false |
| `billed` | false | true | false |

What a host may conclude, one line each. `actsOutsideThisWindow`: the instrument acts in its
own browser, so nothing it reports is evidence about this window. `autonomous`: it decides its
own steps, and what happens between the ask and the answer is not enumerated in advance.
`canActAsThisPerson`: it is **able** to act with the browser session of the person at this
machine — the review caught the first draft asserting that it *does*, which the same payload's
own caveats falsify by telling the operator to run it on an isolated profile, so the flag
states the capability, which is what a host can actually gate on. `outsideTheAuditTrail`:
nothing it does appears in Proctor's audit trail. `billed`: it needs a model credential and a
run costs whatever that model costs.

**Two limits, stated because a flag read as a verdict is worse than prose.** A true flag is not
a claim that the instrument is unsafe, and five false flags are not a claim that one is safe.
And **the flags describe what Proctor recommends, not everything that could happen**: the
handoff is advisory and never a refusal, so a caller who ignores it and drives a signed-in tab
through the accessibility plane is doing something no flag on that handoff describes. A host
whose policy is "nothing may act in a live browser session" gates on the presence of a
`browser` object, not on a flag.

`flags` is absent exactly when the handoff points at no instrument — a deny-listed page, a
`file:` payload, a window only partly read, a missing tool. The set is a pure function of the
instrument, identical at both detail levels and on every page, which is what makes the
"describes the instrument" promise checkable.

**A machine-readable reason for the absence of a lane stays cut, with the rationale corrected.**
The first draft cut it saying hosts have only two cases; the review showed there are three —
follow a lane, no tool, or drive this web app here — and that the third is exactly the one that
matters. It is cut because `surface` already *is* that discriminator, so the host contract
reads "`use == null` is not enough; read `surface`" rather than "there is nothing more to
know". An enum whose cases duplicate a field beside it is a second spelling, not a signal.

### `surface`: the machine-readable half of the PWA decision

One string on the handoff, always present: `browserWindow` or `installedWebApp`. It is the
identification answer this item exists to fix, expressed so a host does not parse a sentence,
and it is on a different subject from the flags — they describe the instrument, this describes
the window.

`browser` stays the host browser's own name (`Google Chrome`) rather than becoming
`Google Chrome web app`. It is an identity field and the browser hosting the window really is
Chrome; the distinction belongs in `surface` for a machine and in `boundary` for a reader, and
`boundary` leads at both detail levels.

## Scope

**In.** `surface` on `KnownBrowser` and on `BrowserHandoff`; the web-app marker split in front
of the existing lookup; the web-app branch in `handoff`; `internalScheme` replacing
`chromiumFamily` as the stored fact, with `chromiumFamily` computed and the scheme list derived
in two parts; `BrowserLaneFlags` and the `flags` field, on a named lane and on the web-app
handoff; the manual-accessibility flag for a web-app bundle id; the four output schemas; README
and CHANGELOG.

**Out.** Which windows reach a lane — the scheme list's membership, the deny list, rule 0's
silent-area guard, the second lane's gate, `PROCTOR_SECOND_LANE`, the Obscura default, and
naming the live-session lane for a web app. Changing the lookup for any id without a web-app
marker. Measuring a browser's engine. A machine-readable no-lane reason. Renaming
`urlUnavailable`. Fixing `continuity` for a no-lane *browser* window, which has the same defect
and is logged. Recognising a `--app=<url>` window, which carries the plain browser bundle id.
Any new tool verb, actuation plane, or change to settling, hashing or the audit trail.

## Behaviour

### Identification

The id is first split at its web-app marker — the first dot-separated component after the first
that equals `app` or `webapp`, case-insensitively — and **today's** exact-then-prefix lookup
runs on the part before it. A marker makes the surface `installedWebApp`; no marker leaves both
the lookup and the surface exactly as they are today. `KnownBrowser` gains `surface` and trades
`chromiumFamily` for `internalScheme`.

### The handoff

`surface` is on every handoff at both detail levels. `flags` is present when a lane is named
and on a web-app handoff, at both detail levels, with all five keys.

A web-app handoff names no lane and carries no `commands`. It reads the URL through the same
rule 0 as any other window and **keeps it** where it was readable. Where that URL is a `file:`
or `data:` payload, or a PDF, the existing advice still applies — the review found the first
draft dropping it, so an installed PDF viewer would have been driven through the accessibility
plane with the "fetch the file and parse it" answer suppressed. `why` says the window is an
installed web app that Proctor drives; `continuity` says the session lives in this window and
that a browser tool would start somewhere else, naming no tool. The private-network note does
not fire, because it is advice about a lane that was not named.

### Everything else

Unchanged, and asserted to be unchanged.

## Acceptance clauses

1. `com.google.Chrome.app.<hash>` identifies as an installed web app hosted by Google Chrome
   and never as Chrome itself; so do `com.brave.Browser.app.…`, `com.microsoft.edgemac.app.…`,
   `org.chromium.Chromium.app.…`, `com.vivaldi.Vivaldi.app.…`, `com.operasoftware.OperaGX.app.…`
   and `com.apple.Safari.WebApp` both bare and with a site and UUID after it.
2. A **channel's** web app identifies as one: `com.google.Chrome.canary.app.<hash>`,
   `com.microsoft.edgemac.Dev.app.<hash>` and `com.brave.Browser.beta.app.<hash>` are installed
   web apps of their browser, not channel variants.
3. Channel variants themselves are untouched: `com.google.Chrome.canary`,
   `com.brave.Browser.beta`, `com.microsoft.edgemac.Dev` and `org.mozilla.nightly` identify as
   their browser with `surface` `browserWindow`, and `com.google.ChromeRemoteDesktop` still
   identifies as nothing.
4. The existing two-stage lookup is untouched for an id with no marker:
   `com.operasoftware.OperaGX` is Opera GX and not an Opera channel,
   `com.apple.SafariTechnologyPreview` is itself and not a Safari channel, and
   `com.apple.Safari.SafeBrowsing.Service` still identifies as nothing.
5. A web-app window names no lane at any detail level, under every combination of Obscura
   presence and the three lane states: no `use`, no `commands`, no `toolUnavailable`, no
   private-network note. `boundary` and `why` say it is an installed web app window Proctor
   drives, `continuity` names no tool, and `url` is present when it was readable.
6. A web-app window keeps the page-specific advice a browser window gets: a `file:` or `data:`
   address returns the not-an-instrument reason, and a `.pdf` address returns the PDF note.
7. `surface` is present on every handoff at both detail levels, and is `installedWebApp`
   exactly for the ids in clauses 1-2 and `browserWindow` for every other catalogue hit.
8. `chromiumFamily` is computed from `internalScheme` and answers exactly as PRO-0024 clause 1
   requires: Chrome, Chromium, Edge, Brave, Arc, Vivaldi and Opera true; Safari, Safari
   Technology Preview, Orion, DuckDuckGo, Firefox, Firefox Developer Edition, Firefox Nightly
   and Zen false; channel variants inherit their row's answer.
9. The routable scheme list is the union of a shared Chromium set and the per-row set; every
   row's own scheme appears in it, and every entry in the per-row half has exactly one owning
   row.
10. **Routing is unchanged.** Across schemes x browsers x Obscura presence x the three lane
    states, every handoff for a `browserWindow` surface is equal to the one this change
    replaced except for the added fields — same `use`, `why`, `url`, `urlUnavailable`, `notes`,
    `commands`, `caveats` and `toolUnavailable`.
11. `flags` is present exactly when the handoff points at an instrument — a named lane, or a
    web-app window — and absent otherwise; it is identical across the two detail levels of one
    handoff and is the same value for one instrument on every page.
12. The five flags take their documented values for all three instruments: Obscura
    (`actsOutsideThisWindow`, `outsideTheAuditTrail`), browser-use (all five), and Proctor on a
    web app (`canActAsThisPerson` only).
13. Flags do not replace prose: for each named lane, every flag set true has its subject stated
    in that lane's `boundary`, `continuity` or `caveats`.
14. PRO-0024's gate still holds over the new fields: with `PROCTOR_SECOND_LANE` unset the
    string `browser-use` appears in no encoded tool result at all, across the full sweep,
    including `flags`, `surface` and a web-app window.
15. The encoded handoff gains exactly two keys and loses none, and the four output schemas that
    document `browser` document both.
16. `proctor_apps` list and attach carry `surface` and `flags` end to end through the encoded
    JSON, from an injected environment rather than the process's own.

## Assumptions recorded in place of questions

- `[Decision]` **An installed web app is an application window Proctor drives**, not a browser
  tab and not an ambiguity handed to the caller. Argued from the Electron boundary PRO-0020
  already drew and from the cold cookie jar; the "no toolbar" argument was falsified and
  dropped.
- `[Decision]` **It still discloses, keeps its URL, and names no tool** in `continuity`.
- `[Decision]` **The live-session lane is not named for a web app.** Out of scope by this
  item's own terms, and it would resurrect a rule PRO-0024's critic deleted. Logged as child
  work with the counter-argument attached.
- `[Decision]` **The engine is not measured.** The available measurement decides on a
  brand-name heuristic that would demote Vivaldi, Opera and Arc, none installed here to check.
- `[Decision]` **Deriving `chromiumFamily` removes the second fact; it does not stop drift**,
  and the spec says so rather than claiming otherwise.
- `[Decision]` **Five flags, uniform polarity, object not array, on the instrument** — including
  Proctor itself for a web app, which is where the live-session risk actually is.
- `[Behaviour]` **`canActAsThisPerson` states a capability, not an invocation.** Proctor cannot
  see which profile the operator will use, and a flag the same payload's caveats falsify is
  worse than none.
- `[Behaviour]` **Safari's web-app bundle id forms are documented, not measured** — no web apps
  exist on this machine. Wrong, they change nothing; right, they fix a window that discloses
  nothing today.
- `[Behaviour]` **`app` is never a release channel**, so the marker cannot swallow a channel
  variant; a closed channel list was rejected because it would swallow a future one.
- `[Behaviour]` **The manual-accessibility flag is applied for a web-app bundle id**, because a
  shim's framework directory is empty by construction and the existing probe cannot see through
  it.
- `[Scope]` **`urlUnavailable` keeps its name.** It is now used only for its actual meaning on
  the web-app path; the browser-window overload is untouched.
- `[Cost]` **A web-app row appears on every `proctor_apps` list entry for an installed web
  app.** One small object per row, on the surface where an instrument is chosen.

## Child work found, not built here

- **Naming the live-session lane for a Chromium installed web app.** Both out-of-family passes
  argued for it and the second sharpened it: a Chromium web app is still an `--app-id=` renderer,
  so its URL, its JavaScript and CDP all work, while the accessibility tree over a single-page
  or canvas application — Figma being the obvious one — does not. Suppressing every lane there
  uses the weaker tool's failure to hide the stronger one. Against it: PRO-0024's critic deleted
  that lane as a fallback for ordinary web content, and a web app is an ordinary page in
  application clothing. A real decision, not a silence, and it belongs to whoever owns the lane's
  scope rather than to this item.
- **A real engine probe.** `isChromiumBased`'s brand-name framework match is a heuristic this
  change declines to promote to an authority, and it is wrong for a web app shim by
  construction. A probe reading a bundle's Info.plist or its loaded images, verified against
  Vivaldi, Opera, Arc and a shim, would let the catalogue stop declaring the engine at all.
- **`continuity` names Obscura on a no-lane browser window.** `continuity(for: lane ?? .obscura)`
  hands a deny-listed or `file:` handoff Obscura's cookie-jar sentence when no lane was named.
  Fixed here for the web-app surface only, because fixing it for browser windows would change
  the output this item promises not to change.
- **`urlUnavailable` carries four kinds of reason** and is named for one of them. Free to
  rename, since nothing on this object has reached a release, but it is a wire change of its
  own.
- **The routable internal-scheme list is global rather than per-window.** A `brave://` or
  `vivaldi://` page in a Chrome window counts as browser-internal, and the second lane drives a
  real Chrome where that page does not exist. Inherited from PRO-0024's hand-written list
  rather than introduced here, and narrowing it to the window's own row would change which
  windows route, which this item is not allowed to do. A test pins the membership so it cannot
  drift in the meantime.
- **The accessibility warm-up flag is set on the shim, not on the browser that owns the
  window.** A Chrome app shim may hand off and self-terminate, in which case the window belongs
  to the parent browser and the flag never needed setting; where the shim stays, poking it is
  not obviously the same as poking Chrome. Neither is measurable without a web app installed
  here.
- **Proctor could record that it recommended a lane**, and does not. Carried forward from
  PRO-0024.
- **`proctor_stability` still does not know a page is page content.** Carried forward from
  PRO-0020 and PRO-0024.
- **`SessionDoctor`'s Screen Recording probe can hang the whole test process.**
  `SCShareableContent.excludingDesktopWindows` is bridged through a checked continuation with no
  timeout, and when the ScreenCaptureKit daemon does not answer it leaks the continuation and
  the run never summarises. Reproduced on unmodified `main`, so it predates this item; it makes
  `swift test` unrunnable to completion on a loaded machine, which is a real cost to every
  future change. A timeout around the probe, answering `false` on expiry the way the existing
  `catch` already does, would fix it.

## What a test cannot reach here

Machine-witnessable from `swift test`: every clause above, against injected lanes, an injected
environment and the existing fake AX engine.

**Not witnessable, and reported as code-complete rather than proven:** that a real Chrome
installed web app's bundle id has the `com.google.Chrome.app.<hash>` form and a channel build's
the `com.google.Chrome.canary.app.<hash>` form; that Safari's is `com.apple.Safari.WebApp`
with a site and UUID after it. No web apps are installed on this machine and the reader's
standing instructions do not call for installing one, so both come from documentation. Also
not witnessable: that a web app window's accessibility tree contains a web area; that the
manual-accessibility flag makes a shim's tree appear; and whether a given shim self-terminates
after handshake, in which case the window is Chrome's and identification never sees the web-app
form.

## Out-of-family review

Spec reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15, no downgrade.
Ten defects; **nine changed the design** and are folded in above. The four that changed it most:

1. **The flags were on the binary, not the work.** With flags only on a named lane, the one
   path that acts in the person's live signed-in session — Proctor driving their installed
   Gmail window — carried none, so a host refusing `canActAsThisPerson` would block the
   autonomous lane and wave that through. Flags now describe the instrument, Proctor included.
2. **The prefix rule missed every web app on a channel build.** `com.google.Chrome.canary.app.<hash>`
   has remainder `canary.app.<hash>`, which does not begin with `app.`. Matching moved to a path
   component.
3. **Identification could not have passed its own clause.** Safari, Chromium and Vivaldi are
   exact-match rows, so `com.apple.Safari.WebApp.<uuid>` matched nothing; promoting them naively
   makes `com.operasoftware.Opera` eat `com.operasoftware.OperaGX`. One table, longest prefix
   wins.
4. **The "no toolbar, so the whole window is the page" pillar is false.** Safari web apps ship a
   navigation toolbar; Chrome and Edge have a tabbed application mode. The pillar is gone and
   the web-area boundary is unchanged.

Also adopted: keep the URL on a web-app handoff rather than suppressing it; give the web app its
own `continuity` instead of Obscura's; run the URL rules so a PDF or `file:` payload in a web
app keeps its existing advice; apply the manual-accessibility flag for a shim, whose framework
directory is empty by construction; rename the credential flag to state a capability rather than
an invocation the caveats themselves falsify; stop claiming the derivation solves drift; and
split the scheme list in two, since the first draft required an owning row for schemes that have
none.

**Answered rather than adopted.** The review would name the live-session lane for a Chromium web
app. The argument is good and it is out of scope twice: it resurrects the fallback rule
PRO-0024's completeness critic deleted, and this item's terms are what is reported and how a
browser is identified, not which windows reach a lane. Recorded as child work with its argument
rather than dismissed. The review's related point that "hosts only have two cases" was false is
accepted, and the machine-readable no-lane reason stays cut on the corrected ground that
`surface` already is that discriminator.

## Plan review, out of family

Plan reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15. Three
findings; **two changed the design before any code was written**, and one sharpened a child
item. The first two attempts hit the measured limit — a prompt that leaves the reviewer to find
the code spends its whole budget searching and returns nothing, which is a lane failure and not
a pass. The third attempt inlined the catalogue verbatim, forbade file reading, and answered in
one round. No downgrade; the gate ran out of family.

1. **Merging the exact and prefix tables was the wrong fix, and it broke this item's own
   constraint.** Longest-prefix-first is not what changes answers — promoting an exact row to a
   prefix is, because every descendant of it starts identifying. `com.apple.Safari.SafeBrowsing.Service`
   and its siblings would have become Safari. Replaced with a marker split in front of the
   untouched lookup, which is a strictly smaller change and leaves every markerless id on
   exactly today's path.
2. **The marker comparison should be case-insensitive**, since Safari spells it `WebApp` and
   nothing guarantees the case of a form nobody here has measured. Adopted. The reviewer also
   confirmed no shipping bundle id carries a bare `app` or `WebApp` component that is not a web
   app, so the false-positive surface is empty, and identified the false negative worth naming:
   a `--app=<url>` window keeps the plain browser id and cannot be told from a tab.
3. **The strongest case against no-lane** is a canvas or single-page web app, where the URL and
   CDP work and the accessibility tree does not. It does not reverse the decision, for the two
   scope reasons already given, but it is now the sharp end of the child item rather than a
   general argument.

## Completeness critic, out of family

Reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15, no downgrade,
against the built change. Six findings; **three changed the code after it was working**, and
the first is the one that mattered:

1. **The warm-up flag was keyed on the wrong predicate.** Setting Chromium's
   `AXManualAccessibility` for any installed web app runs the Chromium accessibility dance
   against a **Safari** web app, whose empty framework directory means exactly what the probe
   says it means. The predicate is now Chromium-family web app, not web app.
2. **The marker split could take an identifier away from the catalogue.** If a browser's own
   bundle id ever carries a non-leading `app` component, splitting at it produces a base that
   matches nothing and the browser stops being recognised. No row does today. The split is now
   tried first and falls back to the untouched lookup on the whole identifier, so it can only
   ever add an answer.
3. **A host could read the web-app flags as the bounded-reader shape.** `autonomous` and
   `billed` are both false there, and a rule built from those two being false would wave
   through Proctor clicking around somebody's signed-in mail. The schema now names
   `canActAsThisPerson` as the flag that answers that question and says plainly that the other
   two do not. The reviewer's own fix, collapsing the five booleans into one `instrument` enum,
   is rejected: it puts the host back to hard-coding instrument names, which is the thing the
   brief asked to stop.

Also adopted, as documentation rather than code: **the fixture proves the old grid did not
move and does not validate the new path**, which is what it was built to do and is now said in
the test's own header rather than left to be inferred. And the global scheme list and the
shim-versus-parent question are logged as child work above.

**Answered rather than adopted.**

- *Drop the URL from a web-app handoff, since keeping it invites a host to point a browser tool
  at the same origin.* The spec review argued the opposite from the same evidence, and its
  argument stands: the address names the site this window is, and withholding it forces a model
  that disagrees with Proctor back onto guessing. The prose says a browser tool would be a
  signed-out visit to the same site.
- *The deny list never sees a web app, so a credential site installed as an app loses it.* The
  deny list is about the browser's **own** configuration and credential pages, which an
  installed web app cannot navigate to; it never covered `http(s)` origins, so nothing is lost.
- *Emit a `toolUnavailable`-shaped object so old hosts keep switching on it.* `toolUnavailable`
  means the tool Proctor would have named is missing, which is false here. `surface` is the
  field that carries this, and the schema says to read it.
- *Keep a tool-agnostic private-network warning on a web-app handoff.* Emitting tool-specific
  advice on a handoff that names no tool is the defect PRO-0024 fixed when it lane-gated the
  notes. A private-network installed web app is a narrow case and the note names Obscura by
  name; the PDF and not-a-page advice, which is genuinely tool-agnostic, does survive.

## Progress — 2026-08-15

Built on `ai/pro-0035` in `.worktrees/PRO-0035`. **680 tests / 84 suites green**, run three
times with the same count, `swift build` clean from scratch with no warnings.

**A note on the count, because it is not the whole suite.** Three agent suites are skipped:
`ObscuraPresenceWiringTests`, `BrowserLaneWiringTests` and `TakeoverWiringTests`. Four tests
across them call `session.doctor`, whose Screen Recording probe is
`SCShareableContent.excludingDesktopWindows`, and on this machine that call does not come back:
the run prints `SWIFT TASK CONTINUATION MISUSE: leaked its continuation without resuming it` and
hangs before the summary. **It is not this change.** The same filter on unmodified `main`
hangs identically, with zero tests started after twenty minutes, and the hang moves between
tests run to run rather than landing on a fixed one. The 16 other tests in those three suites
have all been observed passing during this work. Logged as child work below.

**What shipped.** In `BrowserTarget.swift`: `BrowserSurface`; `internalScheme` replacing
`chromiumFamily` as the stored fact with `chromiumFamily` computed from it; the web-app marker
split in front of the untouched exact-then-prefix lookup; a two-part derived scheme list;
`BrowserLaneFlags` with its three instrument values; `surface` and `flags` on `BrowserHandoff`;
rule 0 lifted verbatim into `readURL` so the web-app branch reads a URL the same way; the
web-app branch and its three strings; one clause added to the Obscura lane's `continuity`, so
the `outsideTheAuditTrail` flag has prose behind it. One condition in `AXEngineImpl` for a
Chromium web-app shim. The four output schemas, README and CHANGELOG.

**Clause to test.** 1-9 and 11-14 to `Tests/ProctorCoreTests/BrowserSurfaceTests.swift`
(15 tests); 10 and 15 to `Tests/ProctorCoreTests/BrowserRoutingBaselineTests.swift`; 14 and 16
to `Tests/ProctorAgentTests/BrowserSurfaceWiringTests.swift`. PRO-0020's, PRO-0023's and
PRO-0024's suites move to the new `KnownBrowser` spelling and are otherwise untouched.

**The routing fence is the load-bearing evidence.** Before a line of source changed,
`BrowserRoutingBaselineTests` recorded 396 handoffs — 3 browsers x 10 URL classes x 2 Obscura
states x 3 lane states x 2 detail levels, plus the app-level case — from the code as it stood,
into a committed fixture, and was confirmed green against it. Every later step had to keep it
green. It caught one real thing during the work and one artefact: the artefact was a
serialisation difference (`JSONSerialization` escapes a forward slash where the generator did
not), fixed by putting both sides through the same serialiser rather than by relaxing the
comparison. What it does **not** do, said here because the critic was right to press on it: it
proves the old grid did not move, and it does not validate the new path. The new path is
covered by the clause tests.

**The tests were shown to bite.** They were written after the source and passed first time, so
the marker-scan floor was mutated from index 1 to index 0 — the trap that would file Zen as a
web app — and three tests failed. Restored, and the fence stayed green throughout.

**Not machine-witnessable here.** That a real Chrome installed web app's bundle id has the
`com.google.Chrome.app.<hash>` form, that a channel build's has the
`com.google.Chrome.canary.app.<hash>` form, and that Safari's is `com.apple.Safari.WebApp` with
a site and UUID after it: no web app is installed on this machine and installing one was not
part of the ask, so all three come from documentation. Also unverified: that a web app window's
tree contains a web area, that the warm-up flag makes a shim's tree appear, and whether a given
shim self-terminates after handshake. Code-complete and unverified, not proven.

**Reviews.** Spec review, plan review and completeness critic all ran out of family on
`grok-4.6` (`--effort xhigh --sandbox read-only`), no downgrade. All three changed the design.
The plan review's first two attempts returned nothing and hit the deadline; the prompt was
rewritten to inline the evidence and forbid file reading, which is the measured failure mode
this repo already documents. The three passes between them reversed the flag placement, killed
a table merge that would have made Safari helper services identify as Safari, falsified the
"a web app has no toolbar" premise the decision first rested on, and caught a warm-up predicate
that would have run the Chromium accessibility dance against a WebKit process.
