# Proctor and Cua: hand over the hands, keep the verdict

**Run** `dr_c02ada57a96b5f68` · free local panel, six tasks, 42 sources, 13 domains · **as of 2026-08-15**

---

## Executive summary

- **Cua Driver subsumes Proctor's actuation layer, and the overlap is convergent rather than coincidental.** It is MIT across the whole monorepo including the driver and Lume, requires macOS 14+, and is under heavy active development: 1,444 commits in 26 weeks with the last eight weeks running 81, 15, 64, 113, 122, 134, 131 and 139 commits. **High confidence** — read from GitHub's own API and the LICENSE file rather than marketing. [8][9][10][6]
- **Three of Proctor's claimed differentiators survived a deliberate attempt to kill them, and are now measured rather than assumed.** Cua has no durable element handle, no capture-trustworthiness metadata, and no repeat-run determinism scoring. **High confidence** — each rests on Cua's own reference documentation. [39][40][1]
- **The strongest single finding: `element_token` is not a durable *semantic* selector.** It is an "Opaque per-snapshot element handle" bundling `element_index` and `snapshot_id`, and Cua treats staleness as a routine error with its own code and refresh instruction. **The narrowing matters and was forced by counter-review**: pixel-coordinate actions *do* replay cleanly in Cua, so replay is not broken, it survives by re-clicking absolute positions — which is precisely what a layout change breaks. **High confidence.** [1][39]
- **Cua's screenshots appear to carry no frame-status or completeness signal**, while Apple documents six `SCFrameStatus` values and requires a consumer to check before trusting a frame. Cua's only verification concept is action-level `effect`, which reports whether a click worked, not whether the image is a valid current frame. **Moderate confidence, downgraded by counter-review**: this rests on absence across three documents, and the `get_window_state` entry was not confirmed to have been read for screenshot metadata specifically. The Apple side rests on a 2022 page. [40][15]
- **The competitive niche is effectively empty, but so is the demand.** The three apparent competitors dissolve on inspection, and no first-hand account was found anywhere of anyone using a computer-use agent to QA an application and report results. **Moderate-to-high confidence on the emptiness; the absence was searched for properly rather than assumed.** [27][28][26][38]
- **Agent task-success rates bound what any of this can be.** macOSWorld puts proprietary computer-use agents above 30% overall and at 17–21% on basic System, File Management and Productivity categories. **Moderate confidence, and deliberately downgraded**: the arXiv entry has had a later version withdrawn by its author, so the figure should be re-checked against the current authoritative version before it is relied on. [41][37]

---

## Detailed findings

### 1. Hand over: the actuation layer

Everything Proctor does that clicks, types, captures, targets a window, finds an element, checks a grant or draws a cursor is now a macOS-only, single-maintainer version of something MIT-licensed with a hundred contributors.

The decisive evidence is not feature parity but **substrate adequacy**: `get_window_state` returns per-element `element_index`, `role`, `label`, `value`, `frame{x,y,w,h}`, `parent_index` and `depth`, and returns the accessibility tree together with a screenshot in one call. [1][2] That is enough structure for a third party to compute its own assertions on top, which was the open question that decided whether a testing layer could be built on someone else's driver at all.

Cua's justification for bundling the tree with the screenshot is worth quoting against ourselves: they do it as a cross-check, "because the tree lies on some surfaces". [2] That is Proctor's tri-observer premise, conceded by the tool it would sit on.

<INFERENCE from="[1][2][5]">Because Cua exposes geometry and pixels together and documents its own silent-failure modes, a verification layer built on it has both the inputs it needs and a ready-made set of defects to detect. The substrate question is answered affirmatively on documentation; it has not been proven by building anything.</INFERENCE>

### 2. Keep: what Cua genuinely does not do

**No durable selector.** This is the one that mattered most and it held. `element_token` is an "Opaque per-snapshot element handle" that bundles `element_index` and `snapshot_id` and "Returns an explicit stale error once a newer snapshot supersedes it", with `stale_element_token` a documented routine error carrying a refresh instruction. [1][39] Cua's replay accordingly cannot replay element-indexed actions at all. Apple's own platform offers the fix Cua does not use: `accessibilityIdentifier` is developer-set and documented as "Use this value for testing. It isn't visible to the user." [16] The cross-process constant `kAXIdentifierAttribute` has existed since macOS 10.7, though Apple documents its existence rather than its semantics or any stability guarantee — a real limit on how strong this claim can be made. [17]

**No capture trustworthiness.** Apple defines six `SCFrameStatus` values including `idle`, `blank`, `suspended` and `stopped`. [15] Nothing in Cua's documented surface carries frame status, staleness or completeness on a screenshot; its `effect` field verifies actions, not images. [40] The consequence is live rather than theoretical: Cua's screen-lock defect remains open, with a user reproducing `capture(app='Ghostty')` returning "0×0 pixels, with 746 AX elements — all of them are AXMenuBar / AXMenuBarItem", and the maintainers' own framing is that "the agent has no way to know any of it happened". [34]

**No determinism scoring — and nor does anyone else on this platform.** No repeat-run variance or first-divergence feature exists in Cua. [1] More importantly, the search for one across the whole native-macOS market came back empty: the pattern is standard in web and CI testing, where Google has described rerunning 24 projects' suites 10,000 times each, and it is absent for XCUITest, Appium-mac2 and Squish-Mac flows. [31] That 2016 source is stale and is cited only to establish that the practice is long-established elsewhere, not for any current claim.

**No out-of-process accessibility audit.** Apple's `performAccessibilityAudit` operates on an `XCUIApplication` from the caller's own UI test target, with no documented path to a separately-launched third-party app. [19] On macOS 14+ only six of its audit types apply — `action`, `contrast`, `elementDetection`, `hitRegion`, `parentChild`, `sufficientElementDescription` — while `dynamicType`, `textClipped` and `trait` carry no macOS availability at all. [22] Both pages are 2023-era or undated and are treated as documenting the API's shape rather than its current behaviour.

**No visual fidelity for native Mac apps anywhere.** Percy and Applitools cover browsers and mobile only [29]; VisWiz is explicitly bring-your-own-capture and "doesn't capture screenshots for you" [30].

**No in-process introspection.** Cua's app-hosted daemon is a TCC permission-identity mechanism, not an introspection API. [4] Apple's accessibility model exposes semantic properties — label, role, value, children — with no visual or style properties in the protocol. [18] <INFERENCE from="[4][18]">There is therefore no cross-process route to resolved colours, fonts or corner radii, which is why an embedded reflector remains the only way to measure visual fidelity against a design in an app you own. Apple never states this negative explicitly; it rests on the absence of any style attribute across the accessibility surface.</INFERENCE>

### 3. Beat: where a verification layer wins

The sharpest opportunity is that **Cua documents its own silent failures and does not detect them.** Minimized-window keyboard commits report success without committing; canvas surfaces silently no-op; coordinate mismatches fail without refusing, because "Nothing refuses, because the coordinates were structurally valid." [5] Off-Space SwiftUI windows return a tree containing "only the menu bar, or just the AXApplication root", while AppKit apps are unaffected. [5]

<INFERENCE from="[5][40][34]">Every one of those is a case where the driver reports success and the machine did nothing, which is precisely what a tri-observer disagreement check between tree, geometry and pixels is built to catch. The product is not a better driver; it is the instrument that tells you when the driver is lying. This follows from Cua's own limits and its lack of frame metadata; nobody has built or measured it.</INFERENCE>

Two market facts support the same position. Cua-Bench scores agents, not applications: its evaluator judges the environment state a trajectory reached, deliberately so it does not score "whether it copied one prescribed sequence of clicks". [3] And nobody, Cua included, publishes a driver-only reliability figure separated from model choice, though Cua does ship a verification contract of roughly forty evidence-bearing cells per harness application with deliberate violation injection. [42]

### 4. The risk that is not competition

The three apparent competitors do not survive inspection. `mac-use` has 4 stars, 13 commits all on one day, and no activity since 30 March 2026. [27] `mac-use-mcp`'s external traffic is bots, including a fix PR from an account holding 17,888 public repositories created under two months earlier, and an explicit directory-marketing issue. [38][28] OculiX is real and active but is a vision-matching SikuliX successor that "drives any graphical interface by what it looks like — not by accessibility hooks", so it is a different category. [26]

The problem is that the demand side is equally empty. No first-hand account was found of anyone using a computer-use agent to QA an application and report results, across Hacker News, GitHub and an archive pull returning 170 subreddit posts with zero mentions. Practitioner reports that do exist are about agents failing: typing into the wrong place and failing to drive a VM at all [32], and, in a neighbouring domain, an agent that "downloaded 3, hallucinated the rest, and reported success" [36]. Both are over 183 days old and are cited as illustrative rather than current.

<INFERENCE from="[41][37][36]">If proprietary agents complete 17–21% of basic desktop tasks, an agent cannot be the actuator in a deterministic test suite. That does not remove the opportunity; it relocates it. The value is in measuring nondeterminism rather than in producing it, which is an argument for the determinism scorer being the lead feature rather than a supporting one.</INFERENCE>

### 5. Depending on Cua

Encouraging: one root MIT licence covers the driver and Lume with no dual-licence split [10]; 652 PRs merged in 90 days from authors other than the two core committers [11]; commit cadence accelerating [9]. The commercial product is sales-led infrastructure layered on the free driver rather than a paywalled driver [12].

Cautionary: YC X25, founded 2025, **stated team size of three** [7]. Every named production user is self-reported with no confirmation from any of the four companies [12]. Press coverage is confined to newsletters restating the README [13]. Reported funding traces only to aggregator databases with no primary announcement.

---

## Evidence table

| Question | Answer | Sources | Confidence |
|---|---|---|---|
| Can a testing layer be built on Cua's surface? | Yes, on documentation: per-element geometry plus pixels in one call | [1][2] | High (documented, unbuilt) |
| Does Cua have a durable selector? | No — per-snapshot token with a stale error | [1][39] | High |
| Does Cua report capture trustworthiness? | No frame-status or completeness metadata | [40][15] | High |
| Does Cua score determinism across runs? | No, and nor does any native-macOS tool | [1][31] | High / Moderate |
| Can Apple's audit reach a third-party app? | No documented path; 6 of 9 audit types on macOS | [19][22] | Moderate (undated pages) |
| Does Cua-Bench score apps under test? | No — it scores agents | [3] | High |
| Is the niche occupied by a real competitor? | No; all three candidates dissolve | [27][28][26][38] | Moderate-high |
| Is anyone doing agent-driven app QA today? | No evidence found | (gap, see below) | Moderate |
| Is Cua safe to depend on? | Licence and governance yes; team size three | [10][11][7][12] | Mixed |

---

## Knowledge gaps

- **No first-hand account of agent-driven QA exists in the searched corpus.** This is an absence, established by real searching including an archive pull, not a proof that nobody does it. Cua routes community discussion to a Discord that is not web-searchable, so an unknown share of experience is structurally invisible to this method.
- **`element_token`'s internal encoding was not read from source.** Its behaviour and lifetime are documented authoritatively; how the opaque value is constructed was not established.
- **Issue 1745 is current only to 2026-08-13.** A fix could have landed since.
- **The macOSWorld figure carries a withdrawal caveat.** A later version was withdrawn by the author; re-check before relying on the number.
- **Source profile is skewed by classification, and the ticks understate it.** The profile reports 5% official-or-academic against a 30% floor, but 37 sources are classed "other" including every `developer.apple.com` and `api.github.com` URL, which are primary. The largest single domain is 29% against a 25% ceiling, which is cua.ai in a study of Cua. Read the mix, not the ticks.
- **Twelve sources carry no readable publication date.** Undated is not current.

---

## Counter-review, and the two findings that change the plan

Four adversarial lenses were run against this report. Nine issues, five high severity.
Two of them are load-bearing and are answered here rather than buried.

### The substrate tension — the strongest argument against the whole plan

Section 1 concludes the substrate is adequate because Cua exposes tree and pixels
together. Sections 2 and 3 establish that **the tree lies on some surfaces** [2],
that off-Space SwiftUI windows return only a menu bar [5], and that **the screenshot
carries no frame-status metadata** [40]. A verification layer needs at least one
trustworthy channel to verify the others against. If the tree is unreliable and the
pixels arrive with no completeness signal, the tri-observer check has no reliable
third leg and the layer inherits the defects it exists to detect.

<INFERENCE from="[2][5][40][15]">This does not kill the plan, but it changes its
architecture and its order. Proctor cannot be a pure consumer of Cua's surface: it
needs its own ScreenCaptureKit path so that frame status is known at the point of
capture, because Apple's own documentation makes checking that status a precondition
of trusting a frame. The correct shape is Cua for actuation and Proctor for
observation, not Cua for both with Proctor computing on its outputs. That inverts the
"build entirely on top" reading and is the single most consequential thing in this
document.</INFERENCE>

### The niche is narrower than "empty"

Saying the niche is empty while also establishing that Appium's Mac2 driver [23] and
Squish [24] test native Mac apps without source access is a contradiction the first
draft did not state its way out of. The honest claim is narrow and should be written
narrowly: **no tool on this platform packages repeat-run determinism scoring, native
visual fidelity, or out-of-process accessibility auditing** — and the incumbents are
the real competitive set, not the three abandoned MCP repos. Appium and Squish are
maintained, have users, and could add repeat-run scoring without inventing anything.
The Squish evidence is also a year old and was not re-checked for 2026 currency.

### Three further corrections applied above

- "No durable selector" was overstated; pixel-coordinate replay works in Cua, so the
  claim is now about *semantic* selectors only.
- The frame-status claim was downgraded from High to Moderate: it rests on absence in
  a partially-searched surface.
- Every claim about what Cua lacks comes from cua.ai, 29% of the registry, and no
  third party has verified the documented surface against the shipped binary. Vendor
  documentation is the weakest possible authority on vendor absences.

### Perishability, which the first draft ignored

This report establishes that Cua ships 130+ commits a week and is accelerating [9],
then rests its recommendation on capability absences observed on a single day. **Every
differentiator named here is perishable.** A verdict with no expiry is the wrong
artifact: this needs re-checking against the same four questions before any rebuild
ships, and again at each milestone. Treat the findings as current to 2026-08-15 and
to nothing later.



## Recommended next steps

1. **Adopt `cua-driver` for actuation and stop maintaining a second one.** The overlap is total and widening at 130+ commits a week. [9]
2. **Keep Proctor's own capture path.** Revised by counter-review: do not consume Cua's screenshots. Apple makes frame status a precondition of trusting a frame [15] and Cua surfaces none [40], so observation stays Proctor's and only actuation is handed over.
3. **Lead with the determinism scorer.** It is the only capability with no packaged equivalent anywhere on this platform, and the agent-reliability numbers make it the thing the category most needs. [31][41]
4. **Build the frame-trustworthiness and tri-observer checks as the wedge.** Cua's own limits page is the specification for what they must catch. [5]
5. **Prove the substrate by spike**, and make the spike specifically about the tension above: whether a trustworthy third channel exists at all when the tree is unreliable and the pixels are unlabelled.
6. **Verify Cua's absences against the shipped binary, not its documentation.** Every "Cua does not do X" here comes from cua.ai. Run `tools/list` against the real MCP server and read the live JSON schema.
7. **Test demand before building further.** The competitive risk is low and the demand risk is high, which is the opposite of what was assumed when this project started. This is the report's thinnest-sourced conclusion: three community sources out of forty-two.
8. **Re-run these four questions before any rebuild ships.** The differentiators are perishable at this commit cadence.
9. **Keep the reflector for apps you own.** It is the only route to resolved visual values, and no cross-process alternative exists. [18][4]
