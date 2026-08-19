import Foundation
import Testing
@testable import ProctorCore

// PRO-0067. The first-run flow's decisions, judged without a window.

@Suite("Walkthrough flow")
struct WalkthroughFlowTests {

    @Test("A1 · the step is a pure function of its three inputs, at all eight combinations")
    func stepAtEveryCombination() {
        // Written out rather than looped, so a wrong answer names the case.
        #expect(WalkthroughFlow.step(introSeen: false, accessibility: false, screenRecording: false) == .intro)
        #expect(WalkthroughFlow.step(introSeen: false, accessibility: true,  screenRecording: false) == .intro)
        #expect(WalkthroughFlow.step(introSeen: false, accessibility: false, screenRecording: true)  == .intro)
        // The case the guard exists for: a machine that already has both grants
        // still opens on the intro, so nobody is dropped into `connect` without
        // learning what they installed.
        #expect(WalkthroughFlow.step(introSeen: false, accessibility: true,  screenRecording: true)  == .intro)

        #expect(WalkthroughFlow.step(introSeen: true,  accessibility: false, screenRecording: false) == .permissions)
        #expect(WalkthroughFlow.step(introSeen: true,  accessibility: true,  screenRecording: false) == .permissions)
        #expect(WalkthroughFlow.step(introSeen: true,  accessibility: false, screenRecording: true)  == .permissions)
        #expect(WalkthroughFlow.step(introSeen: true,  accessibility: true,  screenRecording: true)  == .granted)
    }

    @Test("A1 · auto-advance fires only from granted, and only with both grants in")
    func autoAdvance() {
        for step in WalkthroughFlow.Step.allCases {
            let fires = WalkthroughFlow.advancesAutomatically(from: step,
                                                              accessibility: true,
                                                              screenRecording: true)
            #expect(fires == (step == .granted),
                    "\(step.rawValue) must not advance itself")
        }
        // And never on a partial grant.
        #expect(!WalkthroughFlow.advancesAutomatically(from: .granted,
                                                       accessibility: true,
                                                       screenRecording: false))
    }

    @Test("A2 · no primary button is labelled with a word that predicts nothing")
    func primaryNamesItsOutcome() {
        let vague: Set<String> = ["continue", "next", "ok", "go", "submit", "proceed"]
        for step in WalkthroughFlow.Step.allCases {
            let label = WalkthroughFlow.primaryAction(for: step)
            #expect(!label.isEmpty)
            #expect(!vague.contains(label.lowercased()),
                    "\(step.rawValue)'s primary action is “\(label)”, which names no outcome")
        }
        #expect(WalkthroughFlow.primaryAction(for: .intro) == "Set up permissions")
        #expect(WalkthroughFlow.primaryAction(for: .connect) == "Done")
    }

    @Test("A2 · every step has a heading and a lede")
    func copyComplete() {
        for step in WalkthroughFlow.Step.allCases {
            #expect(!WalkthroughFlow.heading(for: step).isEmpty)
            #expect(!WalkthroughFlow.lede(for: step).isEmpty)
        }
    }

    @Test("A4 · skipping reaches the same terminal state as completing")
    func skippingCompletes() {
        // Deliberate rather than accidental: the alternative is a window that
        // reappears at every launch for somebody who has decided against it.
        for exit in WalkthroughFlow.Exit.allCases {
            #expect(WalkthroughFlow.completes(exit))
        }
    }

    @Test("A5 · the Screen Recording row states its restart requirement")
    func restartStated() {
        // macOS caches the answer per process for that process's life, so the
        // fact is true whether or not a restart is offered.
        #expect(WalkthroughFlow.Grant.screenRecording.needsRestart)
        #expect(!WalkthroughFlow.Grant.accessibility.needsRestart)
        #expect(WalkthroughFlow.Copy.restartNote.contains("restart"))
    }

    @Test("A3 · identifiers are unique and namespaced")
    func identifiers() {
        let all = WalkthroughFlow.ID.all
        #expect(Set(all).count == all.count)
        for id in all { #expect(id.hasPrefix("proctor.walkthrough.")) }
    }

    @Test("the step order has one path and one end")
    func ordering() {
        var seen: [WalkthroughFlow.Step] = [.intro]
        var step = WalkthroughFlow.Step.intro
        while let n = WalkthroughFlow.next(after: step) { seen.append(n); step = n }
        #expect(seen == [.intro, .permissions, .granted, .connect])
        #expect(WalkthroughFlow.next(after: .connect) == nil)
    }
}
