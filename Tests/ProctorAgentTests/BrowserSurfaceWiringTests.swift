import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0035 — the wiring half.
//
// The decision is pure and tested in `BrowserSurfaceTests`. What is tested here
// is that it survives the trip to the wire: that an installed web app's window
// carries its surface, its flags and no lane through the encoded JSON of both the
// surface where an instrument is chosen (`proctor_apps` attach) and the surface a
// model spends its time on (`proctor_snapshot`), and that the operator's gate is
// still total over the two fields this item adds.
//
// The environment is injected, as PRO-0024 established: a process's environment is
// cached at launch, so `setenv` in a test does nothing and a suite reaching for
// `ProcessInfo` lets whichever test ran first decide for the whole process.
//
// Not testable here: that a real installed web app's bundle identifier has the
// shape this assumes, and that its accessibility tree contains a web area at all.
// Both need a machine with a web app installed on it; this one has none.

@Suite("Installed web app wiring")
struct BrowserSurfaceWiringTests {

    private static let chromeWebApp = "com.google.Chrome.app.gaedmjdfmmahhbjefcbgaolhfnkkmbaa"
    private static let chrome = "com.google.Chrome"

    private static let pageProbe = WebContentProbe(areas: [
        WebArea(url: "https://mail.example.com/inbox", frame: Rect(x: 0, y: 0, w: 800, h: 600))
    ])

    private func session(bundleId: String, laneSet: Bool, obscura: Bool = true,
                         browserUse: Bool = true) async throws -> Session {
        let ax = FakeAX(bundleId: bundleId)
        ax.webContentProbe = Self.pageProbe
        let session = Session(
            ax: ax, capture: FakeCapture(),
            tools: ToolProbes(
                obscura: ToolProbe(probe: {
                    ToolPresence(tool: ObscuraTool.binary, available: obscura,
                                 path: obscura ? "/opt/homebrew/bin/obscura" : nil)
                }),
                browserUse: ToolProbe(probe: {
                    ToolPresence(tool: BrowserUseTool.binary, available: browserUse,
                                 path: browserUse ? "/opt/homebrew/bin/browser-use" : nil)
                }),
                environment: laneSet ? [BrowserUseTool.laneVariable: BrowserUseTool.binary] : [:]))
        await session.setAuditSink(AuditCollector().sink)
        _ = try await session.attachResolved(bundleId: bundleId, pid: nil, name: nil)
        return session
    }

    private func wireHandoff(_ encodable: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(encodable)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["browser"] as? [String: Any])
    }

    // MARK: - Clause 16 — the surface and the flags reach the wire

    @Test("an installed web app carries its surface, its flags and no lane end to end")
    func aWebAppCarriesSurfaceAndFlagsThroughTheWire() async throws {
        let session = try await self.session(bundleId: Self.chromeWebApp, laneSet: true)

        // The surface where the instrument is chosen.
        let attach = try wireHandoff(
            try await session.attach(bundleId: Self.chromeWebApp, pid: nil, name: nil))
        #expect(attach["surface"] as? String == "installedWebApp")
        #expect(attach["use"] == nil)
        #expect(attach["commands"] == nil)
        #expect(attach["caveats"] == nil)
        #expect(attach["toolUnavailable"] == nil)

        let flags = try #require(attach["flags"] as? [String: Any])
        // The one that matters: driving somebody's installed mail window acts in
        // their live signed-in session, and before this it carried no flag at all.
        #expect(flags["canActAsThisPerson"] as? Bool == true)
        #expect(flags["actsOutsideThisWindow"] as? Bool == false)
        #expect(flags["outsideTheAuditTrail"] as? Bool == false)
        #expect(flags["autonomous"] as? Bool == false)
        #expect(flags["billed"] as? Bool == false)

        // And the surface a model spends its time on.
        let snapshot = try wireHandoff(
            try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil))
        #expect(snapshot["surface"] as? String == "installedWebApp")
        #expect(snapshot["use"] == nil)
        #expect((snapshot["flags"] as? [String: Any])?["canActAsThisPerson"] as? Bool == true)
        #expect(snapshot["url"] as? String == "https://mail.example.com/inbox")
    }

    @Test("an ordinary browser window still names its lane and carries that lane's flags")
    func aBrowserWindowStillNamesItsLane() async throws {
        let session = try await self.session(bundleId: Self.chrome, laneSet: false)
        let attach = try wireHandoff(
            try await session.attach(bundleId: Self.chrome, pid: nil, name: nil))
        #expect(attach["surface"] as? String == "browserWindow")
        #expect(attach["use"] as? String == "obscura")
        let flags = try #require(attach["flags"] as? [String: Any])
        #expect(flags["actsOutsideThisWindow"] as? Bool == true)
        #expect(flags["outsideTheAuditTrail"] as? Bool == true)
        #expect(flags["canActAsThisPerson"] as? Bool == false)
    }

    // MARK: - Clause 14 — the gate is still total, over the new fields too

    @Test("with the variable unset the wire never carries the name, web app included")
    func theGateHoldsOverTheNewFieldsAtTheWire() async throws {
        for bundleId in [Self.chrome, Self.chromeWebApp] {
            for obscura in [true, false] {
                let session = try await self.session(bundleId: bundleId, laneSet: false,
                                                     obscura: obscura, browserUse: true)
                let attach = try await session.attach(bundleId: bundleId, pid: nil, name: nil)
                #expect(!String(decoding: try JSONEncoder().encode(attach), as: UTF8.self)
                            .contains("browser-use"), "\(bundleId)")
                let snapshot = try await session.snapshot(window: "win-1", options: .init(),
                                                          sinceRevision: nil)
                #expect(!String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
                            .contains("browser-use"), "\(bundleId)")
            }
        }
    }
}
