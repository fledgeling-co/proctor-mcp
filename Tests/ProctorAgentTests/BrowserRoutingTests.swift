import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0020 — the wiring half of routing browser work to Obscura.
//
// The decision itself is pure and tested in ProctorCoreTests. What is tested here
// is where the decision reaches the wire: that attaching to a browser says so
// once and in full, that a read or an act into a page says so briefly, that a read
// or an act into the browser's own chrome says nothing, and above all that a
// native app hosting a web view is never routed — that last one is the boundary
// the feature is for, and the only way to check it is to run the same web-area
// probe under two different bundle identifiers.
//
// What is NOT testable here: that a real Chrome window answers AXURL, and that a
// real page element sits inside a real AXWebArea's frame. Both need a window
// server and a running browser.

@Suite("Browser routing")
struct BrowserRoutingTests {

    private static let chrome = "com.google.Chrome"
    private static let nativeApp = "com.example.nativeapp"

    /// A window showing a page at 100,200 800x600 — everything above y=200 is the
    /// browser's own toolbar.
    private static let pageProbe = WebContentProbe(areas: [
        WebArea(url: "https://example.com/dashboard",
                frame: Rect(x: 100, y: 200, w: 800, h: 600))
    ])

    private func harness(bundleId: String,
                         probe: WebContentProbe? = nil,
                         nodeFrame: Rect? = nil) async throws -> (Session, FakeAX) {
        let ax = FakeAX(bundleId: bundleId)
        ax.webContentProbe = probe
        if let nodeFrame { ax.nodeFrame = nodeFrame }
        let session = Session(ax: ax, capture: FakeCapture())
        // The trail is a real file for a real agent; a test that forgets this
        // writes to the operator's own history.
        await session.setAuditSink(AuditCollector().sink)
        _ = try await session.attachResolved(bundleId: bundleId, pid: nil, name: nil)
        return (session, ax)
    }

    private func browser(_ json: JSONValue?) -> [String: JSONValue]? {
        json?.objectValue?["browser"]?.objectValue
    }

    // MARK: - proctor_apps

    @Test("listing marks a browser and leaves everything else alone")
    func listMarksBrowsers() async throws {
        let (session, _) = try await harness(bundleId: Self.chrome)
        let rows = try await session.listApps(includeWindowless: true).objectValue?["apps"]?.arrayValue
        let row = try #require(rows?.first?.objectValue)
        let handoff = try #require(row["browser"]?.objectValue)
        #expect(handoff["browser"]?.stringValue == "Google Chrome")
        #expect(handoff["boundary"]?.stringValue == BrowserTarget.boundary)
        // Brief: the caveats belong to attach, not to every row of a list.
        #expect(handoff["caveats"] == nil)

        let (native, _) = try await harness(bundleId: Self.nativeApp)
        let nativeRows = try await native.listApps(includeWindowless: true)
            .objectValue?["apps"]?.arrayValue
        #expect(nativeRows?.first?.objectValue?["browser"] == nil)
    }

    @Test("attaching to a browser says it once, in full")
    func attachCarriesFullDetail() async throws {
        // Attach is the moment the instrument is chosen, so it is the one place
        // the measured Obscura edges are worth their tokens.
        let (session, _) = try await harness(bundleId: Self.chrome)
        let handoff = try #require(browser(try await session.attach(bundleId: Self.chrome,
                                                                    pid: nil, name: nil)))
        #expect(handoff["caveats"]?.arrayValue?.count == 7)
        #expect(handoff["commands"]?.arrayValue?.isEmpty == false)
        #expect(handoff["use"]?.stringValue == "obscura")
        #expect(handoff["continuity"]?.stringValue == BrowserTarget.continuity)
    }

    @Test("attaching to a native app says nothing about browsers")
    func attachToNativeAppIsSilent() async throws {
        let (session, _) = try await harness(bundleId: Self.nativeApp)
        let result = try await session.attach(bundleId: Self.nativeApp, pid: nil, name: nil)
        #expect(browser(result) == nil)
    }

    // MARK: - The boundary

    @Test("the same page probe routes in a browser and never in a native app")
    func webViewInsideANativeAppIsNeverRouted() async throws {
        // This is the feature's boundary in one test. A native Mac app hosting a
        // WKWebView, and an Electron app, both present an AXWebArea; neither is
        // reachable by Obscura, because reaching their content means attaching to
        // the host process. Identity comes from the bundle, and only from there.
        let (browserSession, _) = try await harness(bundleId: Self.chrome, probe: Self.pageProbe)
        let inBrowser = try await browserSession.snapshot(window: "win-1",
                                                          options: .init(), sinceRevision: nil)
        #expect(inBrowser.browser?.url == "https://example.com/dashboard")

        let (nativeSession, _) = try await harness(bundleId: Self.nativeApp, probe: Self.pageProbe)
        let inNativeApp = try await nativeSession.snapshot(window: "win-1",
                                                           options: .init(), sinceRevision: nil)
        #expect(inNativeApp.browser == nil)
    }

    @Test("a browser window with no page in it is not a page")
    func browserWindowWithoutWebContent() async throws {
        // A browser's About panel or preferences sheet is a native window that
        // happens to belong to a browser. Nothing there is Obscura's.
        let (session, _) = try await harness(bundleId: Self.chrome, probe: nil)
        let snapshot = try await session.snapshot(window: "win-1", options: .init(),
                                                  sinceRevision: nil)
        #expect(snapshot.browser == nil)
    }

    // MARK: - proctor_find

    @Test("finding an element in the page discloses; finding one in the toolbar does not")
    func findRespectsTheBoundary() async throws {
        let inPage = try await harness(bundleId: Self.chrome, probe: Self.pageProbe,
                                       nodeFrame: Rect(x: 200, y: 300, w: 80, h: 24))
        let pageResult = try await inPage.0.find(window: "win-1",
                                                 predicate: FindPredicate(role: "AXButton"),
                                                 limit: 25)
        #expect(browser(pageResult)?["url"]?.stringValue == "https://example.com/dashboard")

        // The reload button, above the web area. Native chrome stays Proctor's, and
        // telling a model to reach for a different tool to press it would be wrong.
        let inChrome = try await harness(bundleId: Self.chrome, probe: Self.pageProbe,
                                         nodeFrame: Rect(x: 120, y: 140, w: 24, h: 24))
        let chromeResult = try await inChrome.0.find(window: "win-1",
                                                     predicate: FindPredicate(role: "AXButton"),
                                                     limit: 25)
        #expect(browser(chromeResult) == nil)
    }

    // MARK: - proctor_act

    @Test("acting on the page discloses once for the whole batch")
    func actDisclosesOncePerCall() async throws {
        let (session, ax) = try await harness(bundleId: Self.chrome, probe: Self.pageProbe,
                                              nodeFrame: Rect(x: 200, y: 300, w: 80, h: 24))
        let steps = (0..<4).map { ActionStep(kind: .press, node: "node-1", label: "step \($0)") }
        let result = try await session.act(window: "win-1", steps: steps, settle: .default,
                                           foreground: false, captureEach: false,
                                           diffEach: false, record: nil)

        // One object on the result, not one per step: the step list is untouched.
        #expect(browser(result)?["url"]?.stringValue == "https://example.com/dashboard")
        let stepResults = try #require(result.objectValue?["steps"]?.arrayValue)
        #expect(stepResults.count == 4)
        for step in stepResults { #expect(step.objectValue?["browser"] == nil) }

        // Nothing was refused and nothing changed plane. The advisory rides along
        // with a batch that ran, exactly as it would have run before.
        #expect(ax.performed.count == 4)
        #expect(stepResults.allSatisfy { $0.objectValue?["plane"]?.stringValue == "accessibility" })
        #expect(result.objectValue?["completed"]?.intValue == 4)
    }

    @Test("acting on the browser's own chrome says nothing")
    func actOnNativeChromeIsSilent() async throws {
        let (session, ax) = try await harness(bundleId: Self.chrome, probe: Self.pageProbe,
                                              nodeFrame: Rect(x: 120, y: 140, w: 24, h: 24))
        let result = try await session.act(window: "win-1",
                                           steps: [ActionStep(kind: .press, node: "node-1")],
                                           settle: .default, foreground: false,
                                           captureEach: false, diffEach: false, record: nil)
        #expect(browser(result) == nil)
        #expect(ax.performed.count == 1)
    }

    @Test("a click at a point inside the page discloses even with no element to name")
    func coordinateStepInsideThePageDiscloses() async throws {
        // The case the brief names: a click at a point in a browser window proves
        // less than a DOM assertion does. The point is given in window coordinates
        // and the web area's frame is in screen coordinates, so the window's origin
        // is what makes the two comparable.
        let (session, _) = try await harness(bundleId: Self.chrome, probe: Self.pageProbe)
        let inside = ActionStep(kind: .click, node: nil, point: [400, 400])
        let result = try await session.act(window: "win-1", steps: [inside], settle: .default,
                                           foreground: true, captureEach: false,
                                           diffEach: false, record: nil)
        #expect(browser(result)?["url"]?.stringValue == "https://example.com/dashboard")

        // The same click in the toolbar strip is native, and stays Proctor's.
        let (other, _) = try await harness(bundleId: Self.chrome, probe: Self.pageProbe)
        let above = ActionStep(kind: .click, node: nil, point: [400, 60])
        let chromeResult = try await other.act(window: "win-1", steps: [above], settle: .default,
                                               foreground: true, captureEach: false,
                                               diffEach: false, record: nil)
        #expect(browser(chromeResult) == nil)
    }

    @Test("a batch that starts in the toolbar and ends in the page still discloses")
    func mixedBatchReachesThePage() async throws {
        // Every step is considered, not a prefix of them. A batch that clicks the
        // address bar, types, and then clicks a result in the page reaches the
        // page, and a check that stopped at the first few targets would miss it.
        let (session, _) = try await harness(bundleId: Self.chrome, probe: Self.pageProbe)
        let steps = [
            ActionStep(kind: .click, node: nil, point: [400, 60]),   // the toolbar
            ActionStep(kind: .key, key: "return"),
            ActionStep(kind: .click, node: nil, point: [400, 400])   // the page
        ]
        let result = try await session.act(window: "win-1", steps: steps, settle: .default,
                                           foreground: true, captureEach: false,
                                           diffEach: false, record: nil)
        #expect(browser(result)?["url"]?.stringValue == "https://example.com/dashboard")
    }

    @Test("a batch that names nothing positional falls back to the window")
    func keyboardOnlyBatchAsksAboutTheWindow() async throws {
        // A keystroke has no frame, so there is nothing to place inside or outside
        // the page. The window is showing a page, and the honest answer for a batch
        // aimed at it is the window's answer.
        let (session, _) = try await harness(bundleId: Self.chrome, probe: Self.pageProbe)
        let result = try await session.act(window: "win-1",
                                           steps: [ActionStep(kind: .key, key: "return")],
                                           settle: .default, foreground: true,
                                           captureEach: false, diffEach: false, record: nil)
        #expect(browser(result)?["url"]?.stringValue == "https://example.com/dashboard")
    }
}
