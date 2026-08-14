# Plan — PRO-0020: Route browser work to Obscura

**Spec:** docs/specs/spec-PRO-0020.md · **Branch:** ai/pro-0020 · **Tier:** Standard

## Shape

One pure module in `ProctorCore` decides everything; one narrow seam on `AXEngine` supplies the
only fact the agent cannot compute (is this node inside a web area, and what does the page say
its URL is); five call sites attach the result. Nothing in the actuation path, the settle path,
the hashing path or the audit path is touched.

## 1. `Sources/ProctorCore/BrowserTarget.swift` — new, pure

- `public struct KnownBrowser: Sendable, Equatable { name, bundleId }`.
- `public enum BrowserCatalogue { public static func identify(bundleId: String?) -> KnownBrowser? }`
  — exact matches first, then a prefix table for channel variants
  (`com.google.Chrome` + `.beta/.dev/.canary`, `com.microsoft.edgemac*`, `com.brave.Browser*`,
  `org.mozilla.firefox*`/`nightly`/`firefoxdeveloperedition`, `com.apple.Safari`,
  `com.apple.SafariTechnologyPreview`, `org.chromium.Chromium`, `company.thebrowser.Browser`,
  `com.kagi.kagimacOS`, `com.vivaldi.Vivaldi`, `com.operasoftware.Opera`,
  `app.zen-browser.zen`, `com.duckduckgo.macos.browser`).
- `public struct WebContentProbe: Sendable, Equatable { insideWebArea: Bool; urls: [String] }` —
  what the AX side reports. `urls` is distinct, in tree order.
- `public struct BrowserHandoff: Codable, Sendable, Equatable` with, in this order: `boundary`,
  `browser`, `bundleId`, `use`, `continuity`, `evidence?`, `url?`, `urlUnavailable?`,
  `commands?`, `caveats?`. Optionals are omitted by `JSONEncoder`, which is how brief and full
  differ on the wire.
- `public enum Detail { case brief, full }`.
- `public static func handoff(for: KnownBrowser, probe: WebContentProbe?, detail: Detail) -> BrowserHandoff?`
  — the whole decision:
  1. distinct URLs partition into http(s) and other;
  2. non-empty and **no** http(s) member → `nil` (the `chrome://` / PDF-viewer suppression);
  3. exactly one http(s) → `url`;
  4. zero URLs → `urlUnavailable: "AXURL was absent or empty on the web area."`;
  5. two or more distinct http(s) → `urlUnavailable: "The window holds several web areas with
     different URLs; Proctor does not pick one."`
  A `nil` probe (the app-level case, where no window was named) skips 1–5 and reports
  `urlUnavailable: "No window was named, so no page URL was read."`
- Constants: `boundary`, `continuity`, `evidence`, `caveats` (the seven, verbatim from the
  spec), `commands` (five templates, each containing the literal `<url>`), `webAreaRole =
  "AXWebArea"`. The URL never reaches a command or a sentence — a unit test asserts that with a
  hostile URL.

## 2. Seam — `Sources/ProctorAgent/Contracts.swift`

```swift
/// Where a window's web content sits, and what it says its URL is. Nil when the
/// window holds none. `node` narrows the question to one element's ancestry.
func webContent(window: String, node: String?) throws -> WebContentProbe?
```
Given a default implementation returning `nil` in a protocol extension, so no existing
conformance breaks.

## 3. `Sources/ProctorAgent/AX/AXEngineImpl.swift`

- `AXRead.url(_:_:)` in `AXValue+Convert.swift` — read `kAXURLAttribute`, accept a `CFURL`,
  return `absoluteString`.
- `webContent(window:node:)`:
  - with a node: walk **up** through `kAXParentAttribute`, bounded at 40 levels, stopping at the
    first element whose `AXRole` is `AXWebArea`; `insideWebArea` is whether one was found, and
    `urls` is that one element's `AXURL` if any.
  - without a node: walk **down** from the window element, bounded by the existing node/depth
    ceilings, collecting `AXURL` from every `AXWebArea` and not descending into one (a page's
    interior holds no second web area worth reading). `insideWebArea` is true when at least one
    was found; `nil` when none was.

## 4. Call sites

A single private helper on `Session`:

```swift
func browserHandoff(app: AppHandle?, window: String?, node: String?, detail: BrowserTarget.Detail) -> BrowserHandoff?
```
It returns `nil` immediately when `BrowserCatalogue.identify` does not match, so a non-browser
pays one dictionary lookup and no AX traffic. Wired at:

- `Session.listApps` — brief, per row, app-level (no window, so no probe).
- `Session.attach` — full, app-level.
- `Session.snapshot` — brief, `webContent(window:node: nil)`. Needs `browser: BrowserHandoff?`
  added to `Snapshot` in `Wire.swift` as a trailing defaulted field (one low-conflict hunk in a
  contended file).
- `Session.find` — brief; probes at most the **first three** matched nodes and stops at the
  first hit.
- `SessionAct.actInLane` — brief, merged into the existing `out` dictionary exactly once. Probes
  at most the first three node-bearing steps; a batch with any point-based step
  (`click`/`hover`/`dragPath` at coordinates) falls back to the window-level probe, so a page
  click discloses even though its target cannot be resolved.

## 5. Tests

`Tests/ProctorCoreTests/BrowserTargetTests.swift` — clauses 1, 6, 8, 9, 10: the catalogue and
its channel variants, the unknown/absent id, a hostile URL never reaching a command or a
sentence, the four URL outcomes including two-differing-web-areas, the non-`http(s)`
suppression, and brief-vs-full field presence with the shared `boundary` and `continuity`.

`Tests/ProctorAgentTests/BrowserRoutingTests.swift` — clauses 2, 3, 4, 5, 7 through `Session`
with `FakeAX`: a browser row marked in `list` and a non-browser row not; full detail on
`attach`; a snapshot of a browser window with a web area carrying the handoff and **the same
probe under a non-browser bundle id carrying none**; one handoff for a multi-step page batch
and none for a chrome-only batch; and an act into page content still performing its steps and
still reporting `plane: accessibility`.

`Fakes.swift` gains `var webContent: WebContentProbe?` and a `nodeRole` knob on `FakeAX`.

## 6. Docs

README gains a short "Browsers" subsection under the tool documentation. `CHANGELOG.md`
`[Unreleased] / Added` gains one entry, prose through `create-luke-content`.

## Risks

- **Wire.swift and CHANGELOG.md are contended.** Both edits are additive and small.
- **The parent walk is AX IPC per level.** Bounded at 40, gated behind the catalogue, and
  capped at three nodes per call.
- **`AXWebArea` on Firefox** may not be exposed; app-level disclosure still fires. Named in the
  spec, not solved.

## Revisions made during the build

Both review gates ran out-of-family on `grok-4.6` and both changed the design, so the plan above
is the shape it started in and this is what shipped:

- **The seam lost its `node:` parameter.** `webContent(window:)` returns every web area with its
  frame, and containment answers all three questions (is the window showing a page, is this
  element inside it, is this coordinate inside it) from one downward walk. The planned upward
  parent walk was one accessibility round trip per level of a DOM, per target.
- **A non-`http(s)` URL no longer suppresses the whole object**; it drops `use`, `url` and
  `commands` and keeps the disclosure. Suppressing it handed the page back to the accessibility
  plane in silence.
- **Only rendered web areas feed the URL decision.** A zero-sized or frameless area beside a real
  one would otherwise make "several web areas" the answer nearly every time.
- **No cap on targets.** `find` reads frames the walk already returned, so considering every
  match is free; `act` resolves each distinct node id once. The planned first-three cap missed a
  batch that starts in the toolbar and ends in the page.
- **The protocol default was deleted** rather than kept, so both conformances must implement the
  seam and a fake cannot make a positive assertion pass vacuously.
