import Testing
import Foundation
@testable import ProctorCore

// PRO-0098, DEF-132. The defect was not that 1.2 seconds is too short — it was
// that a clock was answering a question only an event can answer. So these
// assertions are about the state the window DRAWS, taken through
// `AgentRecovery.decide`, rather than about a boolean on a model nothing can
// reach: `ProctorUI` is an executable target with no test target, and a decision
// that lives only inside `AgentModel` is a decision no test can grade.
//
// Every case below drives probes rather than time. A restart that takes twelve
// seconds and a restart that takes twelve minutes are the same sequence here,
// which is the point: nothing in the lifecycle reads a clock any more.

@Suite("PRO-0098 · a restart ends when the agent comes back")
struct RestartWatchTests {

    /// The window's state during a restart, as the menu and the status block draw
    /// it. `nil` means no offer, which is what "we are applying, hold on" looks
    /// like. `.startAgent` is the red "the background agent is not answering".
    private func drawn(_ watch: RestartWatch, reachable: Bool) -> AgentRecovery.Kind? {
        AgentRecovery.decide(applying: watch.isApplying,
                             reachable: reachable,
                             agentSeesScreenRecording: .granted,
                             windowSeesScreenRecording: true,
                             runInFlight: false)?.kind
    }

    // MARK: - The defect itself

    @Test("a restart that outlives 1.2 s never draws the agent-down state")
    func aSlowRestartIsNotAnOutage() {
        var watch = RestartWatch(giveUpAfterProbes: 30)
        watch.begin()

        // Eight probes on the 2.0 s doctor cadence is sixteen seconds — an order
        // of magnitude past the old 1.2 s clearing, and an ordinary duration for a
        // `launchctl kickstart -k` on a loaded machine. Under the fixed timer the
        // window was drawing "the background agent is not answering" for all of it.
        for probe in 1...8 {
            watch.observed(reachable: false)
            #expect(watch.isApplying, "the watch gave up at probe \(probe)")
            #expect(drawn(watch, reachable: false) == nil,
                    "the agent-down state was drawn at probe \(probe) of a restart in flight")
        }

        // And it ends on the event, not on a further wait.
        watch.observed(reachable: true)
        #expect(watch.state == .settled)
        #expect(watch.isApplying == false)
    }

    /// The arming for the case above, and it is the whole reason that case can
    /// fail. `decide` returns `nil` for a great many reasons; if it returned `nil`
    /// with `applying` false as well, the loop above would pass over a model that
    /// had lost the state entirely. This is the same call with the same
    /// unreachable agent and the applying state gone, and it MUST draw the red.
    @Test("with the applying state gone, the same unreachable agent draws the red")
    func theInstrumentReportsTheStateItIsWatchingFor() {
        var watch = RestartWatch()
        #expect(watch.isApplying == false)
        #expect(drawn(watch, reachable: false) == .startAgent)

        // Which is exactly what the fixed timer produced: cleared on a stopwatch,
        // with the agent still on its way back.
        watch.begin()
        watch.observed(reachable: false)
        #expect(drawn(watch, reachable: false) == nil)
        watch.cancel()                      // stand in for the 1.2 s clearing
        #expect(drawn(watch, reachable: false) == .startAgent)
    }

    // MARK: - The wait still ends

    @Test("a restart that never comes back is abandoned and the agent is reported down")
    func aRestartThatNeverLandsStopsClaimingToBeInFlight() {
        var watch = RestartWatch(giveUpAfterProbes: 4)
        watch.begin()
        for _ in 1...3 {
            watch.observed(reachable: false)
            #expect(watch.isApplying)
        }
        watch.observed(reachable: false)
        #expect(watch.state == .abandoned)
        #expect(watch.isApplying == false)
        // By now it is a true statement rather than a guess, so the window says it.
        #expect(drawn(watch, reachable: false) == .startAgent)
    }

    @Test("the give-up counts probes rather than elapsed time")
    func theGiveUpIsEvidenceNotDuration() {
        // Two watches, the same wall clock, different amounts of evidence. A
        // deadline could not tell these apart; a count can, and that is the
        // difference between this and raising 1.2 to a larger number.
        var busy = RestartWatch(giveUpAfterProbes: 5)
        var quiet = RestartWatch(giveUpAfterProbes: 5)
        busy.begin()
        quiet.begin()
        for _ in 1...5 { busy.observed(reachable: false) }
        quiet.observed(reachable: false)
        #expect(busy.state == .abandoned)
        #expect(quiet.state == .applying)
        #expect(quiet.probes == 1)
    }

    // MARK: - The edges the polling timer creates

    @Test("probes arriving when no restart was asked for are not counted")
    func anIdleWatchIsNotAdvancedByThePoll() {
        var watch = RestartWatch(giveUpAfterProbes: 2)
        // The doctor poll runs for the app's whole life. A watch that counted
        // every tick would arrive at a restart already out of patience.
        for _ in 1...50 { watch.observed(reachable: false) }
        #expect(watch.state == .idle)
        #expect(watch.probes == 0)

        watch.begin()
        watch.observed(reachable: false)
        #expect(watch.isApplying, "an idle poll consumed this restart's budget")
    }

    @Test("a second restart is not judged on the first one's probes")
    func beginResetsTheEvidence() {
        var watch = RestartWatch(giveUpAfterProbes: 3)
        watch.begin()
        watch.observed(reachable: false)
        watch.observed(reachable: false)
        #expect(watch.probes == 2)

        watch.begin()
        #expect(watch.probes == 0)
        watch.observed(reachable: false)
        watch.observed(reachable: false)
        #expect(watch.isApplying)
    }

    @Test("a settled watch is not reopened by a later probe")
    func theRestartEndsOnce() {
        var watch = RestartWatch()
        watch.begin()
        watch.observed(reachable: true)
        #expect(watch.state == .settled)
        // The agent going away again later is an outage, not a continuation of a
        // restart Proctor asked for, and the window should say so.
        for _ in 1...10 { watch.observed(reachable: false) }
        #expect(watch.state == .settled)
        #expect(drawn(watch, reachable: false) == .startAgent)
    }

    @Test("a give-up count below one is refused rather than making every restart instant")
    func theCountHasAFloor() {
        var watch = RestartWatch(giveUpAfterProbes: 0)
        watch.begin()
        watch.observed(reachable: false)
        #expect(watch.state == .abandoned)
        #expect(watch.giveUpAfterProbes == 1)
    }

    // MARK: - The 1.2 is still there, and still means what it meant

    @Test("the 1.2-second beat before the first probe is not raised")
    func theDelayIsUnchanged() throws {
        // The brief's explicit instruction: do not raise 1.2 to a larger number,
        // because that makes the window wrong less often on this machine and says
        // nothing about what it is waiting for. This reads the source rather than
        // trusting the diff.
        let model = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ProctorUI/AgentModel.swift")
        let source = try String(contentsOf: model, encoding: .utf8)

        #expect(source.contains("asyncAfter(deadline: .now() + 1.2)"),
                "the beat before the first probe is gone or was changed")

        // And the thing that WAS wrong is gone: nothing clears the applying state
        // from inside that block any more.
        let afterDelay = try #require(source.range(of: "asyncAfter(deadline: .now() + 1.2)"))
        let block = source[afterDelay.upperBound...].prefix(400)
        #expect(!block.contains("isApplying = false"),
                "the applying state is still cleared by the timer")
        #expect(source.contains("restartWatch.observed(reachable:"),
                "no probe is fed to the restart lifecycle")
    }
}
