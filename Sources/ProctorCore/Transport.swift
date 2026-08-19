import Foundation

// Length-prefixed JSON framing over a Unix domain socket. Four-byte big-endian
// length, then payload. Newline framing loses to newlines inside captured UI
// text, which is exactly the payload this carries.

public struct FrameCodec: Sendable {
    public init() {}

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count <= Wire.maxFrameBytes else {
            throw AgentError(code: .internalError,
                             message: "frame of \(body.count) bytes exceeds the \(Wire.maxFrameBytes) byte limit",
                             remedy: "Reduce maxNodes or maxDepth, or request a diff with sinceRevision.")
        }
        var out = Data(capacity: body.count + 4)
        var be = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
        out.append(body)
        return out
    }

    /// Incremental reader: feed bytes, pull whole frames.
    public final class Reader {
        private var buffer = Data()
        public init() {}

        public func feed(_ data: Data) { buffer.append(data) }

        public func next() throws -> Data? {
            guard buffer.count >= 4 else { return nil }
            let length = buffer.prefix(4).withUnsafeBytes {
                UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
            }
            guard length <= UInt32(Wire.maxFrameBytes) else {
                throw AgentError(code: .internalError,
                                 message: "declared frame length \(length) exceeds the limit",
                                 remedy: "The stream is out of sync; reconnect.")
            }
            guard buffer.count >= 4 + Int(length) else { return nil }
            let body = buffer.subdata(in: 4..<(4 + Int(length)))
            buffer.removeSubrange(0..<(4 + Int(length)))
            return body
        }
    }
}

// MARK: - Socket client

/// Blocking client used by the shim. Deliberately simple: the shim holds no
/// permissions, keeps no state, and does nothing but forward.
public final class SocketClient {
    private var fd: Int32 = -1
    private let reader = FrameCodec.Reader()
    public let path: String

    public init(path: String = Wire.socketPath) { self.path = path }

    public var isConnected: Bool { fd >= 0 }

    public func connect() throws {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else {
            throw AgentError(code: .agentUnavailable, message: "could not create a socket",
                             remedy: "This is a local resource failure; retry.")
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(s)
            throw AgentError(code: .internalError, message: "socket path is too long: \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, size) }
        }
        guard rc == 0 else {
            close(s)
            throw AgentError(
                code: .agentUnavailable,
                message: "the Proctor agent is not answering at \(path)",
                remedy: "Run `proctor-shim install` to install and load the agent, then `proctor_doctor` to confirm it is ready.")
        }
        fd = s
    }

    /// PRO-0074. Open a watch and read pushed frames until the agent closes or
    /// `stop` returns true.
    ///
    /// The connection is held rather than reopened per frame: `send` opens a
    /// socket, asks, reads and closes, which is right for a tool call and wrong
    /// for supervision. A surface that reopened per frame would be polling with
    /// extra steps.
    public func watch(_ onFrame: (SupervisionFrame) throws -> Bool) throws {
        if !isConnected { try connect() }
        let request = AgentRequest(id: UUID().uuidString,
                                   tool: SupervisionFrame.watchTool,
                                   arguments: .object([:]))
        try writeAll(try FrameCodec.encode(request))
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            while let body = try reader.next() {
                let response = try JSONDecoder().decode(AgentResponse.self, from: body)
                if let error = response.error { throw error }
                guard let result = response.result,
                      let payload = try? JSONEncoder().encode(result),
                      let frame = try? JSONDecoder().decode(SupervisionFrame.self, from: payload)
                else { continue }
                if try onFrame(frame) { return }
            }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 {
                throw AgentError(
                    code: .agentUnavailable,
                    message: "the agent closed the supervision stream",
                    remedy: "Check the agent with `proctor doctor`.")
            }
            reader.feed(Data(chunk[0..<n]))
        }
    }

    private func writeAll(_ frame: Data) throws {
        try frame.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 {
                    throw AgentError(code: .agentUnavailable,
                                     message: "the connection to the agent closed while sending",
                                     remedy: "Check the agent with `proctor doctor`.")
                }
                sent += n
            }
        }
    }

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        if !isConnected { try connect() }
        let frame = try FrameCodec.encode(request)
        try frame.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 {
                    throw AgentError(code: .agentUnavailable,
                                     message: "the connection to the agent closed while sending",
                                     remedy: "Check the agent with `proctor_doctor`.")
                }
                sent += n
            }
        }
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            if let body = try reader.next() {
                return try JSONDecoder().decode(AgentResponse.self, from: body)
            }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 {
                throw AgentError(code: .agentUnavailable,
                                 message: "the connection to the agent closed while waiting for a reply",
                                 remedy: "Check the agent with `proctor_doctor`.")
            }
            reader.feed(Data(chunk[0..<n]))
        }
    }

    public func disconnect() {
        if fd >= 0 { close(fd); fd = -1 }
    }

    deinit { disconnect() }
}
