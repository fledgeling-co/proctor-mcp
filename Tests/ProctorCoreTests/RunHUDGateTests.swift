import Testing
import Foundation
@testable import ProctorCore

// PRO-0033 — a person's click reaches Stop.
//
// The gate, the coordinate flip, and the tap's Stop route, as values. What a
// test here cannot reach is named in the spec and not pretended at: the tap
// swallowing a real click, the panel receiving one, `ignoresMouseEvents` taking
// effect in the window server, and the published rectangle matching what is on
// screen.
//
// What a wrong answer costs is specific and asymmetric, which is why several of
// these assert a direction rather than just a value. A gate that fails closed
// costs a swallowed synthetic event. A gate that fails open costs the kill
// switch, and a click that was aimed at Stop lands in the application the run is
// driving instead.

private func point(_ x: Double, _ y: Double) -> RunHUDPlacement.Point {
    RunHUDPlacement.Point(x: x, y: y)
}

/// A panel docked bottom-right of a 1728x1117 display, in Quartz space.
private let panel = Rect(x: 1342, y: 731, w: 352, h: 352)

private func step(_ kind: ActionStep.Kind, node: String? = "n1") -> ActionStep {
    ActionStep(kind: kind, node: node)
}

@Suite("Run HUD mouse gate")
struct RunHUDGateTests {

    // MARK: - A1: the plane AND the point

    @Test("a step posting away from the panel does not move it")
    func gateNeedsBothThePlaneAndThePoint() {
        // The whole of the change. Before this, every synthetic step made the
        // panel click-through for its duration, so a person's click on Stop
        // passed through into the application under test — the kill switch dead
        // and the run corrupted by the same gesture — whether or not the step
        // went anywhere near the panel.
        #expect(!RunHUDGate.stepsAside(points: [point(400, 300)], panel: panel))
        #expect(RunHUDGate.stepsAside(points: [point(1500, 900)], panel: panel))
    }

    @Test("the panel's own edges count as being in the way")
    func edgesAreInside() {
        #expect(RunHUDGate.stepsAside(points: [point(1342, 731)], panel: panel))
        #expect(RunHUDGate.stepsAside(points: [point(1694, 1083)], panel: panel))
        #expect(!RunHUDGate.stepsAside(points: [point(1341.9, 731)], panel: panel))
    }

    @Test("no panel and no resolved target both mean do not step aside")
    func nothingToStandInTheWay() {
        // Both fail toward keeping Stop clickable. The cost of being wrong that
        // way is one swallowed synthetic event; the cost of the other way is the
        // kill switch.
        #expect(!RunHUDGate.stepsAside(points: [point(1500, 900)], panel: nil))
        #expect(!RunHUDGate.stepsAside(points: [], panel: panel))
        #expect(!RunHUDGate.stepsAside(points: [point(1500, 900)],
                                       panel: Rect(x: 0, y: 0, w: 0, h: 0)))
    }

    // MARK: - A-iv: a route is tested along its whole length

    @Test("a drag that crosses the panel with both ends outside it still moves it")
    func aRouteIsTestedAlongItsWholeLength() {
        // Both endpoints are clear of the panel and the gesture passes straight
        // through it. Testing only the ends would leave the panel intercepting
        // the middle of somebody's drag.
        let across = [point(1200, 900), point(1800, 900)]
        #expect(RunHUDGate.stepsAside(points: across, panel: panel))

        let clear = [point(1200, 400), point(1800, 400)]
        #expect(!RunHUDGate.stepsAside(points: clear, panel: panel))
    }

    @Test("a multi-segment route is tested at every segment")
    func everySegmentCounts() {
        let route = [point(100, 100), point(200, 200), point(1200, 900), point(1800, 900)]
        #expect(RunHUDGate.stepsAside(points: route, panel: panel))
    }

    // MARK: - A13: the flip is arrangement-wide

    @Test("the AppKit and Quartz transforms are inverses")
    func theQuartzFlipRoundTrips() {
        let appKit = Rect(x: 1342, y: 34, w: 352, h: 352)
        let quartz = RunHUDPlacement.quartz(from: appKit, primaryMaxY: 1117)
        #expect(quartz.y == 1117 - 34 - 352)
        let back = RunHUDPlacement.appKit(from: quartz, primaryMaxY: 1117)
        #expect(back.x == appKit.x && back.y == appKit.y)
        #expect(back.w == appKit.w && back.h == appKit.h)
    }

    @Test("a display above the menu bar is not inverted, because the flip is against the primary")
    func aDisplayAboveTheMenuBarIsNotInverted() {
        // A second display stacked above the primary has positive AppKit y
        // beyond the primary's height, which is Quartz y ABOVE zero — negative.
        // Flipping against that screen's own maxY instead would place the
        // rectangle back down inside the primary display, where a click on empty
        // screen would stop a run.
        let onSecond = Rect(x: 0, y: 1200, w: 352, h: 352)
        let quartz = RunHUDPlacement.quartz(from: onSecond, primaryMaxY: 1117)
        #expect(quartz.y < 0)
        #expect(RunHUDPlacement.appKit(from: quartz, primaryMaxY: 1117).y == 1200)
    }
}

@Suite("Run HUD gate in the model")
struct RunHUDGateModelTests {

    private func began() -> RunHUDState {
        var state = RunHUDState()
        state.apply(.runBegan(total: 3, app: "Acme Console"))
        return state
    }

    @Test("the gate follows the event, not the step's kind")
    func theGateFollowsTheEvent() {
        var state = began()
        state.apply(.stepActing(step: step(.click), node: nil, synthetic: true,
                                stepsAside: false))
        // Synthetic, but posting somewhere the panel is not: the words go up and
        // the panel stays clickable.
        #expect(state.model.syntheticInFlight)
        #expect(!state.model.stepsAside)

        state.apply(.stepActing(step: step(.click), node: nil, synthetic: true,
                                stepsAside: true))
        #expect(state.model.stepsAside)
    }

    @Test("a fallback opens the gate and an accessibility success does not")
    func aFallbackOpensItAndAnAccessibilitySuccessDoesNot() {
        // `scroll` is not a synthetic kind. Before this it could never move the
        // panel, so a fallback wheel event posted under the panel was swallowed
        // by it.
        var state = began()
        state.apply(.stepActing(step: step(.scroll), node: nil, synthetic: false,
                                stepsAside: true))
        #expect(state.model.stepsAside)
        #expect(!state.model.syntheticInFlight)

        var other = began()
        other.apply(.stepActing(step: step(.scroll), node: nil, synthetic: false,
                                stepsAside: false))
        #expect(!other.model.stepsAside)
    }

    @Test("the gate closes on the settle, not at the next step")
    func theGateClosesOnTheSettle() {
        // Holding it to the next step leaves Stop dead across the settle and the
        // gap between steps, which is exactly when somebody reaches for it — and
        // it contradicts PRO-0026's claim that the panel is clickable between
        // steps. The statement is deliberately left up: the words are about the
        // plane and the batch is not over.
        var state = began()
        state.apply(.stepActing(step: step(.click), node: nil, synthetic: true,
                                stepsAside: true))
        #expect(state.model.stepsAside)
        state.apply(.stepSettled(step: step(.click), node: nil, settleMs: 40,
                                 plane: .syntheticEvent))
        #expect(!state.model.stepsAside)
        #expect(state.model.syntheticInFlight)
    }

    @Test("every ending closes the gate")
    func everyEndingClosesTheGate() {
        // Five endings, and every path through a run reaches one of them. A gate
        // left open on any of them is a panel that never takes a click again.
        let endings: [RunHUDEvent] = [
            .stepSettled(step: step(.click), node: nil, settleMs: 10, plane: .syntheticEvent),
            .stepRefused(step: step(.click), node: nil),
            .stepFailed(step: step(.click), node: nil),
            .yielded(reason: .userInput),
            .runEnded(.completed)
        ]
        for ending in endings {
            var state = began()
            state.apply(.stepActing(step: step(.click), node: nil, synthetic: true,
                                    stepsAside: true))
            #expect(state.model.stepsAside)
            state.apply(ending)
            #expect(!state.model.stepsAside, "\(ending) left the gate open")
        }
    }

    @Test("a paused run takes no clicks away from itself")
    func aPausedRunIsClickable() {
        // Resume is on the panel. A gate left open through a pause would make
        // the button that ends the pause unclickable.
        var state = began()
        state.apply(.stepActing(step: step(.click), node: nil, synthetic: true,
                                stepsAside: true))
        state.apply(.yielded(reason: .userInput))
        #expect(!state.model.stepsAside)
    }
}
