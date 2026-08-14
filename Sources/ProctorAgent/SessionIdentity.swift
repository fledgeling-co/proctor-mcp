import Foundation
import Darwin
import ProctorCore

// Who is on the other end of the socket, and why the answer is not asked for.
//
// The label a person reads in the run HUD decides whose agent they stop. A
// connection that could name itself could name itself as somebody else's
// project in the very UI used to make that decision, so nothing here reads the
// request: the identity comes from the process behind the socket, which is
// readable without being told.
//
// A pid is not an answer to "which session is this". `LOCAL_PEERPID` gives the
// process; `PROC_PIDVNODEPATHINFO` gives its working directory, whose last
// component is the project a person recognises — `diolog-web`, `armada`,
// `proctor-mcp`. Four characters of a hash of the process and its start time
// separate two sessions in the same repo.
//
// WHY THE PROCESS AND NOT THE CONNECTION. `MCPServer.callAgent` opens a fresh
// socket for every single tool call and closes it again
// (`let client = SocketClient(); defer { client.disconnect() }`), so a
// per-connection id would rename a session on every call and the waiting cap
// would count nothing. The shim *process* lives as long as the MCP client does,
// which is exactly the lifetime a session name should have.
//
// The start time is in the key as well as the pid because pids are reused: a new
// client that inherited a dead one's pid would otherwise inherit its waiting
// allowance and its name.
//
// WHAT THIS IS NOT. It is not an authorisation boundary, and nothing should ever
// be granted on the strength of it. The socket is `chmod 0600` and every caller
// is already the owning user; identity here decides what a person reads on the
// panel and which allowance a waiting run counts against. That is why a peer the
// kernel will not describe gets a plain name rather than a refusal — refusing
// would break the agent for a client whose `proc_pidinfo` is denied, in exchange
// for hardening a boundary that is not load-bearing.

enum SessionIdentity {

    /// Set for the whole of one request, inside the task that dispatches it, so
    /// every method the request reaches can read it without the identity ever
    /// becoming a parameter on the wire or on six call sites.
    ///
    /// Read it at a run's entry point, on the dispatching task. A task-local
    /// rides actor hops but does not reach a detached task or a `deinit`, so a
    /// run records its identity once at the top rather than looking it up later.
    @TaskLocal static var current: RunSessionIdentity = .unattributed

    /// Read the peer off an accepted socket. Every failure path lands on the
    /// unattributed identity rather than throwing: an unreadable peer is a
    /// session that gets a plain name, never a call that is refused.
    static func fromPeer(of fd: Int32) -> RunSessionIdentity {
        guard let pid = peerPID(fd) else { return .unattributed }
        let started = startTime(of: pid)
        let project = projectName(for: pid) ?? "unknown"
        let key = "\(pid):\(UInt64(started))"
        return RunSessionIdentity(project: project,
                                  connection: shortID(key),
                                  key: key)
    }

    /// The process on the other end of a Unix domain socket, as the kernel
    /// reports it — not as the peer claims.
    static func peerPID(_ fd: Int32) -> pid_t? {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else {
            return nil
        }
        return pid
    }

    /// The peer's working directory, reduced to its last component. A path is
    /// what the client already tells macOS about itself, and the folder it runs
    /// in is the name a person uses for the work.
    static func projectName(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let read = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, Int32(size))
        }
        guard read == Int32(size) else { return nil }
        let raw = info.pvi_cdir.vip_path
        let capacity = MemoryLayout.size(ofValue: raw)
        let path = withUnsafePointer(to: raw) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        return name(fromDirectory: path)
    }

    /// The last component of a path, with the shapes that carry no information
    /// stripped: a client sitting at `/` or in a home directory has no project
    /// name to give.
    static func name(fromDirectory path: String) -> String? {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        let component = (trimmed as NSString).lastPathComponent
        guard !component.isEmpty, component != "/", component != "." else { return nil }
        return component
    }

    /// When the process started, so a reused pid is a different session.
    static func startTime(of pid: pid_t) -> Double {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let read = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(size))
        }
        guard read == Int32(size) else { return 0 }
        return Double(info.pbi_start_tvsec)
    }

    /// Four hex characters, derived and stable. Short enough to sit beside the
    /// project name on one line, which is the only job it has — the scheduler
    /// judges identity on the full key, so a collision here costs a moment's
    /// confusion and never somebody else's waiting allowance.
    static func shortID(_ key: String) -> String {
        let digest = Canonical.hash(key)
        return String(digest.prefix(4))
    }
}

public extension RunSessionIdentity {
    /// What a client whose process cannot be read is called. Named rather than
    /// blank: an empty label in the HUD reads as a bug in the panel.
    static let unattributed = RunSessionIdentity(project: "unknown session",
                                                 connection: "----",
                                                 key: "unattributed")
}
