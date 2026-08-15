# PRO-0035: The browser catalogue stops guessing, and the handoff is machine-readable

**ID:** PRO-0035
**Status:** Triage
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

**A `com.google.Chrome.app.<hash>` window is an application window. Proctor drives it
natively, names no browser lane for it, and says so in one sentence.** Not a browser tab, and
not ambiguous.

The brief warns that the third reading is not automatically the honest one, and it is right:
an object that says "this might be a browser window and might be an app window" moves the
decision to a model holding strictly less information than Proctor has. Proctor knows the
bundle id, knows what that form means, and knows what it already does with the identical case
one shelf over. It should answer.

**The argument that settles it is consistency with a boundary this repo already drew.**
PRO-0020's whole point is that a web view inside a native Mac application is never routed —
that is the WKWebView/Electron boundary, and `webViewInsideANativeAppIsNeverRouted` is the
test that pins it. An Electron application *is* a Chromium browser rendering one origin's web
content in a window with its own bundle id, its own dock icon and its own session. Slack, VS
Code and Discord are exactly that, and Proctor drives all three natively without a word about
Obscura. An installed web app is the same shape, built by a different vendor's tooling:
a Chromium view hosting one origin, presented as an application. Routing the Chrome-installed
Slack to a browser tool while driving the Electron Slack natively is an inconsistency the
boundary cannot justify, and the user-visible difference between the two is nil.

**Two further facts, both checkable, point the same way.**

- **The boundary sentence is false for a web app.** It promises that "the native chrome around
  it — toolbar, tab bar, menus, sheets, the downloads popover — stays Proctor's." An installed
  web app window has no toolbar, no tab bar and no address field. Half the sentence describes
  nothing, and the half that remains tells a model to leave the entire window.
- **The recommendation is confidently useless.** Handing the window's address to Obscura opens
  that site in a different engine with no cookie jar. A site is installed as an app precisely
  because somebody uses it signed in, so the discontinuity `continuity` discloses is not an
  edge here; it is the normal case, and the advice fails at a login wall every time.

**What Proctor says instead, and why it says anything at all.** The purest form of "drive it
natively" is to identify nothing — return no handoff, exactly as an Electron app gets none.
That is rejected for the reason PRO-0020 rejected silence for `chrome://`: a model that reads
the bundle id `com.google.Chrome.app.abc123` will conclude *Chrome*, and Proctor staying quiet
leaves it to act on that conclusion believing Proctor had nothing to say. The bundle id is
Chrome-shaped and the window is not Chrome, which is a page-specific thing Proctor knows and
can state in one sentence. It is also not a behaviour change into silence: today this window
gets Chrome's full handoff, `use: "obscura"`, a URL and command templates.

So a web app window carries a handoff that names **no lane** — no `use`, no `commands`, no
`flags`, no `notes`, no `toolUnavailable` — whose `boundary` says it is an installed web app
window that Proctor drives as an application, and which carries `evidence` at **both** detail
levels rather than only the full one. The asymmetry against a browser window is earned: in a
browser window a step may target native chrome, so the render-tree caveat is conditional; in a
web app window every step is into page content, so it always applies.

### The identification bug is the prefix rule treating a hash as a release channel

`identify` matches `com.google.Chrome` and accepts **any** remainder as a channel variant,
which is how `.canary`, `.beta` and `.dev` are covered without enumerating them. A per-site
app's remainder is `app.<hash>`, so it is read as a channel of Chrome. That is the whole
defect, and the fix is to stop treating one particular remainder as a channel:

- remainder empty → the browser itself;
- remainder begins `app.` (Chromium browsers) or `WebApp.` (Safari) → an installed web app
  hosted by that browser;
- any other remainder → a channel variant, exactly as today.

A **closed list of channel words was considered and rejected**: a channel Chrome ships next
year would then identify as nothing at all and lose PRO-0020's disclosure entirely, which
trades a known bug for an unknown one. `app` is never a channel name, so the targeted marker
costs nothing and regresses nothing.

Safari's form is `com.apple.Safari.WebApp.<uuid>` and is **documented rather than measured** —
no web apps are installed on this machine, so nothing here verified it. Including it is
upside-only: `com.apple.Safari` is an exact-match row and not a prefix rule, so a Safari web
app identifies as nothing today and discloses nothing. If the form is right the window gains a
correct answer; if it is wrong, behaviour is what it already is.

### `chromiumFamily`: derived from one fact per row, because measuring it would be a worse guess

**The obvious answer — measure the engine from the app bundle — was tried against real bundles
and fails.** `AXEngineImpl.isChromiumBased` already reads `Contents/Frameworks` and is the
natural authority: an app that ships a Chromium framework is Chromium whatever a table written
in August 2026 says, and Opera changing engine would change Proctor's answer with no edit.
Measured on this machine: Chrome ships `Google Chrome Framework.framework` and Safari ships no
`Frameworks` directory at all, so both answer correctly. But that function decides on a
**brand-name heuristic** — a framework whose name contains `Chrom`, `Edge` or `Brave` — and
Vivaldi, Opera and Arc name their frameworks after themselves. None of the three is installed
here to check, which is the point: adopting the measurement would demote three browsers the
table currently gets right, on the strength of a second guess about framework naming that this
machine cannot settle. Replacing a declared fact with a differently-declared one is not the
improvement the brief asked for.

**So the fact is derived rather than measured, and the derivation removes the second fact
entirely.** `chromiumFamily` was always a proxy for one question — does the page in front of
Proctor exist in the browser the second lane drives — and the precise per-row fact behind it is
which internal scheme namespace that browser owns. Chrome and Chromium own `chrome`, Edge owns
`edge`, Brave `brave`, Vivaldi `vivaldi`, Opera `opera`, Arc `arc`; Safari, Safari Technology
Preview, Orion, DuckDuckGo, Firefox, Firefox Developer Edition, Firefox Nightly and Zen own
none, because their internal pages are `about:` pages and `about:` is deliberately not a
routed scheme.

So `KnownBrowser` carries `internalScheme: String?` in place of `chromiumFamily: Bool`, and
`chromiumFamily` becomes a computed property — `internalScheme != nil`. One fact per row where
there were two, and the two can no longer disagree because there is only one. `internalSchemes`
becomes derived the same way: the shared Chromium set (`chrome`, `chrome-extension`,
`chrome-untrusted`, `chrome-search`, `chrome-native`, `chrome-error`, `isolated-app`,
`devtools`) plus every row's own scheme, so a scheme cannot exist without an owning browser and
a browser cannot own a scheme the router has never heard of. Adding a browser stays one line
and now answers both questions with it.

**Routing behaviour is identical for every browser in the table**, before and after, and a
clause asserts it. This is a change to how the fact is stored and derived, not to which windows
route.

### The flag set: five booleans, true always meaning "this is a thing to weigh"

The brief's third weakness is the real wire change. `why` names the rule that fired — a fact
about a scheme — while what the caller is being handed is a lane with a blast radius, and a
host that wants to refuse an unaudited or credential-holding lane has to read English written
for a person.

`flags` is an object on the handoff, present **exactly when a lane is named** and carrying all
five keys every time. An object rather than an array of set names, because a host reading
`flags.autonomous` must be able to tell `false` from "this Proctor does not know that flag";
an array collapses the two and a wire contract hosts gate on cannot afford that.

Polarity is uniform — **true means the risk is present** — so a host's rule is "refuse if any
flag I care about is true" rather than a per-flag lookup of which way round it reads.

| Flag | obscura | browser-use | What a host may conclude |
|---|---|---|---|
| `actsOutsideThisWindow` | true | true | The lane acts in its own browser, not the window Proctor is attached to, so nothing it reports is evidence about this window. |
| `autonomous` | false | true | The lane decides its own steps; what happens between the ask and the answer is not enumerated in advance and cannot be reviewed before it runs. |
| `actsAsThisPerson` | false | true | In its default mode the lane acts with the browser session of the person at this machine, on every origin they are signed in to. |
| `outsideTheAuditTrail` | true | true | Nothing the lane does appears in Proctor's audit trail, so the trail is not a complete account of what happened to this page. |
| `billed` | false | true | The lane needs a model credential and a run costs whatever that model costs. |

What a host may **not** conclude, stated because a flag that is read as a verdict is worse than
prose: a true flag is not a claim that the lane is unsafe, and a set of five false flags is not
a claim that a lane is safe. They are the facts Proctor holds about what taking the advice
commits the caller to, and nothing beyond that.

**Two flags are true on both lanes today, and that is deliberate rather than an oversight.**
A constant field looks like noise until you ask who reads it: the point of a machine-readable
set is that a host gating on "nothing unaudited" must not have to hard-code the string
`browser-use`, and a third lane may well answer differently. A host that has to know the lane
names to interpret the flags has been handed prose with braces around it.

**The flags never replace the prose and never carry anything the prose does not.** `boundary`,
`continuity` and `caveats` still say all of this in sentences, because a model reads those and
a host reads the flags. The flag set is a pure function of the lane — identical at both detail
levels and on every page — which is what makes that promise checkable.

**A machine-readable reason for the absence of a lane was designed and cut.** A `noLaneReason`
enum would let a host branch on deny-listed versus not-a-page versus partly-read. It is cut
because `use == null` and `toolUnavailable` already separate the only two cases a host acts on
differently — there is advice and there is none, and where there is none the tool may or may
not be missing. Branching further changes nothing a host would do, and every unused enum case
is a wire commitment.

### `surface`: the machine-readable half of the PWA decision

One string on the handoff, always present: `browserWindow` or `installedWebApp`. It is the
identification answer this item exists to fix, expressed so a host does not parse a sentence to
find it, and it is on a different subject from the flags — the flags describe the lane, this
describes the window.

`browser` stays the host browser's own name (`Google Chrome`) rather than becoming
`Google Chrome web app`. It is an identity field and the browser hosting the window really is
Chrome; the distinction belongs in `surface` for a machine and in `boundary` for a reader, and
`boundary` leads at both detail levels so it is the first thing seen either way.

## Scope

**In.** `surface` on `KnownBrowser` and on `BrowserHandoff`; the `app.` / `WebApp.` marker in
`identify`; the web-app branch in `handoff`, ahead of the ladder; `internalScheme` replacing
`chromiumFamily` as the stored fact, with `chromiumFamily` computed and `internalSchemes`
derived; `BrowserLaneFlags` and the `flags` field; the four output schemas; README and
CHANGELOG.

**Out.** Any change to how a lane is chosen — the scheme list, the deny list, rule 0's
silent-area guard, the second lane's gate, `PROCTOR_SECOND_LANE`, the Obscura default.
Measuring a browser's engine. A machine-readable no-lane reason. Renaming `urlUnavailable`.
Any new tool verb, actuation plane, or change to settling, hashing or the audit trail. Driving
a web app any differently from any other application — the point of the decision is that
nothing about actuation changes.

## Behaviour

### Identification

`KnownBrowser` gains `surface` and trades `chromiumFamily` for `internalScheme`. `identify`
matches as it does today, then reads the remainder after the matched prefix: `app.<anything>`
or `WebApp.<anything>` yields the same row with `surface: .installedWebApp`; anything else
yields `surface: .browserWindow`. An exact-match row is always a browser window, since an exact
id has no remainder.

### The handoff

`surface` is on every handoff at both detail levels. `flags` is on a handoff exactly when `use`
is, at both detail levels, with all five keys.

A handoff whose `surface` is `installedWebApp` short-circuits the ladder entirely: no lane, no
`url`, no `commands`, no `flags`, no `notes`, no `toolUnavailable`, whatever the page's scheme
and whatever either tool's state. `boundary` says what the window is and that Proctor drives
it; the reason rides in `urlUnavailable` beside PRO-0024's `notAnInstrument`, which is the
established place for "the address is readable and neither tool is the instrument for it".
`continuity` keeps Obscura's sentence, because it remains the true statement about what handing
this address to a browser tool would do. `evidence` is present at both detail levels.

### Everything else

Unchanged, and asserted to be unchanged.

## Acceptance clauses

1. `com.google.Chrome.app.<hash>` identifies as an installed web app hosted by Google Chrome
   and never as Chrome itself; so do the `com.brave.Browser.app.`, `com.microsoft.edgemac.app.`,
   `org.chromium.Chromium.app.` and `com.vivaldi.Vivaldi.app.` forms, and
   `com.apple.Safari.WebApp.<uuid>`.
2. Channel variants are untouched: `com.google.Chrome.canary`, `com.google.Chrome.beta`,
   `com.brave.Browser.beta`, `com.microsoft.edgemac.Dev` and `org.mozilla.nightly` still
   identify as their browser with `surface` `browserWindow`; `com.google.ChromeRemoteDesktop`
   still identifies as nothing.
3. A web-app window names no lane at any detail level: no `use`, no `why`, no `commands`, no
   `flags`, no `notes`, no `toolUnavailable`; `boundary` says it is an installed web app window
   Proctor drives as an application; `evidence` is present at **both** detail levels.
4. A web-app window never reaches the ladder: a `chrome://settings` URL, an `https` URL, a
   `file:` URL, a private-network `.pdf` URL and no URL at all produce the same no-lane web-app
   handoff, under every combination of Obscura presence and the three lane states.
5. `surface` is present on every handoff at both detail levels and takes `installedWebApp`
   exactly for the bundle ids in clause 1 and `browserWindow` for every other catalogue hit.
6. `chromiumFamily` is computed from `internalScheme` and answers exactly as PRO-0024 clause 1
   requires: Chrome, Chromium, Edge, Brave, Arc, Vivaldi and Opera true; Safari, Safari
   Technology Preview, Orion, DuckDuckGo, Firefox, Firefox Developer Edition, Firefox Nightly
   and Zen false; channel variants inherit their rule's answer.
7. `internalSchemes` is derived, not listed: it contains the shared Chromium set and every
   catalogue row's own scheme, no scheme appears in it without an owning row, and every row's
   scheme appears in it.
8. **Routing is unchanged.** Across schemes x browsers x Obscura presence x the three lane
   states, every handoff for a `browserWindow` surface is equal to the one this change replaced
   except for the two added fields — same `use`, same `why`, same `url`, same `urlUnavailable`,
   same `notes`, same `commands`, same `caveats`, same `toolUnavailable`.
9. `flags` is present exactly when `use` is present, is identical across the two detail levels
   of one handoff, and is the same value for one lane on every page — a pure function of the
   lane.
10. The five flags take their documented values: on the Obscura lane `actsOutsideThisWindow`
    and `outsideTheAuditTrail` are true and the other three false; on the browser-use lane all
    five are true.
11. Flags do not replace prose: for each lane, every flag set true has its subject stated in
    that lane's `boundary`, `continuity` or `caveats`.
12. PRO-0024's gate still holds over the new fields: with `PROCTOR_SECOND_LANE` unset the
    string `browser-use` appears in no encoded tool result at all, across the full sweep,
    including `flags` and `surface` and including a web-app window.
13. The encoded handoff gains exactly two keys and loses none, and the four output schemas that
    document `browser` document both.
14. `proctor_apps` list and attach carry `surface` and, where a lane is named, `flags` end to
    end through the encoded JSON, from an injected environment rather than the process's own.

## Assumptions recorded in place of questions

- `[Decision]` **An installed web app is an application window Proctor drives natively**, not a
  browser tab and not an ambiguity handed to the caller. Argued above from the Electron
  boundary PRO-0020 already drew.
- `[Decision]` **It still discloses**, in one sentence naming no lane, because its bundle id is
  Chrome-shaped and silence leaves a model acting on that.
- `[Decision]` **The engine is not measured.** The available measurement decides on a
  brand-name heuristic that would demote Vivaldi, Opera and Arc, none installed here to check.
  Derivation from the row's own scheme namespace removes the second fact without adding a
  second guess.
- `[Decision]` **Five flags, uniform polarity, object not array.** Two are constant across both
  current lanes on purpose, so a host need not hard-code a lane name.
- `[Behaviour]` **Safari's web-app bundle id form is documented, not measured** — no web apps
  exist on this machine. Wrong, it changes nothing; right, it fixes a window that discloses
  nothing today.
- `[Behaviour]` **`app` is never a release channel**, so the marker cannot swallow a channel
  variant; a closed channel list was rejected because it would swallow a future one.
- `[Scope]` **`urlUnavailable` keeps its name** though it now carries a fourth kind of reason.
  Renaming a field is free here (nothing has shipped) but it is not this item's job, and the
  machine-readable answer to that overload is `surface` and `flags`, not a better noun.
- `[Cost]` **A web-app row appears on every `proctor_apps` list entry for an installed web
  app.** One small object per row, on the surface where an instrument is chosen.

## Child work found, not built here

- **A machine-readable reason for the absence of a lane.** Designed and cut above; if a host
  ever needs to branch on deny-listed versus not-a-page versus partly-read, that is the item.
- **A real engine probe.** `isChromiumBased`'s brand-name framework match is a heuristic that
  this change declines to promote to an authority. A probe that reads a bundle's Info.plist or
  its framework's own version, verified against Vivaldi, Opera and Arc, would let the catalogue
  stop declaring the engine at all.
- **`urlUnavailable` now carries four kinds of reason** and is named for one of them. Free to
  rename, since nothing on this object has reached a release, but it is a wire change of its
  own.
- **Proctor could record that it recommended a lane**, and does not. Carried forward unchanged
  from PRO-0024.
- **`proctor_stability` still does not know a page is page content.** Carried forward unchanged
  from PRO-0020 and PRO-0024.

## What a test cannot reach here

Machine-witnessable from `swift test`: every clause above, against injected lanes, an injected
environment and the existing fake AX engine.

**Not witnessable, and reported as code-complete rather than proven:** that a real Chrome
installed web app's bundle id has the `com.google.Chrome.app.<hash>` form, and that Safari's is
`com.apple.Safari.WebApp.<uuid>`. No web apps are installed on this machine; both forms come
from documentation. The Chrome form is the brief's own statement and the Safari one is upside
only. Also not witnessable: that a real web app window's accessibility tree contains a web area
covering the whole window, which is the assumption behind saying every step in one is into page
content.
