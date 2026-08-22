import Foundation
import Testing
@testable import ProctorCore

// PRO-0085 — the boundary between Proctor's internal agent verbs and the tools an
// MCP host may call. CASE-0372..CASE-0374, REQ-093.
//
// `AgentVerbs.swift:20-24` states this boundary in prose: the verbs below are
// internal, none is in `ToolCatalogue`, so the shim — which gates `tools/call` on
// the catalogue — cannot reach them and no MCP host can put a person's stop button
// away or read their activity feed through this path. `MCPServer.swift:224` is that
// gate. Nothing asserted it until here, and a comment that goes false still reads
// as true: adding `proctor_hud` to the catalogue would hand an MCP client a
// person's Pause, Resume and Stop, and both the comment and the proctor skill would
// keep saying it could not.
//
// The proctor skill in `fledgeling-plugins` now tells every agent on this machine
// that a call to an internal verb is refused. This is where that claim is checked.
//
// WHAT THIS DOES NOT COVER: the skill file lives in another repository and nothing
// here reads it. `references/tools.md` drifting from the catalogue again is caught
// by re-running the count against `ToolCatalogue.all`, not by this suite.

@Suite("Agent verb boundary")
struct AgentVerbBoundaryTests {

    /// The internal verbs, read from `AgentVerbs` rather than copied, so a renamed
    /// constant moves the assertion with it instead of leaving it asserting a
    /// string nothing uses any more.
    private static let internalVerbs: [(label: String, verb: String)] = [
        ("hud", AgentVerbs.hud),
        ("queue", AgentVerbs.queue),
        ("recentActivity", AgentVerbs.recentActivity)
    ]

    // CASE-0372
    @Test("no internal agent verb has a catalogue spec, so tools/call refuses it")
    func internalVerbsAreNotCatalogueTools() {
        for (label, verb) in Self.internalVerbs {
            #expect(ToolCatalogue.spec(named: verb) == nil,
                    "AgentVerbs.\(label) is \(verb), which has a catalogue spec — the shim's tools/call gate would forward it to the agent")
        }
    }

    // CASE-0373
    @Test("proctor_doctor is the one agent verb that is also a catalogue tool")
    func doctorIsACatalogueTool() {
        // Named in `AgentVerbs` because the status window calls it by the same
        // name. If this goes nil the exclusion above has swept up a real tool.
        #expect(ToolCatalogue.spec(named: AgentVerbs.doctor) != nil,
                "AgentVerbs.doctor is \(AgentVerbs.doctor) and has no catalogue spec")
    }

    // CASE-0374
    @Test("the catalogue ships 21 tools, each named once")
    func catalogueShipsTwentyOneUniquelyNamedTools() {
        let names = ToolCatalogue.all.map(\.name)
        #expect(names.count == 21,
                "ToolCatalogue.all holds \(names.count) specs; references/tools.md in the proctor skill documents 21 and needs the same edit")
        #expect(Set(names).count == names.count,
                "two catalogue specs share a name: \(names.sorted().joined(separator: ", "))")
    }
}
