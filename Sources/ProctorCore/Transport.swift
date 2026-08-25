import Foundation

// Length-prefixed JSON framing over a Unix domain socket. Four-byte big-endian
// length, then payload. Newline framing loses to newlines inside captured UI
// text, which is exactly the payload this carries.

/// Stop a write to a closed peer from killing the process.
///
/// A Unix-domain write to a socket whose far end has gone raises SIGPIPE, and
/// the default disposition for SIGPIPE is to terminate. Measured 2026-08-25 on
/// this machine: a two-write probe against a listener that accepts and closes
/// exits **141** — 128 + 13 — with no error returned and nothing written
/// anywhere. For `proctor-shim` that means an agent dying mid-write takes the
/// MCP server with it: the host sees its server vanish, the caller gets no
/// `agentUnavailable`, and no audit record is written because the process is
/// already gone.
///
/// `SO_NOSIGPIPE` turns it into `EPIPE` on the call, which every send path here
/// already handles as "the connection closed while sending". Set per socket
/// rather than by installing a process-wide `SIG_IGN` handler: a library has no
/// business changing a signal disposition its host may depend on, and a shim
/// embedded in someone else's process is exactly that case.
@discardableResult
public func proctorSuppressSIGPIPE(_ fd: Int32) -> Int32 {
    var on: Int32 = 1
    return setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
}

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

    /// Seconds to wait on a send or a reply, or 0 to wait indefinitely.
    ///
    /// Zero is the default and is what the shim needs: a tool call carries a
    /// batch that can legitimately run for minutes, and a bound here would
    /// abort the run rather than the wait. A caller that is polling sets one,
    /// because an agent that holds the socket and never answers is the case a
    /// closed connection does not cover. Measured 2026-08-19: with the agent
    /// stopped by SIGSTOP a poll sat in `read` past 25 seconds while the status
    /// window went on showing Ready.
    public var ioTimeoutSeconds: Int = 0

    /// How a bound is asked for, told to the client rather than timed by a caller.
    ///
    /// The bound here is not a timer this type runs — it is a socket option, and
    /// the kernel holds it. `setsockopt(SO_RCVTIMEO/SO_SNDTIMEO)` *is* the
    /// mechanism, the way `ScreenRecordingProbe.timer` is the bound arm rather
    /// than a detail of it, so that call is the thing worth injecting.
    ///
    /// Injectable because otherwise the only way to ask "was the bound applied?"
    /// is to time a send, and a stopwatch measures the machine. The test that did
    /// that read `#expect(waited < 10)` around a 1-second bound: an assertion
    /// with nine seconds of slack in it, which passes on a healthy machine
    /// whatever the client does and fails on a loaded one whatever the client
    /// does. With the applier told to the client, a test watches the kernel be
    /// asked for `ioTimeoutSeconds` and reads no clock at all. REQ-056, DEF-106.
    ///
    /// The bound itself does not move. `seconds` is whatever `ioTimeoutSeconds`
    /// is set to, and nothing here changes what a caller chose.
    public typealias BoundApplier = @Sendable (_ fd: Int32, _ option: Int32, _ seconds: Int) -> Int32

    /// The real one. A spy in a test forwards to this after recording, so the
    /// bound a test asserts about is the bound the run actually got.
    public static let liveBound: BoundApplier = { fd, option, seconds in
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        return setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private let applyBound: BoundApplier

    public init(path: String = Wire.socketPath,
                applyBound: @escaping BoundApplier = SocketClient.liveBound) {
        self.path = path
        self.applyBound = applyBound
    }

    public var isConnected: Bool { fd >= 0 }

    public func connect() throws {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        if s >= 0 { proctorSuppressSIGPIPE(s) }
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
        applyIOTimeout()
    }

    /// A wedged peer is not a closed one. `connect` succeeds against a stopped
    /// process because the listener is still bound, so only a receive timeout
    /// distinguishes "answering slowly" from "never answering".
    private func applyIOTimeout() {
        guard ioTimeoutSeconds > 0 else { return }
        _ = applyBound(fd, SO_RCVTIMEO, ioTimeoutSeconds)
        _ = applyBound(fd, SO_SNDTIMEO, ioTimeoutSeconds)
    }

    /// Whether a short read or write was the timeout expiring rather than the
    /// peer closing. The two need different messages: one is a wedged agent, the
    /// other is a gone one.
    private func expired(_ n: Int) -> Bool {
        guard ioTimeoutSeconds > 0, n < 0 else { return false }
        return errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT
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
                if expired(n) {
                    throw AgentError(
                        code: .agentUnavailable,
                        message: "the Proctor agent did not accept a request within \(ioTimeoutSeconds)s",
                        remedy: "The agent is running but not answering. Restart it with `launchctl kickstart -k gui/$(id -u)/app.fledgeling.procter.agent`.")
                }
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
            if expired(n) {
                throw AgentError(
                    code: .agentUnavailable,
                    message: "the Proctor agent did not answer within \(ioTimeoutSeconds)s",
                    remedy: "The agent is running but not answering. Restart it with `launchctl kickstart -k gui/$(id -u)/app.fledgeling.procter.agent`.")
            }
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
