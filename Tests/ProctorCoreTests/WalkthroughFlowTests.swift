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

    // MARK: - PRO-0100, DEF-162 and DEF-163. The two records, made to agree.

    /// The design of record, read as text — the same footing every clause above
    /// stands on, and it claims nothing above it.
    private static func designSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("design/surfaces/proctor-surfaces.html"),
            encoding: .utf8)
    }

    /// The `wt-foot` of one `data-state` pane of the walkthrough surface.
    private static func footer(ofState state: String, in design: String) throws -> String {
        let pane = try #require(design.range(of: "data-state=\"\(state)\""),
                                "no walkthrough pane with data-state=\(state)")
        let rest = design[pane.upperBound...]
        let foot = try #require(rest.range(of: "<div class=\"wt-foot\">"),
                                "the \(state) pane draws no footer")
        let after = rest[foot.upperBound...]
        let end = try #require(after.range(of: "</div>\n        </div>")
                               ?? after.range(of: "</div>"),
                               "the \(state) footer never closes")
        return String(after[..<end.lowerBound])
    }

    /// DEF-162. The design gains the way out; the build is unchanged.
    ///
    /// The two records disagreed and the referral settled which one yields. The
    /// build is right: `Skip setup` postdates this design page, it is gated by
    /// `WalkthroughFlow.showsSkip` and by nothing else, and a verifier proved
    /// that removing it strands a person macOS will not grant to while the whole
    /// suite stays green. So the drawing that was never revised is the one that
    /// changed.
    ///
    /// Asserted on the pane that refuses, because that is the pane where the way
    /// out matters — and in the order the app draws it, so the two records agree
    /// on sequence and not only on presence.
    @Test("DEF-162 · the design of record draws the way out on the pane that refuses")
    func theDesignDrawsSkipOnThePermissionsPane() throws {
        let design = try Self.designSource()
        let foot = try Self.footer(ofState: "permissions", in: design)
        #expect(foot.contains(WalkthroughFlow.Copy.skip),
                "the permissions pane's footer draws no \(WalkthroughFlow.Copy.skip); the app draws one and the two records disagree")
        let back = try #require(foot.range(of: WalkthroughFlow.Copy.back))
        let skip = try #require(foot.range(of: WalkthroughFlow.Copy.skip))
        let primary = try #require(foot.range(of: WalkthroughFlow.primaryAction(for: .permissions)))
        #expect(back.lowerBound < skip.lowerBound && skip.lowerBound < primary.lowerBound,
                "the design draws Back, Skip and the primary in a different order from the app")
        // The build's own rule, asserted here too so this case fails if the two
        // are ever made to agree by changing the app instead.
        #expect(WalkthroughFlow.showsSkip(on: .permissions,
                                          accessibility: false, screenRecording: false))
    }

    /// DEF-163. The build stops drawing a refusing control as an invitation.
    ///
    /// The other direction, and a referral is what separated them: taken as one
    /// question these two would have had one wrong answer. `.borderedProminent`
    /// was applied unconditionally, so on a KEY window the refusal drew in the
    /// accent fill with only the label dimmed — an inactive window being the
    /// only state in which macOS greyed it enough to read as refusing, and not
    /// the state a person is in while working the flow. The design of record
    /// already settles the rule and the build diverged from it.
    ///
    /// Read from the view's source: `source-analysis`, and it says the drawing
    /// site is bound to the Core rule, not that a window drew a plain button.
    @Test("DEF-163 · the primary is filled only where it can be pressed")
    func thePrimaryIsProminentOnlyWhenEnabled() throws {
        let source = Self.withoutComments(try Self.walkthroughSource())

        // The unconditional form must not appear on the primary at all. Every
        // `.borderedProminent` in this file now sits inside a branch: one in
        // `PrimaryProminence`, one in `HeroPermRow`.
        #expect(!source.contains(".buttonStyle(.borderedProminent)\n                        .disabled("),
                "the primary still takes .borderedProminent unconditionally")

        let modifier = try #require(source.range(of: "private struct PrimaryProminence"),
                                    "the prominence branch does not exist")
        let row = try #require(source.range(of: "private struct HeroPermRow"),
                               "HeroPermRow moved; this case reads the span between the two")
        // Declared before HeroPermRow, or `theRowDoesNotDecideItsOwnProminence`
        // starts counting this modifier's fill as one of the row's.
        #expect(modifier.lowerBound < row.lowerBound,
                "PrimaryProminence is declared after HeroPermRow, inside the span that case measures")

        let branch = String(source[modifier.lowerBound..<row.lowerBound])
        #expect(branch.components(separatedBy: ".borderedProminent").count - 1 == 1,
                "the prominence branch draws the filled style \(branch.components(separatedBy: ".borderedProminent").count - 1) times; one is the rule")
        #expect(branch.components(separatedBy: ".buttonStyle(.bordered)").count - 1 == 1,
                "the prominence branch has no plain style, so a refusing primary is still drawn filled")
        let ifEnabled = try #require(branch.range(of: "if enabled {"))
        let filled = try #require(branch.range(of: ".borderedProminent"))
        let plain = try #require(branch.range(of: ".buttonStyle(.bordered)"))
        #expect(ifEnabled.lowerBound < filled.lowerBound && filled.lowerBound < plain.lowerBound,
                "the filled style is not the enabled branch")

        // And the branch takes the SAME rule the `.disabled` takes, so the fill
        // and the refusal can never nominate different states. This is the
        // clause that would catch a second predicate drifting from the first.
        #expect(source.contains("PrimaryProminence(\n                            enabled: WalkthroughFlow.primaryEnabled("),
                "the prominence branch does not read WalkthroughFlow.primaryEnabled")
    }

    /// The design of record and the build now agree on the refusing primary's
    /// treatment too, which is the half DEF-163 changed the app for.
    @Test("DEF-163 · the design draws the refusing primary plain, and says why")
    func theDesignDrawsTheRefusingPrimaryPlain() throws {
        let design = try Self.designSource()
        let foot = try Self.footer(ofState: "permissions", in: design)
        let primary = try #require(
            foot.range(of: "<button type=\"button\" class=\"btn\" disabled>"),
            "the design's refusing primary is no longer drawn plain-and-disabled")
        #expect(foot[primary.upperBound...].hasPrefix(WalkthroughFlow.primaryAction(for: .permissions)))
        #expect(!foot.contains("class=\"btn prominent\" disabled"),
                "the design draws a disabled control in the accent fill, which is the defect")
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
        // PRO-0082 changed this one deliberately, and it is the only string in
        // this list that has moved since PRO-0090 recorded them. It read
        // "Already allowed? Open System Settings"; the question was the
        // misdirection, and `WalkthroughSettingsLineTests` holds the clause.
        #expect(WalkthroughFlow.Copy.openSettings == "Open Settings")
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

    // MARK: - PRO-0086. The refusal says why, and the door out stays open.

    /// A1. The biconditional, at all sixteen combinations.
    ///
    /// Asked as one clause rather than two lists because the failure this item
    /// exists to remove is a refusing state with no reason, and its mirror — a
    /// reason drawn beside a button a person can press — is the same defect
    /// wearing the other face. Either one breaks this test at the state that
    /// caused it.
    @Test("DEF-160 · a reason exists exactly where the primary refuses, at all sixteen combinations")
    func aReasonExistsExactlyWhereThePrimaryRefuses() {
        var explained: [String] = []
        for step in WalkthroughFlow.Step.allCases {
            for ax in [false, true] {
                for sr in [false, true] {
                    let enabled = WalkthroughFlow.primaryEnabled(
                        on: step, accessibility: ax, screenRecording: sr)
                    let reason = WalkthroughFlow.primaryDisabledReason(
                        on: step, accessibility: ax, screenRecording: sr)
                    #expect((reason == nil) == enabled,
                            "\(step.rawValue) ax=\(ax) sr=\(sr): enabled \(enabled), reason \(String(describing: reason))")
                    if let reason {
                        #expect(!reason.isEmpty)
                        explained.append("\(step.rawValue)/\(ax)/\(sr)")
                    }
                }
            }
        }
        // The population, printed as a set. It is A3's population — the three
        // states PRO-0081 created — and every one of them now carries a sentence.
        #expect(explained.sorted() == ["permissions/false/false",
                                       "permissions/false/true",
                                       "permissions/true/false"],
                "the explained set is \(explained.sorted())")
    }

    /// A2. What the sentence says, in each of the three states, and the
    /// coherence clause: the caption and the filled Allow button nominate the
    /// same first move.
    ///
    /// WHICH ASSERTION CARRIES THE COHERENCE CLAUSE: the verbatim sentences at
    /// the foot of this test, not the `prominentGrant` agreement above them.
    /// The agreement check cannot fail — the reason names every missing grant,
    /// and `prominentGrant` returns one of the missing grants, so
    /// `reason.contains(prominent.title)` is true by construction whichever
    /// missing grant the caption nominates. A mutation taking the first move
    /// from `missing.last` instead of from `prominentGrant` passes it and is
    /// caught by the literal `"… Start with Accessibility."` alone. The
    /// agreement clause is kept as a statement of the rule; the literal is the
    /// guard.
    @Test("DEF-160 · the reason names every missing grant and agrees with the prominent one")
    func theReasonNamesTheMissingGrantAndTheNextAction() {
        typealias G = WalkthroughFlow.Grant
        for ax in [false, true] {
            for sr in [false, true] {
                guard let reason = WalkthroughFlow.primaryDisabledReason(
                    on: .permissions, accessibility: ax, screenRecording: sr) else { continue }
                let missing = G.allCases.filter { $0 == .accessibility ? !ax : !sr }
                for grant in missing {
                    #expect(reason.contains(grant.title),
                            "ax=\(ax) sr=\(sr): “\(reason)” does not name \(grant.title)")
                }
                for held in G.allCases where !missing.contains(held) {
                    #expect(!reason.contains(held.title),
                            "ax=\(ax) sr=\(sr): “\(reason)” names \(held.title), which is already granted")
                }
                // The next action names the row's own button word, so the
                // instruction points at a control that is on screen.
                #expect(reason.contains(WalkthroughFlow.Copy.allow),
                        "“\(reason)” does not name the control to press")
                let prominent = WalkthroughFlow.prominentGrant(accessibility: ax, screenRecording: sr)
                #expect(prominent != nil)
                if let prominent {
                    #expect(reason.contains(prominent.title),
                            "“\(reason)” does not nominate \(prominent.title), which is the Grant drawn prominent")
                }
            }
        }
        // The three sentences, written out, so a reword is a decision somebody
        // makes rather than a silent one.
        #expect(WalkthroughFlow.primaryDisabledReason(
            on: .permissions, accessibility: false, screenRecording: false)
                == "Allow Accessibility and Screen Recording above to continue. Start with Accessibility.")
        #expect(WalkthroughFlow.primaryDisabledReason(
            on: .permissions, accessibility: true, screenRecording: false)
                == "Allow Screen Recording above to continue.")
        #expect(WalkthroughFlow.primaryDisabledReason(
            on: .permissions, accessibility: false, screenRecording: true)
                == "Allow Accessibility above to continue.")
        // Only the both-missing state names a first move; with one grant left
        // there is nothing to order.
        #expect(!(WalkthroughFlow.primaryDisabledReason(
            on: .permissions, accessibility: true, screenRecording: false) ?? "")
                .contains(WalkthroughFlow.Copy.reasonStart))
    }

    /// A5. A grant taken away mid-flow refuses the primary again — and the
    /// person is told why and can still leave. The lockout this guards against
    /// is the refusal arriving with no caption and no exit.
    @Test("DEF-160 · a revocation refuses, explains, and does not trap")
    func aRevocationIsNotALockout() {
        // Both held: the primary is live and says nothing.
        #expect(WalkthroughFlow.primaryEnabled(on: .permissions,
                                               accessibility: true, screenRecording: true))
        #expect(WalkthroughFlow.primaryDisabledReason(on: .permissions,
                                                      accessibility: true, screenRecording: true) == nil)
        // Either grant goes away.
        for (ax, sr) in [(false, true), (true, false)] {
            #expect(!WalkthroughFlow.primaryEnabled(on: .permissions,
                                                    accessibility: ax, screenRecording: sr))
            let reason = WalkthroughFlow.primaryDisabledReason(on: .permissions,
                                                               accessibility: ax, screenRecording: sr)
            #expect(reason != nil, "ax=\(ax) sr=\(sr) refuses with no reason, which is the lockout")
            // The way out, asked at this state. `!Copy.skip.isEmpty` stood here
            // and was an instrument reading itself: a non-empty string constant
            // is false in no tree anyone could write, so it counted nothing
            // towards the clause it was listed under. `showsSkip` is the rule
            // the view's condition reads, and it is false in a tree where the
            // revocation closes the door.
            #expect(WalkthroughFlow.showsSkip(on: .permissions,
                                              accessibility: ax, screenRecording: sr),
                    "ax=\(ax) sr=\(sr) refuses the primary and draws no way out, which is the lockout")
            #expect(WalkthroughFlow.completes(.skipped))
        }
    }

    /// A6. The restart requirement, as a rule about when it is stated. The
    /// design of record draws it in the pane where the grant is missing and
    /// omits it where it is held.
    @Test("DEF-161 · the restart requirement is stated while Screen Recording is missing")
    func theRestartRequirementIsStatedWhileTheGrantIsMissing() {
        #expect(WalkthroughFlow.statesRestartNote(screenRecording: false))
        #expect(!WalkthroughFlow.statesRestartNote(screenRecording: true))
        // PRO-0067's A5 stands: the fact is true whether or not a restart is
        // offered, and it is the Screen Recording grant that carries it.
        #expect(WalkthroughFlow.Grant.screenRecording.needsRestart)
        #expect(WalkthroughFlow.Copy.restartNote.contains(WalkthroughFlow.Grant.screenRecording.title))
    }

    /// A3, A4, A6's rendered halves — read from the view's source, because there
    /// is no `ProctorUI` test target and no window server here. This is
    /// `source-analysis` and claims nothing above it: it says the drawing site
    /// is bound to the Core rule, not that a window drew the sentence. The glass
    /// lane asks that, and CASE-0316 records what it answered.
    @Test("DEF-160 · the footer draws the reason and hands it to the button")
    func theFooterDrawsTheReason() throws {
        let source = Self.withoutComments(try Self.walkthroughSource())
        #expect(source.contains("WalkthroughFlow.primaryDisabledReason("),
                "the view does not read the Core rule")
        #expect(source.contains("WalkthroughFlow.ID.reason"),
                "the caption carries no identifier, so no glass lane can find it")
        #expect(source.contains(".hint(disabledReason)"),
                "the disabled button does not carry the reason as an accessibility hint")
    }

    @Test("DEF-161 · the permissions sheet draws the restart note")
    func theSheetDrawsTheRestartNote() throws {
        let source = Self.withoutComments(try Self.walkthroughSource())
        #expect(source.contains("WalkthroughFlow.Copy.restartNote"),
                "the constant is still rendered nowhere, which is DEF-161")
        #expect(source.contains("WalkthroughFlow.statesRestartNote("),
                "the view decides for itself when to draw the note")
    }

    /// A4. The door out, read as a count rather than as a reading. One
    /// `.disabled(` in the whole file and it is the primary's: a `.disabled` on
    /// Skip, or on Back, would make the refusal a trap and would land here.
    @Test("DEF-160 · skip is drawn beside the refusal and nothing disables it")
    func skipIsNeverClosed() throws {
        let source = Self.withoutComments(try Self.walkthroughSource())
        let disables = source.components(separatedBy: ".disabled(").count - 1
        #expect(disables == 1,
                "Walkthrough.swift carries \(disables) `.disabled(` modifiers; exactly one — the primary's — is the rule, and a second could close the way out")
        let skip = try #require(source.range(of: "WalkthroughFlow.ID.skip"))
        let primary = try #require(source.range(of: "WalkthroughFlow.ID.primary)"))
        #expect(skip.lowerBound < primary.lowerBound,
                "Skip setup is drawn after the primary; the one `.disabled(` can no longer be attributed by order")
        // And the one that exists sits after Skip's declaration, so the count
        // above cannot be satisfied by a `.disabled` on Skip with the primary's
        // removed.
        let disabled = try #require(source.range(of: ".disabled(!WalkthroughFlow.primaryEnabled("))
        #expect(primary.lowerBound < disabled.lowerBound)
    }

    /// A4, the presence half — the half the count clause above cannot reach.
    ///
    /// `skipIsNeverClosed` counts `.disabled(` over the whole file, and a
    /// verifier closed the door out without adding one: wrapping the button in
    /// `if step != .connect, WalkthroughFlow.primaryEnabled(…)` removes Skip in
    /// exactly the three refusing states, and the count, the ordering and the
    /// rest of the suite all stayed green. A file-level `#require(range(of:
    /// "WalkthroughFlow.ID.skip"))` stood in for a per-state claim, and a
    /// substring in a file says nothing about a state.
    ///
    /// So the claim is asked in two halves, each of which the other cannot
    /// cover. The rule is asked at all sixteen states in Core, where a lockout
    /// written into the rule fails at the states it closes. The view's
    /// condition is then read verbatim, whitespace collapsed, and must be that
    /// rule and nothing else — a second clause on this `if` is how the door
    /// closes with no `.disabled` anywhere, and it lands here.
    @Test("DEF-160 · the way out is drawn in every refusing state, and its condition reads one rule")
    func skipIsOfferedInEveryRefusingState() throws {
        var offered: [String] = []
        for step in WalkthroughFlow.Step.allCases {
            for ax in [false, true] {
                for sr in [false, true] {
                    let shows = WalkthroughFlow.showsSkip(
                        on: step, accessibility: ax, screenRecording: sr)
                    #expect(shows == (step != .connect),
                            "\(step.rawValue) ax=\(ax) sr=\(sr): showsSkip \(shows)")
                    if shows { offered.append("\(step.rawValue)/\(ax)/\(sr)") }
                }
            }
        }
        // A3's population, named state by state rather than counted. These are
        // the three the design of record draws with the primary disabled, and
        // they are the three a lockout removes.
        for refusing in ["permissions/false/false",
                         "permissions/false/true",
                         "permissions/true/false"] {
            #expect(offered.contains(refusing),
                    "\(refusing) refuses the primary and offers no way out; the offered set is \(offered.sorted())")
        }

        // And the view asks that rule, with nothing else on the condition.
        let source = Self.withoutComments(try Self.walkthroughSource())
        let button = try #require(source.range(of: "Button(WalkthroughFlow.Copy.skip)"))
        let head = String(source[..<button.lowerBound])
        let start = try #require(head.range(of: "if ", options: .backwards))
        let condition = String(head[start.lowerBound...])
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        #expect(condition == "if WalkthroughFlow.showsSkip(on: step.flow, accessibility: granted(.accessibility), screenRecording: granted(.screenRecording)) {",
                "Skip setup is drawn under “\(condition)”; A4 requires the Core rule and no second clause, because a clause here closes the way out in the states that need it")
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
