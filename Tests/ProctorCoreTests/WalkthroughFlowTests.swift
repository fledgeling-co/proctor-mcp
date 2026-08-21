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

    // MARK: - PRO-0081, closing PRO-0067's carried A3

    @Test("A3 · the primary refuses on permissions with a grant missing, and nowhere else")
    func primaryEnablement() {
        // All sixteen combinations written out rather than looped, so a wrong
        // answer names its case. This function is what gives A3 a population:
        // before it, no state disabled the control, and the clause "present in
        // the tree in every state where it is disabled" was asked over an empty
        // set and would have read green having measured nothing.
        var disabled: [String] = []
        for step in WalkthroughFlow.Step.allCases {
            for ax in [false, true] {
                for sr in [false, true] {
                    let enabled = WalkthroughFlow.primaryEnabled(
                        on: step, accessibility: ax, screenRecording: sr)
                    let expected = step != .permissions || (ax && sr)
                    #expect(enabled == expected,
                            "\(step.rawValue) ax=\(ax) sr=\(sr): enabled \(enabled), expected \(expected)")
                    if !enabled { disabled.append("\(step.rawValue)/\(ax)/\(sr)") }
                }
            }
        }
        // The count, printed rather than implied. Three of the sixteen refuse,
        // and they are the three the design of record draws disabled.
        #expect(disabled.sorted() == ["permissions/false/false",
                                      "permissions/false/true",
                                      "permissions/true/false"],
                "the disabled set is \(disabled.sorted()); A3's population is these states")
    }

    @Test("A3 · intro and connect never refuse, whatever macOS has answered")
    func theOnlyRefusalIsTheOneWithAGrantMissing() {
        // The specific regression: disabling the primary on `intro` would trap
        // somebody on the step that explains the app, and on `connect` it would
        // stop them finishing. Skip setup is never disabled either — the flow
        // declines to pretend a grant landed, it does not hold the door shut.
        for step in [WalkthroughFlow.Step.intro, .granted, .connect] {
            #expect(WalkthroughFlow.primaryEnabled(on: step,
                                                   accessibility: false,
                                                   screenRecording: false))
        }
    }

    @Test("A3 · the walkthrough draws the disabled control rather than removing it")
    func theViewDisablesRatherThanHides() throws {
        // The half a pure function cannot answer, read from the view's source:
        // the button is declared unconditionally and carries a `.disabled`
        // modifier, rather than sitting behind an `if` that would take it out of
        // the tree. Whether it is genuinely in the rendered tree is a question
        // for the glass lane, and CASE-0100 asks it there.
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/ProctorUI/Walkthrough.swift"),
            encoding: .utf8)
        let primary = try #require(source.range(of: "WalkthroughFlow.ID.primary"))
        let before = String(source[..<primary.lowerBound]).suffix(400)
        let after = String(source[primary.upperBound...]).prefix(400)
        let around = before + after
        #expect(around.contains(".disabled(!WalkthroughFlow.primaryEnabled("),
                "the primary action is not gated by the Core rule")
        #expect(!around.contains("if step != .connect {\n                    Button(WalkthroughFlow.primaryAction"),
                "the primary action is behind a condition; A3 requires it present and disabled")
    }
}
