import Foundation
import Testing
@testable import ProctorCore

// PRO-0026 — taking the front visibly, and holding it.
//
// What a test can reach here is the whole of the decision: when the statement
// goes up, what it says, how it is drawn, which events the block holds, and how
// long an arming may last. What it cannot reach is named in the spec and not
// pretended at — a panel presenting, a tint, a tap swallowing anything, and
// Escape arriving in one. Those were measured with probes (T1, T2, T3 in
// `Takeover.swift`'s header) rather than asserted here.

@Suite("Takeover policy")
struct TakeoverPolicyTests {

    private func demand(certain: Int = 0, conditional: Int = 0, total: Int = 4,
                        requested: Bool = false, raises: Bool = false) -> ForegroundDemand {
        ForegroundDemand(certainSteps: certain, conditionalSteps: conditional, raises: raises,
                         requestedForeground: requested, totalSteps: total)
    }

    // MARK: - A1: up for exactly as long as the machine is held

    @Test("a batch with a certainly synthetic step announces itself before it runs")
    func certainAnnounces() {
        #expect(Takeover.shows(demand: demand(certain: 1, requested: true), sawSynthetic: false))
    }

    @Test("a batch that only might need the front announces nothing until one does")
    func conditionalWaitsForTheMeasurement() {
        // `type` and `scroll` decide their plane at the element, so a batch that
        // may fall back cannot claim the machine up front. It claims it the
        // moment one actually did.
        let mayFallBack = demand(conditional: 2, requested: true)
        #expect(!Takeover.shows(demand: mayFallBack, sawSynthetic: false))
        #expect(Takeover.shows(demand: mayFallBack, sawSynthetic: true))
    }

    @Test("an accessibility batch never draws it")
    func accessibilityDrawsNothing() {
        #expect(!Takeover.shows(demand: demand(), sawSynthetic: false))
    }

    @Test("an inert foreground request draws nothing, because it takes nothing")
    func inertRequestDrawsNothing() {
        // PRO-0025 A1: a `foreground: true` with nothing to spend it on no longer
        // takes the front, so announcing that it had would be a second lie on top
        // of the one that item removed.
        let inert = demand(certain: 0, conditional: 0, requested: true)
        #expect(inert.requestWasInert)
        #expect(!Takeover.shows(demand: inert, sawSynthetic: false))
    }

    // MARK: - The label

    @Test("the label claims a hold only while one is armed")
    func labelNeverOverclaims() {
        let held = Takeover.label(app: "Acme Console", blocking: true)
        let open = Takeover.label(app: "Acme Console", blocking: false)
        #expect(held.line.contains("held"))
        #expect(held.line.contains("Esc"))
        // Worded for the batch rather than for the instant, so it does not
        // flicker several times a second across a run of fast steps.
        #expect(held.line.contains("while it acts"))
        #expect(!open.line.contains("held"))
        // And when nothing is held it says so in as many words, because a
        // full-screen veil reads as a modal sheet and somebody who clicks it to
        // dismiss it is clicking into the application Proctor is driving.
        #expect(open.line.contains("still reach"))
        #expect(held.title == open.title)
    }

    @Test("the application's own name is fenced, and its absence is not a hole")
    func labelFencesTheName() {
        #expect(Takeover.label(app: "Acme Console", blocking: false).title
                == "Proctor is driving \"Acme Console\"")
        #expect(Takeover.label(app: nil, blocking: false).title == "Proctor is driving this Mac")
        // A name is an application's own accessibility title and carries whatever
        // that carries; it goes through the same sanitiser every other object does.
        let noisy = Takeover.label(app: "Acme\nConsole\u{0007}", blocking: false)
        #expect(!noisy.title.contains("\n"))
        #expect(!noisy.title.contains("\u{0007}"))
    }

    // MARK: - A9, A10: how it is drawn

    @Test("the tint sits below the run panel, so Pause and Stop stay visible")
    func belowTheRunPanel() {
        let spec = Takeover.surface(reduceTransparency: false, reduceMotion: false, hudLevel: 25)
        #expect(spec.level < 25)
        // Derived from the panel's level rather than written down twice, so the
        // two cannot drift into numbers that happen to be ordered today.
        #expect(Takeover.surface(reduceTransparency: false, reduceMotion: false,
                                 hudLevel: 40).level == 39)
    }

    @Test("the tint never takes a click and never enters a capture")
    func neverTakesAClickOrAFrame() {
        // Both are always true, because both are the difference between an
        // annotation and a defect: a panel that could take a click could eat the
        // one landing on Stop, and a tint inside a frame poisons every visual
        // assertion this tool exists to make.
        for transparency in [true, false] {
            for motion in [true, false] {
                let spec = Takeover.surface(reduceTransparency: transparency,
                                            reduceMotion: motion, hudLevel: 25)
                #expect(spec.ignoresMouseEvents)
                #expect(spec.excludedFromCapture)
                #expect(spec.alpha > 0 && spec.alpha < 1)
            }
        }
    }

    @Test("Reduce Motion drops the fades and Reduce Transparency plates the label")
    func accessibilitySettingsApply() {
        let plain = Takeover.surface(reduceTransparency: false, reduceMotion: false, hudLevel: 25)
        let reduced = Takeover.surface(reduceTransparency: true, reduceMotion: true, hudLevel: 25)
        #expect(plain.fades)
        #expect(!reduced.fades)
        #expect(!plain.labelPlate)
        #expect(reduced.labelPlate)
        // Reduce Transparency asks for legibility, not for an opaque screen:
        // somebody watching Proctor drive their Mac has to see what it is doing.
        #expect(reduced.alpha > plain.alpha)
        #expect(reduced.alpha < 1)
    }

    // MARK: - A7: how long an arming may last

    @Test("an arming is bounded by the step's own duration and by a ceiling")
    func armingIsBounded() {
        #expect(Takeover.armSeconds(stepDurationMs: nil) == Takeover.slackSeconds)
        #expect(Takeover.armSeconds(stepDurationMs: 300) == 0.3 + Takeover.slackSeconds)
        // A drag is clamped to 30s by the actuator, which is the longest step
        // there is, and the ceiling sits just above it so a legitimate drag is
        // never cut short: 30s + the slack is 32s, under the 35s bound.
        #expect(Takeover.armSeconds(stepDurationMs: 30_000) == 32)
        // Past the ceiling the block is not holding a step, it is holding
        // somebody's Mac.
        #expect(Takeover.armSeconds(stepDurationMs: 600_000) == Takeover.ceilingSeconds)
        #expect(Takeover.armSeconds(stepDurationMs: -5) == Takeover.slackSeconds)
    }

    // MARK: - A4: the switches

    @Test("the overlay is on by default and the block is off by default")
    func switchesDefaultOppositeWays() {
        // The asymmetry IS the decision. The statement costs nobody anything;
        // intercepting somebody's keyboard is a capability, and PRO-0018 already
        // settled that a weaker capability than this one ships opt-in.
        #expect(Takeover.overlayEnabled(in: [:]))
        #expect(!Takeover.blockEnabled(in: [:]))
        #expect(!Takeover.overlayEnabled(in: ["PROCTOR_TAKEOVER": "0"]))
        #expect(!Takeover.overlayEnabled(in: ["PROCTOR_TAKEOVER": "off"]))
        #expect(Takeover.blockEnabled(in: ["PROCTOR_TAKEOVER_INPUT": "1"]))
        #expect(!Takeover.blockEnabled(in: ["PROCTOR_TAKEOVER_INPUT": ""]))
        #expect(!Takeover.blockEnabled(in: ["PROCTOR_TAKEOVER_INPUT": "no"]))
    }

    // MARK: - A11: what the run says afterwards

    @Test("a run that drew nothing says nothing")
    func silenceWhenNothingHappened() {
        let quiet = TakeoverReport(shown: false, blocked: false, blockedMs: 0, swallowed: 0,
                                   releasedBy: nil)
        #expect(quiet.note == nil)
    }

    @Test("a run that showed but held nothing says which of the two it was")
    func shownButNotHeld() {
        let shown = TakeoverReport(shown: true, blocked: false, blockedMs: 0, swallowed: 0,
                                   releasedBy: "runEnded")
        let note = shown.note ?? ""
        #expect(note.contains("Input was not held"))
        #expect(!note.contains("held the keyboard"))
    }

    @Test("a run that held the machine says for how long and how often it was fought")
    func heldSaysSo() {
        let held = TakeoverReport(shown: true, blocked: true, blockedMs: 2400, swallowed: 3,
                                  releasedBy: "stopped")
        let note = held.note ?? ""
        #expect(note.contains("2.4s"))
        #expect(note.contains("3 times"))
        #expect(note.contains("stopped"))
    }

    @Test("the report reaches the wire, and is absent from a result that never drew")
    func reportEncodes() throws {
        let report = TakeoverReport(shown: true, blocked: true, blockedMs: 120, swallowed: 1,
                                    releasedBy: "deadline")
        let json = try JSONValue.encode(report)
        #expect(json["shown"]?.boolValue == true)
        #expect(json["blocked"]?.boolValue == true)
        #expect(json["blockedMs"]?.intValue == 120)
        #expect(json["swallowed"]?.intValue == 1)
        #expect(json["releasedBy"]?.stringValue == "deadline")

        // A result from a run that took nothing encodes exactly as it did before
        // this existed, which is what makes the new block free for every caller
        // who never sees it.
        let bare = ActResult(window: "w", steps: [], completed: 0, failedAt: nil, finalHash: nil)
        let encoded = try JSONValue.encode(bare)
        #expect(encoded["takeover"] == nil || encoded["takeover"] == .null)
    }
}

@Suite("Input block")
struct InputBlockTests {

    private static let ourPid: Int64 = 4242

    private func ours(_ kind: InputEventKind, keyCode: Int64? = nil,
                      button: Int64? = nil) -> InputBlockDecision {
        var gate = InputBlock.Gate()
        return gate.decide(kind: kind, sourcePid: Self.ourPid, userData: ProctorEventTag.value,
                           ourPid: Self.ourPid, keyCode: keyCode, button: button)
    }

    // MARK: - A5: only ours passes

    @Test("every event Proctor posts passes, whatever it is")
    func ourOwnEventsAlwaysPass() {
        // T1: a swallowing session tap eats events this process posts to the HID
        // tap. Without this rule the block would break every foreground step it
        // was drawn for.
        for kind in InputEventKind.allCases {
            #expect(ours(kind, keyCode: 12, button: 0) == .pass)
        }
    }

    @Test("our own posted Escape does not stop the run that posted it")
    func ourEscapeIsJustAKeystroke() {
        // A `key` step that types Escape to dismiss a dialog must not abort the
        // run that asked for it, which is why ours is decided before any chord is
        // considered.
        #expect(ours(.keyDown, keyCode: InputBlock.releaseKeyCode) == .pass)
    }

    @Test("a tagged event passes even when the pid is somebody else's, and vice versa")
    func eitherFieldIsEnough() {
        // Two independent readings, so a macOS that stops attributing one of them
        // does not silently switch the pass rule off.
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .keyDown, sourcePid: 0, userData: ProctorEventTag.value,
                            ourPid: Self.ourPid, keyCode: 12) == .pass)
        #expect(gate.decide(kind: .keyDown, sourcePid: Self.ourPid, userData: 0,
                            ourPid: Self.ourPid, keyCode: 12) == .pass)
    }

    @Test("a remapper's events are held, because they are the person's")
    func aProcessIsNotAPass() {
        // The finding that changed this design. A Mac running Karabiner or a
        // vendor mouse driver delivers the person's own keystrokes carrying THAT
        // process's pid, so a rule passing anything with a pid on it passes
        // precisely what the block exists to hold.
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .keyDown, sourcePid: 991, userData: 7,
                            ourPid: Self.ourPid, keyCode: 12) == .swallow)
    }

    @Test("hardware is held")
    func hardwareIsHeld() {
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .keyDown, sourcePid: 0, userData: 0,
                            ourPid: Self.ourPid, keyCode: 12) == .swallow)
        #expect(gate.decide(kind: .scroll, sourcePid: 0, userData: 0,
                            ourPid: Self.ourPid) == .swallow)
    }

    // MARK: - A6: Escape

    @Test("Escape stops the run and does not also reach the application")
    func escapeStopsAndIsSwallowed() {
        var gate = InputBlock.Gate()
        let decision = gate.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                                   keyCode: InputBlock.releaseKeyCode)
        #expect(decision == .stopRun)
        #expect(!decision.delivers)
        // And its own key-up goes with it, so the application is not left holding
        // an Escape it never saw pressed.
        #expect(gate.decide(kind: .keyUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            keyCode: InputBlock.releaseKeyCode) == .swallow)
    }

    // MARK: - A5b: the panic chords

    @Test("every way out of a Mac that is driving itself is passed")
    func panicChordsPass() {
        // Somebody must be able to switch application, force quit, lock the
        // screen and photograph what is happening, whoever sent the event.
        for chord in InputBlock.panicChords {
            var gate = InputBlock.Gate()
            let decision = gate.decide(kind: .keyDown, sourcePid: 0, userData: 0,
                                       ourPid: Self.ourPid, keyCode: chord.keyCode,
                                       modifiers: chord.modifiers)
            #expect(decision.delivers)
        }
    }

    @Test("the two chords that mean stop also stop the run")
    func forceQuitAndLockAlsoStop() {
        // Passing Ctrl-Cmd-Q and going on posting is the worst end state this
        // has: locking the screen raises Secure Event Input, which releases the
        // block, and the run would carry on driving a locked session with the
        // hold gone. Somebody reaching for Force Quit or the lock means make
        // this stop, so it does.
        var gate = InputBlock.Gate()
        let forceQuit = gate.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                                    keyCode: 53, modifiers: [.command, .option])
        #expect(forceQuit == .passAndStop)
        #expect(forceQuit.delivers && forceQuit.stops)
        var second = InputBlock.Gate()
        let lock = second.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                                 keyCode: 12, modifiers: [.command, .control])
        #expect(lock == .passAndStop)
        // Switching application and taking a screenshot are not aborts, so they
        // pass without ending anything.
        var third = InputBlock.Gate()
        let switcher = third.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                                    keyCode: 48, modifiers: [.command])
        #expect(switcher == .pass)
        #expect(!switcher.stops)
    }

    @Test("a chord is exact, so the list cannot widen into anything with Command held")
    func chordsAreExact() {
        var gate = InputBlock.Gate()
        // Cmd-Tab passes; Tab alone and Cmd-Shift-Ctrl-Tab do not.
        #expect(gate.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            keyCode: 48, modifiers: []) == .swallow)
        var second = InputBlock.Gate()
        #expect(second.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                              keyCode: 48, modifiers: [.command, .shift, .control]) == .swallow)
        // And an ordinary Command chord is still held: Cmd-W into the application
        // under test is a person driving it, which is the thing being stopped.
        var third = InputBlock.Gate()
        #expect(third.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                             keyCode: 13, modifiers: [.command]) == .swallow)
    }

    // MARK: - A5c: a pair is swallowed as a pair

    @Test("an up whose down was never swallowed passes")
    func armingMidGestureDoesNotStrandADown() {
        // The finding that would have made this feature worse than not having it.
        // Somebody holding the mouse down before the block armed must not have the
        // end of their gesture eaten: the application would keep a button nobody
        // is pressing, and that state outlives the block, the run and the process.
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .mouseUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0) == .pass)
        #expect(gate.decide(kind: .mouseDragged, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0) == .pass)
        #expect(gate.decide(kind: .keyUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            keyCode: 12) == .pass)
    }

    @Test("a down the block swallowed takes its own up and its drags with it")
    func aWholeGestureIsHeld() {
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .mouseDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0) == .swallow)
        #expect(gate.decide(kind: .mouseDragged, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0) == .swallow)
        #expect(gate.decide(kind: .mouseUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0) == .swallow)
        // And once it has gone, the next up for that button passes again.
        #expect(gate.decide(kind: .mouseUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0) == .pass)
    }

    @Test("buttons and keys are tracked separately, so one gesture cannot free another")
    func trackingIsPerKeyAndPerButton() {
        var gate = InputBlock.Gate()
        _ = gate.decide(kind: .mouseDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                        button: 0)
        #expect(gate.decide(kind: .mouseUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 1) == .pass)
        _ = gate.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid, keyCode: 4)
        #expect(gate.decide(kind: .keyUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            keyCode: 5) == .pass)
    }

    @Test("a modifier is never held")
    func modifiersPass() {
        // `flagsChanged` is not in the tap's mask and would not be swallowed if it
        // were: half a modifier pair leaves an application holding a Shift nobody
        // is pressing, and a modifier on its own actuates nothing.
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .modifier, sourcePid: 0, userData: 0,
                            ourPid: Self.ourPid) == .pass)
        #expect(gate.decide(kind: .other, sourcePid: 0, userData: 0,
                            ourPid: Self.ourPid) == .pass)
    }

    @Test("the gate forgets everything when the block goes down")
    func resetIsComplete() {
        // Nothing from one run may decide anything in the next: a down swallowed
        // in one run must not make an unrelated up disappear in the following one.
        var gate = InputBlock.Gate()
        _ = gate.decide(kind: .mouseDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                        button: 0)
        gate.reset()
        #expect(gate.decide(kind: .mouseUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0) == .pass)
    }

    @Test("delivery and stopping are separate questions, and one case is both")
    func deliveryAndStoppingAreSeparate() {
        #expect(InputBlockDecision.pass.delivers && !InputBlockDecision.pass.stops)
        #expect(!InputBlockDecision.swallow.delivers && !InputBlockDecision.swallow.stops)
        #expect(!InputBlockDecision.stopRun.delivers && InputBlockDecision.stopRun.stops)
        #expect(InputBlockDecision.passAndStop.delivers && InputBlockDecision.passAndStop.stops)
    }

    // MARK: - The two predicates point opposite ways, on purpose

    @Test("the block's rule and the yield's rule disagree, and each is right")
    func theTwoPredicatesAreMirrors() {
        // A remapper's event: not a person by PRO-0018's rule (so it does not
        // hold the run through that signal), and not ours by this one (so it does
        // not reach the application). Collapsing them into one predicate makes one
        // of the two wrong.
        #expect(!PersonInput.isAPerson(sourcePid: 991, userData: 7, sinceSyntheticPost: nil))
        #expect(!InputBlock.isOurs(sourcePid: 991, userData: 7, ourPid: Self.ourPid))

        // And the grace window belongs to one of them and not the other. As a
        // pass rule it would open the gate to real hardware for a quarter of a
        // second after every post, which on short steps is most of the time the
        // block claims to be closed.
        #expect(!PersonInput.isAPerson(sourcePid: 0, userData: 0, sinceSyntheticPost: 0.05))
        #expect(!InputBlock.isOurs(sourcePid: 0, userData: 0, ourPid: Self.ourPid))
    }
}

// MARK: - PRO-0033: the tap's route to Stop

@Suite("The block's Stop route")
struct InputBlockStopRouteTests {

    private static let ourPid: Int64 = 4242
    /// The run panel's Stop button, in the Quartz screen space the tap reports
    /// `CGEvent.location` in.
    private static let stop = Rect(x: 1600, y: 1040, w: 64, h: 28)

    private func at(_ x: Double, _ y: Double) -> RunHUDPlacement.Point {
        RunHUDPlacement.Point(x: x, y: y)
    }

    private func person(_ gate: inout InputBlock.Gate, _ kind: InputEventKind,
                        _ point: RunHUDPlacement.Point, postInFlight: Bool = false,
                        stopRect: Rect? = InputBlockStopRouteTests.stop) -> InputBlockDecision {
        gate.decide(kind: kind, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                    button: 0, location: point, stopRect: stopRect,
                    postInFlight: postInFlight)
    }

    // MARK: A8 — decided on the up, and no half of a gesture left behind

    @Test("a person's press on Stop ends the run, and it is decided on the up")
    func stopIsDecidedOnTheUp() {
        // The down is swallowed rather than acted on, because stopping on the
        // down tears the panel, the rectangle and the tap down while the button
        // is still held — and the person's mouse-up then lands live in the
        // application the run was driving. That is a forwarded click, which is
        // the one thing this feature is not allowed to produce.
        var gate = InputBlock.Gate()
        #expect(person(&gate, .mouseDown, at(1620, 1050)) == .swallow)
        #expect(person(&gate, .mouseUp, at(1620, 1050)) == .stopRun)
    }

    @Test("the up that stops the run is swallowed rather than delivered")
    func theStoppingUpIsAlsoSwallowed() {
        var gate = InputBlock.Gate()
        _ = person(&gate, .mouseDown, at(1620, 1050))
        #expect(!person(&gate, .mouseUp, at(1620, 1050)).delivers)
    }

    @Test("an up away from the button is a cancel, and is still swallowed")
    func anUpOutsideTheRectDoesNotStop() {
        // Moving off a button before releasing cancels it everywhere else on
        // macOS. It must not reach the application either: the down was
        // swallowed, so delivering the up alone leaves an application holding an
        // up for something it never saw pressed.
        var gate = InputBlock.Gate()
        _ = person(&gate, .mouseDown, at(1620, 1050))
        #expect(person(&gate, .mouseUp, at(400, 400)) == .swallow)
    }

    @Test("a click that never touched the button is swallowed, exactly as before")
    func aClickElsewhereIsUnchanged() {
        var gate = InputBlock.Gate()
        #expect(person(&gate, .mouseDown, at(400, 400)) == .swallow)
        #expect(person(&gate, .mouseUp, at(400, 400)) == .swallow)
    }

    // MARK: A8b — the up follows its own down

    @Test("a post beginning mid-click does not lose the press")
    func aPostBeginningMidClickDoesNotLoseThePress() {
        // Somebody presses Stop; Proctor begins a post between their down and
        // their up. Re-testing the rectangle at the up would find it suppressed
        // by the in-flight rule, and the press would be swallowed and silently
        // lost — they pressed Stop, watched the button go down, and the run
        // carried on. The record made at the down is what decides it.
        var gate = InputBlock.Gate()
        #expect(person(&gate, .mouseDown, at(1620, 1050)) == .swallow)
        #expect(person(&gate, .mouseUp, at(1620, 1050), postInFlight: true) == .stopRun)
    }

    @Test("a rectangle that arrives between the down and the up cannot invent a press")
    func aLateRectangleInventsNothing() {
        var gate = InputBlock.Gate()
        #expect(person(&gate, .mouseDown, at(1620, 1050), stopRect: nil) == .swallow)
        #expect(person(&gate, .mouseUp, at(1620, 1050)) == .swallow)
    }

    // MARK: A9 — Proctor's own click can never press Stop

    @Test("the rectangle is not consulted at all while one of our posts is in flight")
    func aPostInFlightIgnoresTheStopRect() {
        // The structural half of the invariant. Proctor's own click happens
        // inside its own declared post, so this holds even if both source fields
        // were lost in transit — which is the right footing for a kill switch,
        // where an identity check alone is not.
        var gate = InputBlock.Gate()
        #expect(person(&gate, .mouseDown, at(1620, 1050), postInFlight: true) == .swallow)
        #expect(person(&gate, .mouseUp, at(1620, 1050), postInFlight: true) == .swallow)
    }

    @Test("our own click passes and is never read as a press")
    func oursIsTestedBeforeTheRect() {
        // The identity half. Ours passes before anything else is considered, so
        // a synthetic click posted at the panel's Stop button goes through to
        // whatever is under it rather than halting the run that posted it —
        // PRO-0015's invariant, unchanged.
        var gate = InputBlock.Gate()
        let down = gate.decide(kind: .mouseDown, sourcePid: Self.ourPid,
                               userData: ProctorEventTag.value, ourPid: Self.ourPid,
                               button: 0, location: at(1620, 1050), stopRect: Self.stop,
                               postInFlight: false)
        let up = gate.decide(kind: .mouseUp, sourcePid: Self.ourPid,
                             userData: ProctorEventTag.value, ourPid: Self.ourPid,
                             button: 0, location: at(1620, 1050), stopRect: Self.stop,
                             postInFlight: false)
        #expect(down == .pass)
        #expect(up == .pass)
    }

    @Test("either source field alone is enough for our own click to pass")
    func eitherFieldIsEnoughAtTheRect() {
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .mouseDown, sourcePid: 0, userData: ProctorEventTag.value,
                            ourPid: Self.ourPid, button: 0, location: at(1620, 1050),
                            stopRect: Self.stop) == .pass)
        #expect(gate.decide(kind: .mouseDown, sourcePid: Self.ourPid, userData: 0,
                            ourPid: Self.ourPid, button: 0, location: at(1620, 1050),
                            stopRect: Self.stop) == .pass)
    }

    // MARK: The pair rule still holds

    @Test("a reset forgets a pending press, so nothing carries into the next run")
    func resetForgetsThePendingPress() {
        var gate = InputBlock.Gate()
        _ = person(&gate, .mouseDown, at(1620, 1050))
        gate.reset()
        // The down is gone with the reset, so the up was never paired and passes
        // — the same answer the pair rule already gives for an up whose down was
        // never swallowed.
        #expect(person(&gate, .mouseUp, at(1620, 1050)) == .pass)
    }

    @Test("a second button's press is tracked separately")
    func trackingIsPerButtonAtTheRect() {
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .mouseDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0, location: at(1620, 1050),
                            stopRect: Self.stop) == .swallow)
        #expect(gate.decide(kind: .mouseDown, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 1, location: at(400, 400),
                            stopRect: Self.stop) == .swallow)
        #expect(gate.decide(kind: .mouseUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 1, location: at(400, 400),
                            stopRect: Self.stop) == .swallow)
        #expect(gate.decide(kind: .mouseUp, sourcePid: 0, userData: 0, ourPid: Self.ourPid,
                            button: 0, location: at(1620, 1050),
                            stopRect: Self.stop) == .stopRun)
    }

    @Test("with no rectangle published nothing can stop the run by mouse")
    func noRectangleNoStop() {
        // The panel is hidden, was taken down after a drawing fault, or the run
        // ended. A rectangle that outlived the panel would let a click on empty
        // screen stop a run.
        var gate = InputBlock.Gate()
        #expect(person(&gate, .mouseDown, at(1620, 1050), stopRect: nil) == .swallow)
        #expect(person(&gate, .mouseUp, at(1620, 1050), stopRect: nil) == .swallow)
    }
}
