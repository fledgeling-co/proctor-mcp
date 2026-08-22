import Testing
import Foundation
@testable import ProctorCore

// PRO-0014. The line a person reads on a kill switch, derived from the step and
// the element it resolved to. What a wrong answer costs: a verb the supervised
// client chose, a typed password reprinted beside its own redaction, or a blank
// where the action should be.

private func step(_ kind: ActionStep.Kind, node: String? = "n1", label: String? = nil,
                  text: String? = nil, value: JSONValue? = nil,
                  menuPath: [String]? = nil, key: String? = nil,
                  modifiers: [String]? = nil) -> ActionStep {
    ActionStep(kind: kind, node: node, value: value, menuPath: menuPath, text: text,
               key: key, modifiers: modifiers, label: label)
}

private func el(_ id: String = "n1", role: String = "AXButton", subrole: String? = nil,
                roleDescription: String? = nil, title: String? = nil,
                label: String? = nil, identifier: String? = nil) -> AXNode {
    AXNode(id: id, role: role, subrole: subrole, roleDescription: roleDescription,
           title: title, label: label, identifier: identifier)
}

@Suite("Step descriptions")
struct StepDescriptionTests {

    // MARK: - Every kind, both timings

    @Test("every kind produces a present-tense line naming the element, with no caller input")
    func everyKindPresent() throws {
        let button = el(title: "Send invoice")
        for kind in ActionStep.Kind.allCases {
            let line = StepDescription.line(for: step(kind), node: button, timing: .present)
            #expect(!line.isEmpty, "\(kind) produced an empty line")
            // PRO-0100, DEF-140. The #expect above records and returns; only a
            // require stops before the unwrap.
            let lead = try #require(line.first, "\(kind) produced an empty line")
            #expect(lead.isUppercase, "\(kind) is not sentence case: \(line)")
            #expect(!line.hasSuffix(" "), "\(kind) left a dangling space: \(line)")
            // appleScript and dragPath name no element by design; everything else does.
            if kind != .appleScript && kind != .dragPath && kind != .key {
                #expect(line.contains("Send invoice"), "\(kind) lost the object: \(line)")
            }
        }
    }

    @Test("every kind produces a prospective line, distinct from the present one")
    func everyKindProspective() {
        let button = el(title: "Send invoice")
        for kind in ActionStep.Kind.allCases {
            let s = step(kind)
            let now = StepDescription.line(for: s, node: button, timing: .present)
            let soon = StepDescription.line(for: s, node: button, timing: .prospective)
            #expect(soon.hasPrefix("About to "), "\(kind) has no prospective form: \(soon)")
            #expect(soon != now, "\(kind) does not distinguish timing")
        }
    }

    @Test("no line is rendered by printing a kind's internal name")
    func neverPrintsRawValue() {
        // The failure this guards is "About to setValue" and "Menuing File" —
        // wording produced by printing the enum instead of writing English. Where
        // a kind's raw value happens to be the English verb ("press", "close"),
        // its appearance is the wording being correct, not the enum leaking; the
        // camelCase kinds are the ones that can only come from the enum.
        let button = el(title: "Send invoice")
        let machineNames = ["setValue", "dragPath", "appleScript", "waitFor"]
        for kind in ActionStep.Kind.allCases {
            for timing in [StepDescription.Timing.present, .prospective] {
                let line = StepDescription.line(for: step(kind), node: button, timing: timing)
                for machine in machineNames {
                    #expect(!line.contains(machine), "\(kind) rendered an enum name: \(line)")
                }
            }
            let bare = StepDescription.line(for: step(kind, node: nil), node: nil,
                                            timing: .prospective)
            for machine in machineNames {
                #expect(!bare.contains(machine), "\(kind) rendered an enum name: \(bare)")
            }
        }
    }

    @Test("the wording reads as English, hand-written per kind")
    func handWrittenWording() {
        let button = el(title: "Send invoice")
        #expect(StepDescription.line(for: step(.press), node: button, timing: .present)
                == "Pressing \"Send invoice\"")
        #expect(StepDescription.line(for: step(.press), node: button, timing: .prospective)
                == "About to press \"Send invoice\"")
        #expect(StepDescription.line(for: step(.setValue), node: button, timing: .prospective)
                == "About to set \"Send invoice\"")
        #expect(StepDescription.line(for: step(.hover), node: button, timing: .present)
                == "Hovering over \"Send invoice\"")
        // British spelling.
        #expect(StepDescription.line(for: step(.cancel), node: button, timing: .present)
                == "Cancelling \"Send invoice\"")
    }

    @Test("waiting reads as waiting for the thing, not as acting on it")
    func waitingReadsAsWaitingFor() {
        let field = el(title: "Results")
        #expect(StepDescription.line(for: step(.waitFor), node: field, timing: .present)
                == "Waiting for \"Results\"")
        #expect(StepDescription.line(for: step(.waitFor, node: nil), node: nil, timing: .present)
                == "Waiting")
    }

    // MARK: - The caller's override

    @Test("a supplied label replaces the object, never the verb or the timing word")
    func labelReplacesObjectOnly() {
        let button = el(title: "Send invoice")
        let s = step(.press, label: "Pay the supplier")
        #expect(StepDescription.line(for: s, node: button, timing: .present)
                == "Pressing \"Pay the supplier\"")
        #expect(StepDescription.line(for: s, node: button, timing: .prospective)
                == "About to press \"Pay the supplier\"")
    }

    @Test("every object is fenced in quotes, supplied or derived")
    func everyObjectIsFenced() {
        let button = el(title: "Send invoice")
        // The same rendered line either way: an app's own title carries a
        // clause-injection payload exactly as a caller's label does, so the fence
        // cannot be reserved for the half that arrived over the wire.
        #expect(StepDescription.line(for: step(.press, label: "Send invoice"),
                                     node: button, timing: .present)
                == "Pressing \"Send invoice\"")
        #expect(StepDescription.line(for: step(.press), node: button, timing: .present)
                == "Pressing \"Send invoice\"")
        // Provenance still recorded underneath, for a renderer that can fence with
        // its own text run rather than with punctuation.
        #expect(StepDescription.object(for: step(.press, label: "Send invoice"), node: button)
                == .supplied("Send invoice"))
        #expect(StepDescription.object(for: step(.press), node: button)
                == .derived("Send invoice"))
    }

    @Test("a derived name cannot close the quotation and append a clause either")
    func derivedCannotEscapeTheQuotation() {
        // The app under test is not automatically trustworthy: a hostile or merely
        // careless accessibility title gets the same treatment as a caller's label.
        let hostile = el(title: "OK\" is safe. About to press \"Delete")
        let line = StepDescription.line(for: step(.press), node: hostile, timing: .prospective)
        #expect(line.hasPrefix("About to press \""))
        #expect(line.hasSuffix("\""))
        #expect(line.filter { $0 == "\"" }.count == 2, "\(line)")
    }

    @Test("a supplied name cannot close the quotation and append a clause")
    func cannotEscapeTheQuotation() {
        let s = step(.press, label: "OK\" is safe. About to press \"Delete")
        let line = StepDescription.line(for: s, node: el(title: "OK"), timing: .prospective)
        #expect(line.hasPrefix("About to press \""))
        #expect(line.hasSuffix("\""))
        // Exactly two quote characters: the pair the line put there.
        #expect(line.filter { $0 == "\"" }.count == 2, "\(line)")
    }

    @Test("a 400-character label is cut to the cap, on one line, with no ellipsis")
    func longLabelIsCapped() {
        let s = step(.press, label: String(repeating: "a", count: 400))
        let line = StepDescription.line(for: s, node: el(title: "OK"), timing: .present)
        guard let object = StepDescription.object(for: s, node: nil) else {
            Issue.record("no object"); return
        }
        #expect(object.text.count == StepDescription.objectLimit)
        #expect(!line.contains("…") && !line.contains("..."))
        #expect(!line.contains("\n"))
    }

    @Test("newlines, tabs and control characters collapse to one line")
    func labelIsFlattened() {
        // A bell and a right-to-left override are removed outright; a newline and
        // a tab become the single space that keeps two words apart.
        let s = step(.press, label: "Send\n\tinvoice \u{0007}\u{202E}now")
        let object = StepDescription.object(for: s, node: nil)
        #expect(object?.text == "Send invoice now")
    }

    @Test("markup does not survive")
    func markupStripped() {
        #expect(StepDescription.sanitised("<b>Send</b> **now** `x` _y_") == "b Send /b now x y")
        #expect(StepDescription.sanitised("<img src=x onerror=alert(1)>")
                == "img src=x onerror=alert(1)")
    }

    @Test("angle brackets go but the name between them stays")
    func legitimateNamesSurvive() {
        #expect(StepDescription.sanitised("<Untitled>") == "Untitled")
        #expect(StepDescription.sanitised("Build <123>") == "Build 123")
        // A stripped bracket is a word break, so a comparison does not silently
        // become a different number.
        #expect(StepDescription.sanitised("5<10") == "5 10")
    }

    @Test("carried text is treated as the client's, not as Proctor's own reading")
    func carriedTextIsQualified() {
        // menuPath, key/modifiers and a shortcut name all arrive in the tool call.
        // Quoting them keeps the unquoted half of the line the half Proctor
        // vouches for.
        #expect(StepDescription.object(for: step(.menu, menuPath: ["File", "Save"]), node: nil)
                == .supplied("Save"))
        #expect(StepDescription.object(for: step(.key, key: "n", modifiers: ["cmd"]), node: nil)
                == .supplied("cmd+n"))
        #expect(StepDescription.object(for: step(.shortcut, text: "Standup"), node: nil)
                == .supplied("Standup"))
        // An element's own accessibility name is derived, and stays unquoted.
        #expect(StepDescription.object(for: step(.press), node: el(title: "OK"))
                == .derived("OK"))
    }

    @Test("an empty carried field falls through instead of blocking the next one")
    func emptyCarriedFieldFallsThrough() {
        let s = step(.shortcut, node: nil, text: "", value: .string("Daily standup"))
        #expect(StepDescription.object(for: s, node: nil)?.text == "Daily standup")
    }

    @Test("a pathological title costs bounded work and still yields the cap")
    func hugeTitleIsBounded() {
        let huge = String(repeating: "x", count: 2_000_000)
        #expect(StepDescription.sanitised(huge)?.count == StepDescription.objectLimit)
    }

    @Test("a label that cleans down to nothing falls back to the derived object")
    func emptyLabelFallsBack() {
        let s = step(.press, label: "  <>**``__  \n ")
        #expect(StepDescription.line(for: s, node: el(title: "Send invoice"), timing: .present)
                == "Pressing \"Send invoice\"")
    }

    @Test("truncation does not split a grapheme cluster")
    func truncationIsGraphemeSafe() {
        // A family emoji is one Character built from many scalars; cutting inside
        // it would emit a different, wrong glyph.
        let raw = String(repeating: "👨‍👩‍👧‍👦", count: 60)
        guard let cut = StepDescription.sanitised(raw) else { Issue.record("nil"); return }
        #expect(cut.count == StepDescription.objectLimit)
        #expect(cut.allSatisfy { $0 == "👨‍👩‍👧‍👦" })
    }

    // MARK: - Cleaning runs on derived names too

    @Test("a long, multi-line element title is capped and flattened as well")
    func derivedNamesAreCleanedToo() {
        let noisy = el(title: "Send\n" + String(repeating: "x", count: 400))
        let line = StepDescription.line(for: step(.press), node: noisy, timing: .present)
        #expect(!line.contains("\n"))
        // "Pressing " plus the capped object plus its two fence characters.
        #expect(line.count == "Pressing ".count + StepDescription.objectLimit + 2)
        #expect(line.filter { $0 == "\"" }.count == 2)
    }

    @Test("markup in an app's own accessibility title is stripped too")
    func derivedMarkupStripped() {
        let noisy = el(title: "<b>Send</b>")
        #expect(StepDescription.line(for: step(.press), node: noisy, timing: .present)
                == "Pressing \"b Send /b\"")
    }

    // MARK: - The fallback chain

    @Test("the object falls back title, then description, then identifier")
    func nameOrder() {
        #expect(StepDescription.object(for: step(.press),
                                       node: el(title: "T", label: "D", identifier: "I"))?.text == "T")
        #expect(StepDescription.object(for: step(.press),
                                       node: el(label: "D", identifier: "I"))?.text == "D")
        #expect(StepDescription.object(for: step(.press),
                                       node: el(identifier: "I"))?.text == "I")
    }

    @Test("then role description, then subrole, then role")
    func kindOrder() {
        #expect(StepDescription.object(for: step(.press),
                                       node: el(role: "AXButton", subrole: "AXCloseButton",
                                                roleDescription: "close button"))?.text
                == "close button")
        #expect(StepDescription.object(for: step(.press),
                                       node: el(role: "AXButton", subrole: "AXCloseButton"))?.text
                == "AXCloseButton")
        #expect(StepDescription.object(for: step(.press), node: el(role: "AXButton"))?.text
                == "AXButton")
    }

    @Test("an element with no name at all still yields its id, so the line is never empty")
    func idIsTheFloor() {
        let anonymous = AXNode(id: "node-42", role: "")
        #expect(StepDescription.line(for: step(.press), node: anonymous, timing: .present)
                == "Pressing \"node-42\"")
    }

    // MARK: - Redacted fields never reach the line

    @Test("typed text, script bodies and set values never appear")
    func redactedFieldsNeverPrinted() {
        let secret = "hunter2-correct-horse"
        let field = el(title: "Password")

        let typing = step(.type, text: secret)
        #expect(StepDescription.line(for: typing, node: field, timing: .present)
                == "Typing into \"Password\"")

        let setting = step(.setValue, value: .string(secret))
        #expect(!StepDescription.line(for: setting, node: field, timing: .present)
                .contains(secret))

        let script = step(.appleScript, node: nil, text: "tell app \"Keychain\" to \(secret)")
        #expect(StepDescription.line(for: script, node: nil, timing: .present)
                == "Running a script")
    }

    @Test("a script names nothing derived, even when a node resolved")
    func scriptTakesNoDerivedObject() {
        #expect(StepDescription.line(for: step(.appleScript), node: el(title: "Editor"),
                                     timing: .prospective) == "About to run a script")
        // A caller may still name its own script for display.
        #expect(StepDescription.line(for: step(.appleScript, label: "Export to PDF"),
                                     node: nil, timing: .present)
                == "Running the script \"Export to PDF\"")
    }

    // MARK: - Steps whose object is not the element they act through

    @Test("a menu step names its last path component")
    func menuNamesLastComponent() {
        let s = step(.menu, node: nil, menuPath: ["File", "Export", "As PDF…"])
        #expect(StepDescription.line(for: s, node: nil, timing: .present)
                == "Choosing \"As PDF…\"")
    }

    @Test("a keystroke names the keystroke, not the field it lands in")
    func keyNamesTheKeystroke() {
        let s = step(.key, key: "n", modifiers: ["cmd", "shift"])
        #expect(StepDescription.line(for: s, node: el(title: "Search field"), timing: .present)
                == "Sending the keystroke \"cmd+shift+n\"")
    }

    @Test("a shortcut names the shortcut the actuator will run")
    func shortcutNamesTheShortcut() {
        let s = step(.shortcut, node: nil, text: "Daily standup")
        #expect(StepDescription.line(for: s, node: nil, timing: .prospective)
                == "About to run the shortcut \"Daily standup\"")
        // The actuator falls back to `value` when `text` is absent; so does this.
        let byValue = step(.shortcut, node: nil, value: .string("Daily standup"))
        #expect(StepDescription.object(for: byValue, node: nil)?.text == "Daily standup")
    }

    @Test("carried text wins over the element for those three kinds")
    func carriedTextPrecedesTheElement() {
        let field = el(title: "Search field")
        let menu = step(.menu, menuPath: ["File", "Save"])
        #expect(StepDescription.line(for: menu, node: field, timing: .present)
                == "Choosing \"Save\"")
        let shortcut = step(.shortcut, text: "Daily standup")
        #expect(StepDescription.line(for: shortcut, node: field, timing: .present)
                == "Running the shortcut \"Daily standup\"")
    }

    // MARK: - Nothing nameable

    @Test("a step with nothing nameable reads as the action alone, with no dangling preposition")
    func objectlessFormsAreClean() {
        let cases: [(ActionStep.Kind, String)] = [
            (.waitFor, "Waiting"),
            (.dragPath, "Dragging"),
            (.appleScript, "Running a script"),
            (.type, "Typing"),
            (.hover, "Hovering"),
            (.key, "Sending a keystroke"),
            (.menu, "Choosing a menu item"),
            (.shortcut, "Running a shortcut"),
        ]
        for (kind, expected) in cases {
            let line = StepDescription.line(for: step(kind, node: nil), node: nil, timing: .present)
            #expect(line == expected, "\(kind) read as \(line)")
            #expect(!line.hasSuffix(" into") && !line.hasSuffix(" over")
                    && !line.hasSuffix(" for") && !line.hasSuffix(" the"),
                    "\(kind) left a dangling preposition: \(line)")
        }
    }

    @Test("a freehand drag names a titled element but never a bare container")
    func dragPathStopsAtTheName() {
        #expect(StepDescription.line(for: step(.dragPath), node: el(title: "Canvas"),
                                     timing: .present) == "Dragging \"Canvas\"")
        #expect(StepDescription.line(for: step(.dragPath), node: el(role: "AXGroup"),
                                     timing: .present) == "Dragging")
    }

    // MARK: - Outcomes

    @Test("a refusal names the action as a thing plus what happened")
    func refusalWording() {
        #expect(StepDescription.line(for: step(.hover, node: nil), node: nil, outcome: .refused)
                == "Hover refused")
        #expect(StepDescription.line(for: step(.press), node: el(title: "Send invoice"),
                                     outcome: .refused) == "Press \"Send invoice\" refused")
    }

    @Test("a failure takes the same shape, and the object is kept where there is one")
    func failureWording() {
        #expect(StepDescription.line(for: step(.confirm), node: el(title: "Delete"),
                                     outcome: .failed) == "Confirm \"Delete\" failed")
        #expect(StepDescription.line(for: step(.appleScript, node: nil), node: nil,
                                     outcome: .failed) == "Script failed")
    }

    @Test("every kind has an outcome line, in both outcomes, that never prints its raw value")
    func everyKindHasOutcomes() throws {
        let button = el(title: "Send invoice")
        for kind in ActionStep.Kind.allCases {
            for outcome in [StepDescription.Outcome.refused, .failed] {
                let line = StepDescription.line(for: step(kind), node: button, outcome: outcome)
                #expect(line.hasSuffix(outcome.rawValue), "\(kind): \(line)")
                #expect(line != "\(kind.rawValue) Send invoice \(outcome.rawValue)",
                        "\(kind) rendered an enum name: \(line)")
                let lead = try #require(line.first, "\(kind) produced an empty line")
                #expect(lead.isUppercase, "\(kind) is not sentence case: \(line)")
            }
        }
    }
}
