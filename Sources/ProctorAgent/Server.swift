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
        // A write to a peer that has gone raises SIGPIPE, whose default
        // disposition is to terminate. See proctorSuppressSIGPIPE.
        if fd >= 0 { proctorSuppressSIGPIPE(fd) }
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
            // The accepted side is the one the agent writes replies down, and a
            // shim that hangs up while a long batch is running is ordinary, so it
            // must not take the agent with it.
            //
            // Measured on Darwin 25.6.0 (DEF-342): an accepted descriptor DOES
            // inherit SO_NOSIGPIPE from its listener, on AF_UNIX and AF_INET
            // alike, so the call below is redundant on this platform. It stays
            // because inheritance is a platform behaviour rather than a promise
            // — Linux has no SO_NOSIGPIPE and wants MSG_NOSIGNAL per send — and
            // because socket_signal_census.py cannot tie an accept() back to the
            // socket() that produced its listener across a function boundary, so
            // requiring the option at both sites is what makes that check
            // decidable. An earlier version of this comment asserted the opposite
            // and nothing had measured it.
            if client >= 0 { proctorSuppressSIGPIPE(client) }
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
                // PRO-0074. A watch is the one request that does not answer and
                // stop. The connection is held and frames are pushed until the
                // client goes away, because a supervision surface that polls
                // shows stale state exactly when a run is moving fastest — the
                // moment somebody is deciding whether to press Stop.
                if let request = try? JSONDecoder().decode(AgentRequest.self, from: body),
                   request.tool == SupervisionFrame.watchTool {
                    watch(fd, id: request.id)
                    return
                }
                // PRO-0074. Pause, Resume and Stop from a supervision client
                // reach the same `RunControl.shared` the HUD panel writes and
                // the run loop reads. One latch, not two: a Stop that halted
                // only the runs a remote client knew about would be a kill
                // switch with a blind spot, which is worse than none.
                if let request = try? JSONDecoder().decode(AgentRequest.self, from: body),
                   request.tool == SupervisionControl.tool {
                    let response = SupervisionControl.perform(request)
                    guard write(frame: response, to: fd) else { return }
                    continue
                }
                let response = respond(to: body, as: identity)
                guard write(frame: response, to: fd) else { return }
            }
        }
    }

    /// Hold this connection open and push supervision frames down it.
    ///
    /// Runs on the connection's own dedicated thread, so blocking here costs
    /// nothing but this client. A watcher that has gone away is noticed on its
    /// next failed write rather than by being asked, because a client over SSH
    /// disappears without saying so.
    private func watch(_ fd: Int32, id: String) {
        let queue = DispatchQueue(label: "proctor.watch.\(fd)")
        let closed = WatchLatch()
        let gate = DispatchSemaphore(value: 0)
        let registration = SupervisionBroadcast.shared.add { [weak self] frame in
            queue.async {
                guard let self, !closed.isClosed else { return }
                guard let payload = try? JSONEncoder().encode(frame),
                      let value = try? JSONDecoder().decode(JSONValue.self, from: payload) else {
                    return
                }
                if !self.write(frame: AgentResponse(id: id, ok: true, result: value), to: fd) {
                    closed.close()
                    gate.signal()
                }
            }
        }
        defer { SupervisionBroadcast.shared.remove(registration.id) }
        if let current = registration.current,
           let payload = try? JSONEncoder().encode(current),
           let value = try? JSONDecoder().decode(JSONValue.self, from: payload) {
            guard write(frame: AgentResponse(id: id, ok: true, result: value), to: fd) else {
                return
            }
        }
        // The client never sends again on a watch connection, so a read of 0 is
        // it closing. Whichever happens first — a failed write or a closed
        // read — ends the watch.
        let reader = DispatchQueue(label: "proctor.watch.read.\(fd)")
        reader.async {
            var byte = [UInt8](repeating: 0, count: 1)
            while true {
                let n = read(fd, &byte, 1)
                if n < 0 && Darwin.errno == EINTR { continue }
                if n <= 0 { break }
            }
            closed.close()
            gate.signal()
        }
        gate.wait()
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
/// A one-way flag saying this watch is over. One-way on purpose: a watch that
/// could reopen would write to a descriptor the connection loop has closed.
private final class WatchLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func close() { lock.lock(); value = true; lock.unlock() }
}

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
