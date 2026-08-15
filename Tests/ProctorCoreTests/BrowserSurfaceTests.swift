import Testing
import Foundation
@testable import ProctorCore

// PRO-0035 — what a bundle identifier names, and what a host can gate on.
//
// Three things are settled here. An installed web app is an **application**
// window Proctor drives, not a browser tab handed to a browser tool. The engine
// fact stops being a second stored boolean beside the name. And the prose the
// handoff has always carried gains a small machine-readable set beside it, so a
// host refusing an unaudited or credential-holding instrument does not have to
// parse English.
//
// The one test that matters most on this machine is in `BrowserLaneTests` and is
// unchanged: with the lane variable unset, `browser-use` appears nowhere. This
// suite adds the same invariant over the two new fields.

@Suite("Installed web apps and the flag set")
struct BrowserSurfaceTests {

    private func probe(_ urls: String?...) -> WebContentProbe {
        WebContentProbe(areas: urls.map { WebArea(url: $0, frame: Rect(x: 0, y: 0, w: 1200, h: 800)) })
    }

    private func lanes(obscura: Bool = true, second: SecondLaneState = .off) -> BrowserLanes {
        BrowserLanes(obscuraAvailable: obscura, secondLane: second)
    }

    // MARK: - Clause 1 — a per-site app is not its browser

    @Test("an installed web app identifies as one, hosted by its browser")
    func webAppBundleIdsIdentifyAsWebApps() {
        let cases: [(String, String)] = [
            ("com.google.Chrome.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa", "Google Chrome"),
            ("com.brave.Browser.app.abcdefghijklmnopqrstuvwxyz012345", "Brave"),
            ("com.microsoft.edgemac.app.aaaabbbbccccddddeeeeffff00001111", "Microsoft Edge"),
            ("org.chromium.Chromium.app.deadbeefdeadbeefdeadbeefdeadbeef", "Chromium"),
            ("com.vivaldi.Vivaldi.app.0123456789abcdef0123456789abcdef", "Vivaldi"),
            ("com.operasoftware.OperaGX.app.fedcba9876543210fedcba9876543210", "Opera GX"),
            // Safari's template identifier carries nothing after the marker, and an
            // instance carries a site and a UUID. Both forms are documented rather
            // than measured: no web app is installed on this machine.
            ("com.apple.Safari.WebApp", "Safari"),
            ("com.apple.Safari.WebApp.example.com.9E1C2A44-0000-4000-8000-000000000000", "Safari")
        ]
        for (id, name) in cases {
            let hit = BrowserCatalogue.identify(bundleId: id)
            #expect(hit?.surface == .installedWebApp, "\(id)")
            #expect(hit?.name == name, "\(id)")
            // The full identifier is reported, not the truncated base: it is what
            // the application says it is.
            #expect(hit?.bundleId == id, "\(id)")
        }
    }

    // MARK: - Clause 2 — a channel build's web app

    @Test("a web app on a channel build is a web app, not a channel")
    func channelWebAppsAreWebAppsNotChannels() {
        // Chromium builds a shim identifier as the **base** bundle id plus the
        // marker, and a channel build's base is the channel's own id. Testing the
        // start of the remainder rather than each component would have missed every
        // web app on every channel — the builds somebody doing this work runs.
        for id in ["com.google.Chrome.canary.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa",
                   "com.google.Chrome.beta.app.aaaabbbbccccdddd",
                   "com.microsoft.edgemac.Dev.app.aaaabbbbccccdddd",
                   "com.brave.Browser.beta.app.aaaabbbbccccdddd"] {
            #expect(BrowserCatalogue.identify(bundleId: id)?.surface == .installedWebApp, "\(id)")
        }
    }

    // MARK: - Clause 3 — channels themselves are untouched

    @Test("a channel variant is still a browser window, and a non-browser is still nothing")
    func channelsAreStillChannels() {
        for id in ["com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
                   "com.brave.Browser.beta", "com.microsoft.edgemac.Dev", "org.mozilla.nightly",
                   // Zen's identifier opens with a component `app`, which is exactly
                   // why the marker scan starts at index 1 rather than 0.
                   "app.zen-browser.zen"] {
            let hit = BrowserCatalogue.identify(bundleId: id)
            #expect(hit != nil, "\(id)")
            #expect(hit?.surface == .browserWindow, "\(id)")
        }
        #expect(BrowserCatalogue.identify(bundleId: "com.google.ChromeRemoteDesktop") == nil)
    }

    // MARK: - Clause 4 — the lookup itself did not move

    @Test("an identifier with no marker takes exactly the path it took before")
    func theLookupIsUntouchedForAMarkerlessId() {
        // Opera GX is its own exact row rather than an Opera channel.
        #expect(BrowserCatalogue.identify(bundleId: "com.operasoftware.OperaGX")?.name == "Opera GX")
        #expect(BrowserCatalogue.identify(bundleId: "com.apple.SafariTechnologyPreview")?.name
                == "Safari Technology Preview")
        // The reason the exact rows were not promoted to prefixes: doing that would
        // identify every descendant of one, and a Safari helper service is not
        // Safari.
        #expect(BrowserCatalogue.identify(bundleId: "com.apple.Safari.SafeBrowsing.Service") == nil)
        #expect(BrowserCatalogue.identify(bundleId: "org.chromium.Chromium.helper") == nil)
    }

    // MARK: - Clause 5 — a web app names no lane, ever

    @Test("a web app names no lane under every combination of tool state")
    func aWebAppNamesNoLaneUnderEveryLaneState() throws {
        let webApp = try #require(BrowserCatalogue.identify(
            bundleId: "com.google.Chrome.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa"))
        for obscura in [true, false] {
            for second in [SecondLaneState.off, .enabled, .unavailable] {
                for detail in [BrowserTarget.Detail.full, .brief] {
                    let out = BrowserTarget.handoff(
                        for: webApp, probe: probe("https://mail.example.com/inbox"),
                        detail: detail, lanes: lanes(obscura: obscura, second: second))
                    #expect(out.use == nil)
                    #expect(out.commands == nil)
                    #expect(out.caveats == nil)
                    #expect(out.toolUnavailable == nil)
                    #expect(out.surface == .installedWebApp)
                    #expect(out.why == BrowserTarget.webAppWhy)
                    #expect(out.boundary == BrowserTarget.webAppBoundary)
                    #expect(out.continuity == BrowserTarget.webAppContinuity)
                    // The address is kept. Withholding it would follow the no-lane
                    // rule elsewhere, but that rule suppresses an address because
                    // the address leads nowhere; here it names the site this window
                    // is, and a model that disagrees with Proctor needs it.
                    #expect(out.url == "https://mail.example.com/inbox")
                    #expect(out.urlUnavailable == nil)
                    // No tool was named, so advice about how to invoke one would be
                    // answering a question nobody asked.
                    #expect(out.notes == nil)
                }
            }
        }
    }

    @Test("a web app never reaches the ladder, whatever the page's scheme is")
    func aWebAppNeverReachesTheLadder() throws {
        let webApp = try #require(BrowserCatalogue.identify(
            bundleId: "com.google.Chrome.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa"))
        // A browser-internal scheme in a Chromium web app with the lane enabled is
        // the one combination that would otherwise route to the second lane.
        for url in ["chrome://settings", "chrome-extension://abcdefghij/options.html",
                    "https://example.com", "about:blank"] {
            let out = BrowserTarget.handoff(for: webApp, probe: probe(url), detail: .full,
                                            lanes: lanes(second: .enabled))
            #expect(out.use == nil, "\(url)")
            #expect(out.surface == .installedWebApp, "\(url)")
        }
        // No window named at all.
        let appLevel = BrowserTarget.handoff(for: webApp, probe: nil, detail: .full,
                                             lanes: lanes(second: .enabled))
        #expect(appLevel.use == nil)
        #expect(appLevel.urlUnavailable == BrowserTarget.noWindowNamed)
    }

    // MARK: - Clause 6 — the page-specific advice survives the short-circuit

    @Test("a web app keeps the advice a browser window would have got about its page")
    func aWebAppKeepsPageSpecificAdvice() throws {
        let webApp = try #require(BrowserCatalogue.identify(
            bundleId: "com.google.Chrome.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa"))
        // An installed PDF viewer would otherwise be driven through the
        // accessibility plane with the honest answer — fetch the file and parse it
        // — suppressed.
        let pdf = BrowserTarget.handoff(for: webApp, probe: probe("https://x.example/q.pdf?t=1"),
                                        detail: .brief, lanes: lanes())
        #expect(pdf.notes == [BrowserTarget.pdfNote])

        for url in ["file:///Users/x/statement.pdf", "data:text/html,<p>hi</p>"] {
            let out = BrowserTarget.handoff(for: webApp, probe: probe(url), detail: .brief,
                                            lanes: lanes())
            #expect(out.urlUnavailable == BrowserTarget.notAnInstrument, "\(url)")
            #expect(out.use == nil, "\(url)")
        }

        // The private-network note is advice about how to invoke Obscura, and no
        // tool was named.
        let local = BrowserTarget.handoff(for: webApp,
                                          probe: probe("http://192.168.1.4:3000/report.pdf?t=1"),
                                          detail: .brief, lanes: lanes())
        #expect(local.notes == [BrowserTarget.pdfNote])
        #expect(local.notes?.contains(BrowserTarget.privateNetworkNote) != true)
    }

    // MARK: - Clause 7 — surface is always on the wire

    @Test("every handoff carries a surface at both detail levels")
    func surfaceIsPresentOnEveryHandoff() throws {
        let encoder = JSONEncoder()
        for id in ["com.google.Chrome", "com.apple.Safari",
                   "com.google.Chrome.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa"] {
            let browser = try #require(BrowserCatalogue.identify(bundleId: id))
            for detail in [BrowserTarget.Detail.full, .brief] {
                let out = BrowserTarget.handoff(for: browser, probe: probe("https://example.com"),
                                                detail: detail, lanes: lanes())
                let wire = String(decoding: try encoder.encode(out), as: UTF8.self)
                #expect(wire.contains("\"surface\""), "\(id)")
                #expect(out.surface == (id.contains(".app.") ? .installedWebApp : .browserWindow))
            }
        }
    }

    // MARK: - Clause 8 — the engine fact is derived from one per-row fact

    @Test("chromiumFamily is computed from the scheme namespace and answers as before")
    func chromiumFamilyIsDerivedFromTheScheme() {
        let chromium = ["com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium",
                        "com.microsoft.edgemac", "com.microsoft.edgemac.Dev", "com.brave.Browser",
                        "com.brave.Browser.beta", "company.thebrowser.Browser",
                        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
                        "com.operasoftware.OperaGX"]
        let notChromium = ["com.apple.Safari", "com.apple.SafariTechnologyPreview",
                           "com.kagi.kagimacOS", "com.duckduckgo.macos.browser",
                           "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
                           "org.mozilla.nightly", "app.zen-browser.zen"]
        for id in chromium {
            let hit = BrowserCatalogue.identify(bundleId: id)
            #expect(hit?.chromiumFamily == true, "\(id)")
            #expect(hit?.internalScheme != nil, "\(id)")
        }
        for id in notChromium {
            let hit = BrowserCatalogue.identify(bundleId: id)
            #expect(hit?.chromiumFamily == false, "\(id)")
            #expect(hit?.internalScheme == nil, "\(id)")
        }
    }

    // MARK: - Clause 9 — the scheme list is derived, and the per-row half is owned

    @Test("the routable scheme list is the shared set plus every row's own namespace")
    func theSchemeListIsDerivedAndOwned() {
        let owned = Set(BrowserCatalogue.ownedInternalSchemes)
        let shared = Set(BrowserTarget.sharedChromiumInternalSchemes)
        let all = Set(BrowserTarget.internalSchemes)

        #expect(all == shared.union(owned))
        // Every entry in the per-row half has exactly one owning row. The shared
        // half is exempt by construction: `chrome-extension`, `devtools` and their
        // siblings are served by every Chromium browser and owned by none, and
        // requiring a row for them would mean inventing one.
        for scheme in owned.subtracting(shared) {
            let owners = BrowserCatalogue.exact.values.filter { $0.scheme == scheme }.count
                + BrowserCatalogue.prefixes.filter { $0.scheme == scheme }.count
            #expect(owners >= 1, "\(scheme) has no owning row")
        }
        for scheme in owned { #expect(all.contains(scheme), "\(scheme) is missing from the list") }
        // `about` stays off it: about:blank is the empty tab every browser opens.
        #expect(!all.contains("about"))

        // The membership is byte-for-byte what PRO-0024 hand-wrote, which is what
        // makes this a refactor rather than a routing change. The completeness
        // critic's sharpest point about this list is that it is *global* — a
        // `brave://` page in a Chrome window counts as browser-internal — but that
        // was already true of the hand-written list, so it is a property inherited
        // rather than introduced, and narrowing it to the window's own row would
        // change which windows route. Logged as child work; pinned here so it
        // cannot drift while nobody is looking.
        #expect(all == Set(["chrome", "chrome-extension", "chrome-untrusted", "chrome-search",
                            "chrome-native", "chrome-error", "isolated-app", "devtools",
                            "edge", "brave", "vivaldi", "opera", "arc"]))
    }

    // MARK: - The marker split can only add an answer

    @Test("an identifier whose truncated base matches nothing falls back to the whole thing")
    func theMarkerSplitNeverStealsAnIdentifier() {
        // No catalogue row today carries a non-leading `app` component, so this is
        // a guard rather than a fix: a split that could take an identifier away
        // from a row it would otherwise have matched breaks the day somebody adds
        // a browser whose own id contains one.
        #expect(BrowserCatalogue.identify(bundleId: "com.nothing.app.here") == nil)
        // A marker whose base is not a browser does not become a web app of one.
        #expect(BrowserCatalogue.identify(bundleId: "com.acme.app.thing") == nil)
        // And the leading-component case stays a browser window.
        #expect(BrowserCatalogue.identify(bundleId: "app.zen-browser.zen")?.surface
                == .browserWindow)
    }

    // MARK: - Clauses 11 and 12 — the flags follow the instrument

    @Test("flags are present exactly when the handoff points at an instrument")
    func flagsFollowTheInstrument() throws {
        let chrome = try #require(BrowserCatalogue.identify(bundleId: "com.google.Chrome"))
        let webApp = try #require(BrowserCatalogue.identify(
            bundleId: "com.google.Chrome.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa"))

        // Obscura named.
        #expect(BrowserTarget.handoff(for: chrome, probe: probe("https://example.com"),
                                      detail: .brief, lanes: lanes()).flags == .obscura)
        // browser-use named.
        #expect(BrowserTarget.handoff(for: chrome, probe: probe("chrome://newtab"), detail: .brief,
                                      lanes: lanes(second: .enabled)).flags == .browserUse)
        // Proctor itself.
        #expect(BrowserTarget.handoff(for: webApp, probe: probe("https://example.com"),
                                      detail: .brief, lanes: lanes()).flags == .proctorNative)

        // No instrument at all: a deny-listed page, a payload that is not a page,
        // and a machine with no Obscura.
        let none: [(WebContentProbe?, BrowserLanes)] = [
            (probe("chrome://settings"), lanes(second: .enabled)),
            (probe("file:///Users/x/page.html"), lanes()),
            (probe("https://example.com"), lanes(obscura: false)),
            (probe("chrome-extension://abc/x.html", nil), lanes(second: .enabled))
        ]
        for (p, l) in none {
            let out = BrowserTarget.handoff(for: chrome, probe: p, detail: .full, lanes: l)
            #expect(out.use == nil)
            #expect(out.flags == nil)
        }
    }

    @Test("each instrument's flags are the documented ones, at both detail levels")
    func flagValuesPerInstrument() throws {
        #expect(BrowserLaneFlags.obscura == BrowserLaneFlags(
            actsOutsideThisWindow: true, autonomous: false, canActAsThisPerson: false,
            outsideTheAuditTrail: true, billed: false))
        #expect(BrowserLaneFlags.browserUse == BrowserLaneFlags(
            actsOutsideThisWindow: true, autonomous: true, canActAsThisPerson: true,
            outsideTheAuditTrail: true, billed: true))
        // The one that made the set worth putting on a no-lane handoff at all:
        // Proctor driving somebody's installed mail window is this window, it is
        // enumerated, it is audited, it is free — and it is their live signed-in
        // session, which nothing else here would have said.
        #expect(BrowserLaneFlags.proctorNative == BrowserLaneFlags(
            actsOutsideThisWindow: false, autonomous: false, canActAsThisPerson: true,
            outsideTheAuditTrail: false, billed: false))

        let chrome = try #require(BrowserCatalogue.identify(bundleId: "com.google.Chrome"))
        let full = BrowserTarget.handoff(for: chrome, probe: probe("chrome://newtab"),
                                         detail: .full, lanes: lanes(second: .enabled))
        let brief = BrowserTarget.handoff(for: chrome, probe: probe("chrome://newtab"),
                                          detail: .brief, lanes: lanes(second: .enabled))
        #expect(full.flags == brief.flags)
        // A pure function of the instrument: the same lane on a different page is
        // the same set.
        let other = BrowserTarget.handoff(for: chrome, probe: probe("chrome://flags-guide"),
                                          detail: .brief, lanes: lanes(second: .enabled))
        #expect(other.flags == full.flags)
    }

    // MARK: - Clause 13 — the flags carry nothing the prose does not

    @Test("every flag set true has its subject stated in that instrument's prose")
    func everyTrueFlagHasItsSubjectInTheProse() {
        let obscura = BrowserTarget.boundary(for: .obscura) + " "
            + BrowserTarget.continuity(for: .obscura) + " "
            + BrowserTarget.caveats(for: .obscura).joined(separator: " ")
        // actsOutsideThisWindow, outsideTheAuditTrail.
        #expect(obscura.contains("its own engine"))
        #expect(obscura.contains("audit trail"))
        #expect(!obscura.contains("autonomous"))

        let browserUse = BrowserTarget.boundary(for: .browserUse) + " "
            + BrowserTarget.continuity(for: .browserUse) + " "
            + BrowserTarget.caveats(for: .browserUse).joined(separator: " ")
        #expect(browserUse.contains("autonomous"))          // autonomous
        #expect(browserUse.contains("real credentials"))    // canActAsThisPerson
        #expect(browserUse.contains("audit trail"))         // outsideTheAuditTrail
        #expect(browserUse.contains("costs"))               // billed
        #expect(browserUse.contains("not this window"))     // actsOutsideThisWindow

        let webApp = BrowserTarget.webAppBoundary + " " + BrowserTarget.webAppWhy + " "
            + BrowserTarget.webAppContinuity
        // canActAsThisPerson is the only flag true here, and the prose says the
        // session lives in this window; actsOutsideThisWindow is false and the
        // prose says Proctor drives it as an application.
        #expect(webApp.contains("session lives in this window"))
        #expect(webApp.contains("drives it as an application"))
    }

    // MARK: - Clause 14 — the gate holds over the new fields too

    @Test("with the lane unset, the new fields never carry the name either")
    func theGateHoldsOverTheNewFields() throws {
        let encoder = JSONEncoder()
        for id in ["com.google.Chrome", "com.apple.Safari",
                   "com.google.Chrome.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa"] {
            let browser = try #require(BrowserCatalogue.identify(bundleId: id))
            for url in ["https://example.com", "chrome://newtab", "chrome://settings",
                        "file:///Users/x/p.html", nil] {
                for obscura in [true, false] {
                    for detail in [BrowserTarget.Detail.full, .brief] {
                        // The variable unset is `secondLane == .off`, whatever is on
                        // disk — that is the whole of the gate.
                        let out = BrowserTarget.handoff(
                            for: browser, probe: probe(url), detail: detail,
                            lanes: lanes(obscura: obscura, second: .off))
                        let wire = String(decoding: try encoder.encode(out), as: UTF8.self)
                        #expect(!wire.contains("browser-use"), "\(id) \(url ?? "<nil>")")
                    }
                }
            }
        }
    }
}
