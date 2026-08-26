import Foundation
import Testing
@testable import ProctorCore

/// SURF-009's controls, each driven and read for the effect outside it.
///
/// The walkthrough declared six controls and nothing actuated any of them, so
/// `campaign.py check` refused the campaign for the surface: a button renders,
/// carries its accessible name and accepts a click whether or not its handler
/// does anything. The existing walkthrough tests assert structure — that a step
/// is a pure function of three inputs, that identifiers are unique, that every
/// step has a heading. None of them presses anything.
///
/// What each control does, and therefore what "the effect" is:
///   primary   advances to the next step, or ends the flow at the last one
///   back      is offered only where there is somewhere to go back to
///   skip      is offered only where skipping is still meaningful, and reaches
///             the same terminal state as finishing
@Suite("The walkthrough's controls move the flow")
struct WalkthroughControlTests {

    @Test("the primary action walks the whole flow to its one end, and no further")
    func primaryAdvancesToTheEnd() {
        var step = WalkthroughFlow.Step.intro
        var visited: [WalkthroughFlow.Step] = [step]
        // Bounded at eight, twice the number of steps: a transition table that
        // ever cycles would otherwise hang the suite rather than fail it.
        for _ in 0..<8 {
            guard let next = WalkthroughFlow.next(after: step) else { break }
            #expect(!visited.contains(next),
                    Comment(rawValue: "the flow revisits \(next) — the path is not one path"))
            visited.append(next)
            step = next
        }
        #expect(visited.count == 4,
                Comment(rawValue: "expected four steps, walked \(visited.map(\.rawValue))"))
        #expect(WalkthroughFlow.next(after: step) == nil,
                "the last step is the end, so the primary there finishes rather than advancing")
    }

    @Test("every step the primary lands on carries a label that names what it does")
    func primaryIsLabelledPerStep() {
        var seen: Set<String> = []
        var step: WalkthroughFlow.Step? = .intro
        while let current = step {
            let label = WalkthroughFlow.primaryAction(for: current)
            #expect(!label.isEmpty, Comment(rawValue: "\(current) has no primary label"))
            seen.insert(label)
            step = WalkthroughFlow.next(after: current)
        }
        #expect(seen.count > 1,
                Comment(rawValue: "every step shares one primary label \(seen) — the control "
                                  + "would then predict nothing about where it goes"))
    }

    @Test("skip is offered where it means something, and reaches the same end as finishing")
    func skipReachesTheEnd() {
        // Both exits complete: the point of the control is that a person who has
        // decided against setup does not meet the window again at the next launch.
        for exit in WalkthroughFlow.Exit.allCases {
            #expect(WalkthroughFlow.completes(exit))
        }
        let offered = [WalkthroughFlow.Step.intro, .permissions, .granted, .connect]
            .filter { WalkthroughFlow.showsSkip(on: $0, accessibility: false,
                                                screenRecording: false) }
        #expect(!offered.isEmpty, "skip is never offered anywhere, so the control is unreachable")
        #expect(offered.count < 4,
                Comment(rawValue: "skip is offered on every step \(offered.map(\.rawValue)); a "
                                  + "control offered unconditionally is not a decision"))
    }
}
