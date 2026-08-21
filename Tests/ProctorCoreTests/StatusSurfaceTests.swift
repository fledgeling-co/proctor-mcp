import Foundation
import Testing
@testable import ProctorCore

// PRO-0066. The status window's decisions, judged without a window.

@Suite("Status surface")
struct StatusSurfaceTests {

    @Test("A1 · the agent-down state draws the notice and nothing else")
    func downWithholds() {
        // The clause this item turns on. Drawing the other sections greyed
        // leaves a permission row on screen that nothing has read, and a stale
        // Ready pill over a dead agent is a false statement about a grant.
        let sections = StatusSurface.sections(for: .down)
        #expect(sections == [.agentDown])
        for forbidden in [StatusSurface.Section.permissions, .tools, .lanes,
                          .switches, .activity, .connect, .agent, .footer] {
            #expect(!sections.contains(forbidden),
                    "\(forbidden.rawValue) is reachable while the agent is unreachable")
        }
    }

    @Test("A1 · every state resolves to a section list, and only ready and partial are full")
    func stateSections() {
        for state in StatusSurface.State.allCases {
            #expect(!StatusSurface.sections(for: state).isEmpty)
        }
        #expect(StatusSurface.sections(for: .ready).count == 8)
        #expect(StatusSurface.sections(for: .partial) == StatusSurface.sections(for: .ready))
        // Checking shows the permissions frame it is filling, and no more: a
        // skeleton under a Connect section nobody can act on is noise.
        #expect(StatusSurface.sections(for: .checking) == [.permissions, .footer])
        #expect(StatusSurface.sections(for: .ready).contains(.lanes),
                "the Lanes block has been on the wire and unrendered since PRO-0036")
    }

    @Test("A1 · the state mapping is a decision, not a view-body branch")
    func stateMapping() {
        #expect(StatusSurface.state(reachable: true, answered: false, lanesAllUsable: true) == .checking)
        #expect(StatusSurface.state(reachable: false, answered: false, lanesAllUsable: true) == .checking)
        #expect(StatusSurface.state(reachable: false, answered: true, lanesAllUsable: true) == .down)
        #expect(StatusSurface.state(reachable: true, answered: true, lanesAllUsable: true) == .ready)
        #expect(StatusSurface.state(reachable: true, answered: true, lanesAllUsable: false) == .partial)
        // An unusable optional lane never makes the window claim the agent is
        // down, and never makes `ready` mean less than it does.
        #expect(StatusSurface.sections(for: .partial).contains(.permissions))
    }

    @Test("A3 · identifiers are unique and namespaced")
    func identifiers() {
        let all = StatusSurface.ID.all
        #expect(Set(all).count == all.count, "identifiers collide")
        for id in all {
            #expect(id.hasPrefix("proctor.status."), "\(id) is not namespaced to this surface")
        }
    }

    @Test("A3 · a switch row's identifier is derived from its variable, so a rename is a red test")
    func switchIdentifiers() {
        #expect(StatusSurface.ID.switchRow("PROCTOR_HUD") == "proctor.status.switch.proctor-hud")
        // Every switch in the catalogue has a row, so a ninth switch cannot be
        // added without this surface gaining one.
        for s in SwitchCatalogue.all {
            #expect(StatusSurface.ID.all.contains(StatusSurface.ID.switchRow(s.variable)))
        }
    }

    @Test("A5 · unconfirmed and unavailable are different answers and are drawn differently")
    func laneStatesDiffer() {
        #expect(StatusSurface.LaneState.unconfirmed.pill != StatusSurface.LaneState.unavailable.pill)
        #expect(StatusSurface.LaneState.ready.pill != StatusSurface.LaneState.unconfirmed.pill)
        // Fail-closed, matching the wire: unconfirmed is not usable either.
        #expect(StatusSurface.LaneState.ready.isUsable)
        #expect(!StatusSurface.LaneState.unconfirmed.isUsable)
        #expect(!StatusSurface.LaneState.unavailable.isUsable)
    }

    @Test("A6 · a skeleton is the height of the row it stands in for")
    func skeletonMatchesRow() {
        // A skeleton of the wrong height guarantees a jump when the answer
        // lands, and this window polls every two seconds.
        #expect(StatusSurface.Geometry.skeletonHeight == StatusSurface.Geometry.rowHeight)
    }

    @Test("A2 · the copy a person reads is here, not in a view body")
    func copyPresent() {
        #expect(!StatusSurface.Copy.downTitle.isEmpty)
        #expect(!StatusSurface.Copy.downConsequence.isEmpty)
        // The down block says what is wrong, what it stops, and what to do.
        #expect(StatusSurface.Copy.downConsequence.contains("no test can run"))
        #expect(StatusSurface.Copy.downStart == "Start the agent")
        // And it does not apologise, which is the register the whole surface set uses.
        for line in [StatusSurface.Copy.downTitle, StatusSurface.Copy.downConsequence] {
            #expect(!line.lowercased().contains("sorry"))
            #expect(!line.lowercased().contains("oops"))
        }
    }

    @Test("A2 · the tools note states that Proctor installs nothing")
    func installsNothing() {
        // Not decoration: a command in a surface a model can read is a command a
        // model will run, and this process holds Accessibility and Screen
        // Recording. The rule is stated where a person can see it.
        // PRO-0081. The subject is renamed, not weakened: this sentence is the
        // design of record's wording, which Core has carried since PRO-0066 and
        // the window has never rendered. `toolsNote` now holds what is actually
        // on screen, and the divergence between the two is DEF-035.
        #expect(StatusSurface.Copy.toolsNoteInDesign.contains("installs nothing"))
        #expect(StatusSurface.Copy.toolsNoteInDesign.contains("never"))
        #expect(StatusSurface.Copy.toolsNote != StatusSurface.Copy.toolsNoteInDesign,
                "if these ever agree, DEF-035 is fixed and one of them should go")
    }

    // MARK: - PRO-0081, closing PRO-0066's carried A2
    //
    // A2 read: *every user-facing string comes from `StatusSurface`; a grep for a
    // quoted string literal in `MainWindow.swift` outside an identifier returns
    // nothing.* It merged carried, with 132 user-facing literals still in the
    // view. The clause's own grep is `scripts/campaign/status_literals.py`, which
    // classifies by syntactic position and is default-deny; these three are the
    // Swift half, and they guard the things the Python cannot see.

    @Test("A2 · every string the window can say is enumerable, and none is a duplicate")
    func copyIsEnumerableAndDistinct() {
        let all = StatusSurface.Copy.all
        #expect(!all.isEmpty)
        for entry in all {
            #expect(!entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(entry.name) is blank; a constant holding nothing is a string the window shows nothing for")
        }
        // Two names for one sentence is how a wording change gets applied to one
        // of them. The two deliberate pairs are the diverged notes, and they are
        // asserted as *different* elsewhere rather than excused here.
        var seen: [String: String] = [:]
        for entry in all {
            if let first = seen[entry.text] {
                Issue.record("\(first) and \(entry.name) hold the same sentence")
            }
            seen[entry.text] = entry.name
        }
    }

    @Test("A2 · the list of copy is the whole of the copy")
    func copyListIsComplete() throws {
        // `Copy.all` is hand-maintained, so a constant added without a row here
        // is invisible to the test above in exactly the way a literal in a view
        // was invisible to everything. Counting the declarations in the file
        // against the length of the list is what makes forgetting it fail.
        let source = try Self.source("Sources/ProctorCore/StatusSurface.swift")
        let opening = try #require(source.range(of: "public enum Copy {"))
        let body = String(source[opening.upperBound...])
        let listStart = try #require(body.range(of: "public static var all:"))
        let declarations = String(body[..<listStart.lowerBound])
            .components(separatedBy: "public static let ").count - 1
        #expect(declarations == StatusSurface.Copy.all.count,
                "StatusSurface.Copy declares \(declarations) constants and Copy.all lists \(StatusSurface.Copy.all.count). Add the new one to the list.")
    }

    @Test("A2 · the window names its copy rather than quoting it")
    func theWindowQuotesNothingItRenders() throws {
        // The Swift-side mirror of the clause's grep. It catches the specific
        // regression the grep was written against — a string typed straight into
        // a rendering construct — without re-implementing the classifier, and it
        // reads the code with whole-line comments dropped so the comments
        // explaining the move do not trip it.
        let source = Self.codeOnly(try Self.source("Sources/ProctorUI/MainWindow.swift"))
        for construct in ["Text(\"", "Button(\"", "SectionTitle(\"",
                          "Label(\"", "title: \"", "message: \""] {
            #expect(!source.contains(construct),
                    "MainWindow.swift renders a literal through \(construct) — it belongs in StatusSurface.Copy, where a test can see it and a translator can find it")
        }
        // And the file still holds its own machinery. Emptying the view into
        // another file would satisfy every check above while moving the problem,
        // so the identifiers it legitimately keeps are counted rather than
        // assumed: SF Symbol names, shell paths and argv, and separators.
        #expect(source.contains("Image(systemName:"))
        #expect(source.contains("/bin/launchctl"))
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// The same source with whole-line comments dropped, so a comment quoting a
    /// forbidden construct while explaining why it moved does not fail the scan.
    private static func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
