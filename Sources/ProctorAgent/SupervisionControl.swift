import Foundation
import ProctorCore

// PRO-0074. The three controls a supervision client may use, and nothing else.
//
// The TUI watches and it halts. It issues no tool calls, authors no flows and
// edits no policy — so the surface that reaches furthest, across SSH onto a Mac
// with no window server, is also the one that can do least.
//
// Every action here reaches `RunControl.shared`, which is the same object the
// HUD panel writes and the run loop reads. That is A4's whole claim: one latch,
// not two. A second latch would let a run be stopped in one place and keep
// going in the other, and a person would have no way to tell which they had
// pressed.

enum SupervisionControl {

    static let tool = "proctor.control"

    /// The actions, named rather than free text so an unknown one is a usage
    /// error rather than a silent no-op that reads as a broken Stop.
    enum Action: String, CaseIterable {
        case pause, resume, stop
    }

    static func perform(_ request: AgentRequest,
                        control: RunControl = .shared) -> AgentResponse {
        guard case .object(let arguments) = request.arguments,
              let raw = arguments["action"]?.stringValue,
              let action = Action(rawValue: raw) else {
            return AgentResponse(id: request.id, ok: false, error: AgentError(
                code: .invalidArguments,
                message: "a supervision control needs one of: "
                       + Action.allCases.map(\.rawValue).joined(separator: ", "),
                remedy: "Send {action: \"stop\"}."))
        }
        apply(action, to: control)
        return AgentResponse(id: request.id, ok: true,
                             result: .object(["action": .string(action.rawValue),
                                              "paused": .bool(control.isPaused),
                                              "stopped": .bool(control.isStopped)]))
    }

    /// Split out so the wiring can be asserted without a socket, and taking the
    /// control rather than reaching for the singleton so a test can drive its
    /// own. PRO-0053 is the reason: a suite that wrote a process-wide latch
    /// reached whichever other suite happened to be stepping concurrently, and
    /// the resulting failure looked like a bug in the feature under test.
    ///
    /// The default is `RunControl.shared`, and the default is the claim — this
    /// is the same object the HUD panel writes and the run loop reads.
    static func apply(_ action: Action, to control: RunControl = .shared) {
        switch action {
        case .pause: control.pause()
        case .resume: control.resume()
        case .stop: control.stop()
        }
    }
}
