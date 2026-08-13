import Foundation
import ProctorCore

// MCP over stdio: JSON-RPC 2.0, one JSON object per line, in on stdin and out
// on stdout. The shim holds no TCC grants and keeps no state — it advertises
// the shared catalogue and forwards every call to the privileged agent. Anything
// it does beyond forwarding is a design mistake.

enum ShimVersion {
    static let value = "0.1.0"
}

/// stdout is the protocol channel. A single stray print corrupts the JSON-RPC
/// stream and ends the session, so every diagnostic goes to stderr.
func shimLog(_ message: String) {
    FileHandle.standardError.write(Data("proctor-shim: \(message)\n".utf8))
}

struct MCPServer {
    private static let mcpProtocolVersion = "2025-06-18"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    func run() {
        shimLog("serving MCP on stdio; agent socket \(Wire.socketPath)")
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)

        // A read can return any fraction of a line, or several lines at once,
        // so lines are cut out of an accumulating buffer rather than assumed.
        readLoop: while true {
            let n = read(0, &chunk, chunk.count)
            if n < 0 {
                if errno == EINTR { continue }
                shimLog("stdin read failed: \(String(cString: strerror(errno)))")
                break readLoop
            }
            if n == 0 { break readLoop }
            buffer.append(contentsOf: chunk[0..<n])

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer = Data(buffer[buffer.index(after: newline)...])
                handle(line: line)
            }
        }

        if !buffer.isEmpty { handle(line: buffer) }
        shimLog("stdin closed; exiting")
    }

    // MARK: - Dispatch

    private func handle(line rawLine: Data) {
        var line = rawLine
        if line.last == 0x0D { line = line.dropLast() }
        guard !line.trimmedIsEmpty else { return }

        let message: JSONValue
        do {
            message = try JSONDecoder().decode(JSONValue.self, from: line)
        } catch {
            shimLog("could not parse a line as JSON: \(error)")
            emit(errorResponse(id: .null, code: -32700, message: "parse error"))
            return
        }

        if let response = response(for: message) { emit(response) }
    }

    /// The JSON-RPC response for one decoded message, or nil for a notification
    /// (answered with silence). The stdio loop and the remote HTTP listener both
    /// call this, so a call behaves identically over either transport — the
    /// wire is the only thing that differs, never the protocol.
    func response(for message: JSONValue) -> JSONValue? {
        guard let method = message["method"]?.stringValue else {
            shimLog("message with no method; ignoring")
            return nil
        }
        let id = message["id"]
        let params = message["params"]?.objectValue ?? [:]

        // A notification carries no id and is answered with silence.
        guard let id else {
            if method != "notifications/initialized" {
                shimLog("notification \(method)")
            }
            return nil
        }

        switch method {
        case "initialize":
            return result(id: id, .object([
                "protocolVersion": .string(Self.mcpProtocolVersion),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(false)])
                ]),
                "serverInfo": .object([
                    "name": .string("proctor"),
                    "version": .string(ShimVersion.value)
                ])
            ]))

        case "tools/list":
            return result(id: id, .object(["tools": .array(ToolCatalogue.all.map(toolEntry))]))

        case "tools/call":
            return result(id: id, callTool(params: params))

        case "ping":
            return result(id: id, .object([:]))

        default:
            return errorResponse(id: id, code: -32601, message: "unknown method: \(method)")
        }
    }

    /// Serialise a response object to compact JSON bytes for a non-stdio
    /// transport. Same encoder the stdio path uses.
    func encode(_ value: JSONValue) -> Data? {
        try? encoder.encode(value)
    }

    private func toolEntry(_ spec: ToolSpec) -> JSONValue {
        .object([
            "name": .string(spec.name),
            "title": .string(spec.title),
            "description": .string(spec.description),
            "inputSchema": spec.inputSchema,
            "annotations": .object(["readOnlyHint": .bool(spec.readOnly)])
        ])
    }

    // MARK: - tools/call

    private func callTool(params: [String: JSONValue]) -> JSONValue {
        guard let name = params["name"]?.stringValue else {
            return toolError(AgentError(
                code: .invalidArguments,
                message: "tools/call arrived without a tool name",
                remedy: "Send params.name as one of the proctor_* tool names from tools/list."))
        }
        guard ToolCatalogue.spec(named: name) != nil else {
            return toolError(AgentError(
                code: .invalidArguments,
                message: "no such tool: \(name)",
                remedy: "Call tools/list; the tools are \(ToolCatalogue.all.map(\.name).joined(separator: ", "))."))
        }

        let arguments = params["arguments"] ?? .object([:])
        let client = SocketClient()
        defer { client.disconnect() }

        do {
            let response = try client.send(AgentRequest(id: UUID().uuidString,
                                                        tool: name,
                                                        arguments: arguments))
            if response.ok {
                return toolSuccess(response.result ?? .object([:]))
            }
            return toolError(response.error ?? AgentError(
                code: .internalError,
                message: "the agent reported failure without an error",
                remedy: "Run proctor_doctor, and check ~/Library/Logs/Proctor/agent.log."))
        } catch let error as AgentError {
            return toolError(error)
        } catch {
            return toolError(AgentError(
                code: .internalError,
                message: "the call to the agent failed: \(error)",
                remedy: "Run `proctor-shim status`, then check ~/Library/Logs/Proctor/agent.log."))
        }
    }

    private func toolSuccess(_ value: JSONValue) -> JSONValue {
        // structuredContent is defined as an object; a bare scalar or array from
        // a tool is boxed rather than dropped.
        let structured: JSONValue = value.objectValue == nil ? .object(["value": value]) : value
        return .object([
            "content": .array([.object(["type": .string("text"), "text": .string(render(value))])]),
            "isError": .bool(false),
            "structuredContent": structured
        ])
    }

    /// The consumer is a model. An error it cannot act on is an error it retries
    /// forever, so the text leads with the remedy rather than the mechanism.
    private func toolError(_ error: AgentError) -> JSONValue {
        var message = error.message
        var remedy = error.remedy ?? "No remedy is recorded for this error."

        if error.code == .agentUnavailable {
            message = """
                the Proctor agent is not answering at \(Wire.socketPath). \
                Proctor is either not installed or not loaded, so no tool call can succeed until \
                that is fixed. Retrying will not help.
                """
            remedy = """
                Run `proctor-shim install` in a terminal. It installs and loads the launchd user \
                agent. Then grant Accessibility and Screen Recording to Proctor in System \
                Settings > Privacy & Security — both are granted to Proctor itself, not to this \
                MCP server or its host. Confirm with `proctor-shim status` or the proctor_doctor \
                tool.
                """
        }

        var text = """
            proctor: \(message)

            Code: \(error.code.rawValue)
            Fix:  \(remedy)
            """
        if let detail = error.detail {
            text += "\n\nDetail: \(render(detail))"
        }

        var structured: [String: JSONValue] = [
            "code": .string(error.code.rawValue),
            "message": .string(message),
            "remedy": .string(remedy)
        ]
        if let detail = error.detail { structured["detail"] = detail }

        return .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(true),
            "structuredContent": .object(structured)
        ])
    }

    // MARK: - Encoding

    private func render(_ value: JSONValue) -> String {
        if case .string(let s) = value { return s }
        guard let data = try? prettyEncoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "<unrenderable result>"
        }
        return text
    }

    private func result(id: JSONValue, _ value: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": value])
    }

    private func errorResponse(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(["code": .number(Double(code)), "message": .string(message)])
        ])
    }

    private func emit(_ value: JSONValue) {
        guard var data = try? encoder.encode(value) else {
            shimLog("could not encode a response")
            return
        }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}

private extension Data {
    var trimmedIsEmpty: Bool {
        allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D || $0 == 0x0A }
    }
}
