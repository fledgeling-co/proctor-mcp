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

    // MARK: - PRO-0090, DEF-056. One prominent Grant at a time.

    /// The design of record's caption is the specification: *"Only one Grant is
    /// prominent at a time: the one to press next"*
    /// (`design/surfaces/proctor-surfaces.html`, walkthrough,
    /// `data-state="permissions"`), drawn with Accessibility's Grant filled and
    /// Screen Recording's plain.
    ///
    /// Before this item `HeroPermRow` gave every ungranted row
    /// `.borderedProminent` unconditionally, so the state the walkthrough opens
    /// in — neither grant held — drew two identical calls to action.
    @Test("DEF-056 · exactly one grant is prominent, at all four combinations")
    func oneProminentGrantAtATime() {
        typealias G = WalkthroughFlow.Grant
        let cases: [(Bool, Bool, G?)] = [
            (false, false, .accessibility),    // the design's own drawing
            (true,  false, .screenRecording),
            (false, true,  .accessibility),
            (true,  true,  nil),
        ]
        for (accessibility, screenRecording, expected) in cases {
            let got = WalkthroughFlow.prominentGrant(accessibility: accessibility,
                                                     screenRecording: screenRecording)
            #expect(got == expected,
                    "accessibility=\(accessibility) screenRecording=\(screenRecording) gave \(String(describing: got))")
        }
    }

    /// The count, said as a count. `prominentGrant` returning one value makes
    /// "only one is prominent" true by construction, so what is worth asserting
    /// is that it is never nil while a grant is still missing — a nil there
    /// would draw two plain buttons and offer no first move either.
    @Test("DEF-056 · a grant is nominated in every state where one is still missing")
    func aGrantIsAlwaysNominatedWhileOneIsMissing() {
        for accessibility in [false, true] {
            for screenRecording in [false, true] {
                let got = WalkthroughFlow.prominentGrant(accessibility: accessibility,
                                                         screenRecording: screenRecording)
                let anyMissing = !(accessibility && screenRecording)
                #expect((got != nil) == anyMissing,
                        "a=\(accessibility) sr=\(screenRecording) nominated \(String(describing: got))")
                if let got { #expect(!(got == .accessibility ? accessibility : screenRecording),
                                     "the nominated grant is already held") }
            }
        }
    }

    /// The half a pure function cannot answer: that the view reads the rule
    /// rather than keeping its own. Read from the view's source, because there
    /// is no `ProctorUI` test target and no window server here — the same
    /// footing `theViewDisablesRatherThanHides` above stands on, and it claims
    /// no more than that.
    @Test("DEF-056 · the row takes prominence as a parameter rather than deciding it")
    func theRowDoesNotDecideItsOwnProminence() throws {
        #expect(try Self.walkthroughSource().contains("WalkthroughFlow.prominentGrant("),
                "the view does not read the Core rule")
        #expect(try Self.walkthroughSource().contains("let prominent: Bool"),
                "HeroPermRow does not take prominence as a parameter")
        // The defect itself: a row that reaches `.borderedProminent` with
        // nothing gating it. Every occurrence must sit under the `prominent`
        // branch, so the unguarded form must not appear at all.
        // Comments stripped first. The count below is of code, and a guard that
        // counted a doc comment naming `.borderedProminent` would report the
        // defect present in a file that had fixed it — which is how this
        // expectation first failed.
        let source = Self.withoutComments(try Self.walkthroughSource())
        let rowStart = try #require(source.range(of: "private struct HeroPermRow"))
        let row = String(source[rowStart.lowerBound...])
        let prominentUses = row.components(separatedBy: ".borderedProminent").count - 1
        #expect(prominentUses == 1,
                "HeroPermRow draws .borderedProminent \(prominentUses) times; DEF-056 needs exactly one, under the `prominent` branch")
        let branch = try #require(row.range(of: "if prominent {"))
        let filled = try #require(row.range(of: ".borderedProminent"))
        #expect(branch.lowerBound < filled.lowerBound,
                ".borderedProminent is not inside the prominent branch")
    }

    // MARK: - PRO-0090, DEF-039. The strings left the view.

    /// The clause `status_literals.py` measures, asked here so the gate owns it
    /// too: no string literal in `Walkthrough.swift` outside a comment.
    ///
    /// This is `source-analysis` and nothing above it. It says the view holds no
    /// literal, not that the window renders the constant — a value-level check
    /// standing in for a rendered one is DEF-035's own lesson.
    @Test("DEF-039 · the walkthrough view holds no string literal of its own")
    func theWalkthroughViewHoldsNoLiterals() throws {
        let quotes = Self.withoutComments(try Self.walkthroughSource())
            .filter { $0 == "\"" }.count
        #expect(quotes == 0,
                "Walkthrough.swift holds \(quotes) quote characters outside comments; every user-facing string belongs in WalkthroughFlow")
    }

    /// Every string this item moved resolves verbatim in Core, so the move was a
    /// move. PRO-0081 shortened one heading in the same operation and a fresh
    /// verifier found it; these are the sentences most likely to be paraphrased.
    @Test("DEF-039 · the moved walkthrough copy is character-identical to what shipped")
    func themovedCopyIsVerbatim() {
        #expect(WalkthroughFlow.Copy.heroTitle == "Enable Proctor")
        #expect(WalkthroughFlow.Copy.allow == "Allow")
        #expect(WalkthroughFlow.Copy.allowed == "Allowed")
        #expect(WalkthroughFlow.Copy.copyConfig == "Copy config")
        #expect(WalkthroughFlow.Copy.openSettings == "Already allowed? Open System Settings")
        #expect(WalkthroughFlow.Copy.connectReadyTitle == "You're all set")
        #expect(WalkthroughFlow.Copy.introCalloutTitle == "Two permissions, asked once")
        #expect(WalkthroughFlow.stepTitle(for: .intro) == "What Proctor does")
        #expect(WalkthroughFlow.stepTitle(for: .connect) == "Point a model at it")
        #expect(WalkthroughFlow.stepTitle(for: .permissions).isEmpty)
        #expect(WalkthroughFlow.Grant.accessibility.glyph == "accessibility")
        #expect(WalkthroughFlow.Grant.screenRecording.glyph == "display")
        #expect(WalkthroughFlow.Grant.accessibility.rowDescription
                == "Lets Proctor read the control tree and drive it")
        #expect(WalkthroughFlow.Grant.screenRecording.rowDescription
                == "Lets Proctor see what your app drew")
        #expect(WalkthroughFlow.Grant.accessibility.allowLabel == "Allow Accessibility")
        #expect(WalkthroughFlow.Grant.screenRecording.allowLabel == "Allow Screen Recording")
    }

    /// The two-values-one-name pairs this file now carries, each kept and each
    /// named. Asserted to DIFFER, so the record cannot rot into a claim that
    /// they agree — the same guard `StatusSurfaceTests` puts on `toolsNote`.
    @Test("DEF-035 · the walkthrough's unrendered twins are kept and differ from what ships")
    func theUnrenderedTwinsAreNamed() {
        #expect(WalkthroughFlow.Copy.grant != WalkthroughFlow.Copy.allow,
                "the design's word and the build's word for the grant control agree; one of the two records is now wrong")
        #expect(WalkthroughFlow.Copy.connectSnippet
                != StatusSurface.Copy.connectSnippet(shimPath: "proctor-shim"),
                "the short snippet and the rendered one agree; one record is now wrong")
        #expect(WalkthroughFlow.Grant.accessibility.why
                != WalkthroughFlow.Grant.accessibility.rowDescription)
    }

    /// Whole-line comments removed, so a source guard counts code.
    ///
    /// Line-based and deliberately crude: it does not understand a trailing
    /// comment after code, which is why every guard above looks for a construct
    /// that lives at the start of its own line.
    static func withoutComments(_ source: String) -> String {
        var out = ""
        var inBlock = false
        for line in source.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if inBlock { if t.contains("*/") { inBlock = false }; continue }
            if t.hasPrefix("/*") { if !t.contains("*/") { inBlock = true }; continue }
            if t.hasPrefix("//") { continue }
            out += line + "\n"
        }
        return out
    }

    private static func walkthroughSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/ProctorUI/Walkthrough.swift"),
            encoding: .utf8)
    }
}
