# Plan — PRO-0035: The browser catalogue stops guessing, and the handoff is machine-readable

**Spec:** docs/specs/spec-PRO-0035.md
**Branch:** ai/pro-0035 (worktree `.worktrees/PRO-0035`)
**Size tier:** Small — two files in `ProctorCore`, one condition in the AX engine, four schema
strings, and the tests. No new dependency, no new tool verb, no new actuation.

## The baseline fixture comes first, because clause 10 is the whole risk

Clause 10 promises that routing did not move. The cheap way to say that is to re-read the
diff; the decisive way is to have the old code write down its answers before anything changes.

**Step 0, before any source edit.** Add `Tests/ProctorCoreTests/BrowserRoutingBaselineTests.swift`
with one test that walks the full sweep — 8 URLs (`https`, `http` private-network `.pdf`,
`chrome://newtab`, `chrome://settings`, `chrome-extension://…`, `file:`, `data:`, `about:blank`)
x 3 browsers (Chrome, Safari, Firefox) x 2 Obscura states x 3 lane states x 2 detail levels,
plus the no-probe app-level case — encodes each handoff with `.sortedKeys`, and compares the
result against `Tests/ProctorCoreTests/Fixtures/browser-routing-baseline.json`. Generate that
fixture from the current `main` code, commit it, and confirm the test is green **before**
touching `BrowserTarget.swift`.

After the change the same test decodes each object, removes the `surface` and `flags` keys, and
requires byte equality with the baseline. A routing change anywhere then fails a test that
cannot be argued with. This is the red→green for clause 10 in reverse — green first, and it
must stay green.

## Files

| File | Change |
|---|---|
| `Sources/ProctorCore/BrowserTarget.swift` | marker split, `BrowserSurface`, `internalScheme`, `BrowserLaneFlags`, the web-app branch, derived scheme list |
| `Sources/ProctorCore/ToolOutputSchemas.swift` | four `browser` descriptions gain `surface` and `flags` |
| `Sources/ProctorAgent/AX/AXEngineImpl.swift` | one condition on `needsFlag` |
| `Tests/ProctorCoreTests/BrowserSurfaceTests.swift` | new — clauses 1-9, 11-13 |
| `Tests/ProctorCoreTests/BrowserRoutingBaselineTests.swift` + fixture | new — clause 10, 15 |
| `Tests/ProctorAgentTests/BrowserSurfaceWiringTests.swift` | new — clauses 14, 16 |
| `Tests/ProctorCoreTests/BrowserTargetTests.swift`, `BrowserLaneTests.swift` | `KnownBrowser` construction moves to `internalScheme` |
| `README.md`, `CHANGELOG.md` | the two new fields |

## 1. The lookup is untouched; a marker split goes in front of it

The plan review killed the first draft's table merge. Promoting the exact rows to prefixes so
that `com.apple.Safari.WebApp.<uuid>` could match Safari also identifies every other descendant
of an exact row — `com.apple.Safari.SafeBrowsing.Service` becomes Safari — which changes a
non-web-app answer and breaks this item's own constraint. `exact` and `prefixes` therefore stay
exactly as they are, and only their value type changes (`chromium: Bool` becomes
`internalScheme: String?`).

```swift
public static func identify(bundleId: String?) -> KnownBrowser? {
    guard let bundleId, !bundleId.isEmpty else { return nil }
    let (base, isWebApp) = splitAtWebAppMarker(bundleId)
    guard let row = lookUp(base) else { return nil }          // today's exact-then-prefix body
    return KnownBrowser(name: row.name, bundleId: bundleId,
                        internalScheme: row.internalScheme,
                        surface: isWebApp ? .installedWebApp : .browserWindow)
}
```

`bundleId` on the returned value stays the **full** id, not the truncated base, because it is
what the app actually reports and a reader comparing it to `proctor_apps` output needs it to
match.

Scheme values: `chrome` for Chrome and Chromium; `edge`, `brave`, `vivaldi`, `arc`; `opera` for
both Opera and Opera GX; `nil` for Safari, Safari Technology Preview, Orion, DuckDuckGo, Zen
and all three Firefox rows.

## 2. The marker split

```swift
static func splitAtWebAppMarker(_ id: String) -> (base: String, isWebApp: Bool)
```

Split on `.`; scan components from index **1** for one that lower-cases to `app` or `webapp`;
the base is everything before it. No marker returns the id unchanged with `false`.

The index-1 floor is load-bearing: `app.zen-browser.zen` opens with a component `app`, and
scanning from zero would truncate it to the empty string and stop identifying Zen. Matching is
case-insensitive because Safari spells it `WebApp` and no id here has been measured.

Worked cases:

| id | base | surface |
|---|---|---|
| `com.google.Chrome.app.<hash>` | `com.google.Chrome` | web app |
| `com.google.Chrome.canary.app.<hash>` | `com.google.Chrome.canary` | web app |
| `com.apple.Safari.WebApp` | `com.apple.Safari` | web app |
| `com.apple.Safari.WebApp.site.<uuid>` | `com.apple.Safari` | web app |
| `com.operasoftware.OperaGX.app.<hash>` | `com.operasoftware.OperaGX` | web app |
| `com.google.Chrome.canary` | unchanged | browser window |
| `app.zen-browser.zen` | unchanged | browser window |
| `com.apple.Safari.SafeBrowsing.Service` | unchanged | **nothing** — no row |
| `com.google.ChromeRemoteDesktop` | unchanged | **nothing** — no row |

Not detectable, and stated in the spec: a `--app=<url>` window carries the plain browser id.

## 3. The scheme list is derived in two parts

```swift
static let sharedChromiumInternalSchemes = ["chrome", "chrome-extension", "chrome-untrusted",
    "chrome-search", "chrome-native", "chrome-error", "isolated-app", "devtools"]
public static let internalSchemes: [String]   // shared ∪ every row's internalScheme, deduped
```

Same membership as today (`edge`, `brave`, `vivaldi`, `opera`, `arc` arrive from rows), so the
baseline fixture is untouched. Clause 9 asserts every row's scheme is present and that every
entry in the per-row half has exactly one owner; the shared half is exempt by construction.

## 4. `BrowserSurface` and `BrowserLaneFlags`

```swift
public enum BrowserSurface: String, Codable, Sendable { case browserWindow, installedWebApp }

public struct BrowserLaneFlags: Codable, Sendable, Equatable {
    public var actsOutsideThisWindow: Bool
    public var autonomous: Bool
    public var canActAsThisPerson: Bool
    public var outsideTheAuditTrail: Bool
    public var billed: Bool
    static let obscura      = …(true,  false, false, true,  false)
    static let browserUse   = …(true,  true,  true,  true,  true)
    static let proctorNative = …(false, false, true,  false, false)
}
```

On `BrowserHandoff`: `surface: BrowserSurface` (non-optional, declared after `bundleId`) and
`flags: BrowserLaneFlags?` (declared after `why`). Declaration order is JSON key order for the
default encoder, and the baseline test sorts keys, so neither placement is load-bearing — but
`surface` beside the identity fields and `flags` beside `why` is what a reader expects.

## 5. Rule 0 is extracted so the web-app branch reuses it

`decide` currently inlines the URL read. Lift it to

```swift
struct URLReading { var url: String?; var unavailable: String?
                    var internalPage: Bool; var otherScheme: Bool }
static func readURL(_ probe: WebContentProbe?) -> URLReading
```

with the body moved verbatim — no behaviour change, and the baseline fixture proves it. `decide`
calls it; the web-app branch calls it too, which is what gives clause 6 (`file:`/`data:` keeps
`notAnInstrument`, a `.pdf` keeps its note) for free rather than by re-implementation.

## 6. The web-app branch, ahead of the ladder

In `handoff`, before `decide`:

```swift
if browser.surface == .installedWebApp {
    let r = readURL(probe)
    return BrowserHandoff(
        boundary: webAppBoundary, browser: browser.name, bundleId: browser.bundleId,
        surface: .installedWebApp,
        use: nil, why: webAppWhy, flags: .proctorNative,
        continuity: webAppContinuity,
        evidence: detail == .full ? evidence : nil,
        url: r.url, urlUnavailable: r.unavailable,
        toolUnavailable: nil, notes: pdfOnlyNotes(url: r.url),
        commands: nil, caveats: nil)
}
```

`caveats` is nil because no lane was named and the seven Obscura edges are a lane's facts.
`pdfOnlyNotes` returns the PDF note and never the private-network one, which is advice about a
lane that was not named.

Three new strings:

- **`webAppBoundary`** — this is an installed web app window rather than a browser window: one
  site opened as an application, with its own dock entry and its own session. Proctor drives it
  as an application. Inside its web area is page content and any toolbar or tab strip the app
  shows is Proctor's, exactly as in a browser window.
- **`webAppWhy`** — no browser tool is named for it. A browser tool opens the address in its own
  engine with an empty cookie jar, and a site is installed as an application because somebody
  uses it signed in, so that is a different, signed-out visit to the same site rather than this
  window.
- **`webAppContinuity`** — the session lives in this window, so driving it here continues it.
  Names no tool.

## 7. The AX engine applies the manual-accessibility flag for a shim

```swift
let chromium = isChromiumBased(app)
    || BrowserCatalogue.identify(bundleId: app.bundleIdentifier)?.surface == .installedWebApp
```

A shim's `Contents/Frameworks` is empty by construction, so the framework probe cannot answer
for it. Code-complete and unverified — it needs a window server and an installed web app, and
this machine has neither.

## 8. Tests, clause by clause

| Clause | Test |
|---|---|
| 1, 2, 3, 4 | `BrowserSurfaceTests.webAppBundleIdsIdentifyAsWebApps`, `.channelWebAppsAreWebAppsNotChannels`, `.channelsAreStillChannels`, `.theLookupIsUntouchedForAMarkerlessId` |
| 5, 6 | `.aWebAppNamesNoLaneUnderEveryLaneState` (sweeps Obscura x 3 lane states x 2 details), `.aWebAppKeepsPageSpecificAdvice` |
| 7 | `.surfaceIsPresentOnEveryHandoff` |
| 8, 9 | `.chromiumFamilyIsDerivedFromTheScheme`, `.theSchemeListIsDerivedAndOwned` |
| 10, 15 | `BrowserRoutingBaselineTests.routingIsUnchanged` |
| 11, 12 | `.flagsFollowTheInstrument`, `.flagValuesPerInstrument` |
| 13 | `.everyTrueFlagHasItsSubjectInTheProse` (substring assertions on each lane's prose) |
| 14 | `BrowserSurfaceWiringTests.theGateStillHoldsOverTheNewFields` — extends PRO-0024's sweep to `surface`, `flags` and a web-app window |
| 16 | `.aWebAppCarriesSurfaceAndFlagsThroughTheWire` — `proctor_apps` list and attach, injected environment |

Updated in place: `BrowserLaneTests` and `BrowserTargetTests` swap `chromiumFamily:` for
`internalScheme:`; `BrowserHandoffToolAvailabilityTests` the same. No clause of PRO-0020,
PRO-0023 or PRO-0024 changes.

## Order of work

1. Baseline test + fixture, green on unchanged code.
2. Marker split, `BrowserSurface`, `internalScheme`, derived scheme list. Build, run the
   baseline — it must still pass, since none of this is meant to move routing.
3. `BrowserLaneFlags`, the two handoff fields. Baseline now needs the strip step.
4. `readURL` extraction. Baseline must not move.
5. The web-app branch and its three strings.
6. The AX engine condition, the schemas, README, CHANGELOG.
7. Full `swift test`, then the out-of-family completeness critic.

## Risks

- **The baseline fixture freezes a bug if one exists today.** It is a regression fence, not a
  correctness claim, and the spec says so.
- **`readURL` is a verbatim lift.** Any accidental edit shows up in the baseline immediately,
  which is why the extraction is its own step.
- **Neither web-app bundle id form is measured here.** A wrong form means the window behaves as
  it does today; it cannot behave worse.
- **The marker split runs on every `identify` call**, including for ids that match nothing. It
  is one `split` and a scan of a handful of components, on a path already doing a dictionary
  lookup, and `identify` is called once per app row rather than per node.
