import Testing
import Foundation
@testable import ProctorCore

// PRO-0019. Whether a batch is going to take the machine, answered once.
//
// What a wrong answer costs is specific. Too low and somebody loses the
// foreground with no warning, which is the whole complaint. Too high and every
// run cries wolf, which costs the notice its meaning by the third time. And an
// answer that disagrees with the scheduler's would mean two different beliefs
// about the same batch inside one process — the scheduler serialising a run the
// panel says is harmless, or the reverse.
//
// Drawing is not testable here and is not pretended to be. Everything decided
// before the pixels is.

private let synthetic: Set<ActionStep.Kind> = [.dragPath, .hover, .click, .key]
private let conditional: Set<ActionStep.Kind> = [.type, .scroll]

private func demand(_ kinds: [ActionStep.Kind], foreground: Bool = false) -> ForegroundDemand {
    ForegroundDemand.forBatch(kinds: kinds, synthetic: synthetic,
                              conditional: conditional, foreground: foreground)
}

@Suite("Foreground demand")
struct ForegroundDemandTests {

    @Test("a batch that only touches the accessibility plane leaves the machine alone")
    func accessibilityOnly() {
        let d = demand([.press, .setValue, .focus, .menu])
        #expect(d.certainSteps == 0)
        #expect(d.conditionalSteps == 0)
        #expect(!d.takesForeground)
        #expect(!d.mayTakeForeground)
        #expect(d.notice(app: "Acme Console") == nil)
    }

    @Test("the kinds with no accessibility route at all are counted as certain")
    func certainKinds() {
        let d = demand([.press, .click, .press, .key, .dragPath, .hover])
        #expect(d.certainSteps == 4)
        #expect(d.totalSteps == 6)
        #expect(d.takesForeground)
    }

    @Test("type and scroll are counted apart, because their plane is the element's decision")
    func conditionalKindsAreSeparate() {
        let d = demand([.press, .type, .scroll])
        #expect(d.certainSteps == 0)
        #expect(d.conditionalSteps == 2)
        // Not `takesForeground`: both usually travel the accessibility plane,
        // and a run held or serialised on the chance one falls back would punish
        // batches that never touch the foreground.
        #expect(!d.takesForeground)
        #expect(d.mayTakeForeground)
    }

    @Test("a raise takes the front without a synthetic step; a bare request does not")
    func raiseAndRequest() {
        #expect(demand([.press, .raise]).takesForeground)
        // PRO-0025. Nothing activates an application except a synthetic post, so
        // `foreground: true` over a batch that cannot post is a request with
        // nothing to spend itself on. It used to take the exclusive lane, arm a
        // contention watch and announce a takeover for a run that then travelled
        // the accessibility plane and left the machine alone.
        #expect(!demand([.press], foreground: true).takesForeground)
        #expect(demand([.press], foreground: true).requestWasInert)
        #expect(!demand([.press]).takesForeground)
    }

    @Test("a foreground request still counts when a step in the batch could use it")
    func requestWithSomethingToSpendItOn() {
        // A `type` reaches the event stream only when the batch asked for the
        // front — the actuator refuses the fallback outright otherwise — so the
        // request is a precondition of posting here, not a habit.
        let typing = demand([.type], foreground: true)
        #expect(typing.mightPost)
        #expect(typing.takesForeground)
        #expect(!typing.requestWasInert)
        // And without the request the same batch cannot post at all.
        #expect(!demand([.type]).takesForeground)
        // A certain kind needs no request.
        #expect(demand([.click]).takesForeground)
    }

    @Test("a raise with a dead foreground request is still a raise")
    func raiseOutranksInertness() {
        let d = demand([.raise], foreground: true)
        #expect(d.takesForeground)
        #expect(!d.requestWasInert)
    }

    @Test("an ignored request is reported rather than silently corrected")
    func inertRequestIsDisclosed() {
        let d = demand([.press, .setValue], foreground: true)
        let report = ForegroundReport.from(d, planes: [.accessibility, .accessibility])
        #expect(report.requestIgnored)
        #expect(!report.ranInForeground)
        #expect(report.measured == 0)
        #expect(report.note?.contains("the request was ignored") == true)
        // And a batch that asked for nothing has nothing to say.
        let quiet = ForegroundReport.from(demand([.press]), planes: [.accessibility])
        #expect(!quiet.requestIgnored)
        #expect(quiet.note == nil)
    }

    @Test("an inert request says nothing on the panel either")
    func inertRequestIsNotAnnounced() {
        // Accessibility is the rule and is never announced, and this batch is
        // going to travel it whatever the flag said.
        #expect(demand([.press, .menu], foreground: true).notice(app: "Acme Console") == nil)
    }

    @Test("takesForeground is exactly the predicate the scheduler already applied")
    func matchesTheLanePredicate() {
        // The refactor's whole risk: if these two ever disagree, a run is
        // serialised on one belief and disclosed on another. Checked over every
        // kind rather than over a chosen few.
        for kind in ActionStep.Kind.allCases {
            for other in ActionStep.Kind.allCases {
                for foreground in [false, true] {
                    let kinds = [kind, other]
                    // The conditional set goes to both, which is the whole point:
                    // a predicate that cannot see `type` and `scroll` cannot tell
                    // a foreground batch that could post from one that asked out
                    // of habit, and the two would drift apart on exactly that.
                    let lanes = LaneDemand.forBatch(kinds: kinds, synthetic: synthetic,
                                                    conditional: conditional,
                                                    app: "app-1", foreground: foreground)
                    let d = demand(kinds, foreground: foreground)
                    #expect(lanes.needsGlobal == d.takesForeground,
                            "\(kind)+\(other) foreground:\(foreground)")
                }
            }
        }
    }

    @Test("an empty batch asks for nothing")
    func empty() {
        let d = demand([])
        #expect(!d.mayTakeForeground)
        #expect(d.notice(app: nil) == nil)
    }
}

@Suite("Foreground notice wording")
struct ForegroundNoticeTests {

    @Test("a certain count with nothing conditional is stated as the total it is")
    func flatCount() {
        let d = demand([.click, .press, .key, .press, .press, .press])
        #expect(d.notice(app: "Acme Console") == "2 of 6 steps need Acme Console in front")
    }

    @Test("a conditional step still to come makes the number a floor, and it says so")
    func floorWhenUnresolved() {
        let d = demand([.click, .type, .press])
        #expect(d.notice(app: "Acme Console") == "At least 1 of 3 steps need Acme Console in front")
    }

    @Test("once every conditional step has resolved, the number stops hedging")
    func stopsHedgingWhenResolved() {
        let d = demand([.click, .type, .press])
        // Both the click and the type ended up on the event stream, so the count
        // is now complete rather than a floor.
        #expect(d.notice(app: "Acme Console", known: 2, resolvedConditional: 1)
                == "2 of 3 steps need Acme Console in front")
    }

    @Test("a batch that only might need the front says might")
    func conditionalOnly() {
        let d = demand([.type, .press])
        #expect(d.notice(app: "Acme Console") == "Up to 1 of 2 steps may need Acme Console in front")
    }

    @Test("a raise with no synthetic step still says the run brings the app forward")
    func raiseWording() {
        #expect(demand([.press, .raise]).notice(app: "Acme Console")
                == "This run brings Acme Console to the front")
    }

    @Test("an unnamed app is described rather than left blank")
    func unnamedApp() {
        #expect(demand([.click]).notice(app: nil)
                == "1 of 1 step need the app under test in front")
    }

    @Test("the app name goes through the same sanitiser every drawn name does")
    func appNameIsSanitised() throws {
        // Markup and newlines are stripped and the name is capped, the way every
        // other name Proctor reads off the screen is. It is NOT quoted, because
        // `RunHUDState.exceptionLine` does not quote it on this same row and two
        // conventions on one line is worse than either — see the note in
        // `notice(app:known:)`.
        let notice = try #require(demand([.click]).notice(app: "Acme\n<b>Console</b>"))
        #expect(!notice.contains("<b>"))
        #expect(!notice.contains("\n"))
        #expect(notice.contains("Acme"))
    }

    @Test("a count cannot be reported below what was known before the run")
    func neverBelowTheFloor() {
        let d = demand([.click, .click])
        // A caller passing a stale smaller number cannot make the panel
        // understate what the batch already contains.
        #expect(d.notice(app: "A", known: 0) == "2 of 2 steps need A in front")
    }
}

@Suite("Foreground report")
struct ForegroundReportTests {

    @Test("what a run needed is measured from the planes its steps travelled")
    func measuresRatherThanPredicts() {
        let d = demand([.click, .type, .press])
        // The type fell back: the element could not be written through the
        // accessibility plane. Nothing before the run could have known.
        let report = ForegroundReport.from(d, planes: [.syntheticEvent, .syntheticEvent,
                                                       .accessibility])
        #expect(report.declaredCertain == 1)
        #expect(report.declaredConditional == 1)
        #expect(report.measured == 2)
        #expect(report.totalSteps == 3)
        #expect(report.ranInForeground)
    }

    @Test("a step that never ran counts as nothing rather than as a synthetic one")
    func unrunStepsDoNotCount() {
        let d = demand([.click, .click])
        let report = ForegroundReport.from(d, planes: [.syntheticEvent, nil])
        #expect(report.measured == 1)
    }

    @Test("a background-safe run has nothing to disclose")
    func silentWhenBackgroundSafe() {
        let report = ForegroundReport.from(demand([.press, .setValue]),
                                           planes: [.accessibility, .accessibility])
        #expect(report.measured == 0)
        #expect(!report.ranInForeground)
        #expect(report.note == nil)
    }

    @Test("a run that took the front says the result is not a background-safe one")
    func saysWhatItCost() throws {
        let report = ForegroundReport.from(demand([.click, .press]),
                                           planes: [.syntheticEvent, .accessibility])
        let note = try #require(report.note)
        #expect(note.contains("1 of 2 steps"))
        #expect(note.contains("not a background-safe one"))
        #expect(note.contains("cannot be repeated unattended"))
    }

    @Test("a run that only raised the app still says it is not background-safe")
    func raiseAloneIsDisclosed() throws {
        let report = ForegroundReport.from(demand([.raise, .press]),
                                           planes: [.accessibility, .accessibility])
        #expect(report.measured == 0)
        #expect(report.ranInForeground)
        let note = try #require(report.note)
        #expect(note.contains("brought the application to the front"))
    }

    @Test("the report survives a round trip, since it goes out on the wire")
    func codableRoundTrip() throws {
        let report = ForegroundReport.from(demand([.click, .type]),
                                           planes: [.syntheticEvent, .accessibility])
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(ForegroundReport.self, from: data) == report)
    }

    @Test("an act result without the block still decodes, so an older reader is not broken")
    func absentBlockDecodes() throws {
        let json = #"{"window":"w1","steps":[],"completed":0}"#
        let result = try JSONDecoder().decode(ActResult.self, from: Data(json.utf8))
        #expect(result.foreground == nil)
    }
}

@Suite("Run HUD foreground disclosure")
struct RunHUDForegroundTests {

    private func step(_ kind: ActionStep.Kind) -> ActionStep {
        ActionStep(kind: kind, node: "n1")
    }

    private func began(_ kinds: [ActionStep.Kind], app: String? = "Acme Console",
                       foreground: Bool = false) -> RunHUDState {
        var state = RunHUDState()
        state.apply(.runBegan(total: kinds.count, app: app,
                              foreground: demand(kinds, foreground: foreground)))
        return state
    }

    @Test("the panel says what the batch contains before its first step runs")
    func saidUpFront() {
        let state = began([.press, .click, .press])
        // Not "a click is happening" — the batch has not started. What is true
        // now is what it contains, and that stays true if it never gets there.
        #expect(state.model.exception == "1 of 3 steps need Acme Console in front")
        #expect(!state.model.syntheticInFlight)
    }

    @Test("a background-safe batch is not announced at all")
    func silentBatchStaysSilent() {
        // Accessibility is the rule and the rule is never announced.
        #expect(began([.press, .setValue]).model.exception == nil)
    }

    @Test("the notice survives the steps that are not themselves synthetic")
    func noticeSurvivesOrdinarySteps() {
        var state = began([.press, .click])
        state.apply(.stepApproaching(step: step(.press), node: nil, synthetic: false))
        #expect(state.model.exception == "1 of 2 steps need Acme Console in front")
        state.apply(.stepActing(step: step(.press), node: nil, synthetic: false))
        #expect(state.model.exception == "1 of 2 steps need Acme Console in front")
        #expect(!state.model.syntheticInFlight)
    }

    @Test("it swaps to the present tense while a synthetic step is in flight, then back")
    func swapsTenseAndBack() {
        var state = began([.click, .press])
        state.apply(.stepActing(step: step(.click), node: nil, synthetic: true))
        #expect(state.model.exception == "Synthetic event — Acme Console must stay in front")
        #expect(state.model.syntheticInFlight)

        state.apply(.stepSettled(step: step(.click), node: nil, settleMs: 12,
                                 plane: .syntheticEvent))
        state.apply(.stepApproaching(step: step(.press), node: nil, synthetic: false))
        #expect(state.model.exception == "1 of 2 steps need Acme Console in front")
        #expect(!state.model.syntheticInFlight)
    }

    @Test("a type that falls back to the event stream raises the count on the row")
    func revisesUpward() {
        var state = began([.type, .click])
        #expect(state.model.exception == "At least 1 of 2 steps need Acme Console in front")

        state.apply(.stepActing(step: step(.type), node: nil, synthetic: false))
        // The field could not be written through the accessibility plane, so the
        // step took the machine. Nothing before this moment could have known.
        state.apply(.stepSettled(step: step(.type), node: nil, settleMs: 8,
                                 plane: .syntheticEvent))
        state.apply(.stepApproaching(step: step(.click), node: nil, synthetic: true))
        state.apply(.stepSettled(step: step(.click), node: nil, settleMs: 8,
                                 plane: .syntheticEvent))
        state.apply(.stepApproaching(step: step(.press), node: nil, synthetic: false))
        #expect(state.model.exception == "2 of 2 steps need Acme Console in front")
    }

    @Test("a type that stayed on the accessibility plane retires the warning instead")
    func retiresTheWarningWhenNothingFellBack() {
        var state = began([.type, .press])
        #expect(state.model.exception == "Up to 1 of 2 steps may need Acme Console in front")
        state.apply(.stepSettled(step: step(.type), node: nil, settleMs: 8,
                                 plane: .accessibility))
        state.apply(.stepApproaching(step: step(.press), node: nil, synthetic: false))
        // The only step that could have taken the machine has run and did not.
        // Leaving a warning up that is now known to be false is the dishonest
        // option, and it is what teaches somebody to ignore the row.
        #expect(state.model.exception == nil)
    }

    @Test("a certain step settling does not count itself a second time")
    func certainStepsAreNotDoubleCounted() {
        var state = began([.click, .press])
        state.apply(.stepActing(step: step(.click), node: nil, synthetic: true))
        state.apply(.stepSettled(step: step(.click), node: nil, settleMs: 8,
                                 plane: .syntheticEvent))
        state.apply(.stepApproaching(step: step(.press), node: nil, synthetic: false))
        // The click was counted before the run. The row states what is known to
        // need the front, not how many events have been posted, so watching one
        // go by must not move it.
        #expect(state.model.exception == "1 of 2 steps need Acme Console in front")
    }

    @Test("the hedge comes off once the last conditional step has run")
    func hedgeRetiresWhenTheDoubtIsSpent() {
        var state = began([.click, .type, .press])
        #expect(state.model.exception == "At least 1 of 3 steps need Acme Console in front")
        // The type stayed on the accessibility plane, so it added nothing — but
        // it also cannot add anything now, and the row stops saying it might.
        state.apply(.stepSettled(step: step(.type), node: nil, settleMs: 8,
                                 plane: .accessibility))
        state.apply(.stepApproaching(step: step(.press), node: nil, synthetic: false))
        #expect(state.model.exception == "1 of 3 steps need Acme Console in front")
    }

    @Test("Pause and Stop stay reachable for the whole of a batch that holds a click")
    func mouseGateFollowsTheStepNotTheText() {
        // The panel ignores mouse events while a synthetic step is in flight, so
        // a click posted under it cannot land on Stop and halt the run that
        // posted it. That gate used to be read off the exception text. The text
        // is now on screen for the whole batch, so if the two were still the
        // same thing the run's own kill switch would be dead throughout.
        var state = began([.press, .click, .press])
        state.apply(.stepApproaching(step: step(.press), node: nil, synthetic: false))
        #expect(state.model.exception != nil)
        #expect(!state.model.syntheticInFlight)
    }

    @Test("the gate opens before the gesture is posted and stays open across it")
    func gateSpansTheWholeGesture() {
        var state = began([.dragPath])
        // Approaching, not acting: the cursor overlay travels first, and a
        // multi-event drag is posted after that.
        state.apply(.stepApproaching(step: step(.dragPath), node: nil, synthetic: true))
        #expect(state.model.syntheticInFlight)
        state.apply(.stepActing(step: step(.dragPath), node: nil, synthetic: true))
        #expect(state.model.syntheticInFlight)
        // Still shut afterwards, so a late event in a slow gesture cannot land
        // on a control that has just become live again.
        state.apply(.stepSettled(step: step(.dragPath), node: nil, settleMs: 30,
                                 plane: .syntheticEvent))
        #expect(state.model.syntheticInFlight)
    }

    @Test("a refusal, a failure and the end of the run all release the gate")
    func gateReleases() {
        for release: (inout RunHUDState) -> Void in [
            { $0.apply(.stepRefused(step: ActionStep(kind: .click), node: nil)) },
            { $0.apply(.stepFailed(step: ActionStep(kind: .click), node: nil)) },
            { $0.apply(.runEnded(.completed)) }
        ] {
            var state = began([.click])
            state.apply(.stepActing(step: step(.click), node: nil, synthetic: true))
            #expect(state.model.syntheticInFlight)
            release(&state)
            #expect(!state.model.syntheticInFlight)
        }
    }

    @Test("a new run replaces the previous run's disclosure rather than inheriting it")
    func doesNotLeakBetweenRuns() {
        var state = began([.click, .press])
        state.apply(.runEnded(.completed))
        state.apply(.runBegan(total: 2, app: "Acme Console",
                              foreground: demand([.press, .press])))
        #expect(state.model.exception == nil)
        #expect(!state.model.syntheticInFlight)
    }
}
