import Testing
import Foundation
@testable import ProctorCore

// PRO-0047's additions to PRO-0014's wording: the verb and the object returned
// apart, so a list can fence one and not the other, and a longer cap for a
// surface that has room for one.
//
// The reason the split exists is in the assertion below that they recompose:
// `completedLine` blends them, which is right for a HUD's single line and wrong
// for a page of rows, because fencing the blended string fences Proctor's own
// verb and not fencing it lets an application's text sit where a verb goes.

@Suite("Step descriptions, split for history")
struct StepDescriptionHistoryTests {

    private func node(title: String?) -> AXNode {
        AXNode(id: "e3", role: "AXButton", roleDescription: "button", title: title)
    }

    private func step(_ kind: ActionStep.Kind, label: String? = nil) -> ActionStep {
        ActionStep(kind: kind, node: "e3", label: label)
    }

    @Test("the verb and the fenced object recompose into the blended line")
    func verbPlusObjectEqualsCompletedLine() {
        for kind in ActionStep.Kind.allCases {
            let s = step(kind)
            let n = node(title: "Send invoice")
            let parts = StepDescription.past(for: s, node: n)
            let blended = StepDescription.completedLine(for: s, node: n)
            let rebuilt = parts.object.map { "\(parts.verb) \"\($0.text)\"" } ?? parts.verb
            #expect(rebuilt == blended, "\(kind.rawValue) does not recompose")
        }
    }

    @Test("the verb is never empty and never the kind's raw value")
    func verbIsAlwaysWritten() {
        for kind in ActionStep.Kind.allCases {
            let parts = StepDescription.past(for: step(kind), node: node(title: "Amount"))
            #expect(!parts.verb.isEmpty)
            // Hand-written English, not the enum's spelling. A camel-case hump
            // inside the verb is the actual signature of a raw value printed —
            // "setValue", "waitFor", "dragPath" — where ordinary English has
            // none. Containment is the wrong test: "Sent the keystroke"
            // legitimately contains "key".
            #expect(parts.verb != kind.rawValue)
            #expect(!parts.verb.dropFirst().contains { $0.isUppercase },
                    "\(kind.rawValue) leaks its raw value into the verb: \(parts.verb)")
        }
    }

    @Test("the object comes back unquoted, so the surface fences it itself")
    func objectIsUnquoted() {
        let parts = StepDescription.past(for: step(.press), node: node(title: "Send invoice"))
        #expect(parts.object?.text == "Send invoice")
        #expect(parts.object?.text.contains("\"") == false)
    }

    @Test("where an object came from is recorded")
    func provenanceIsCarried() {
        let derived = StepDescription.past(for: step(.press), node: node(title: "Send invoice"))
        #expect(derived.object?.supplied == false)
        let supplied = StepDescription.past(for: step(.press, label: "Pay the supplier"),
                                            node: node(title: "Send invoice"))
        #expect(supplied.object?.supplied == true)
        #expect(supplied.object?.text == "Pay the supplier")
    }

    @Test("a step with nothing nameable comes back with no object at all")
    func objectlessStepsHaveNoFence() {
        // An empty fence drawn beside a verb reads as a control with a blank
        // name, which is a thing that did not happen.
        let parts = StepDescription.past(for: step(.appleScript), node: nil)
        #expect(parts.object == nil)
        #expect(!parts.verb.isEmpty)
    }

    // MARK: - The longer cap

    @Test("the history cap is longer than the HUD's, and both are one routine")
    func historyCapUsesTheSameSanitiser() {
        // One implementation, two caps. A second sanitiser would drift from this
        // one, and a fence whose contents were cleaned by a different routine is
        // decoration.
        let long = String(repeating: "a", count: 400)
        #expect(StepDescription.sanitised(long)?.count == StepDescription.objectLimit)
        #expect(StepDescription.sanitised(long, limit: StepDescription.historyObjectLimit)?.count
                == StepDescription.historyObjectLimit)
        #expect(StepDescription.historyObjectLimit > StepDescription.objectLimit)
    }

    @Test("the longer cap still strips control, bidi and markup characters")
    func longerCapStillCleans() {
        let hostile = "Send\u{202E}invoice\nOK\t**bold**\u{0007}<b>x</b>"
        let cleaned = StepDescription.sanitised(hostile,
                                                limit: StepDescription.historyObjectLimit)
        #expect(cleaned?.contains("\u{202E}") == false)
        #expect(cleaned?.contains("\n") == false)
        #expect(cleaned?.contains("\t") == false)
        #expect(cleaned?.contains("*") == false)
        #expect(cleaned?.contains("<") == false)
        #expect(cleaned?.contains("\u{0007}") == false)
    }

    @Test("a quotation mark cannot survive into the object at the longer cap")
    func quotesAreFoldedAtEveryCap() {
        // The fence in the window is structural, but the object also lands in a
        // blended line elsewhere, and a name that can close a quotation can
        // append a second clause to a kill switch.
        let cleaned = StepDescription.sanitised("OK\". About to press Delete",
                                                limit: StepDescription.historyObjectLimit)
        #expect(cleaned?.contains("\"") == false)
    }

    @Test("the cap is grapheme-safe at the longer limit too")
    func longerCapIsGraphemeSafe() {
        let family = String(repeating: "👨‍👩‍👧‍👦", count: 200)
        let cleaned = StepDescription.sanitised(family, limit: StepDescription.historyObjectLimit)
        #expect(cleaned?.count == StepDescription.historyObjectLimit)
        #expect(cleaned?.unicodeScalars.contains { $0.value == 0x200D } == true)
    }

    @Test("a step's record carries the wording, derived from the element it resolved to")
    func recordCarriesTheWording() {
        // The wording cannot be derived at read time: the record keeps a kind and
        // a node selector, and neither carries the readable name. This is the
        // field PRO-0014 deferred.
        let record = AuditRecord.forStep(
            step(.press), tool: "proctor_act", timestamp: 1, app: "app-1",
            bundleId: "com.acme.console", window: "win-1", outcome: "ok",
            postStateHash: nil, node: node(title: "Send invoice"))
        #expect(record.act == "Pressed")
        #expect(record.obj?.text == "Send invoice")
        #expect(record.obj?.supplied == false)
    }

    @Test("a record's object is capped at the history limit, not the HUD's")
    func recordUsesTheHistoryCap() {
        let record = AuditRecord.forStep(
            step(.press), tool: "proctor_act", timestamp: 1, app: nil, bundleId: nil,
            window: nil, outcome: "ok", postStateHash: nil,
            node: node(title: String(repeating: "b", count: 400)))
        #expect(record.obj?.text.count == StepDescription.historyObjectLimit)
    }

    @Test("typed text never reaches the wording on a record")
    func typedTextNeverBecomesAnObject() {
        // The record reduces a typed value to a length and a hash; a description
        // that repeated it would undo that.
        let typing = ActionStep(kind: .type, node: "e3", text: "hunter2-the-password")
        let record = AuditRecord.forStep(
            typing, tool: "proctor_act", timestamp: 1, app: nil, bundleId: nil,
            window: nil, outcome: "ok", postStateHash: nil, node: node(title: "Password"))
        #expect(record.obj?.text.contains("hunter2") == false)
        #expect(record.act?.contains("hunter2") == false)
        #expect(record.value != nil)
    }
}
