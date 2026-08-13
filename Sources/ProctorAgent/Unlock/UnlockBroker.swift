import Foundation
import Darwin
import Security
import os

/// Shared state: is an unlock turn open and authorized right now?
///
/// A turn is opened by an authenticated `proctor_unlock` call, carries a short
/// TTL so a crashed client cannot leave the door open, and is closed on relock
/// or when the caller ends it. The broker reads `authorized()` and nothing
/// else — the whole security decision is "did a real Proctor turn ask for
/// this, and is it still live".
final class UnlockTurn: @unchecked Sendable {
    static let shared = UnlockTurn()
    private let lock = NSLock()
    private var openUntil: Date?

    // Observable evidence that the login-path mechanism actually reached the
    // broker. os_log from a launchd agent is not reliably visible, so the
    // handshake records itself here where `proctor_unlock status` can read it —
    // this is how a locked test proves the plugin ran without watching a screen.
    private var lastContact: Date?
    private var lastReply: String?
    private var lastPeerVerified: Bool?
    private var contactCount = 0

    /// Open (or extend) a turn. Kept short; the coordinator re-opens per unlock
    /// rather than holding one for a whole session.
    func open(ttl: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        openUntil = Date().addingTimeInterval(ttl)
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        openUntil = nil
    }

    func authorized() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let until = openUntil else { return false }
        if Date() >= until { openUntil = nil; return false }
        return true
    }

    func recordContact(peerVerified: Bool, reply: String) {
        lock.lock(); defer { lock.unlock() }
        lastContact = Date()
        lastReply = reply
        lastPeerVerified = peerVerified
        contactCount += 1
    }

    struct ContactInfo: Sendable {
        var lastContact: Date?
        var lastReply: String?
        var lastPeerVerified: Bool?
        var contactCount: Int
    }

    func contactInfo() -> ContactInfo {
        lock.lock(); defer { lock.unlock() }
        return ContactInfo(lastContact: lastContact, lastReply: lastReply,
                           lastPeerVerified: lastPeerVerified, contactCount: contactCount)
    }
}

/// The socket the authorization mechanism talks to.
///
/// The mechanism runs inside the system authorization host and connects here to
/// ask whether an unlock is authorized. This end verifies the peer really is a
/// platform binary anchored to Apple — i.e. the authorization host, not some
/// local process impersonating it — and answers ALLOW only when a turn is live.
/// Everything is fail-closed: a peer that fails the requirement, or no live
/// turn, gets DENY.
final class UnlockBroker: @unchecked Sendable {
    static let socketDir = "/tmp/app.fledgeling.procter"
    static let socketPath = "\(socketDir)/unlock.sock"

    private let log = Logger(subsystem: "app.fledgeling.procter", category: "unlock-broker")
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "app.fledgeling.procter.unlock-broker")

    func start() {
        queue.async { [weak self] in self?.run() }
    }

    private func run() {
        // The directory is world-traversable on purpose: the authorization host
        // runs as _securityagent and has to reach the socket. The security is
        // the peer check below, never the path permissions — exactly the point
        // the research said to get right.
        try? FileManager.default.createDirectory(
            atPath: Self.socketDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])
        unlink(Self.socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { log.error("socket() failed errno=\(errno)"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                Self.socketPath.withCString { src in strncpy(dst, src, 103) }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else { log.error("bind() failed errno=\(errno)"); close(fd); return }
        // 0666 so the host can connect; peer-auth is the gate, not the mode.
        chmod(Self.socketPath, 0o666)
        guard listen(fd, 8) == 0 else { log.error("listen() failed errno=\(errno)"); close(fd); return }
        listenFD = fd
        log.log("unlock broker listening on \(Self.socketPath, privacy: .public)")

        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { if errno == EINTR { continue }; break }
            handle(client)
        }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        var tv = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard peerIsAuthorizationHost(client) else {
            _ = "DENY\n".withCString { send(client, $0, 5, 0) }
            UnlockTurn.shared.recordContact(peerVerified: false, reply: "DENY")
            log.error("unlock broker: peer failed the platform requirement — denied")
            return
        }
        // Drain the request line; its content does not matter, the turn state does.
        var buf = [UInt8](repeating: 0, count: 64)
        _ = recv(client, &buf, buf.count, 0)

        let allowed = UnlockTurn.shared.authorized()
        let reply = allowed ? "ALLOW\n" : "DENY\n"
        _ = reply.withCString { send(client, $0, strlen($0), 0) }
        UnlockTurn.shared.recordContact(peerVerified: true, reply: allowed ? "ALLOW" : "DENY")
        log.log("unlock broker: \(reply.trimmingCharacters(in: .newlines), privacy: .public)")
    }

    /// The connecting process must be a platform binary anchored to Apple. When
    /// our mechanism runs, it is hosted inside the system authorization host,
    /// which satisfies this; a random local process does not.
    private func peerIsAuthorizationHost(_ fd: Int32) -> Bool {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        let rc = withUnsafeMutablePointer(to: &token) {
            getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, $0, &len)
        }
        guard rc == 0, len == socklen_t(MemoryLayout<audit_token_t>.size) else { return false }
        let data = Data(bytes: &token, count: Int(len))
        let attrs = [kSecGuestAttributeAudit: data] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(
                "anchor apple" as CFString, [], &req) == errSecSuccess,
              let req else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
