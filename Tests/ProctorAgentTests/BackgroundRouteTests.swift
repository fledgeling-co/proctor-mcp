import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0025 — take the background route wherever one exists, and say which one
// was taken.
//
// Two things are testable here and one is not. The wiring is: what a batch's
// foreground demand does to the lane it takes and to the result it returns, and
// whether the route a step travelled reaches the caller. The rules the new
// accessibility routes turn on are, because they are arithmetic. What is not is
// the routes themselves — `AXSelectedText` against a real text view, a real
// scroll area's bar — because those need an application on screen and an
// AXUIElement, and this suite has neither. That gap is named in the spec rather
// than papered over with a mock that would only be testing itself.

@Suite("Background routes and their reporting")
struct BackgroundRouteTests {

    private static let target = "com.example.target"

    private func harness() async throws -> (session: Session, ax: FakeAX) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture())
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax)
    }

    private func act(_ h: (session: Session, ax: FakeAX), _ steps: [ActionStep],
                     foreground: Bool = false) async throws -> JSONValue {
        try await h.session.act(window: h.ax.window.id, steps: steps, settle: .default,
                                foreground: foreground, captureEach: false, diffEach: false,
                                record: nil)
    }

    private func step(_ kind: ActionStep.Kind) -> ActionStep {
        ActionStep(kind: kind, node: "node-1")
    }

    @Test("a step says which route it took, not only which side it travelled")
    func routeReachesTheCaller() async throws {
        let h = try await harness()
        // Two steps that both report the accessibility plane and got there
        // differently. Without the route the difference — "we found another way
        // rather than taking the foreground" — is invisible from outside.
        h.ax.routeAt = [0: .selectedText, 1: .scrollBar]
        let result = try await act(h, [step(.type), step(.scroll)])
        let steps = try #require(result["steps"]?.arrayValue)
        #expect(steps[0]["plane"]?.stringValue == "accessibility")
        #expect(steps[0]["route"]?.stringValue == "selectedText")
        #expect(steps[1]["route"]?.stringValue == "scrollBar")
    }

    @Test("a step that never ran carries no route")
    func refusedStepHasNoRoute() async throws {
        let h = try await harness()
        // A click with foreground false is refused before anything is actuated,
        // so there is no route to report and none is invented.
        let result = try await act(h, [step(.click)])
        let steps = try #require(result["steps"]?.arrayValue)
        #expect(steps[0]["ok"]?.boolValue == false)
        #expect(steps[0]["route"] == nil || steps[0]["route"] == .null)
    }

    @Test("a foreground request nothing can use is ignored and reported")
    func inertForegroundRequestIsReported() async throws {
        let h = try await harness()
        let result = try await act(h, [step(.press), step(.setValue)], foreground: true)
        let block = try #require(result["foreground"])
        #expect(block["requestIgnored"]?.boolValue == true)
        #expect(block["ranInForeground"]?.boolValue == false)
        // And the run really did stay on the accessibility plane throughout.
        #expect(block["measured"]?.intValue == 0)
        // In words as well as as a flag, beside the records the way the yield
        // note already rides alongside. A caller reading prose is the one most
        // likely to be passing `foreground: true` out of habit.
        let note = try #require(result["foregroundNote"]?.stringValue)
        #expect(note.contains("the request was ignored"))
    }

    @Test("a foreground request a step could use is honoured as before")
    func liveForegroundRequestIsKept() async throws {
        let h = try await harness()
        h.ax.planeAt = [0: .syntheticEvent]
        let result = try await act(h, [step(.type)], foreground: true)
        let block = try #require(result["foreground"])
        #expect(block["requestIgnored"]?.boolValue == false)
        #expect(block["ranInForeground"]?.boolValue == true)
        #expect(block["measured"]?.intValue == 1)
    }
}

@Suite("Scroll and value rules")
struct ActuationRuleTests {

    @Test("a scroll bar moves by lines per page fraction, and stops at the ends")
    func scrollFractionClamps() {
        #expect(Actuator.scrollFraction(from: 0.5, by: 4, linesPerPage: 16) == 0.75)
        #expect(Actuator.scrollFraction(from: 0.5, by: -4, linesPerPage: 16) == 0.25)
        // Past either end is the end, not a negative or an over-scroll — an
        // out-of-range value is rejected by the bar and would lose the write.
        #expect(Actuator.scrollFraction(from: 0.98, by: 10, linesPerPage: 16) == 1)
        #expect(Actuator.scrollFraction(from: 0.01, by: -10, linesPerPage: 16) == 0)
    }

    @Test("line height and lines per page derivation")
    func lineAndPageDerivation() {
        #expect(Actuator.lineHeight(from: Rect(x: 0, y: 0, w: 100, h: 20)) == 20)
        #expect(Actuator.lineHeight(from: Rect(x: 0, y: 0, w: 100, h: 200)) == 16) // clamped fallback
        #expect(Actuator.linesPerPage(viewport: 320, lineHeight: 16) == 20)
        #expect(Actuator.linesPerPage(viewport: Double?.none, lineHeight: 16) == 16)
        #expect(Actuator.prefersPageAction(delta: 10, linesPerPage: 16) == true)
        #expect(Actuator.prefersPageAction(delta: 3, linesPerPage: 16) == false)
        #expect(Actuator.wheelPixels(delta: 3, lineHeight: 16) == 48)
    }

    @Test("a bar that did not move did not scroll")
    func movedIsMeasured() {
        #expect(Actuator.moved(from: 0.2, to: 0.3))
        // Already at the end: the write is accepted and the document does not
        // move. Reporting that as a scroll is how a caller comes to believe a
        // list was paged when it was already at the bottom.
        #expect(!Actuator.moved(from: 1.0, to: 1.0))
        #expect(!Actuator.moved(from: 0.5, to: 0.5))
    }

    @Test("a write is judged by reading it back")
    func writesAreReadBack() {
        #expect(Actuator.tookValue(read: "hello", expected: "hello"))
        // The case this exists for: a web input or custom text view accepts the
        // set, reports success, and keeps its old value. Believing the return
        // code there both reports a step that did nothing and stops the second
        // accessibility route from ever being tried.
        #expect(!Actuator.tookValue(read: "", expected: "hello"))
        #expect(!Actuator.tookValue(read: "old", expected: "hello"))
        // A field that will not report its own value cannot be checked, and
        // disbelieving every such write would push them all to the event
        // stream — the cost this whole path exists to avoid.
        #expect(Actuator.tookValue(read: nil, expected: "hello"))
    }
}

@Suite("Pointer plane wiring")
struct PointerPlaneWiringTests {

    @Test("the plane comes from the window list, not from the handle's beliefs")
    func planeFollowsTheWindowList() async throws {
        let ax = FakeAX(bundleId: "com.example.target")
        let session = Session(ax: ax, capture: FakeCapture())
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: "com.example.target", pid: nil, name: nil)

        // The fake's window says it is neither minimised nor off its Space, and
        // its CoreGraphics number belongs to no window on this machine — so the
        // plane is `hidden`, which is the point: the handle's own belief is not
        // what decides, the window list is.
        //
        // DEF-337. That number used to be the literal 7, which is Notification
        // Centre on a running Mac, so this assertion passed or failed according
        // to whether Notification Centre happened to be up. The fixture now takes
        // one above the highest live window number, and the absence it rests on
        // is asserted here rather than assumed — a fixture that stops being
        // absent must make the test say so, not quietly invert what it proves.
        let id = try #require(ax.window.cgWindowID)
        #expect(TestWindowIDs.isAbsentOnScreen(id),
                "the fixture's window number is on screen, so this test would be measuring a real window rather than a fabricated one")
        #expect(ax.window.isMinimized == false)
        #expect(ax.window.isOnActiveSpace == true)
        #expect(await session.cursorPlane(for: ax.window) == .hidden)
    }

    @Test("PROCTOR_CURSOR=0 turns the pointer off")
    func killSwitch() {
        // The overlay reads this once at start-up, and `showCursor` checks it
        // before resolving a plane or reading the window list, so a disabled
        // overlay costs nothing. That ordering is a code fact; what is testable
        // is the switch itself.
        #expect(!OverlaySwitch.isOn("PROCTOR_CURSOR", in: ["PROCTOR_CURSOR": "0"]))
        #expect(!OverlaySwitch.isOn("PROCTOR_CURSOR", in: ["PROCTOR_CURSOR": "false"]))
        #expect(OverlaySwitch.isOn("PROCTOR_CURSOR", in: [:]))
    }
}
