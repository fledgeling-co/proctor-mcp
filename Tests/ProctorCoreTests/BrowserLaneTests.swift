import Testing
import Foundation
@testable import ProctorCore

// PRO-0024 — the second browser lane.
//
// Two gates stand in front of it and they do different jobs: the environment
// variable decides whether `browser-use` may be **named**, and the binary on disk
// decides whether the lane is **usable**. The first test in this file is the one
// that matters most on this machine, whose operator's standing rule removes the
// tool: with the variable unset, the string does not appear anywhere.

@Suite("Second browser lane")
struct BrowserLaneTests {

    private let chrome = KnownBrowser(name: "Google Chrome", bundleId: "com.google.Chrome",
                                      chromiumFamily: true)
    private let safari = KnownBrowser(name: "Safari", bundleId: "com.apple.Safari",
                                      chromiumFamily: false)
    private let firefox = KnownBrowser(name: "Firefox", bundleId: "org.mozilla.firefox",
                                       chromiumFamily: false)

    private func probe(_ urls: String?...) -> WebContentProbe {
        WebContentProbe(areas: urls.map { WebArea(url: $0, frame: Rect(x: 0, y: 0, w: 800, h: 600)) })
    }

    private func lanes(obscura: Bool, second: SecondLaneState) -> BrowserLanes {
        BrowserLanes(obscuraAvailable: obscura, secondLane: second)
    }

    private func json(_ handoff: BrowserHandoff) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(handoff), as: UTF8.self)
    }

    private func presence(_ tool: String, _ available: Bool) -> ToolPresence {
        ToolPresence(tool: tool, available: available,
                     path: available ? "/opt/homebrew/bin/" + tool : nil)
    }

    // MARK: - Clause 1

    @Test("the catalogue knows which browsers are Chromium, channels included")
    func chromiumFamilyIsKnownPerBrowser() {
        let chromium = ["org.chromium.Chromium", "com.google.Chrome", "com.google.Chrome.canary",
                        "com.google.Chrome.beta", "com.microsoft.edgemac",
                        "com.microsoft.edgemac.Dev", "com.brave.Browser",
                        "com.brave.Browser.beta", "company.thebrowser.Browser",
                        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
                        "com.operasoftware.OperaGX"]
        let notChromium = ["com.apple.Safari", "com.apple.SafariTechnologyPreview",
                           "com.kagi.kagimacOS", "com.duckduckgo.macos.browser",
                           "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
                           "org.mozilla.nightly", "app.zen-browser.zen"]
        for id in chromium {
            #expect(BrowserCatalogue.identify(bundleId: id)?.chromiumFamily == true, "\(id)")
        }
        for id in notChromium {
            #expect(BrowserCatalogue.identify(bundleId: id)?.chromiumFamily == false, "\(id)")
        }
    }

    // MARK: - Clause 2 — the gate

    @Test("with the variable unset the second tool is never named, in any field, anywhere")
    func theNameNeverAppearsUnlessTheOperatorNamedIt() throws {
        // The whole cross product: every scheme this feature routes on, both
        // browser families, both Obscura states, both detail levels — and both
        // presences of browser-use itself, because presence alone must not be
        // enough. This is the test that stands between a machine whose operator
        // removed browser-use and a Proctor that recommends it anyway.
        let urls = ["https://example.com/a", "chrome://newtab", "file:///tmp/x.html",
                    "data:text/html,<p>x", "about:blank"]
        for url in urls {
            for browser in [chrome, safari, firefox] {
                for obscura in [true, false] {
                    for onDisk in [true, false] {
                        let gate = BrowserLanes.make(obscura: presence("obscura", obscura),
                                                     browserUse: presence("browser-use", onDisk),
                                                     environment: [:])
                        #expect(gate.secondLane == .off)
                        for detail in [BrowserTarget.Detail.brief, .full] {
                            let out = BrowserTarget.handoff(for: browser, probe: probe(url),
                                                            detail: detail, lanes: gate)
                            #expect(!(try json(out).contains("browser-use")),
                                    "\(url) / \(browser.name) / obscura \(obscura) / on disk \(onDisk)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Clause 3 — the three states, computed in one place

    @Test("the gate has three states and the variable alone decides whether the name is allowed")
    func theGateHasThreeStates() {
        let here = presence("browser-use", true)
        let gone = presence("browser-use", false)
        let obscura = presence("obscura", true)
        let named = [BrowserUseTool.laneVariable: "browser-use"]

        #expect(BrowserLanes.make(obscura: obscura, browserUse: here,
                                  environment: [:]).secondLane == .off)
        #expect(BrowserLanes.make(obscura: obscura, browserUse: here,
                                  environment: named).secondLane == .enabled)
        #expect(BrowserLanes.make(obscura: obscura, browserUse: gone,
                                  environment: named).secondLane == .unavailable)
        // A value that names something else is not consent for this tool.
        #expect(BrowserLanes.make(obscura: obscura, browserUse: here,
                                  environment: [BrowserUseTool.laneVariable: "1"])
                    .secondLane == .off)
        #expect(BrowserLanes.make(obscura: obscura, browserUse: here,
                                  environment: [BrowserUseTool.laneVariable: "  Browser-Use "])
                    .secondLane == .enabled)
        #expect(BrowserLanes.make(obscura: presence("obscura", false), browserUse: here,
                                  environment: named).obscuraAvailable == false)
    }

    // MARK: - Clause 4 — rule 1, the browser-internal page

    @Test("a page inside the browser goes to the lane that has such a page, and only there")
    func aBrowserInternalPageRoutesToTheSecondLane() {
        let on = lanes(obscura: true, second: .enabled)
        for url in ["chrome://newtab", "chrome-extension://abcdef/popup.html",
                    "chrome-search://local-ntp/x", "chrome-error://chromewebdata/",
                    "chrome-untrusted://media-app/", "isolated-app://abc/"] {
            let out = BrowserTarget.handoff(for: chrome, probe: probe(url), detail: .full,
                                            lanes: on)
            #expect(out.use == "browser-use", "\(url)")
            #expect(out.why == BrowserTarget.whyInternalScheme)
            #expect(out.url == url)
            #expect(out.urlUnavailable == nil)
        }

        // The claim has to be true. Firefox is not a Chromium, so `about:config`
        // is not a page browser-use opens either, and this falls back to PRO-0020.
        let inFirefox = BrowserTarget.handoff(for: firefox, probe: probe("chrome://newtab"),
                                              detail: .full, lanes: on)
        #expect(inFirefox.use == nil)
        #expect(inFirefox.url == nil)
        #expect(inFirefox.urlUnavailable == BrowserTarget.notOpenable)
    }

    @Test("a real page beside an internal one is still the real page")
    func aMixedWindowResolvesToTheRealPage() {
        // PRO-0020 already answers this and the second lane does not disturb it:
        // the https area is the page somebody is looking at.
        let out = BrowserTarget.handoff(
            for: chrome, probe: probe("chrome://newtab", "https://example.com"),
            detail: .brief, lanes: lanes(obscura: true, second: .enabled))
        #expect(out.use == "obscura")
        #expect(out.url == "https://example.com")
    }

    // MARK: - Clause 5 — rule 2, unchanged when the lane is off

    @Test("with the lane off a browser-internal page is exactly what PRO-0020 emitted")
    func ruleTwoIsPROZeroTwentyUnchanged() {
        for url in ["chrome://newtab", "about:blank", "devtools://devtools/bundled/x.html"] {
            let out = BrowserTarget.handoff(for: chrome, probe: probe(url), detail: .full,
                                            lanes: .obscuraOnly)
            #expect(out.use == nil, "\(url)")
            #expect(out.url == nil)
            #expect(out.commands == nil)
            #expect(out.why == nil)
            #expect(out.urlUnavailable == BrowserTarget.notOpenable)
            #expect(out.boundary == BrowserTarget.boundary(for: .obscura))
            #expect(out.continuity == BrowserTarget.continuity(for: .obscura))
        }
        // about: is deliberately not a browser-internal scheme here: about:blank
        // is the empty tab every browser opens, and starting an autonomous agent
        // for one is absurd.
        let blank = BrowserTarget.handoff(for: chrome, probe: probe("about:blank"),
                                          detail: .full,
                                          lanes: lanes(obscura: true, second: .enabled))
        #expect(blank.use == nil)
        #expect(!BrowserTarget.isBrowserInternal("about:blank"))
    }

    // MARK: - Clause 6 — rule 3, a local file is nobody's page

    @Test("a local file or an inline payload names neither tool")
    func aLocalFileIsNotEitherToolsJob() throws {
        for url in ["file:///Users/x/page.html", "data:text/html,<p>hello"] {
            let out = BrowserTarget.handoff(for: chrome, probe: probe(url), detail: .full,
                                            lanes: lanes(obscura: true, second: .enabled))
            #expect(out.use == nil, "\(url)")
            #expect(out.urlUnavailable == BrowserTarget.notAnInstrument)
            let encoded = try json(out)
            #expect(!encoded.contains("browser-use"))
            // Pointing an agent holding a live profile at a local file is a worse
            // answer than no answer, and Obscura is not the instrument either.
            #expect(!(out.notes ?? []).contains { $0.contains("obscura") })
        }
    }

    // MARK: - Clause 7 — the second lane is never a fallback for an ordinary page

    @Test("an ordinary page with Obscura gone is told Obscura is gone, never handed the agent")
    func theSecondLaneIsNeverAFallback() {
        // An earlier draft routed here whenever Obscura was missing. That made a
        // credentialed autonomous agent the default for every web page on a
        // machine without Obscura, on exactly the pages most likely to be hostile,
        // since that agent's loop ingests what it reads. Obscura being uninstalled
        // is a fact about the machine, not a capability fact about the page.
        for browser in [chrome, safari, firefox] {
            for probe in [self.probe("https://example.com/a"), nil] {
                let out = BrowserTarget.handoff(for: browser, probe: probe, detail: .full,
                                                lanes: lanes(obscura: false, second: .enabled))
                #expect(out.use == nil, "\(browser.name)")
                #expect(out.toolUnavailable == ObscuraTool.absence)
            }
        }
    }

    // MARK: - The pages no lane is offered for

    @Test("the browser's own credential, extension and history pages are nobody's to drive")
    func sensitiveInternalPagesGetNoLane() {
        let on = lanes(obscura: true, second: .enabled)
        for url in ["chrome://settings", "chrome://settings/passwords",
                    "chrome://password-manager/passwords", "chrome://extensions",
                    "chrome://flags", "chrome://history", "chrome://net-internals/#dns",
                    "brave://wallet", "edge://settings/profiles",
                    "devtools://devtools/bundled/x.html"] {
            let out = BrowserTarget.handoff(for: chrome, probe: probe(url), detail: .full,
                                            lanes: on)
            #expect(out.use == nil, "\(url)")
            #expect(out.url == nil)
            #expect(out.urlUnavailable == BrowserTarget.sensitiveInternal)
        }
        // A page that merely looks like one of them is not one of them.
        #expect(!BrowserTarget.isSensitiveInternal("chrome://settings-guide"))
        #expect(!BrowserTarget.isSensitiveInternal("https://example.com/settings"))
    }

    @Test("a window Proctor has only partly read is not routed on what it did read")
    func aPartlyReadWindowIsNotRouted() {
        // One extension frame beside a signed-in tab whose AXURL came back empty
        // would otherwise read as "every URL here is internal", and route a bank
        // to an agent holding the operator's cookies.
        let partly = WebContentProbe(areas: [
            WebArea(url: "chrome-extension://abcdef/popup.html",
                    frame: Rect(x: 0, y: 0, w: 400, h: 300)),
            WebArea(url: nil, frame: Rect(x: 0, y: 0, w: 800, h: 600))
        ])
        let out = BrowserTarget.handoff(for: chrome, probe: partly, detail: .full,
                                        lanes: lanes(obscura: true, second: .enabled))
        #expect(out.use == nil)
        #expect(out.urlUnavailable == BrowserTarget.partialURLs)
    }

    // MARK: - Clause 8 — rule 5, the default, which says it is the default

    @Test("the default lane is Obscura and says so in a sentence")
    func ruleFiveIsTheDefault() {
        for second in [SecondLaneState.off, .enabled, .unavailable] {
            let out = BrowserTarget.handoff(for: chrome, probe: probe("https://example.com/a"),
                                            detail: .full,
                                            lanes: lanes(obscura: true, second: second))
            #expect(out.use == "obscura", "\(second)")
            #expect(out.why == BrowserTarget.whyDefault)
            #expect(out.commands == BrowserTarget.commands(for: .obscura))
            #expect(out.caveats == BrowserTarget.caveats(for: .obscura))
            #expect(out.toolUnavailable == nil)
        }
    }

    // MARK: - Clause 9 — the ladder is complete

    @Test("no combination recommends a tool the machine does not have")
    func theLadderNeverNamesAToolThatIsNotThere() {
        for obscura in [true, false] {
            for second in [SecondLaneState.off, .enabled, .unavailable] {
                for browser in [chrome, safari] {
                    for probe in [self.probe("https://example.com/a"), nil] {
                        let out = BrowserTarget.handoff(for: browser, probe: probe, detail: .brief,
                                                        lanes: lanes(obscura: obscura, second: second))
                        switch out.use {
                        case "obscura":
                            #expect(obscura, "recommended obscura without obscura")
                        case "browser-use":
                            Issue.record("an ordinary page must never reach the second lane")
                        case nil:
                            #expect(!obscura)
                            #expect(out.toolUnavailable != nil)
                        default:
                            Issue.record("unknown lane \(out.use ?? "")")
                        }
                        // A lane is always accompanied by its reason, and never
                        // the other way round.
                        #expect((out.use == nil) == (out.why == nil))
                    }
                }
            }
        }
    }

    // MARK: - Clause 10 — enabled and not installed

    @Test("a lane that was enabled and is not installed says so, without an install command")
    func anEnabledLaneThatIsMissingSaysSo() throws {
        let out = BrowserTarget.handoff(for: chrome, probe: probe("chrome://newtab"),
                                        detail: .full,
                                        lanes: lanes(obscura: true, second: .unavailable))
        #expect(out.use == nil)
        let absence = try #require(out.toolUnavailable)
        #expect(absence.tool == "browser-use")
        #expect(absence.docs == BrowserUseTool.docs)
        // Proctor asks nobody to install this. `ToolAbsence` cannot carry command
        // text and this is where that matters most.
        for field in [absence.missing, absence.docs, absence.askThePerson] {
            for fragment in ["curl", "pip ", "pipx", "uvx", "brew ", "tar ", "mv "] {
                #expect(!field.contains(fragment), "\(fragment) in an absence")
            }
        }
    }

    // MARK: - Clauses 11 and 13 — what the second lane says about itself

    @Test("the second lane discloses what it is at both detail levels, not only in the caveats")
    func theSecondLaneDisclosesItselfEarly() {
        let on = lanes(obscura: true, second: .enabled)
        let brief = BrowserTarget.handoff(for: chrome, probe: probe("chrome://newtab"),
                                          detail: .brief, lanes: on)
        let full = BrowserTarget.handoff(for: chrome, probe: probe("chrome://newtab"),
                                         detail: .full, lanes: on)

        // A `why` about a scheme cannot carry what the lane actually is, and the
        // brief form is what a model sees on every step of a batch.
        #expect(brief.continuity.contains("real credentials"))
        #expect(brief.continuity.contains("audit trail"))
        #expect(brief.boundary.contains("autonomous agent"))
        #expect(brief.boundary == full.boundary)
        #expect(brief.continuity == full.continuity)
        #expect(brief.why == full.why)

        // Different from Obscura's, at both levels.
        #expect(brief.boundary != BrowserTarget.boundary(for: .obscura))
        #expect(brief.continuity != BrowserTarget.continuity(for: .obscura))

        let caveats = full.caveats ?? []
        #expect(caveats.contains { $0.contains("remote-debugging") })
        #expect(caveats.contains { $0.contains("different browser") })
        #expect(caveats.contains { $0.contains("model credential") })
        #expect(caveats.contains { $0.contains("isolated browser profile") })
        #expect(brief.caveats == nil)

        // `use` is the binary's own spelling, because that is what a reader types.
        #expect(BrowserLane.browserUse.rawValue == "browser-use")
        #expect(full.use == "browser-use")
        // `why` is a sentence, not a token.
        #expect((full.why ?? "").hasSuffix("."))
        #expect((full.why ?? "").count > 60)
    }

    // MARK: - Clause 12 — no command for the second lane

    @Test("the second lane ships no command anywhere, and no Obscura flag either")
    func theSecondLaneShipsNoCommands() throws {
        let on = lanes(obscura: true, second: .enabled)
        for detail in [BrowserTarget.Detail.brief, .full] {
            let out = BrowserTarget.handoff(for: chrome, probe: probe("chrome://newtab"),
                                            detail: detail, lanes: on)
            #expect(out.commands == nil, "commands must be absent, not empty")
            let encoded = try json(out)
            for fragment in ["uvx", "pip ", "pipx", "curl", "--allow-private-network",
                             "obscura fetch", "obscura serve"] {
                #expect(!encoded.contains(fragment), "\(fragment) reached the wire")
            }
        }
        #expect(BrowserTarget.commands(for: .browserUse) == nil)
    }

    // MARK: - Clause 14 — notes

    @Test("notes are Obscura's facts, several at once, and never ride the other lane")
    func notesAreObscuraOnly() {
        let url = "http://192.168.1.4:3000/report.pdf?token=1"
        for detail in [BrowserTarget.Detail.brief, .full] {
            let onObscura = BrowserTarget.handoff(for: chrome, probe: probe(url), detail: detail,
                                                  lanes: .obscuraOnly)
            #expect(onObscura.notes == [BrowserTarget.privateNetworkNote, BrowserTarget.pdfNote],
                    "\(detail)")
        }
        // The other lane never carries them: a warning about an SSRF block that
        // lane does not have would be advice for the wrong tool. (The lane only
        // ever fires on a browser-internal page, which is neither private-network
        // nor a PDF, so this is belt and braces on a rule that holds by
        // construction.)
        let onSecond = BrowserTarget.handoff(for: chrome, probe: probe("chrome://newtab"),
                                             detail: .full,
                                             lanes: lanes(obscura: true, second: .enabled))
        #expect(onSecond.use == "browser-use")
        #expect(onSecond.notes == nil)

        // A PDF is matched on the path, so a query string does not hide it and a
        // page that merely mentions one is not one.
        #expect(BrowserTarget.isPDF("https://a.example/x.PDF?y=1#p2"))
        #expect(!BrowserTarget.isPDF("https://a.example/pdf-guide"))
        let plain = BrowserTarget.handoff(for: chrome, probe: probe("https://example.com/a"),
                                          detail: .brief, lanes: .obscuraOnly)
        #expect(plain.notes == nil)
    }

    // MARK: - The status row, decided here rather than in a view

    @Test("the status row appears only when this machine has something to say about the lane")
    func theStatusRowFollowsTheGate() {
        #expect(BrowserUseTool.statusSummary(secondLane: .off, found: false) == nil)
        // Presence alone buys no row: the operator's switch is what makes the
        // tool part of this machine's Proctor, on every surface alike.
        #expect(BrowserUseTool.statusSummary(secondLane: .off, found: true) == nil)
        #expect(BrowserUseTool.statusSummary(secondLane: .enabled, found: true) == "second lane on")
        #expect(BrowserUseTool.statusSummary(secondLane: .unavailable, found: false)
                == "lane set, not installed")
    }
}
