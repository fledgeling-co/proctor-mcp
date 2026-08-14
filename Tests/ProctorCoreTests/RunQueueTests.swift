import Foundation
import Testing
@testable import ProctorCore

// PRO-0016 — the contention model, as arithmetic.
//
// The scheduler's whole value is that it decides *before* anything runs, from
// facts already known: which steps a batch holds and whether it asked for the
// app in front. So the decisions are provable here, with no window, no actor and
// no client — which is also the only place the starvation and fairness rules can
// be proved at all, because reproducing them against a real machine would mean
// racing two agents and hoping.

@Suite("Run lanes")
struct RunLaneTests {

    private let synthetic: Set<ActionStep.Kind> = [.dragPath, .hover, .click, .key]
    private let conditional: Set<ActionStep.Kind> = [.type, .scroll]

    private func demand(_ kinds: [ActionStep.Kind], app: String = "app:1",
                        foreground: Bool = false) -> LaneDemand {
        LaneDemand.forBatch(kinds: kinds, synthetic: synthetic, conditional: conditional,
                            app: app, foreground: foreground)
    }

    @Test("an accessibility batch contends for its own app and nothing else")
    func accessibilityTakesOneLane() {
        let lanes = demand([.press, .setValue, .menu]).lanes
        #expect(lanes == [.app("app:1")])
        // Two sessions driving different apps genuinely do not interfere, and the
        // lane set is what says so.
        #expect(lanes.isDisjoint(with: demand([.press], app: "app:2").lanes))
    }

    @Test("a synthetic step takes the whole machine as well as its app")
    func syntheticTakesTheMachine() {
        for kind in [ActionStep.Kind.click, .hover, .dragPath, .key] {
            let lanes = demand([.press, kind]).lanes
            #expect(lanes.contains(.global), "\(kind.rawValue) enters the one event stream")
            // And the app it raises, because raising changes where everybody
            // else's clicks land.
            #expect(lanes.contains(.app("app:1")))
        }
    }

    @Test("a step that raises a window takes the machine too")
    func raiseTakesTheMachine() {
        // Raising moves the ground under every synthetic event anybody else is
        // posting, which is the same hazard the event stream itself carries.
        #expect(demand([.press, .raise]).needsGlobal)
        #expect(!demand([.press, .focus]).needsGlobal)
    }

    @Test("asking for the app in front takes the machine only when a step could use it")
    func foregroundTakesTheMachine() {
        // PRO-0025. `foreground: true` over a batch that cannot reach the event
        // stream promises a takeover that never happens: nothing activates an
        // application except a synthetic post. Such a run took the exclusive
        // global lane and serialised against every other session for nothing.
        #expect(!demand([.press], foreground: true).needsGlobal)
        #expect(!demand([.press], foreground: false).needsGlobal)
        // A batch holding a `type` is a different matter: the actuator will post
        // if the element refuses the value, and it is allowed to precisely
        // because the caller asked for the front.
        #expect(demand([.press, .type], foreground: true).needsGlobal)
        #expect(!demand([.press, .type], foreground: false).needsGlobal)
        // And a certain kind never needed asking.
        #expect(demand([.click], foreground: true).needsGlobal)
    }

    @Test("the lane set is fixed before the run and never grows")
    func laneSetIsFixed() {
        // Taking lanes one at a time is how two runs wedge each other, so the
        // demand is one value computed once from the whole batch — the last step
        // counts as much as the first.
        let late = demand([.press, .setValue, .focus, .click])
        let early = demand([.click, .press])
        #expect(late.lanes == early.lanes)
    }
}

@Suite("Queue fairness")
struct RunQueuePlanTests {

    private func run(_ id: Int, lanes: Set<RunLane>, session: String = "s1") -> RunTicketInfo {
        RunTicketInfo(id: id,
                      identity: RunSessionIdentity(project: session, connection: "0000",
                                                   key: session),
                      summary: "run \(id)", lanes: lanes, since: 0)
    }

    @Test("two runs against different apps both start")
    func differentAppsRunTogether() {
        let waiting = [run(1, lanes: [.app("a")]), run(2, lanes: [.app("b")])]
        #expect(RunQueuePlan.grantable(waiting: waiting, busy: [], held: false) == [1, 2])
    }

    @Test("two runs against the same app take turns")
    func sameAppSerialises() {
        let waiting = [run(1, lanes: [.app("a")]), run(2, lanes: [.app("a")])]
        #expect(RunQueuePlan.grantable(waiting: waiting, busy: [], held: false) == [1])
        // And the second only goes once the first has given the lane back.
        #expect(RunQueuePlan.grantable(waiting: [waiting[1]], busy: [.app("a")], held: false) == [])
        #expect(RunQueuePlan.grantable(waiting: [waiting[1]], busy: [], held: false) == [2])
    }

    @Test("only one whole-machine run anywhere at a time, and it holds the app it raises")
    func globalIsExclusive() {
        let global = run(1, lanes: [.global, .app("a")])
        // One at a time anywhere on the machine: they share one event stream.
        #expect(RunQueuePlan.grantable(waiting: [global], busy: [.global], held: false) == [])
        // And it blocks process-directed work on the app it raises, because
        // raising changes where everybody else's clicks land.
        #expect(RunQueuePlan.grantable(waiting: [global], busy: [.app("a")], held: false) == [])
        #expect(RunQueuePlan.grantable(waiting: [global], busy: [], held: false) == [1])
        // What it deliberately does NOT block is an accessibility run on a
        // different app. That work is IPC to another process and is unaffected by
        // what is in front, which is the whole reason this is three lanes rather
        // than one queue — queueing it would make Proctor feel broken for the
        // common case.
        let alongside = [global, run(2, lanes: [.app("z")])]
        #expect(RunQueuePlan.grantable(waiting: alongside, busy: [], held: false) == [1, 2])
    }

    @Test("a whole-machine run at the head of the line is not walked past for ever")
    func globalIsABarrier() {
        // The failure this prevents: a trickle of single-app work against apps the
        // waiting run does not touch would otherwise start ahead of it, one after
        // another, for as long as the trickle lasted.
        let waiting = [run(1, lanes: [.global, .app("a")]), run(2, lanes: [.app("b")])]
        #expect(RunQueuePlan.grantable(waiting: waiting, busy: [.app("a")], held: false) == [])
    }

    @Test("first come, first served within a lane")
    func fifoWithinALane() {
        // Second in the line must not be overtaken by third simply because both
        // want the same busy lane and the scan kept walking.
        let waiting = [run(1, lanes: [.app("a")]), run(2, lanes: [.app("a")]),
                       run(3, lanes: [.app("a")])]
        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [], held: false)
        #expect(granted == [1])
    }

    @Test("a run blocked on one app does not hold up a different app behind it")
    func blockedRunDoesNotBlockAnotherApp() {
        let waiting = [run(1, lanes: [.app("a")]), run(2, lanes: [.app("b")])]
        #expect(RunQueuePlan.grantable(waiting: waiting, busy: [.app("a")], held: false) == [2])
    }

    @Test("a held queue starts nothing at all, including the active session's own next run")
    func holdStopsEverything() {
        let waiting = [run(1, lanes: [.app("a")], session: "s1"),
                       run(2, lanes: [.app("b")], session: "s2")]
        #expect(RunQueuePlan.grantable(waiting: waiting, busy: [], held: true) == [])
        // A hold a session could jump by simply sending its next batch would not
        // be a control, so releasing is the only way anything moves.
        #expect(RunQueuePlan.grantable(waiting: waiting, busy: [], held: false) == [1, 2])
    }

    @Test("the give-up ceiling is adjustable by the same kind of setting as the off-switches")
    func waitLimitIsConfigurable() {
        #expect(RunQueuePlan.waitLimit(from: [:]) == RunQueuePlan.defaultWaitLimit)
        #expect(RunQueuePlan.waitLimit(from: ["PROCTOR_QUEUE_WAIT_LIMIT": "5"]) == 5)
        #expect(RunQueuePlan.waitLimit(from: ["PROCTOR_QUEUE_WAIT_LIMIT": "nope"])
                == RunQueuePlan.defaultWaitLimit)
        // Hosts cut a tool call off around a minute, so the default has to fire
        // inside that or the caller gets silence instead of Proctor's reason.
        #expect(RunQueuePlan.defaultWaitLimit < 60)
    }
}

@Suite("Queue refusals")
struct RunQueueRefusalTests {

    @Test("a person's removal is never reported as a failed step")
    func personIsNotAFault() {
        for cleared in [true, false] {
            let error = RunQueueRefusal.droppedByPerson(cleared: cleared).error
            // One is a signal to stop and ask; a fault is a signal to retry, and
            // conflating them is how a person's decision becomes a retry loop.
            #expect(error.code == .haltedByPerson)
            #expect(error.code != .actionFailed)
            #expect(error.message.contains("a person"))
            #expect(error.remedy?.contains("Ask before") == true)
        }
        #expect(RunQueueRefusal.droppedByPerson(cleared: true).error.message.contains("cleared"))
    }

    @Test("giving up says the machine was busy and where the call stood")
    func timeoutSaysWhereItStood() {
        let error = RunQueueRefusal.timedOut(seconds: 45, position: 2, waiting: 3).error
        #expect(error.code == .queueBusy)
        #expect(error.message.contains("second of 3"))
        #expect(error.message.contains("45"))
        // Nothing ran, and the caller has to be able to tell that from a run that
        // half-happened.
        #expect(error.message.contains("never ran any step")
                || error.message.contains("without running any step"))
    }

    @Test("a session that keeps queueing is refused rather than allowed to starve the others")
    func capRefusesImmediately() {
        let error = RunQueueRefusal.tooManyWaiting(cap: 3).error
        #expect(error.code == .queueBusy)
        #expect(error.message.contains("3 runs waiting"))
        #expect(error.remedy?.contains("Nothing was actuated") == true)
    }
}

@Suite("Session identity")
struct RunSessionIdentityTests {

    @Test("two sessions are the same only when the same process is behind them")
    func identityIsTheProcess() {
        let a = RunSessionIdentity(project: "proctor-mcp", connection: "a3f1", key: "101:900")
        let collision = RunSessionIdentity(project: "diolog-web", connection: "a3f1", key: "202:900")
        // A four-character id collides now and then. It is a display string, and
        // a collision there must never merge two clients' waiting allowances.
        #expect(a != collision)
        #expect(a == RunSessionIdentity(project: "proctor-mcp", connection: "zzzz", key: "101:900"))
    }

    @Test("the panel prints the project and the short id, never a pid")
    func labelIsWhatAPersonReads() {
        let identity = RunSessionIdentity(project: "proctor-mcp", connection: "a3f1", key: "101:900")
        #expect(identity.label == "proctor-mcp a3f1")
        #expect(!identity.label.contains("101"))
    }
}

@Suite("Queue bar model")
struct RunQueueModelTests {

    private func run(_ id: Int, project: String, waitingSince: Double,
                     summary: String = "Act ×3") -> RunTicketInfo {
        RunTicketInfo(id: id,
                      identity: RunSessionIdentity(project: project, connection: "0000",
                                                   key: "\(id)"),
                      summary: summary, lanes: [.app("a")], since: waitingSince)
    }

    @Test("the bar is absent entirely when nothing is waiting")
    func absentWhenNothingWaits() {
        // The queue costs nothing until there is contention, and two runs going at
        // once in different lanes is not contention.
        let snapshot = RunQueueSnapshot(active: [run(1, project: "a", waitingSince: 0),
                                                 run(2, project: "b", waitingSince: 0)],
                                        waiting: [])
        let model = RunQueueModel.from(snapshot, live: 1, now: 10, expanded: false)
        #expect(!model.visible)
        #expect(model.waitingCount == 0)
    }

    @Test("a held queue keeps its bar even with nothing waiting, so Hold can be released")
    func heldQueueStaysVisible() {
        // The wedge this prevents: Hold lives inside this bar, so a bar that
        // vanished when the last waiter timed out would hold the machine with no
        // way on screen to let it go, and every later run would wait out its
        // ceiling with nothing saying why.
        var model = RunQueueModel.from(RunQueueSnapshot(held: true), live: nil,
                                       now: 0, expanded: false)
        #expect(model.visible)
        #expect(model.label.contains("held"))
        model.held = false
        model.waitingCount = 0
        #expect(!model.visible)
    }

    @Test("the count counts only the waiting ones")
    func countIsWaitingOnly() {
        let snapshot = RunQueueSnapshot(active: [run(1, project: "a", waitingSince: 0),
                                                 run(2, project: "b", waitingSince: 0)],
                                        waiting: [run(3, project: "c", waitingSince: 0)])
        let model = RunQueueModel.from(snapshot, live: 1, now: 0, expanded: true)
        // Counting the running ones would overstate how blocked the machine is.
        #expect(model.waitingCount == 1)
        #expect(model.label == "1 session waiting")
    }

    @Test("the list shows every run that is not on the live line, running or waiting")
    func listShowsRunningAndWaiting() {
        let snapshot = RunQueueSnapshot(active: [run(1, project: "live", waitingSince: 0),
                                                 run(2, project: "other", waitingSince: 0)],
                                        waiting: [run(3, project: "queued", waitingSince: 0)])
        let model = RunQueueModel.from(snapshot, live: 1, now: 64, expanded: true)
        #expect(model.rows.count == 2)
        // A run in another lane is running, not queued. Calling it queued would
        // understate what the scheduler can actually do.
        #expect(model.rows[0].session == "other")
        #expect(model.rows[0].position == nil)
        #expect(!model.rows[0].isWaiting)
        #expect(model.rows[1].session == "queued")
        #expect(model.rows[1].position == 1)
        #expect(model.rows[1].waited == "1:04")
    }

    @Test("positions renumber from one, so a drop leaves no gap")
    func positionsRenumber() {
        let waiting = [run(7, project: "a", waitingSince: 0), run(9, project: "b", waitingSince: 0)]
        let model = RunQueueModel.from(RunQueueSnapshot(waiting: waiting), live: nil,
                                       now: 0, expanded: true)
        #expect(model.rows.map(\.position) == [1, 2])
        // The drop control carries the scheduler's own id, so it removes the run a
        // person pointed at rather than whatever has slid into that place.
        #expect(model.rows.map(\.run) == [7, 9])
    }

    @Test("the queue's words are never the run's words")
    func holdIsNotPause() {
        var model = RunQueueModel()
        #expect(model.holdLabel == "Hold")
        model.held = true
        #expect(model.holdLabel == "Held")
        // Two controls both called "pause" is how somebody stops the wrong thing.
        for label in [model.holdLabel, "Clear"] {
            #expect(!label.lowercased().contains("pause"))
            #expect(!label.lowercased().contains("stop"))
        }
    }

    @Test("a run's own line is fenced the way every other object on the panel is")
    func summariesAreFenced() {
        // A flow name is caller-supplied and an app name is read off the screen,
        // and both are shown to a person deciding what to stop.
        let replay = StepDescription.runLine(.replay(flow: "checkout"), app: "Acme Console")
        #expect(replay == "Replay \"checkout\" · \"Acme Console\"")
        #expect(StepDescription.runLine(.act(steps: 6), app: nil) == "Act ×6")
        #expect(StepDescription.runLine(.stability(flow: "login", runs: 5), app: "Safari")
                == "Stability ×5 of \"login\" · \"Safari\"")
        // Markup and newlines in a supplied name never reach the panel intact.
        let hostile = StepDescription.runLine(.replay(flow: "a\nb<em>c"), app: nil)
        #expect(!hostile.contains("\n"))
        #expect(!hostile.contains("<"))
    }
}

@Suite("Queue health report")
struct RunQueueSnapshotTests {

    @Test("occupancy is answerable per lane, so a wedged lane is not invisible")
    func laneReport() {
        let identity = RunSessionIdentity(project: "p", connection: "0000", key: "k")
        let snapshot = RunQueueSnapshot(
            active: [RunTicketInfo(id: 1, identity: identity, summary: "s",
                                   lanes: [.app("a"), .global], since: 0)],
            waiting: [RunTicketInfo(id: 2, identity: identity, summary: "s",
                                    lanes: [.app("a")], since: 0)])
        let report = snapshot.laneReport
        #expect(report.count == 2)
        let app = try! #require(report.first { $0.lane == "app:a" })
        #expect(app.active == 1)
        #expect(app.waiting == 1)
        let global = try! #require(report.first { $0.lane == "global" })
        #expect(global.active == 1)
        #expect(global.waiting == 0)
    }
}
