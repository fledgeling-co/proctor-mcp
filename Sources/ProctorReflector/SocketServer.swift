#if DEBUG || PROCTOR_REFLECTOR

import Darwin
import Foundation

/// A Unix domain socket server on its own queue. Accept and per-connection reads
/// block on background threads; the main thread is only ever entered from the
/// handler, and never waited on from it.
final class SocketServer: @unchecked Sendable {
    typealias Handler = @Sendable (JSONValue) -> JSONValue

    let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "app.fledgeling.procter.reflector",
                                      qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var stopped = false

    /// More than a handful of simultaneous inspectors is a bug in the caller, not
    /// a workload to scale for.
    private static let maxConnections = 4

    init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    // MARK: - Lifecycle

    func start() {
        sweepDeadSockets()

        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        // A write to a peer that has gone raises SIGPIPE, whose default
        // disposition is to terminate. The Reflector is embedded in somebody
        // else's application, so taking that process down over a dropped
        // debugging socket is the worst version of this fault.
        if fd >= 0 {
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        }
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, Int32(Self.maxConnections)) == 0 else {
            close(fd)
            unlink(path)
            return
        }
        chmod(path, 0o600)

        lock.lock()
        listenFD = fd
        stopped = false
        lock.unlock()

        queue.async { [weak self] in self?.acceptLoop(fd) }
    }

    func stop() {
        lock.lock()
        stopped = true
        let fd = listenFD
        listenFD = -1
        lock.unlock()

        // Closing the listening descriptor is what unblocks accept(). Live
        // connections notice on their next read, so stop() never waits on a
        // worker — which is what keeps it safe to call from the main thread.
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    // MARK: - Accept

    private func acceptLoop(_ fd: Int32) {
        while !isStopped {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            // This is the descriptor `serve` writes down. It inherits
            // SO_NOSIGPIPE from the listener above on Darwin — measured, DEF-342
            // — so this is belt and braces rather than a fix, kept for the same
            // two reasons as `Server.swift`: inheritance is a platform behaviour,
            // and the source census cannot pair an accept() with its listener.
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            queue.async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        let reader = Frame.Reader()
        var chunk = [UInt8](repeating: 0, count: 65536)

        while !isStopped {
            var handled = false
            do {
                while let body = try reader.next() {
                    handled = true
                    let request = (try? JSONDecoder().decode(JSONValue.self, from: body)) ?? .null
                    let response = handler(request)
                    guard writeAll(fd, try Frame.encode(response)) else { return }
                }
            } catch {
                let failure = JSONValue.object(["id": .string(""), "ok": .bool(false),
                                                "result": .null, "error": .string("\(error)")])
                if let data = try? Frame.encode(failure) { _ = writeAll(fd, data) }
                return
            }
            if handled { continue }

            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                reader.feed(Data(chunk[0..<n]))
            } else if n == 0 || errno != EINTR {
                return
            }
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 {
                    if errno == EINTR { continue }
                    return false
                }
                sent += n
            }
            return true
        }
    }

    // MARK: - Discovery hygiene

    /// The agent finds reflectors by scanning this directory for
    /// `reflector-<pid>.sock`, so a socket file left behind by a crashed process
    /// is a false advertisement. Clearing the dead ones on start keeps the
    /// discovery contract honest.
    private func sweepDeadSockets() {
        let directory = (path as NSString).deletingLastPathComponent
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        for entry in entries where entry.hasPrefix("reflector-") && entry.hasSuffix(".sock") {
            let digits = entry.dropFirst("reflector-".count).dropLast(".sock".count)
            guard let pid = Int32(digits), pid != ProcessInfo.processInfo.processIdentifier else { continue }
            if kill(pid, 0) != 0 && errno == ESRCH {
                unlink("\(directory)/\(entry)")
            }
        }
    }
}

#endif
