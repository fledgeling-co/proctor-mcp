import Foundation
import ProctorCore

/// The Unix domain socket the shim connects to. One malformed frame is a fact
/// about one connection, never about the server: a client that desynchronises
/// its stream loses its own connection and nothing else.
final class Server: @unchecked Sendable {

    private let dispatcher: Dispatcher
    let path: String

    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var stopping = false

    /// How long a reply may take to be accepted by the client before the
    /// connection is given up on. Generous, because a large capture payload on a
    /// slow reader is normal; finite, because the alternative is a thread parked
    /// for the life of the process.
    static let replyDeadlineSeconds = 30

    init(dispatcher: Dispatcher, path: String = Wire.socketPath) {
        self.dispatcher = dispatcher
        self.path = path
    }

    // MARK: - Lifecycle

    func start() throws {
        signal(SIGPIPE, SIG_IGN)

        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // A socket left behind by a crashed agent would make bind fail with
        // EADDRINUSE even though nothing is listening.
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Server.errno("socket") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw AgentError(code: .internalError, message: "socket path is too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, size) }
        }
        guard bound == 0 else { close(fd); throw Server.errno("bind \(path)") }
        guard listen(fd, 16) == 0 else { close(fd); unlink(path); throw Server.errno("listen") }

        // The socket carries every privileged operation this agent can perform,
        // so only the owning user may connect to it.
        guard chmod(path, 0o600) == 0 else {
            close(fd); unlink(path)
            throw Server.errno("chmod 0600 \(path)")
        }

        lock.lock(); listenFD = fd; stopping = false; lock.unlock()

        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "app.fledgeling.procter.accept"
        thread.stackSize = 512 * 1024
        thread.start()
    }

    func stop() {
        lock.lock()
        stopping = true
        let fd = listenFD
        listenFD = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    static func unlinkSocket(at path: String = Wire.socketPath) {
        unlink(path)
    }

    private static func errno(_ what: String) -> AgentError {
        AgentError(code: .internalError,
                   message: "\(what) failed: \(String(cString: strerror(Darwin.errno)))",
                   remedy: "Another agent may already own \(Wire.socketPath). Stop it, or unload the "
                         + "launchd job \(Wire.agentLabel), and try again.")
    }

    // MARK: - Accept

    private var isStopping: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopping
    }

    private func acceptLoop(_ fd: Int32) {
        while !isStopping {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if Darwin.errno == EINTR { continue }
                if isStopping { break }
                // The listening socket is unusable; there is nothing to retry.
                break
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            // A reply nobody is reading is abandoned rather than held for ever.
            // A caller that died with its window full leaves `send` blocking on a
            // connection thread that will never come back, and with the queue in
            // place that thread may also be holding a lane. A dead socket errors
            // immediately; this is for the one that is merely gone.
            var replyDeadline = timeval(tv_sec: Server.replyDeadlineSeconds, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &replyDeadline,
                       socklen_t(MemoryLayout<timeval>.size))

            // Who this is, read from the kernel's view of the process on the
            // other end and never from anything the client sends. Read here,
            // once, while the socket is open: the peer is only knowable from an
            // accepted fd.
            let identity = SessionIdentity.fromPeer(of: client)

            let worker = Thread { [weak self] in self?.serve(client, as: identity) }
            worker.name = "app.fledgeling.procter.conn"
            worker.stackSize = 1024 * 1024
            worker.start()
        }
    }

    // MARK: - One connection

    private func serve(_ fd: Int32, as identity: RunSessionIdentity) {
        defer { close(fd) }
        let reader = FrameCodec.Reader()
        var chunk = [UInt8](repeating: 0, count: 65536)

        while true {
            let n = read(fd, &chunk, chunk.count)
            if n < 0 && Darwin.errno == EINTR { continue }
            if n <= 0 { return }
            reader.feed(Data(chunk[0..<n]))

            while true {
                let body: Data?
                do {
                    body = try reader.next()
                } catch {
                    // The length prefix is nonsense, so the stream cannot be
                    // resynchronised. Drop this connection and keep serving.
                    return
                }
                guard let body else { break }
                let response = respond(to: body, as: identity)
                guard write(frame: response, to: fd) else { return }
            }
        }
    }

    private func respond(to body: Data, as identity: RunSessionIdentity) -> AgentResponse {
        let request: AgentRequest
        do {
            request = try JSONDecoder().decode(AgentRequest.self, from: body)
        } catch {
            return AgentResponse(
                id: Server.salvagedID(from: body),
                ok: false,
                error: AgentError(code: .invalidArguments,
                                  message: "the request frame is not a valid AgentRequest: \(error)",
                                  remedy: "Send {id, tool, arguments}."))
        }
        return dispatchBlocking(request, as: identity)
    }

    /// A frame that failed to decode may still carry a usable id, and a reply
    /// the client can correlate is worth more than a well-formed one it cannot.
    private static func salvagedID(from body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let id = object["id"] as? String else { return "unknown" }
        return id
    }

    /// Each connection owns a dedicated thread, not a cooperative one, so
    /// blocking it on the actor is legal and keeps the read loop sequential —
    /// which is what the wire protocol promises.
    private func dispatchBlocking(_ request: AgentRequest,
                                  as identity: RunSessionIdentity) -> AgentResponse {
        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        let dispatcher = self.dispatcher
        Task.detached {
            // The session's name is bound for the whole of one request. A
            // task-local rides every actor hop the request makes, so the run that
            // eventually joins the queue knows whose it is without the identity
            // ever becoming an argument on the wire — which is the one place a
            // client could have named itself as somebody else.
            let response = await SessionIdentity.$current.withValue(identity) {
                await dispatcher.handle(request)
            }
            box.set(response)
            semaphore.signal()
        }
        semaphore.wait()
        return box.take() ?? AgentResponse(
            id: request.id, ok: false,
            error: AgentError(code: .internalError, message: "the handler produced no response"))
    }

    private func write(frame response: AgentResponse, to fd: Int32) -> Bool {
        let data: Data
        do {
            data = try FrameCodec.encode(response)
        } catch {
            // Usually the response exceeded the frame limit. Reply with the
            // error itself rather than closing on the client silently.
            let fallback = AgentResponse(
                id: response.id, ok: false,
                error: (error as? AgentError)
                    ?? AgentError(code: .internalError, message: "could not encode the response: \(error)"))
            guard let recovery = try? FrameCodec.encode(fallback) else { return false }
            return writeAll(recovery, to: fd)
        }
        return writeAll(data, to: fd)
    }

    private func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var sent = 0
            while sent < raw.count {
                let n = send(fd, base.advanced(by: sent), raw.count - sent, 0)
                if n < 0 && Darwin.errno == EINTR { continue }
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }
}

/// A one-shot handoff from the dispatch task back to the blocked connection
/// thread.
private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AgentResponse?

    func set(_ response: AgentResponse) {
        lock.lock(); value = response; lock.unlock()
    }

    func take() -> AgentResponse? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
