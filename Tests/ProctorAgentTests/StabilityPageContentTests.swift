import Testing
import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0038 — the wiring half, and the half that matters.
//
// The shapes are pinned in `StabilityDisclosureTests`. What is proved here is that
// a real `Session` classifies a step **at the moment it ran** rather than scanning
// the flow beforehand, and that a hash Proctor cannot vouch for never reaches the
// fold.
//
// The moment is the whole feature. A step's target usually does not exist until the
// steps before it have run — the click that opens the page — so a sweep classified
// up front would ship no disclosure for exactly the flow this exists to describe,
// and would still publish the render-tree number. `aWebAreaThatAppearsMidFlowIsStillClassified`
// is that case and it is the one an out-of-family review added.
//
// Not testable here: that a real browser's accessibility tree reports its web areas
// with the frames this assumes. That needs a machine with a browser being driven;
// `FakeAX` supplies the probe instead, which is the same seam `BrowserSurfaceWiringTests`
// uses.

@Suite("Stability knows when it is scoring a page")
struct StabilityPageContentTests {

    private static let chrome = "com.google.Chrome"
    /// A page filling the lower half of the fake's 800x600 window.
    private static let page = WebContentProbe(areas: [
        WebArea(url: "https://example.com/", frame: Rect(x: 0, y: 300, w: 800, h: 300))
    ])
    private static let insidePage = Rect(x: 100, y: 400, w: 40, h: 20)
    private static let inChrome = Rect(x: 100, y: 20, w: 40, h: 20)

    private func session(bundleId: String = chrome) async throws -> (Session, FakeAX) {
        let ax = FakeAX(bundleId: bundleId)
        let session = Session(ax: ax, capture: FakeCapture())
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: bundleId, pid: nil, name: nil)
        return (session, ax)
    }

    /// Record a flow of `steps` and sweep it `runs` times.
    private func sweep(_ session: Session, ax: FakeAX, steps: [ActionStep],
                       runs: Int = 2) async throws -> StabilityReport {
        _ = try await session.flowStart(name: "sweep", window: ax.window.id, description: nil)
        _ = try await session.act(window: ax.window.id, steps: steps, settle: .default,
                                  foreground: false, captureEach: false, diffEach: false,
                                  record: "sweep")
        _ = try await session.flowStop()
        return try await session.stability(flow: "sweep", runs: runs, window: ax.window.id,
                                           resetBetween: [], includeTiles: false,
                                           captureEach: false, pointerMarks: false)
    }

    // MARK: - A1 — one detection, and a native window pays nothing for it

    @Test("a window no browser renders carries no subject and is never asked for web content")
    func nonBrowserWindowReadsNoWebContent() async throws {
        let (session, ax) = try await session(bundleId: "com.example.fake")
        // Set deliberately: if the catalogue gate were missing, this probe would be
        // read and the step would classify, so a positive assertion would pass for
        // the wrong reason.
        ax.webContentProbe = Self.page
        ax.nodeFrame = Self.insidePage

        let report = try await sweep(session, ax: ax,
                                     steps: [ActionStep(kind: .press, node: "n1")])
        #expect(report.stepBasis == nil)
        #expect(report.pageContent == nil)
    }

    // MARK: - A2 — classified at the step, not scanned before the sweep

    @Test("a web area that only appears mid-flow still classifies the step that met it")
    func aWebAreaThatAppearsMidFlowIsStillClassified() async throws {
        let (session, ax) = try await session()
        ax.nodeFrame = Self.insidePage
        // Recorded with no page in the window at all. This is the half that makes
        // the test mean something: whatever the sweep concludes cannot have come
        // from the recording, because at record time there was nothing to see.
        ax.webContentProbe = nil

        _ = try await session.flowStart(name: "sweep", window: ax.window.id, description: nil)
        _ = try await session.act(window: ax.window.id,
                                  steps: [ActionStep(kind: .press, node: "n1")],
                                  settle: .default, foreground: false, captureEach: false,
                                  diffEach: false, record: "sweep")
        _ = try await session.flowStop()

        // The page is up by the time the sweep runs, which is the shape of every
        // flow that opens something and then drives it.
        ax.webContentProbe = Self.page

        let report = try await session.stability(flow: "sweep", runs: 2, window: ax.window.id,
                                                 resetBetween: [], includeTiles: false,
                                                 captureEach: false, pointerMarks: false)
        // Classified from the sweep's own passes. A scan of the recording would have
        // had nothing to classify, and a subject inherited from the recorded step
        // would have said browserChrome.
        let basis = try #require(report.stepBasis)
        #expect(basis[0].subjects == [.pageContent])
        #expect(report.pageContent?.steps == [0])
    }

    @Test("repeats that disagree about the boundary report both, rather than the first")
    func repeatsThatDisagreeAboutTheBoundaryReportBoth() async throws {
        let (session, ax) = try await session()
        ax.nodeFrame = Self.insidePage
        ax.webContentProbe = Self.page

        _ = try await session.flowStart(name: "sweep", window: ax.window.id, description: nil)
        _ = try await session.act(window: ax.window.id,
                                  steps: [ActionStep(kind: .press, node: "n1")],
                                  settle: .default, foreground: false, captureEach: false,
                                  diffEach: false, record: "sweep")
        _ = try await session.flowStop()

        // The page goes away between the two passes — a navigation, a tab close.
        // The step's target now sits in the chrome, so the two repeats classified
        // the same step index two different ways.
        //
        // Perform 0 was the recording and the sweep's passes are performs 1 and 2.
        // Clearing on perform 1 puts the change AFTER the first pass has classified
        // and acted, and BEFORE the second pass classifies, which is what a
        // navigation between repeats looks like. The index comes from the fake
        // rather than a captured counter, which Swift 6 will not let a `@Sendable`
        // closure mutate.
        ax.onPerform = { index in
            if index >= 1 { ax.webContentProbe = nil }
        }

        let report = try await session.stability(flow: "sweep", runs: 2, window: ax.window.id,
                                                 resetBetween: [], includeTiles: false,
                                                 captureEach: false, pointerMarks: false)

        // Both, in first-seen order. Collapsing to one would label the other repeat
        // with something it did not do, and this step's instability belongs to the
        // flow taking two paths rather than to the application.
        let basis = try #require(report.stepBasis)
        #expect(basis[0].subjects == [.pageContent, .browserChrome])
        // It was page content in at least one repeat, so the disclosure names it.
        #expect(report.pageContent?.steps == [0])
    }

    @Test("a browser sweep that never touched the page carries no page disclosure")
    func anAllChromeSweepCarriesNoPageDisclosure() async throws {
        let (session, ax) = try await session()
        ax.webContentProbe = Self.page
        ax.nodeFrame = Self.inChrome

        let report = try await sweep(session, ax: ax,
                                     steps: [ActionStep(kind: .press, node: "n1")])
        let basis = try #require(report.stepBasis)
        #expect(basis[0].subjects == [.browserChrome])
        // The key is absent, exactly as on a native window: nothing here was
        // measured over a render tree.
        #expect(report.pageContent == nil)
    }

    // MARK: - A3 / A5 — per step, with the browser named once

    @Test("a flow touching chrome and then the page reports both, by step index")
    func aFlowTouchingChromeThenPageReportsBoth() async throws {
        let (session, ax) = try await session()
        ax.webContentProbe = Self.page
        // Two elements, two frames: the toolbar button and something on the page.
        ax.nodesByID = [
            "toolbar": AXNode(id: "toolbar", role: "AXButton", title: "Reload",
                              frame: Self.inChrome),
            "link": AXNode(id: "link", role: "AXLink", title: "Next", frame: Self.insidePage)
        ]

        let report = try await sweep(session, ax: ax, steps: [
            ActionStep(kind: .press, node: "toolbar"),
            ActionStep(kind: .press, node: "link")
        ])

        let basis = try #require(report.stepBasis)
        #expect(basis.map(\.step) == [0, 1])
        #expect(basis[0].subjects == [.browserChrome])
        #expect(basis[1].subjects == [.pageContent])

        // One disclosure for the sweep, naming only the step that was page content.
        // A single flag on the report would have marked the reload button suspect.
        let page = try #require(report.pageContent)
        #expect(page.steps == [1])
        #expect(page.browser == "Google Chrome")
        #expect(page.bundleId == Self.chrome)
        #expect(page.evidence == BrowserTarget.evidence)
    }

    // MARK: - A4 — the score is still there, and still a verdict

    @Test("a page-content sweep still scores and still returns a determinism verdict")
    func pageContentStillScoresAndStillVerdicts() async throws {
        let (session, ax) = try await session()
        ax.webContentProbe = Self.page
        ax.nodeFrame = Self.insidePage

        let report = try await sweep(session, ax: ax,
                                     steps: [ActionStep(kind: .press, node: "n1")])
        // Nothing is withheld for being page content. A flow that agreed across
        // every repeat agreed, and saying which tree it agreed in does not make
        // the agreement less true.
        #expect(report.deterministic)
        #expect(report.firstDivergence == nil)
        #expect(report.stepInstability == [0])
        #expect(report.pageContent != nil)
    }

    // MARK: - A10 — on a browser window, absence means one thing

    @Test("a step naming no resolvable target is unclassified rather than absent")
    func everyStepOfABrowserWindowCarriesASubject() async throws {
        let (session, ax) = try await session()
        ax.webContentProbe = Self.page
        // A menu path names neither an element nor a point, so which side of the
        // boundary it fell on was never established. That is its own answer, and
        // it must not look like the answer a native window gives.
        let report = try await sweep(session, ax: ax,
                                     steps: [ActionStep(kind: .menu, menuPath: ["File", "New"])])

        let basis = try #require(report.stepBasis)
        #expect(basis[0].subjects == [.unclassified])
        // And no page-content disclosure, because nothing was measured over a page.
        #expect(report.pageContent == nil)
    }

    // MARK: - A6 / A7 / A8 / A8b — an unvouchable hash is evidence, not a sample

    /// A backend death that says the action may already have landed. The flag is
    /// the backend's own claim; PRO-0045 forbids reading it off the code.
    private static let unvouchable = AgentError(
        code: .actionIndeterminate,
        message: "the backend stopped answering mid-step",
        indeterminate: true)

    @Test("an unvouchable hash never reaches the score, and is kept on the step")
    func anUnvouchedHashIsNotFolded() async throws {
        let (session, ax) = try await session(bundleId: "com.example.fake")

        _ = try await session.flowStart(name: "sweep", window: ax.window.id, description: nil)
        _ = try await session.act(window: ax.window.id,
                                  steps: [ActionStep(kind: .press, node: "n1")],
                                  settle: .default, foreground: false, captureEach: false,
                                  diffEach: false, record: "sweep")
        _ = try await session.flowStop()

        // Performs 0 is the recording. The sweep's two passes are performs 1 and 2;
        // the second pass dies mid-step with the action's fate unknown.
        ax.failPerformWith = [2: Self.unvouchable]

        let report = try await session.stability(flow: "sweep", runs: 2, window: ax.window.id,
                                                 resetBetween: [], includeTiles: false,
                                                 captureEach: false, pointerMarks: false)

        let basis = try #require(report.stepBasis)
        // One repeat contributed a hash; the other's post-state was refused.
        #expect(basis[0].samples == 1)
        #expect(basis[0].withheld == 1)
        // A8 — one sample is no comparison, so no number is published for it,
        // even though the legacy array still carries the 0.0 that made this a trap.
        #expect(basis[0].instability == nil)
        #expect(report.stepInstability == [0])
        // A8b — and the sweep is not deterministic on that evidence.
        #expect(!report.deterministic)
        // A7 — the reading itself survives where it belongs.
        #expect(report.notes.contains { $0.contains("withheld from the score") })
    }

    @Test("the withheld reading is still on the step it was taken for")
    func theWithheldHashStaysOnTheStep() async throws {
        let (session, ax) = try await session(bundleId: "com.example.fake")
        ax.failPerformWith = [0: Self.unvouchable]
        let result = try await session.act(window: ax.window.id,
                                           steps: [ActionStep(kind: .press, node: "n1")],
                                           settle: .default, foreground: false,
                                           captureEach: false, diffEach: false, record: nil)
        let steps = try #require(result.objectValue?["steps"]?.arrayValue)
        let step = try #require(steps.first?.objectValue)
        // Evidence, not proof, and reported beside the score rather than into it.
        #expect(step["stateHash"]?.stringValue != nil)
        #expect(step["ok"]?.boolValue == false)
    }

    @Test("an indeterminate step is the last result in its repeat")
    func anIndeterminateStepIsTheLastResultInItsRepeat() async throws {
        // The assumption the withholding rests on: such a step ends its repeat, so
        // stopping the hash collection there drops nothing that ran. The day this
        // stops being true, the `break` in the sweep starts losing later steps —
        // which is why it is pinned rather than left in a comment.
        let (session, ax) = try await session(bundleId: "com.example.fake")
        ax.failPerformWith = [0: Self.unvouchable]
        let result = try await session.act(window: ax.window.id, steps: [
            ActionStep(kind: .press, node: "n1"),
            ActionStep(kind: .press, node: "n2")
        ], settle: .default, foreground: false, captureEach: false, diffEach: false, record: nil)

        let steps = try #require(result.objectValue?["steps"]?.arrayValue)
        #expect(steps.count == 1)
        #expect(result.objectValue?["failedAt"]?.intValue == 0)
    }

    // MARK: - the two surfaces agree

    @Test("the entry's instability is the number the legacy array carries")
    func entryInstabilityAgreesWithTheLegacyArray() async throws {
        let (session, ax) = try await session()
        ax.webContentProbe = Self.page
        ax.nodeFrame = Self.insidePage

        let report = try await sweep(session, ax: ax, steps: [
            ActionStep(kind: .press, node: "n1"),
            ActionStep(kind: .press, node: "n2")
        ], runs: 3)

        // Both come from one fold, so this is a regression guard rather than the
        // mechanism — but two fields that can disagree and are never checked are
        // worse than one field, which PRO-0051 established.
        let basis = try #require(report.stepBasis)
        for entry in basis where entry.instability != nil {
            #expect(entry.instability == report.stepInstability[entry.step])
        }
    }
}
