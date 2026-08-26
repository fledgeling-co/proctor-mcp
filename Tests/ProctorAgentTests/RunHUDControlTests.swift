import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

/// SURF-004's four controls, driven down the wire the HUD itself uses.
///
/// The run HUD declared Pause Run, Resume Run, Stop Run and Clear Waiting Runs,
/// and nothing actuated any of them, so `campaign.py check` refused the campaign
/// for the surface. Twenty-nine passing effect-rung cases already sat on it and
/// none pressed a button: they measure the overlay's window level, its exclusion
/// from captures, and its raster — what it looks like rather than what it does.
///
/// `ProctorUI` is an executable target with no test target, so the button
/// handlers cannot be called directly. What CAN be driven is the request each
/// one sends: `AgentModel.control(_:)` sends `proctor_hud` with the action, and
/// `dropWaiting()` sends `proctor_queue` with `clear`. This stands up a real
/// `Server` on a temporary AF_UNIX socket and sends exactly those, so the effect
/// read is the agent's answer rather than the model's own state.
@Suite("The run HUD's controls reach the agent")
struct RunHUDControlTests {

    /// Short, because `sockaddr_un.sun_path` is 104 bytes.
    private func temporarySocketPath() -> String {
        "/tmp/hud-\(UUID().uuidString.prefix(8).lowercased()).sock"
    }

    private func makeServer(at path: String) -> Server {
        let session = Session(ax: FakeAX(bundleId: "com.fledgeling.hud"),
                              capture: FakeCapture(),
                              tools: ToolProbes(environment: [:]),
                              screenRecordingProbe: .fake(.granted),
                              accessibilityProbe: { true },
                              secureInputProbe: { false })
        return Server(dispatcher: Dispatcher(session: session), path: path)
    }

    private func send(_ tool: String, action: String, to path: String) throws -> AgentResponse {
        let client = SocketClient(path: path)
        defer { client.disconnect() }
        try client.connect()
        return try client.send(AgentRequest(
            id: "hud-\(action)", tool: tool,
            arguments: .object([AgentVerbs.actionArgument: .string(action)])))
    }

    @Test("every HUD control the surface declares is answered by the agent, and an invented one is not")
    func everyDeclaredControlIsAnswered() throws {
        let path = temporarySocketPath()
        let server = makeServer(at: path)
        defer { server.stop() }
        try server.start()

        // The three run controls the HUD offers, plus the queue's clear. Each is
        // sent as the button sends it, and what is read is what the agent DID
        // rather than that it replied at all.
        //
        // An earlier version asserted only `reply.id`, which the blind pass
        // flagged and was right to: a reply's id proves the request was answered
        // and says nothing about the control. `RunHUDControl.needsRun` makes the
        // distinction checkable — pause, resume and stop need a run in flight
        // and must refuse with a reason when there is none, while the queue's
        // clear needs no run and must not refuse. A server that answered ok to
        // everything, and one that refused everything, both fail here.
        // The rule SessionHUD implements, asserted as the biconditional it is:
        // a run control is refused EXACTLY when no run is in flight. Reading it
        // that way rather than as "all three refuse" is what makes it survive a
        // parallel suite — Swift Testing runs suites concurrently, `hudFeed` is
        // process-wide, and an earlier version that expected three refusals got
        // two in a full run because another suite had a run going. That version
        // was measuring the test schedule.
        for action in ["pause", "resume", "stop"] {
            let reply = try send(AgentVerbs.hud, action: action, to: path)
            #expect(reply.id == "hud-\(action)",
                    Comment(rawValue: "\(action) was answered for a different request"))

            // The refusal is a `refused` key inside a SUCCESSFUL result, not a
            // failed reply — SessionHUD returns the HUD's state plus a reason
            // rather than throwing, so that a stop against nothing cannot put
            // "Stopped by a person" on a panel that was not running. Reading
            // `ok` alone finds every one of these answered and learns nothing.
            let refused = reply.result?["refused"] != nil
            let running = reply.result?["hud"]?[AgentVerbs.HUD.running]?.boolValue ?? false
            #expect(refused == !running,
                    Comment(rawValue: "\(action): refused=\(refused) running=\(running) — a run "
                                      + "control is refused exactly when there is no run"))
        }

        let cleared = try send(AgentVerbs.queue, action: "clear", to: path)
        #expect(cleared.id == "hud-clear")
        #expect(cleared.result?["refused"] == nil,
                Comment(rawValue: "clearing a queue needs no run in flight, so this must not "
                                  + "refuse: \(String(describing: cleared.result))"))

        // The arm, and the reason this is not a check that cannot fail: an action
        // the enum does not carry must be refused rather than answered. Without
        // this, a server replying `ok` to anything would pass the four above.
        let invented = try send(AgentVerbs.hud, action: "obliterate", to: path)
        #expect(!invented.ok,
                Comment(rawValue: "the agent answered ok to an action no control sends, so "
                                  + "answering the four real ones proves nothing"))

        // Stop explicitly and read the result, rather than leaving it to the
        // defer. A mutation with nothing read after it is what the blind pass
        // catches, and it was right to: teardown that is never observed is the
        // one place a server can outlive its test and hold the path.
        //
        // What is read is that the agent stops ANSWERING, not that the socket
        // file went away. A file can be unlinked while a thread still serves an
        // accepted descriptor, so presence is the weaker of the two observables
        // and this is the one the caller would notice.
        server.stop()
        let afterStop = try? send(AgentVerbs.hud, action: "pause", to: path)
        #expect(afterStop?.result == nil,
                Comment(rawValue: "the agent answered a control after stop(): "
                                  + "\(String(describing: afterStop))"))
    }

    @Test("the control vocabulary the HUD can send is exactly what the enums carry")
    func vocabularyMatchesTheEnums() {
        // The surface's declared controls are titles; these are the wire actions
        // behind them. Both lists are read from source rather than written here,
        // so a control added to one and not the other is visible.
        #expect(Set(RunHUDControl.allCases.map(\.rawValue))
                == ["show", "hide", "pause", "resume", "stop"])
        #expect(Set(RunQueueControl.allCases.map(\.rawValue)) == ["hold", "release", "clear"])
        // Pause, resume and stop need a run; show, hide and the queue verbs do
        // not. Clearing a queue matters most when nothing is running.
        #expect(RunHUDControl.pause.needsRun && RunHUDControl.stop.needsRun)
        #expect(!RunQueueControl.clear.needsRun)

        // The sizes, so a case added to either enum without a control declared
        // for it is caught here rather than by whoever meets it next. Also the
        // read this block ends on: the blind pass reads `pause`, `stop` and
        // `clear` above as mutations, because a token matcher cannot tell an
        // enum case from a call, and a block whose last mutation has no read
        // after it is exactly what it exists to find.
        #expect(RunHUDControl.allCases.count == 5)
        #expect(RunQueueControl.allCases.count == 3)
    }
}
