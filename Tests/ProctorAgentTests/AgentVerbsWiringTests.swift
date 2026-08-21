import Testing
import Foundation
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0090, DEF-039 one layer down. The window polls the agent for what is
// running and what the run panel is doing, and until now each side spelled the
// payload's keys for itself. Nothing failed when they parted: the reader takes
// `?? false` for a key it cannot find, so a rename would have shipped as a menu
// bar quietly wrong about whether a run was taking the machine.
//
// This runs the real writer and checks the document it produced against the
// constants the reader uses, rather than checking that somebody typed the same
// string twice.
@Suite("Agent verbs wiring")
struct AgentVerbsWiringTests {

    @Test("the run panel's payload carries exactly the keys the window reads")
    func hudWireKeysMatchTheReader() throws {
        let feed = RunHUDFeed(drawing: true)
        let wire = feed.wire
        let object = try #require(wire.objectValue,
                                  "RunHUDFeed.wire is not an object; the window subscripts it")

        let expected = Set([AgentVerbs.HUD.phase, AgentVerbs.HUD.running,
                            AgentVerbs.HUD.drawing, AgentVerbs.HUD.canShow])
        #expect(Set(object.keys) == expected,
                "RunHUDFeed.wire writes \(Set(object.keys).sorted()) and the window reads \(expected.sorted())")

        // The phase has to resolve back through the reader's own initialiser
        // path: it is the one key with no default, so a drift there turns the
        // whole HUDState nil and the menu bar loses its character silently.
        let phase = try #require(object[AgentVerbs.HUD.phase]?.stringValue)
        #expect(RunHUDPhase(rawValue: phase) != nil)
    }

    @Test("the activity feed carries the keys the menu bar reads out of it")
    func activityKeysMatchTheReader() async throws {
        let session = Self.plainSession()
        await session.activityBegin(tool: AgentVerbs.doctor)
        await session.activityEnd(tool: AgentVerbs.doctor, ok: true)

        let projection = await session.recentActivity()
        let object = try #require(projection.objectValue)
        for key in [AgentVerbs.Activity.current, AgentVerbs.Activity.recent,
                    AgentVerbs.Activity.queueWaiting, AgentVerbs.Activity.hud,
                    AgentVerbs.Activity.foreground] {
            #expect(object[key] != nil,
                    "the activity projection has no \(key); the menu bar reads it and would take the default")
        }

        // One completed row, read exactly as the window reads it.
        let rows = try #require(object[AgentVerbs.Activity.recent]?.arrayValue)
        let row = try #require(rows.first?.objectValue)
        #expect(row[AgentVerbs.Activity.tool]?.stringValue == AgentVerbs.doctor)
        #expect(row[AgentVerbs.Activity.ok]?.boolValue == true)
        #expect(row[AgentVerbs.Activity.at]?.stringValue != nil)

        // And the foreground block, whose keys the menu bar turns into the line
        // it draws about a run taking the machine.
        let foreground = try #require(object[AgentVerbs.Activity.foreground]?.objectValue)
        for key in [AgentVerbs.Foreground.running, AgentVerbs.Foreground.active,
                    AgentVerbs.Foreground.takesForeground,
                    AgentVerbs.Foreground.mayTakeForeground,
                    AgentVerbs.Foreground.notice, AgentVerbs.Foreground.yield] {
            #expect(foreground[key] != nil,
                    "the foreground block has no \(key)")
        }
        let yield = try #require(foreground[AgentVerbs.Foreground.yield]?.objectValue)
        #expect(yield[AgentVerbs.Foreground.active] != nil)
        #expect(yield[AgentVerbs.Foreground.line] != nil)
    }

    @Test("the four verbs the window calls are the four the agent routes")
    func verbsAreRouted() {
        // Three of them are internal by design: not in ToolCatalogue, so the
        // shim — which gates tools/call on the catalogue — cannot reach them and
        // no MCP host can put a person's stop button away or read their activity
        // feed through this path.
        let catalogue = Set(ToolCatalogue.all.map(\.name))
        for verb in [AgentVerbs.recentActivity, AgentVerbs.hud, AgentVerbs.queue] {
            #expect(!catalogue.contains(verb),
                    "\(verb) reached ToolCatalogue, so a host can now call it")
        }
        // And the one that is a catalogue tool is in it, so the check above can
        // report a non-empty catalogue rather than an empty one.
        #expect(catalogue.contains(AgentVerbs.doctor))
    }

    private static func plainSession() -> Session {
        Session(ax: FakeAX(bundleId: "com.apple.TextEdit"), capture: FakeCapture(),
                tools: ToolProbes())
    }
}
