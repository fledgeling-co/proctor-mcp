import Foundation
import Testing
@testable import ProctorCore

// PRO-0082, A2 and DEF-181. The correction PRO-0036 applied at the status
// window, applied to the report instead.
//
// PRO-0036 partitioned the grants list on arrival in the window, so the window
// stopped drawing the Shortcuts CLI — a program on a disk — beside Accessibility
// and Screen Recording, which are decisions macOS holds about Proctor. Every
// other reader of the same report kept drawing it. The agent no longer sends it
// (`StatusWindowDebtWiringTests` holds that half), and this file holds the other
// half: a report from an agent OLDER than PRO-0082 still carries the entry, and
// the TUI must not put it back in the permissions pane.
//
// The fixture is therefore the old agent's report and not this one's. A test
// built from a current report would pass with the partition deleted, because
// there is nothing left in the list for it to remove.

@Suite("TUI readiness — the permissions pane holds only permissions")
struct TUIReadinessPartitionTests {

    /// A doctor reply in the shape an agent from before PRO-0082 sends on a Mac
    /// that is missing `/usr/bin/shortcuts` — the only condition under which the
    /// old code appended the row at all.
    static func oldAgentReport() -> JSONValue {
        .object([
            "grants": .array([
                grant("Accessibility", "granted"),
                grant("Screen Recording", "granted"),
                grant("Automation", "unconfirmed"),
                grant("Input Monitoring", "denied"),
                grant("Shortcuts CLI", "denied")
            ]),
            "lanes": .array([
                .object(["lane": .string("mac"), "state": .string("ready")])
            ])
        ])
    }

    static func grant(_ name: String, _ state: String) -> JSONValue {
        .object(["name": .string(name), "state": .string(state)])
    }

    @Test("an older agent's Shortcuts CLI row does not reach the readiness pane")
    func theMisfiledToolIsFilteredOut() {
        let read = TUISurface.readiness(from: Self.oldAgentReport())
        let names = read.grants.map { $0.cells[0] }

        #expect(!names.contains(StatusChecks.shortcutsCLI),
                Comment(rawValue: "the pane drew \(names.joined(separator: ", "))"))
        // The other half of the same claim, and the reason this is not just a
        // filter that empties the pane: every real permission the fixture carried
        // is still there, in the report's own order, with its state intact.
        #expect(names == ["Accessibility", "Screen Recording", "Automation", "Input Monitoring"])
        #expect(read.grants.map { $0.cells[1] } == ["granted", "granted", "unconfirmed", "denied"])
        // And the pane is not reading a different report from the one that still
        // carries the row — if the fixture had lost it, this test would prove
        // nothing about the partition.
        let carried = Self.oldAgentReport()["grants"]?.arrayValue?
            .compactMap { $0["name"]?.stringValue } ?? []
        #expect(carried.contains(StatusChecks.shortcutsCLI),
                "the fixture must actually be the old agent's report")
    }

    @Test("the partition is the window's rule rather than a second opinion about which is which")
    func thePaneAndTheWindowAgreeNameByName() {
        // Both surfaces resolve through `StatusChecks.resolvedKind`, so this walks
        // every name the map knows and asserts the two spellings of the rule
        // cannot disagree. A surface holding its own list is how PRO-0036's fix
        // came to cover one reader and not the others.
        for (name, kind) in StatusChecks.known {
            let byName = StatusChecks.kindIsPermission(name)
            let byValue = !StatusChecks.permissions(
                in: [DoctorReport.Grant(name: name, state: .granted, required: false,
                                        howToFix: "…")]).isEmpty
            #expect(byName == byValue, "\(name) is a permission to one surface and a tool to the other")
            #expect(byName == (kind != .tool))

            let report = JSONValue.object(["grants": .array([Self.grant(name, "granted")])])
            let drawn = TUISurface.readiness(from: report).grants.map { $0.cells[0] }
            #expect(drawn.contains(name) == byName,
                    "\(name) reaches the readiness pane as \(drawn), which contradicts the partition")
        }
    }

    @Test("lanes are untouched by the grants partition")
    func lanesAreUnaffected() {
        // The filter sits in a loop that shares a function with the lanes loop.
        // A filter written one `guard` too high would empty both, and every
        // assertion above would still pass.
        let read = TUISurface.readiness(from: Self.oldAgentReport())
        #expect(read.lanes.map { $0.cells[0] } == ["mac"])
    }
}
