import Testing
@testable import ProctorCore

// PRO-0028. The menu's "Re-check now" is gone; this is what took its slot.
//
// A1 (the row is an absence in a SwiftUI view) and A6 (the in-app grant path is
// unchanged and now has a second caller) are read off the diff — there is no test
// target for `ProctorUI` and no window server under `swift test`.
@Suite("Menu recovery offers")
struct AgentRecoveryTests {

    /// Everything healthy: reachable, the grant in place, nothing applying.
    private func healthy(applying: Bool = false,
                         reachable: Bool = true,
                         agentSees: Bool = true,
                         windowSees: Bool? = true,
                         running: Bool = false) -> AgentRecovery.Offer? {
        AgentRecovery.decide(applying: applying,
                             reachable: reachable,
                             agentSeesScreenRecording: agentSees,
                             windowSeesScreenRecording: windowSees,
                             runInFlight: running)
    }

    // MARK: A2 — offered only for a stale Screen Recording grant

    @Test("a healthy agent offers nothing")
    func healthyOffersNothing() {
        #expect(healthy() == nil)
        #expect(healthy(windowSees: nil) == nil)
        #expect(healthy(running: true) == nil)
    }

    @Test("the agent denying a grant this window can see offers the restart")
    func staleGrantOffersTheRestart() {
        let offer = healthy(agentSees: false, windowSees: true)
        #expect(offer?.kind == .restartAgent)
        #expect(offer?.action == "Restart Agent")
    }

    // The narrowing the out-of-family review made first: this decides on Screen
    // Recording alone. Accessibility is read live by the agent and lands on the
    // 2-second poll, so a SIGKILL for it would drop a run to fix nothing. The
    // function cannot see any other grant, which is the point — pinned here so a
    // later change that widens the input has to argue with a test.
    @Test("no other grant is an input")
    func decidesOnScreenRecordingAlone() {
        #expect(healthy() == nil)
    }

    // MARK: A3 — a restart is offered only where a restart is the cure

    // The critic's first finding, and the one that changed the design. Offering
    // the restart whenever the agent said "denied" would have put a permanent row
    // on every Mac that has not granted Screen Recording and is not going to,
    // with a button that cannot create a grant. A restart cures a stale answer,
    // never an absent permission.
    @Test("an absent permission is never offered a restart")
    func absentPermissionIsNotOfferedARestart() {
        for windowSees in [false, nil] as [Bool?] {
            #expect(healthy(agentSees: false, windowSees: windowSees) == nil)
        }
    }

    @Test("the sentence claims staleness only where it is confirmed")
    func theSentenceClaimsWhatItKnows() {
        let reason = try! #require(healthy(agentSees: false, windowSees: true)?.reason)
        #expect(reason.contains("Screen Recording is granted"))
        #expect(reason.contains("earlier answer"))
    }

    // MARK: A4 — a run in flight is named as the cost

    @Test("a run in flight is named as the cost")
    func runInFlightIsNamed() {
        let running = try! #require(
            healthy(agentSees: false, windowSees: true, running: true)?.reason)
        let idle = try! #require(
            healthy(agentSees: false, windowSees: true)?.reason)
        #expect(running.hasSuffix("Restarting stops the run in flight."))
        #expect(!idle.contains("stops the run"))
    }

    @Test("naming the cost changes nothing but the sentence")
    func costDoesNotChangeTheAction() {
        let running = healthy(agentSees: false, windowSees: true, running: true)
        let idle = healthy(agentSees: false, windowSees: true)
        #expect(running?.kind == idle?.kind)
        #expect(running?.action == idle?.action)
    }

    // MARK: A7 — a restart already in flight is not offered a second one

    // `launchctl kickstart -k` is a SIGKILL. Without this a second click during
    // the 1.2s settle stacks a second kill on a process mid-launch, and the
    // momentary unreachability would meanwhile present as "Start Agent" — an
    // offer to start something that is already coming back.
    @Test("nothing is offered while a restart is in flight")
    func applyingOffersNothing() {
        #expect(healthy(applying: true, reachable: false) == nil)
        #expect(healthy(applying: true, agentSees: false, windowSees: true) == nil)
        #expect(healthy(applying: true, reachable: false,
                        agentSees: false, windowSees: true, running: true) == nil)
    }

    // MARK: A8 — an unreachable agent is offered a start

    // Removing "Re-check now" would otherwise have left the menu with nothing to
    // do about a wedged agent. The old row's refresh was never the cure for that
    // either; a start is.
    @Test("an unreachable agent is offered a start, whatever it last said")
    func unreachableIsOfferedAStart() {
        for agentSees in [true, false] {
            for windowSees in [true, false, nil] as [Bool?] {
                let offer = healthy(reachable: false,
                                    agentSees: agentSees, windowSees: windowSees)
                #expect(offer?.kind == .startAgent)
                #expect(offer?.action == "Start Agent")
            }
        }
    }

    @Test("an unreachable agent is never offered a restart")
    func unreachableIsNeverOfferedARestart() {
        #expect(healthy(reachable: false, agentSees: false, windowSees: true)?.kind
                != .restartAgent)
    }

    // MARK: A5 — the buttons are in the register of their neighbours

    @Test("the button titles match the menu's other verbs")
    func titlesMatchTheRegister() {
        // `Relaunch Proctor`, `Quit Proctor`, `Stop Run`, `Pause Run` — title
        // case, verb then object, and no ellipsis, because these act rather than
        // opening something.
        #expect(AgentRecovery.startAction == "Start Agent")
        #expect(AgentRecovery.restartAction == "Restart Agent")
        for title in [AgentRecovery.startAction, AgentRecovery.restartAction] {
            #expect(!title.contains("…"))
        }
    }

    // A menu row truncates a long sentence and reads it aloud as one string.
    // PRO-0027's neighbour — "Proctor was updated. Relaunch to use the new
    // version." — is the length this idiom is known to carry.
    @Test("the sentences stay near the length the menu already carries")
    func sentencesStayShort() {
        let reasons = [
            try! #require(healthy(reachable: false)?.reason),
            try! #require(healthy(agentSees: false, windowSees: true)?.reason),
            try! #require(healthy(agentSees: false, windowSees: true, running: true)?.reason)
        ]
        for reason in reasons { #expect(reason.count <= 120) }
    }
}
