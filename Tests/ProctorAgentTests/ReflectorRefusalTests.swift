import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// What Proctor says when the app under test embeds no reflector.
//
// Found by arming: nothing in the suite exercised this path, so the promise that
// an unavailable instrument is reported rather than approximated was carried by
// nothing. There is no cross-process equivalent of computed styles on macOS, so
// the only honest answer here is a refusal that names a remedy, and a guessed
// value returned in the shape of a measurement would be worse than no value.
//
// What this cannot reach, and does not pretend to: a live reflector inside a
// real app. That needs a build of another application with the package embedded,
// and it is recorded in the campaign as the ceiling of this lane.

@Suite("Reflector absence is reported, never approximated")
struct ReflectorRefusalTests {

    private let window = WindowHandle(id: "win-1", app: "app-1", title: "Fake Window",
                                      frame: Rect(x: 0, y: 0, w: 640, h: 480),
                                      isMain: true, isMinimized: false, isOnActiveSpace: true,
                                      cgWindowID: TestWindowIDs.absent())

    @Test("inspect refuses with its own code rather than returning a shape")
    func inspectRefuses() {
        let bridge = NullReflectorBridge()
        var thrown: AgentError?
        do {
            _ = try bridge.inspect(pid: 4242, window: window, node: nil, maxDepth: 4,
                                   includeConstraints: true, presentation: true)
            Issue.record("inspect returned a value where no reflector is embedded")
        } catch let error as AgentError {
            thrown = error
        } catch {
            Issue.record("inspect threw something other than an AgentError")
        }
        #expect(thrown?.code == .reflectorUnavailable)
        #expect(thrown?.message.contains("4242") == true, "the refusal names the process it is about")
        #expect(thrown?.remedy?.contains("ProctorReflector") == true)
        #expect(thrown?.remedy?.contains("proctor_snapshot") == true,
                "the remedy names the ceiling for an app you do not own")
    }

    @Test("the liveness reads answer nil rather than guessing")
    func livenessIsUnknownNotFalse() {
        // nil is not the same as false here, and the difference is load-bearing:
        // false would tell a settle that the app is busy, which is a claim about
        // a process this bridge cannot see at all.
        let bridge = NullReflectorBridge()
        #expect(bridge.isIdle(pid: 4242) == nil)
        #expect(bridge.renderRevision(pid: 4242) == nil)
        #expect(!bridge.isConnected(pid: 4242))
    }
}
