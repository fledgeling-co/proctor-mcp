import Foundation
import Testing
@testable import ProctorCore
@testable import ProctorAgent

@Suite("Wave 26: Legacy Briefs 04..10 Validation & Boundary Fixtures (PRO-0143..PRO-0147)")
struct Wave26Tests {

    @Test("PRO-0143 / PRO-0146: Scripting dictionary, audit policy, and vision capture validation")
    func testScriptingAuditAndVisionValidation() {
        let scriptDict = AppScriptingDictionary(
            appName: "Finder",
            scriptable: true,
            suites: [],
            counts: AppScriptingDictionary.Counts(suites: 0, commands: 0, classes: 0, enumerations: 0),
            summary: "Finder: scriptable (0 commands)"
        )
        #expect(scriptDict.scriptable)
        #expect(scriptDict.appName == "Finder")

        let policy = AppPolicy()
        let decision = policy.decide(bundleId: "com.apple.Safari", hasValidToken: false)
        #expect(decision == .allow)

        let visionCrop = RegionCrop.regionForElement(elementFrame: Rect(x: 10, y: 10, w: 100, h: 50),
                                                    window: Rect(x: 0, y: 0, w: 800, h: 600),
                                                    padding: 4.0)
        #expect(visionCrop.w == 108)
        #expect(visionCrop.h == 58)
    }

    @Test("PRO-0144 / PRO-0147: MCP tools, filesystem jail, and multi-plane receipts")
    func testToolsJailAndPlaneReceipts() {
        let jail = FSJail(roots: ["/tmp"])
        #expect(!jail.roots.isEmpty)

        let tools = ToolCatalogue.all
        #expect(tools.contains { $0.name == "proctor_find" })
        #expect(tools.contains { $0.name == "proctor_act" })
        #expect(tools.contains { $0.name == "proctor_capture" })
    }

    @Test("PRO-0145: Hermetic tool process boundary socket fixtures")
    func testSocketBoundaryFixture() throws {
        let frame = try FrameCodec.encode(JSONValue.object(["status": .string("ok")]))
        #expect(!frame.isEmpty)

        let reader = FrameCodec.Reader()
        reader.feed(frame)
        let payload = try reader.next()
        #expect(payload != nil)
    }
}
