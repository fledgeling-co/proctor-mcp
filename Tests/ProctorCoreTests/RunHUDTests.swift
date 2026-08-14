import Testing
import Foundation
@testable import ProctorCore

// PRO-0015. What the run HUD says and where it sits, as values.
//
// The panel is a kill switch, so what a wrong answer costs is specific: a run
// that looks stopped and is not, a counter that reflows the line beside it, a
// person's own decision drawn as a fault, or the accessibility plane announced
// so loudly that the one case that actually constrains somebody — a synthetic
// step needing the app in front — stops standing out.
//
// Drawing is not testable here and is not pretended to be. Everything the panel
// decides is.

private func step(_ kind: ActionStep.Kind, node: String? = "n1",
                  label: String? = nil) -> ActionStep {
    ActionStep(kind: kind, node: node, label: label)
}

private func el(_ title: String = "Send invoice") -> AXNode {
    AXNode(id: "n1", role: "AXButton", title: title)
}

@Suite("Run HUD state")
struct RunHUDStateTests {

    private func running(total: Int = 7, app: String? = "Acme Console") -> RunHUDState {
        var state = RunHUDState()
        state.apply(.runBegan(total: total, app: app))
        return state
    }

    // MARK: - One line, one source of words

    @Test("the live line is StepDescription's, in both timings, with no second wording table")
    func lineComesFromStepDescription() {
        var state = running()
        let press = step(.press)
        state.apply(.stepApproaching(step: press, node: el(), synthetic: false))
        #expect(state.model.line == StepDescription.line(for: press, node: el(),
                                                         timing: .prospective))
        #expect(state.model.line == "About to press \"Send invoice\"")
        #expect(state.model.phase == .travelling)

        state.apply(.stepActing(step: press, node: el(), synthetic: false))
        #expect(state.model.line == StepDescription.line(for: press, node: el(),
                                                         timing: .present))
        #expect(state.model.line == "Pressing \"Send invoice\"")
        #expect(state.model.phase == .acting)
    }

    @Test("the verb carries the state, so no line needs a status label beside it")
    func verbCarriesTheState() {
        // Each of the mock's states reads differently from the words alone, with
        // nothing else on the row to disambiguate them.
        var lines: Set<String> = []
        var state = running()
        state.apply(.stepApproaching(step: step(.press), node: el(), synthetic: false))
        lines.insert(state.model.line)
        state.apply(.stepActing(step: step(.press), node: el(), synthetic: false))
        lines.insert(state.model.line)
        state.apply(.paused(step: step(.press), node: el()))
        lines.insert(state.model.line)
        state.apply(.runEnded(.completed))
        lines.insert(state.model.line)
        #expect(lines.count == 4)
        #expect(lines.contains("Paused before \"Send invoice\""))
        #expect(lines.contains("Run complete"))
    }

    @Test("a pause with no step to name still says what it is, rather than going blank")
    func pauseWithNothingPending() {
        var state = running()
        state.apply(.paused(step: nil, node: nil))
        #expect(state.model.line == "Paused")
        #expect(state.model.phase == .paused)
    }

    @Test("Pause and Resume are the same control, and never borrow the queue's words")
    func pauseLabel() {
        var state = running()
        #expect(state.model.pauseLabel == "Pause")
        state.apply(.paused(step: nil, node: nil))
        #expect(state.model.pauseLabel == "Resume")
        state.apply(.resumed)
        #expect(state.model.pauseLabel == "Pause")
        // Hold and Clear belong to the queue and must never appear on the run's
        // own control, which is how somebody stops the wrong thing.
        #expect(!["Hold", "Held", "Clear"].contains(state.model.pauseLabel))
    }

    // MARK: - Counting

    @Test("the counter and the rail track the batch in flight")
    func counterTracksTheBatch() {
        var state = running(total: 7)
        #expect(state.model.counter == "0/7")
        #expect(state.model.progress == 0)

        for _ in 0..<3 {
            state.apply(.stepActing(step: step(.press), node: el(), synthetic: false))
            state.apply(.stepSettled(step: step(.press), node: el(), settleMs: 412))
        }
        #expect(state.model.counter == "3/7")
        #expect(abs(state.model.progress - 3.0 / 7.0) < 0.0001)
    }

    @Test("a repeated sweep shows each pass in turn rather than one total across all of them")
    func eachPassCountsItself() {
        var state = running(total: 3)
        for _ in 0..<3 {
            state.apply(.stepSettled(step: step(.press), node: el(), settleMs: 100))
        }
        #expect(state.model.counter == "3/3")
        state.apply(.runEnded(.completed))

        // The next pass of the sweep starts its own count, and its own trail.
        state.apply(.runBegan(total: 3, app: "Acme Console"))
        #expect(state.model.counter == "0/3")
        #expect(state.model.trail.isEmpty)
        #expect(state.model.visible)
    }

    @Test("progress never runs past the end of the rail")
    func progressIsBounded() {
        var state = running(total: 1)
        for _ in 0..<4 {
            state.apply(.stepSettled(step: step(.press), node: el(), settleMs: 1))
        }
        #expect(state.model.progress == 1)
    }

    @Test("a batch with no steps does not divide by zero")
    func emptyBatch() {
        let state = running(total: 0)
        #expect(state.model.progress == 0)
        #expect(state.model.counter == "0/0")
    }

    // MARK: - The trail

    @Test("the trail holds the three most recent steps, newest last, with their settle times")
    func trailKeepsThree() {
        var state = running()
        for index in 0..<5 {
            state.apply(.stepSettled(step: step(.press, label: "step \(index)"),
                                     node: el(), settleMs: 100 + index))
        }
        #expect(state.model.trail.count == RunHUDState.trailDepth)
        #expect(state.model.trail.first?.text == "Pressed \"step 2\"")
        #expect(state.model.trail.last?.text == "Pressed \"step 4\"")
        #expect(state.model.trail.last?.settleMs == 104)
        #expect(state.model.trail.allSatisfy { $0.outcome == .done })
    }

    @Test("a trail row is past tense and comes from the same table as the live line")
    func trailWordingIsDerived() {
        var state = running()
        let focus = step(.focus)
        state.apply(.stepSettled(step: focus, node: el("Amount"), settleMs: 412))
        #expect(state.model.trail.last?.text
                == StepDescription.completedLine(for: focus, node: el("Amount")))
        #expect(state.model.trail.last?.text == "Focused \"Amount\"")
    }

    @Test("a refused step lands in the trail with no settle time rather than a fabricated one")
    func refusedRowHasNoTime() {
        var state = running()
        state.apply(.stepRefused(step: step(.hover), node: el()))
        #expect(state.model.phase == .blocked)
        #expect(state.model.trail.last?.outcome == .refused)
        #expect(state.model.trail.last?.settleMs == nil)
        #expect(state.model.line == StepDescription.line(for: step(.hover), node: el(),
                                                          outcome: .refused))
    }

    @Test("a step that failed or never settled is the error state, in red")
    func failedStepIsError() {
        var state = running()
        state.apply(.stepFailed(step: step(.press), node: el()))
        #expect(state.model.phase == .error)
        #expect(state.model.tone == .red)
        #expect(state.model.trail.last?.outcome == .failed)
    }

    // MARK: - The exception, not the rule

    @Test("the accessibility plane is never announced")
    func accessibilityIsNeverAnnounced() {
        var state = running()
        state.apply(.stepApproaching(step: step(.press), node: el(), synthetic: false))
        #expect(state.model.exception == nil)
        state.apply(.stepActing(step: step(.press), node: el(), synthetic: false))
        #expect(state.model.exception == nil)
    }

    @Test("a synthetic step says so, in words, once, naming the app that must stay in front")
    func syntheticIsStatedOnce() {
        var state = running(app: "Acme Console")
        state.apply(.stepActing(step: step(.click), node: el(), synthetic: true))
        #expect(state.model.exception == "Synthetic event — Acme Console must stay in front")

        // And it goes when the plane does, so it is never left standing over a
        // step it does not describe.
        state.apply(.stepApproaching(step: step(.press), node: el(), synthetic: false))
        #expect(state.model.exception == nil)
    }

    @Test("an unnamed app still produces a sentence rather than a hole in one")
    func syntheticWithoutAnAppName() {
        var state = running(app: nil)
        state.apply(.stepActing(step: step(.click), node: el(), synthetic: true))
        #expect(state.model.exception == "Synthetic event — the app under test must stay in front")
    }

    @Test("the exception is gone once the run has ended")
    func exceptionClearsAtTheEnd() {
        var state = running()
        state.apply(.stepActing(step: step(.click), node: el(), synthetic: true))
        state.apply(.runEnded(.completed))
        #expect(state.model.exception == nil)
    }

    // MARK: - Endings

    @Test("a person's own stop is not drawn as a fault")
    func stopIsNotAFault() {
        var state = running()
        state.apply(.runEnded(.stoppedByPerson))
        #expect(state.model.phase == .paused)
        #expect(state.model.tone == .quiet)
        #expect(state.model.phase != .error)
        #expect(state.model.line == "Stopped by a person")
    }

    @Test("an ending a person needs to read holds longer than one they do not")
    func lingerSplitsByEnding() {
        // Three seconds is enough for "it worked"; an unattended machine would
        // lose a blocked or errored ending in that time, and those are the two
        // somebody actually has to act on.
        for ending in [RunHUDEnding.completed, .stoppedByPerson] {
            var state = running()
            state.apply(.runEnded(ending))
            #expect(state.model.lingerSeconds == RunHUDState.quietLinger)
        }
        for ending in [RunHUDEnding.blocked, .failed] {
            var state = running()
            state.apply(.runEnded(ending))
            #expect(state.model.lingerSeconds == RunHUDState.loudLinger)
        }
        #expect(RunHUDState.loudLinger > RunHUDState.quietLinger)
    }

    @Test("the panel is on screen for a run and gone once the linger is over")
    func visibility() {
        var state = RunHUDState()
        #expect(!state.model.visible)
        state.apply(.runBegan(total: 2, app: "Acme Console"))
        #expect(state.model.visible)
        state.apply(.runEnded(.completed))
        #expect(state.model.visible)
        state.apply(.lingerElapsed)
        #expect(!state.model.visible)
    }

    // MARK: - Colour

    @Test("every state a run reaches is readable from its words and colour alone")
    func readableWithoutMotion() {
        // The clause reduced motion has to satisfy: with nothing animating, each
        // state a person can land on still tells them which one it is. Tone
        // alone is not enough (travelling and acting share one, as the reference
        // intends), so the pair has to be distinct.
        var seen: Set<String> = []
        func record(_ state: RunHUDState) {
            seen.insert("\(state.model.tone.rawValue)|\(state.model.line)")
        }
        var travelling = running()
        travelling.apply(.stepApproaching(step: step(.press), node: el(), synthetic: false))
        record(travelling)
        var acting = running()
        acting.apply(.stepActing(step: step(.press), node: el(), synthetic: false))
        record(acting)
        var blocked = running()
        blocked.apply(.stepRefused(step: step(.hover), node: el()))
        record(blocked)
        var failed = running()
        failed.apply(.stepFailed(step: step(.press), node: el()))
        record(failed)
        var paused = running()
        paused.apply(.paused(step: step(.press), node: el()))
        record(paused)
        var finished = running()
        finished.apply(.runEnded(.completed))
        record(finished)
        var stopped = running()
        stopped.apply(.runEnded(.stoppedByPerson))
        record(stopped)

        #expect(seen.count == 7)
    }

    @Test("one state variable drives the whole panel, and every phase has a tone")
    func everyPhaseHasATone() {
        let expected: [RunHUDPhase: RunHUDTone] = [
            .idle: .quiet, .travelling: .accent, .acting: .accent, .blocked: .amber,
            .paused: .quiet, .finished: .green, .error: .red
        ]
        for phase in RunHUDPhase.allCases {
            #expect(phase.tone == expected[phase], "\(phase) has the wrong tone")
        }
    }
}

@Suite("Run HUD placement")
struct RunHUDPlacementTests {

    @Test("the panel docks off the usable corner, so a Dock cannot sit on top of it")
    func docksClearOfTheDock() {
        // The real arrangement this was found on: a laptop whose Dock takes the
        // bottom 67pt, and an external display above and to the left that reports
        // no inset at all. Placement is given the USABLE rect, so the caller hands
        // it `visibleFrame`; measuring from the full frame put the panel's lower
        // third behind the Dock on the one screen that had one, which is why the
        // fault looked like it only happened sometimes.
        let laptopUsable = Rect(x: 0, y: 67, w: 1728, h: 1017)
        let panel = RunHUDPlacement.Size(w: 352, h: 200)
        let target = Rect(x: 411, y: 493, w: 905, h: 448)

        guard let placed = RunHUDPlacement.place(panel: panel, in: [laptopUsable],
                                                 target: target) else {
            Issue.record("no placement"); return
        }
        #expect(placed.screen == 0)
        // Bottom edge clears the Dock by the inset, rather than starting 34pt off
        // a screen edge that is 67pt of Dock.
        #expect(placed.origin.y == 67 + RunHUDPlacement.defaultInset)
        #expect(placed.origin.y >= laptopUsable.y)
        #expect(placed.origin.x + panel.w <= laptopUsable.x + laptopUsable.w)
    }

    @Test("the panel follows the driven window to the screen it is actually on")
    func followsTheWindowAcrossScreens() {
        // Both screens as macOS reports them here: the external sits ABOVE and to
        // the left of the laptop, so its origin is negative in x and positive in y.
        // A window on it must not pull the panel to the laptop, or vice versa.
        let laptop = Rect(x: 0, y: 67, w: 1728, h: 1017)
        let external = Rect(x: -716, y: 1117, w: 2560, h: 1440)
        let panel = RunHUDPlacement.Size(w: 352, h: 200)

        let onLaptop = Rect(x: 411, y: 493, w: 905, h: 448)
        let onExternal = Rect(x: -349, y: 1908, w: 586, h: 488)

        #expect(RunHUDPlacement.place(panel: panel, in: [laptop, external],
                                      target: onLaptop)?.screen == 0)
        #expect(RunHUDPlacement.place(panel: panel, in: [laptop, external],
                                      target: onExternal)?.screen == 1)
    }

    private let panel = RunHUDPlacement.Size(w: 352, h: 200)
    /// A laptop beside a larger display, the arrangement the union-panel bug was
    /// measured on.
    private let laptop = Rect(x: 0, y: 0, w: 1728, h: 1117)
    private let external = Rect(x: 1728, y: 0, w: 2560, h: 1440)

    @Test("the panel goes on the screen holding the driven window")
    func followsTheDrivenWindow() throws {
        let screens = [laptop, external]
        let onLaptop = try #require(RunHUDPlacement.place(
            panel: panel, in: screens, target: Rect(x: 100, y: 100, w: 800, h: 600)))
        #expect(onLaptop.screen == 0)

        let onExternal = try #require(RunHUDPlacement.place(
            panel: panel, in: screens, target: Rect(x: 2000, y: 300, w: 900, h: 700)))
        #expect(onExternal.screen == 1)
    }

    @Test("it is docked into the screen's bottom-right corner at the reference's inset")
    func dockedBottomRight() throws {
        let placement = try #require(RunHUDPlacement.place(
            panel: panel, in: [laptop], target: laptop))
        #expect(placement.origin.x == 1728 - 34 - 352)
        #expect(placement.origin.y == 34)
    }

    @Test("the panel is never sized to the union of the displays")
    func neverSpansDisplays() throws {
        // The failure this rule exists for: a panel sized to both displays is a
        // 26-megapixel backing store the window server accepts, reports healthy,
        // and never presents. A 352pt panel cannot reach two screens at once.
        let placement = try #require(RunHUDPlacement.place(
            panel: panel, in: [laptop, external], target: external))
        let screen = [laptop, external][placement.screen]
        #expect(placement.origin.x >= screen.x)
        #expect(placement.origin.x + panel.w <= screen.x + screen.w)
        #expect(placement.origin.y >= screen.y)
        #expect(placement.origin.y + panel.h <= screen.y + screen.h)
    }

    @Test("a window straddling two screens goes to the one showing most of it")
    func straddlingWindow() throws {
        let straddle = Rect(x: 1400, y: 200, w: 900, h: 500)   // 328 left, 572 right
        let placement = try #require(RunHUDPlacement.place(
            panel: panel, in: [laptop, external], target: straddle))
        #expect(placement.screen == 1)
    }

    @Test("a window on a display that is no longer there goes to the nearest one")
    func offEveryScreen() throws {
        let placement = try #require(RunHUDPlacement.place(
            panel: panel, in: [laptop], target: Rect(x: 4000, y: 200, w: 400, h: 300)))
        #expect(placement.screen == 0)
    }

    @Test("with no window named at all the panel still has somewhere to be")
    func noTarget() throws {
        let placement = try #require(RunHUDPlacement.place(panel: panel, in: [laptop, external],
                                                            target: nil))
        #expect(placement.screen == 0)
    }

    @Test("no screens means no placement rather than a panel at the origin")
    func noScreens() {
        #expect(RunHUDPlacement.place(panel: panel, in: [], target: laptop) == nil)
    }

    @Test("a dragged position is clamped back onto its screen, never off the edge")
    func clampingADraggedPosition() {
        let inside = RunHUDPlacement.clamp(RunHUDPlacement.Point(x: 400, y: 300),
                                           size: panel, into: laptop)
        #expect(inside == RunHUDPlacement.Point(x: 400, y: 300))

        let past = RunHUDPlacement.clamp(RunHUDPlacement.Point(x: 5000, y: -900),
                                         size: panel, into: laptop)
        #expect(past.x == 1728 - 352)
        #expect(past.y == 0)
    }

    @Test("a screen smaller than the panel pins it rather than producing a negative box")
    func screenSmallerThanThePanel() {
        let tiny = Rect(x: 0, y: 0, w: 200, h: 120)
        let point = RunHUDPlacement.clamp(RunHUDPlacement.Point(x: 900, y: 900),
                                          size: panel, into: tiny)
        #expect(point == RunHUDPlacement.Point(x: 0, y: 0))
    }

    @Test("an accessibility frame converts into AppKit's y-up space")
    func flipping() {
        // An AX frame is y down from the top of the primary display; AppKit is y
        // up from its bottom. A window 100pt from the top of a 1117pt display.
        let flipped = RunHUDPlacement.appKit(from: Rect(x: 10, y: 100, w: 800, h: 600),
                                             primaryMaxY: 1117)
        #expect(flipped == Rect(x: 10, y: 417, w: 800, h: 600))
    }
}

@Suite("Overlay off-switches")
struct OverlaySwitchTests {

    @Test("the HUD's switch is the pointer's shape exactly")
    func offValues() {
        for off in ["0", "off", "false", "no", "OFF", "False", " no "] {
            #expect(!OverlaySwitch.isOn(off), "\(off.debugDescription) should be off")
        }
        for on in ["1", "on", "true", "yes", "", "anything"] {
            #expect(OverlaySwitch.isOn(on), "\(on.debugDescription) should be on")
        }
    }

    @Test("both are on by default, because opting out of a stop control is deliberate")
    func onByDefault() {
        #expect(OverlaySwitch.isOn(nil))
        #expect(OverlaySwitch.isOn("PROCTOR_HUD", in: [:]))
        #expect(OverlaySwitch.isOn("PROCTOR_CURSOR", in: [:]))
    }

    @Test("the two switches are independent, so either can be left on alone")
    func independent() {
        let environment = ["PROCTOR_CURSOR": "0"]
        #expect(!OverlaySwitch.isOn("PROCTOR_CURSOR", in: environment))
        #expect(OverlaySwitch.isOn("PROCTOR_HUD", in: environment))
    }
}

@Suite("Run HUD wording extensions")
struct RunHUDWordingTests {

    @Test("every kind has a past form, so no trail row can fall back to a raw kind name")
    func everyKindHasAPastForm() {
        for kind in ActionStep.Kind.allCases {
            let named = StepDescription.completedLine(for: step(kind), node: el())
            #expect(!named.isEmpty)
            #expect(named.first!.isUppercase, "\(kind): \(named)")
            // A kind with no hand-written past form would print itself —
            // "SetValue Amount", "DragPath", "WaitFor". Every real one is
            // inflected, so none of them is its own raw value.
            let verb = named.split(separator: " ").first.map(String.init) ?? named
            #expect(verb.lowercased() != kind.rawValue.lowercased(),
                    "\(kind) leaked its raw value: \(named)")

            // And with no element to name, so a bare keystroke still reads.
            let alone = StepDescription.completedLine(for: step(kind, node: nil), node: nil)
            #expect(!alone.isEmpty)
            #expect(!alone.hasSuffix(" "), "\(kind) left a dangling preposition: \(alone)")
        }
    }

    @Test("a name is fenced wherever it appears, live line or trail, whoever supplied it")
    func namesStayFenced() {
        let supplied = step(.press, label: "Pay the supplier")
        #expect(StepDescription.completedLine(for: supplied, node: el())
                == "Pressed \"Pay the supplier\"")
        #expect(StepDescription.objectText(for: supplied, node: el())
                == "\"Pay the supplier\"")
        #expect(StepDescription.objectText(for: step(.press), node: el()) == "\"Send invoice\"")
    }

    @Test("a step naming nothing has no object, so a pause says so rather than trailing off")
    func noObject() {
        #expect(StepDescription.objectText(for: step(.appleScript, node: nil), node: nil) == nil)
    }
}
