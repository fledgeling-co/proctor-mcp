import Testing
@testable import ProctorCore

@Suite("Every control on the status window can be told from its neighbours")
struct AccessibilityNameTests {

    // Measured on the shipped window before this existed: nine AXCheckBox
    // elements with no name at all, and seven AXButton elements every one of
    // which was called "Details". The property below is the one that was
    // missing, and it is held over the real catalogue rather than an example, so
    // adding a tenth switch or an eighth tool cannot quietly reintroduce it.

    @Test("no switch toggle is nameless, and no two share a name")
    func switchTogglesAreDistinct() {
        let names = SwitchCatalogue.all.map { AccessibilityNames.switchToggle(title: $0.title) }
        #expect(names.count == SwitchCatalogue.all.count)
        #expect(AccessibilityNames.allDistinct(names), "\(names)")
    }

    @Test("a tool's disclosure names its tool, so seven of them are seven names")
    func toolDisclosuresAreDistinct() {
        let tools = ["obscura", "simctl", "cua-driver", "maestro", "lume", "prlctl", "Shortcuts CLI"]
        let collapsed = tools.map { AccessibilityNames.toolDisclosure(tool: $0, expanded: false) }
        #expect(AccessibilityNames.allDistinct(collapsed), "\(collapsed)")
        for (tool, name) in zip(tools, collapsed) {
            #expect(name.contains(tool))
        }
        // Expanded and collapsed differ, so the control says what pressing it does.
        let expanded = tools.map { AccessibilityNames.toolDisclosure(tool: $0, expanded: true) }
        #expect(AccessibilityNames.allDistinct(expanded))
        #expect(zip(collapsed, expanded).allSatisfy { $0 != $1 })
    }

    @Test("the repeated permission controls name their permission")
    func grantActionsAreDistinct() {
        let grants = [StatusChecks.accessibility, StatusChecks.screenRecording, StatusChecks.automation]
        var names: [String] = []
        for grant in grants {
            names.append(AccessibilityNames.grantAction(.openSettings, grant: grant))
            names.append(AccessibilityNames.grantAction(.how, grant: grant))
        }
        #expect(AccessibilityNames.allDistinct(names), "\(names)")
        #expect(names.allSatisfy { name in grants.contains { name.contains($0) } })
    }

    @Test("the whole surface's controls are distinct together, not just within a kind")
    func wholeSurfaceIsDistinct() {
        // A switch called the same thing as a tool disclosure would be two
        // controls with one name, and checking each list on its own would miss it.
        var names = SwitchCatalogue.all.map { AccessibilityNames.switchToggle(title: $0.title) }
        names += ["obscura", "simctl", "maestro"].map {
            AccessibilityNames.toolDisclosure(tool: $0, expanded: false)
        }
        names += [StatusChecks.accessibility, StatusChecks.screenRecording].map {
            AccessibilityNames.grantAction(.openSettings, grant: $0)
        }
        #expect(AccessibilityNames.allDistinct(names), "\(names)")
    }

    @Test("an empty name is refused, which is the defect this replaces")
    func emptyIsNotAName() {
        #expect(!AccessibilityNames.allDistinct(["Run panel", "", "Drawn pointer"]))
        #expect(!AccessibilityNames.allDistinct(["Details", "Details"]))
    }
}
