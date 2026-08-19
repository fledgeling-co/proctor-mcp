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
        #expect(StatusSurface.Copy.toolsNote.contains("installs nothing"))
        #expect(StatusSurface.Copy.toolsNote.contains("never"))
    }
}
