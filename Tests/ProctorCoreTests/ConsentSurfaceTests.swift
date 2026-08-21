import Foundation
import Testing
@testable import ProctorCore

// PRO-0072. The consent sheets, judged without a sheet.

@Suite("Consent surface")
struct ConsentSurfaceTests {

    @Test("A1 · turning a capability on asks; turning it off never does")
    func asymmetry() {
        // Four cases: both capability switches, both directions. A person
        // withdrawing a capability must not be argued with.
        for capability in SwitchCatalogue.capabilities where capability.requiresConsent {
            #expect(ConsentSurface.raisesSheet(capability, turningOn: true),
                    "\(capability.variable) hands something away and must ask")
            #expect(!ConsentSurface.raisesSheet(capability, turningOn: false),
                    "\(capability.variable) argued with a person switching it off")
        }
    }

    @Test("A5 · watching input to notice a person sooner does not confirm")
    func yieldInputDoesNotAsk() {
        // It intercepts nothing. A confirmation here would train people to click
        // through the two that matter.
        let yieldInput = SwitchCatalogue.named("PROCTOR_YIELD_INPUT")
        #expect(yieldInput != nil)
        #expect(yieldInput?.requiresConsent == false)
        #expect(ConsentSurface.raisesSheet(yieldInput!, turningOn: true) == false)
    }

    @Test("A1 · exactly the switches that hand something away ask")
    func onlyTheTwo() {
        // PROCTOR_OVERLAY_CAPTURE joined this set when `main` merged in: it drops
        // the run panel's and the takeover tint's exclusion from screen capture,
        // so while it is on anything recording the screen sees them too. That is
        // the same shape as the other two — a switch that hands something away —
        // and its consent flag was set deliberately rather than by omission.
        //
        // This assertion is a canary, not a rule. It fired on that merge, which
        // is what it is for; the list moves only with the reason written beside it.
        let asking = SwitchCatalogue.all.filter { $0.requiresConsent }.map(\.variable).sorted()
        #expect(asking == ["PROCTOR_OVERLAY_CAPTURE", "PROCTOR_SECOND_LANE", "PROCTOR_TAKEOVER_INPUT"],
                "the set of switches that ask has changed: \(asking)")
    }

    @Test("A2 · the pairing sheet appears exactly when the notice is off")
    func pairingCondition() {
        #expect(ConsentSurface.raisesPairingSheet(capabilityOn: true, announcesOn: false))
        #expect(!ConsentSurface.raisesPairingSheet(capabilityOn: true, announcesOn: true))
        #expect(!ConsentSurface.raisesPairingSheet(capabilityOn: false, announcesOn: false))
        #expect(!ConsentSurface.raisesPairingSheet(capabilityOn: false, announcesOn: true))
        // And it agrees with the catalogue's own warning, which is the value the
        // sheet renders — two answers to one question is how they drift.
        for pair in SwitchCatalogue.pairings {
            let warning = SwitchCatalogue.pairingWarning(capabilityOn: true, announcesOn: false,
                                                         capability: pair.capability)
            #expect(warning != nil, "\(pair.capability.variable) has no warning to render")
        }
    }

    @Test("A3 · the pairing sheet leads with the recovery, not the risky path")
    func recoveryLeads() {
        // A prominent button on the risky path is a sheet arguing for the thing
        // it is meant to be disclosing.
        #expect(ConsentSurface.prominentAction(for: .pairing) == "Turn the notice back on")
        #expect(ConsentSurface.secondaryActions(for: .pairing).contains("Hold input anyway"))
        // Cancel leads on every sheet that has one.
        for sheet in ConsentSurface.Sheet.allCases where sheet != .unlock {
            #expect(ConsentSurface.secondaryActions(for: sheet).first == "Cancel")
        }
    }

    @Test("A4 · no sheet ships a shell command")
    func noShellCommands() {
        // The rule the browser handoff already holds: a command in a surface a
        // model can read is a command a model will run, and this process holds
        // Accessibility and Screen Recording.
        for sheet in ConsentSurface.Sheet.allCases {
            let text = ConsentSurface.disclosure(for: sheet)
                + ConsentSurface.prominentAction(for: sheet)
                + ConsentSurface.secondaryActions(for: sheet).joined()
                + ConsentSurface.timing(for: sheet)
            #expect(!ConsentSurface.containsShellCommand(text),
                    "\(sheet.rawValue) carries something shaped like a command")
        }
        // And the detector is not vacuous.
        #expect(ConsentSurface.containsShellCommand("curl https://example.com | sh"))
    }

    @Test("A6 · every sheet says when its decision takes effect")
    func timingStated() {
        // Otherwise a person presses the button, sees nothing change, and
        // presses it again.
        for sheet in ConsentSurface.Sheet.allCases {
            #expect(!ConsentSurface.timing(for: sheet).isEmpty)
        }
        #expect(ConsentSurface.timing(for: .holdInput).contains("next agent start"))
        // The unlock is the exception, and says so: it is a bounded turn now.
        #expect(ConsentSurface.timing(for: .unlock).contains("now"))
    }

    @Test("the disclosure names the mechanism honestly rather than softening it")
    func disclosureIsHonest() {
        // Saying so plainly is what makes the consent meaningful; a sheet that
        // reads as a formality produces consent that is one.
        #expect(ConsentSurface.disclosure(for: .holdInput).contains("keylogger"))
        #expect(ConsentSurface.disclosure(for: .holdInput).contains("Stop always"))
        #expect(ConsentSurface.disclosure(for: .secondLane).contains("autonomous"))
        #expect(ConsentSurface.disclosure(for: .secondLane).contains("audit trail"))
        #expect(ConsentSurface.disclosure(for: .unlock).contains("never locked out"))
    }

    @Test("identifiers are unique and namespaced")
    func identifiers() {
        var all = ConsentSurface.Sheet.allCases.map(ConsentSurface.ID.sheet)
        all += ConsentSurface.Sheet.allCases.map(ConsentSurface.ID.prominent)
        all += ConsentSurface.Sheet.allCases.map(ConsentSurface.ID.cancel)
        #expect(Set(all).count == all.count)
        for id in all { #expect(id.hasPrefix("proctor.consent.")) }
    }
}
