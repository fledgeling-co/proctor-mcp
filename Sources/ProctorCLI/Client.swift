import Foundation
import ProctorCore

// The same socket the MCP shim uses, through the same `SocketClient` in Core.
//
// One path into the agent, deliberately. A second client here could drift into a
// second set of behaviours — a different timeout, a different framing, a gate
// skipped — and the whole claim of this binary is that a CLI call is not a
// privilege bypass.
enum Client {

    static func call(tool: String, arguments: [String: JSONValue]) throws -> JSONValue {
        let client = SocketClient()
        defer { client.disconnect() }
        let response = try client.send(AgentRequest(id: UUID().uuidString,
                                                    tool: tool,
                                                    arguments: .object(arguments)))
        if response.ok { return response.result ?? .object([:]) }
        throw response.error ?? AgentError(
            code: .internalError,
            message: "the agent reported failure without an error",
            remedy: "Run proctor doctor, and check ~/Library/Logs/Proctor/agent.log.")
    }
}
