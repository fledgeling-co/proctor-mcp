import Testing
import Foundation
@testable import ProctorCore

// PRO-0020. Which half of a browser window is Proctor's, and what it says about
// the other half. What a wrong answer costs: a model told to drive a page through
// a flattened accessibility tree when the DOM was one command away, or told to
// point Obscura at a page it cannot open, or handed a page URL spliced into a
// shell command.

@Suite("Browser catalogue")
struct BrowserCatalogueTests {

    @Test("the browsers people actually run are recognised, channels included")
    func knownBrowsers() {
        let expected: [(String, String)] = [
            ("com.apple.Safari", "Safari"),
            ("com.apple.SafariTechnologyPreview", "Safari Technology Preview"),
            ("com.google.Chrome", "Google Chrome"),
            ("com.google.Chrome.canary", "Google Chrome"),
            ("com.google.Chrome.beta", "Google Chrome"),
            ("com.google.Chrome.dev", "Google Chrome"),
            ("org.chromium.Chromium", "Chromium"),
            ("com.microsoft.edgemac", "Microsoft Edge"),
            ("com.microsoft.edgemac.Dev", "Microsoft Edge"),
            ("com.brave.Browser", "Brave"),
            ("com.brave.Browser.beta", "Brave"),
            ("org.mozilla.firefox", "Firefox"),
            ("org.mozilla.firefoxdeveloperedition", "Firefox Developer Edition"),
            ("org.mozilla.nightly", "Firefox Nightly"),
            ("company.thebrowser.Browser", "Arc"),
            ("com.kagi.kagimacOS", "Orion"),
            ("com.vivaldi.Vivaldi", "Vivaldi")
        ]
        for (bundleId, name) in expected {
            #expect(BrowserCatalogue.identify(bundleId: bundleId)?.name == name,
                    "expected \(bundleId) to be \(name)")
        }
    }

    @Test("an app that merely hosts web content is not a browser")
    func webViewHostsAreNotBrowsers() {
        // The boundary the whole feature rests on. Slack, VS Code and any native
        // app with a WKWebView all show an AXWebArea; none of them is reachable by
        // Obscura, because reaching their content means attaching to the host
        // process. Identity comes from the bundle, never from the tree.
        for bundleId in ["com.tinyspeck.slackmacgap", "com.microsoft.VSCode",
                         "com.apple.finder", "com.example.app", ""] {
            #expect(BrowserCatalogue.identify(bundleId: bundleId) == nil)
        }
        #expect(BrowserCatalogue.identify(bundleId: nil) == nil)
    }

    @Test("a prefix rule matches the product and its channels, not a lookalike")
    func prefixRuleIsNotSubstringMatching() {
        #expect(BrowserCatalogue.identify(bundleId: "com.google.ChromeRemoteDesktop") == nil)
        #expect(BrowserCatalogue.identify(bundleId: "com.google.Chrome.canary") != nil)
    }
}

@Suite("Browser handoff")
struct BrowserHandoffTests {

    private let chrome = KnownBrowser(name: "Google Chrome", bundleId: "com.google.Chrome")

    private func probe(_ urls: String?...) -> WebContentProbe {
        WebContentProbe(areas: urls.map { WebArea(url: $0, frame: Rect(x: 0, y: 0, w: 10, h: 10)) })
    }

    @Test("one page URL is reported, and reported once")
    func singleURL() {
        let handoff = BrowserTarget.handoff(for: chrome, probe: probe("https://example.com/a"),
                                            detail: .brief, lanes: .obscuraOnly)
        #expect(handoff.url == "https://example.com/a")
        #expect(handoff.urlUnavailable == nil)
        #expect(handoff.use == "obscura")
    }

    @Test("a window with no readable URL says so rather than guessing")
    func absentURL() {
        let handoff = BrowserTarget.handoff(for: chrome, probe: probe(nil), detail: .brief, lanes: .obscuraOnly)
        #expect(handoff.url == nil)
        #expect(handoff.urlUnavailable == BrowserTarget.urlAbsent)
    }

    @Test("two web areas at different URLs is reported, not resolved")
    func severalURLs() {
        // Proctor does not pick one. A URL that is the wrong tab is worse than no
        // URL, because a model cannot tell it is wrong.
        let handoff = BrowserTarget.handoff(
            for: chrome, probe: probe("https://a.example", "https://b.example"), detail: .brief, lanes: .obscuraOnly)
        #expect(handoff.url == nil)
        #expect(handoff.urlUnavailable == BrowserTarget.severalURLs)
    }

    @Test("the same page spelled two ways is one page")
    func trailingSlashAndFragmentAreNotTwoPages() {
        let handoff = BrowserTarget.handoff(
            for: chrome,
            probe: probe("https://example.com/a", "https://example.com/a/", "https://example.com/a#x"),
            detail: .brief, lanes: .obscuraOnly)
        #expect(handoff.url == "https://example.com/a")
        #expect(handoff.urlUnavailable == nil)
    }

    @Test("a page Obscura cannot open keeps the disclosure and drops the recommendation")
    func nonWebSchemeIsNotRecommended() {
        // chrome://, the new tab page, DevTools and the built-in PDF viewer are all
        // real pages that Obscura cannot fetch. Naming a tool that will fail there
        // is worse advice than naming none; staying silent would be worse still,
        // because a model would drive the page believing nothing was said about it.
        for url in ["chrome://newtab", "about:blank", "devtools://devtools/bundled/x.html",
                    "chrome-extension://abcdef/popup.html"] {
            let handoff = BrowserTarget.handoff(for: chrome, probe: probe(url), detail: .full, lanes: .obscuraOnly)
            #expect(handoff.use == nil, "\(url) should not recommend a tool")
            #expect(handoff.url == nil)
            #expect(handoff.commands == nil)
            #expect(handoff.urlUnavailable == BrowserTarget.notOpenable)
            // The disclosure itself survives.
            #expect(handoff.boundary == BrowserTarget.boundary(for: .obscura))
            #expect(handoff.continuity == BrowserTarget.continuity(for: .obscura))
        }
    }

    @Test("a page beside a devtools panel is still the page")
    func webSchemeWinsOverASiblingNonWebArea() {
        let handoff = BrowserTarget.handoff(
            for: chrome, probe: probe("devtools://devtools/x.html", "https://example.com"),
            detail: .brief, lanes: .obscuraOnly)
        #expect(handoff.url == "https://example.com")
        #expect(handoff.use == "obscura")
    }

    @Test("a local dev server carries its own caveat even in the brief form")
    func privateNetworkNoteReachesTheBriefForm() {
        // The brief form omits the seven caveats, and the private-network block is
        // the one that would otherwise present as a network error nobody can place.
        for url in ["http://localhost:3000/x", "http://127.0.0.1:8080",
                    "http://192.168.1.4:5173", "http://10.0.0.2", "http://172.20.1.1",
                    "http://dev.local"] {
            let handoff = BrowserTarget.handoff(for: chrome, probe: probe(url), detail: .brief, lanes: .obscuraOnly)
            #expect(handoff.notes?.first == BrowserTarget.privateNetworkNote, "\(url) is private")
        }
        let public_ = BrowserTarget.handoff(for: chrome, probe: probe("https://example.com"),
                                            detail: .brief, lanes: .obscuraOnly)
        #expect(public_.notes == nil)
    }

    @Test("a collapsed or frameless web area does not count as a second page")
    func zeroSizedAreasDoNotMakeTwoPages() {
        // A real browser tree carries more web areas than the page in front of you:
        // a docked DevTools pane, a print preview, an area collapsed to nothing.
        // Counting those would make "several web areas" the answer nearly every
        // time, which is a correct-sounding way of never answering.
        let probe = WebContentProbe(areas: [
            WebArea(url: "https://example.com", frame: Rect(x: 0, y: 0, w: 800, h: 600)),
            WebArea(url: "https://hidden.example", frame: Rect(x: 0, y: 0, w: 0, h: 0)),
            WebArea(url: "https://frameless.example", frame: nil)
        ])
        let handoff = BrowserTarget.handoff(for: chrome, probe: probe, detail: .brief, lanes: .obscuraOnly)
        #expect(handoff.url == "https://example.com")
    }

    @Test("when no area reports a frame at all, none is discarded")
    func framelessEverywhereKeepsEveryArea() {
        // Then the frames are what is missing, not the content, and discarding on
        // a measurement nobody took would silently pick a page.
        let probe = WebContentProbe(areas: [
            WebArea(url: "https://a.example", frame: nil),
            WebArea(url: "https://b.example", frame: nil)
        ])
        let handoff = BrowserTarget.handoff(for: chrome, probe: probe, detail: .brief, lanes: .obscuraOnly)
        #expect(handoff.urlUnavailable == BrowserTarget.severalURLs)
    }

    @Test("a hostile URL never reaches a command or a sentence")
    func urlIsNeverInterpolated() throws {
        // A page URL is attacker-controlled text. It travels in its own field, and
        // the command templates keep their literal placeholder, so nothing a page
        // can name ends up inside a string a model may paste into a shell.
        let hostile = "https://evil.example/\"; rm -rf ~ #"
        let handoff = BrowserTarget.handoff(for: chrome, probe: probe(hostile), detail: .full, lanes: .obscuraOnly)
        #expect(handoff.url == hostile)

        let commands = try #require(handoff.commands)
        // Every command that takes a URL takes the placeholder, and no command
        // anywhere carries a character the page chose.
        #expect(commands.contains { $0.contains(BrowserTarget.urlPlaceholder) })
        for command in commands where command.contains("fetch") {
            #expect(command.contains(BrowserTarget.urlPlaceholder))
        }
        for command in commands {
            #expect(!command.contains("rm -rf"))
            #expect(!command.contains("evil.example"))
        }
        for sentence in [handoff.boundary, handoff.continuity, handoff.evidence ?? ""] {
            #expect(!sentence.contains("evil.example"))
        }
    }

    @Test("full says everything once; brief says the part that is always true")
    func detailLevels() {
        let full = BrowserTarget.handoff(for: chrome, probe: probe("https://example.com"),
                                         detail: .full, lanes: .obscuraOnly)
        let brief = BrowserTarget.handoff(for: chrome, probe: probe("https://example.com"),
                                          detail: .brief, lanes: .obscuraOnly)

        #expect(full.caveats?.count == 7)
        #expect(full.commands?.isEmpty == false)
        #expect(full.evidence != nil)

        #expect(brief.caveats == nil)
        #expect(brief.commands == nil)
        #expect(brief.evidence == nil)

        // The boundary and the discontinuity are the two things a reader needs at
        // every level, so they are identical at both.
        #expect(brief.boundary == full.boundary)
        #expect(brief.continuity == full.continuity)
    }

    @Test("without a window there is no page, and it says that rather than nothing")
    func appLevelHandoff() {
        let handoff = BrowserTarget.handoff(for: chrome, probe: nil, detail: .full, lanes: .obscuraOnly)
        #expect(handoff.url == nil)
        #expect(handoff.urlUnavailable == BrowserTarget.noWindowNamed)
        #expect(handoff.caveats?.count == 7)
    }

    @Test("omitted fields are absent on the wire, not null")
    func encodingOmitsAbsentFields() throws {
        let brief = BrowserTarget.handoff(for: chrome, probe: probe("https://example.com"),
                                          detail: .brief, lanes: .obscuraOnly)
        let json = try JSONValue.encode(brief).objectValue ?? [:]
        #expect(json["caveats"] == nil)
        #expect(json["commands"] == nil)
        #expect(json["urlUnavailable"] == nil)
        #expect(json["url"] != nil)
        #expect(json["boundary"] != nil)
    }
}

@Suite("Web content containment")
struct WebContentProbeTests {

    private let page = WebContentProbe(areas: [
        WebArea(url: "https://example.com", frame: Rect(x: 100, y: 200, w: 800, h: 600))
    ])

    @Test("a point inside the page is page content and a point in the toolbar is not")
    func pointContainment() {
        #expect(page.contains(x: 500, y: 400))
        #expect(!page.contains(x: 500, y: 150))   // above the web area: the toolbar
        #expect(!page.contains(x: 50, y: 400))    // left of it
        #expect(!page.contains(x: 500, y: 900))   // below it
    }

    @Test("an element's whole frame has to be inside the page")
    func rectContainment() {
        #expect(page.contains(Rect(x: 200, y: 300, w: 100, h: 40)))
        // A frame straddling the boundary is chrome as far as this is concerned,
        // which errs toward not claiming something is page content.
        #expect(!page.contains(Rect(x: 50, y: 300, w: 100, h: 40)))
    }

    @Test("a web area reported as the whole window makes the toolbar read as page")
    func windowSizedWebAreaOverDiscloses() {
        // Some browsers report the web area as the window rather than the content
        // rect. Then a toolbar target sits geometrically inside the page and picks
        // up the advisory. That is recorded here as the known behaviour rather
        // than papered over with a guessed toolbar height: the cost is an advisory
        // on a native control, and the alternative — inventing a chrome inset —
        // would silently drop the disclosure on a real page instead.
        let windowSized = WebContentProbe(areas: [
            WebArea(url: "https://example.com", frame: Rect(x: 0, y: 0, w: 1000, h: 800))
        ])
        #expect(windowSized.contains(x: 500, y: 20))
    }

    @Test("a web area with no frame contains nothing")
    func framelessAreaContainsNothing() {
        let frameless = WebContentProbe(areas: [WebArea(url: "https://example.com", frame: nil)])
        #expect(!frameless.contains(x: 10, y: 10))
    }
}
// MARK: - PRO-0023: what the handoff says when Obscura is not installed

@Suite("Browser handoff when Obscura is missing")
struct BrowserHandoffToolAvailabilityTests {

    private let chrome = KnownBrowser(name: "Google Chrome", bundleId: "com.google.Chrome",
                                      internalScheme: "chrome")
    private let page = WebContentProbe(areas: [
        WebArea(url: "https://example.com/dashboard", frame: Rect(x: 0, y: 0, w: 800, h: 600))
    ])
    private let internalPage = WebContentProbe(areas: [
        WebArea(url: "chrome://newtab", frame: Rect(x: 0, y: 0, w: 800, h: 600))
    ])

    /// PRO-0024 replaced the post-hoc `withTool` patch with a `lanes` argument,
    /// because the lane now decides the boundary text, the continuity text, the
    /// caveats and the commands together and a patch could no longer express it.
    /// The clauses these tests pin are PRO-0023's, unchanged; only the call is new.
    private func handoff(_ probe: WebContentProbe?, _ detail: BrowserTarget.Detail,
                         available: Bool) -> BrowserHandoff {
        BrowserTarget.handoff(for: chrome, probe: probe, detail: detail,
                              lanes: BrowserLanes(obscuraAvailable: available, secondLane: .off))
    }

    @Test("a missing tool drops the recommendation, keeps the URL, and says why")
    func aMissingToolDropsTheRecommendationAndKeepsTheURL() {
        let out = handoff(page, .full, available: false)
        // Printing `obscura fetch` on a machine with no obscura is the thing this
        // feature exists to stop.
        #expect(out.use == nil)
        #expect(out.commands == nil)
        #expect(out.toolUnavailable == ObscuraTool.absence)
        // The URL is a fact about the page rather than advice, and it is what
        // makes the recommendation actionable the moment the install finishes.
        #expect(out.url == "https://example.com/dashboard")
        // Which half of the window is Proctor's does not depend on what happens to
        // be installed.
        #expect(out.boundary == BrowserTarget.boundary(for: .obscura))
        #expect(out.continuity == BrowserTarget.continuity(for: .obscura))
        #expect(out.evidence == BrowserTarget.evidence)
        #expect(out.caveats == BrowserTarget.caveats(for: .obscura))
    }

    @Test("a present tool changes nothing at all")
    func aPresentToolChangesNothing() {
        let out = handoff(page, .full, available: true)
        #expect(out.toolUnavailable == nil)
        #expect(out.use == "obscura")
        #expect(out.commands == BrowserTarget.commands(for: .obscura))
        #expect(handoff(page, .brief, available: true).commands == nil)
    }

    @Test("a page Obscura could not open anyway gains no absence")
    func aPageObscuraCannotOpenGainsNoAbsence() {
        // There was no recommendation to repair, so naming a missing tool that
        // would not help this page is noise.
        let out = handoff(internalPage, .full, available: false)
        #expect(out.toolUnavailable == nil)
        #expect(out.use == nil)
        #expect(out.urlUnavailable == BrowserTarget.notOpenable)
        #expect(out == handoff(internalPage, .full, available: true))
    }

    @Test("both detail levels carry the same absence")
    func bothDetailLevelsCarryTheSameAbsence() {
        // It is the reason the recommendation is absent, so a brief handoff that
        // merely lacked `use` would be indistinguishable from the chrome:// case.
        // The evidence — where Proctor looked — lives on proctor_doctor instead.
        #expect(handoff(page, .brief, available: false).toolUnavailable
                == handoff(page, .full, available: false).toolUnavailable)
        #expect(handoff(page, .brief, available: false).commands == nil)
    }

    @Test("an app-level handoff with no window discloses the absence too")
    func anAppLevelHandoffDisclosesTheAbsence() {
        let out = handoff(nil, .full, available: false)
        #expect(out.toolUnavailable != nil)
        #expect(out.use == nil)
    }
}
