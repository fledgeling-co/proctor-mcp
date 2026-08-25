import Foundation
import Testing
@testable import ProctorCore

/// A real listener on a private path, driven into the states a wedged agent
/// actually produces.
///
/// PRO-0140, PRO-0141 and PRO-0145 all ask for the same thing from different
/// angles: what the client does when the other end of the socket stops
/// behaving. A fake transport cannot answer it — the interesting failures are
/// the kernel's, not the protocol's — so this fixture binds a real
/// `AF_UNIX` socket, accepts on a background thread, and can be told to answer
/// correctly, answer late, answer with rubbish, or hang up mid-frame.
///
/// The leak half is measured by SCALING rather than by an exact count. A first
/// version compared `openDescriptorCount()` either side of each call and failed
/// at 13 against 5: Swift Testing runs suites in parallel, so a process-wide
/// descriptor count moves under a test for reasons that have nothing to do with
/// it. A leak is monotonic in the number of calls and parallel noise is not, so
/// the sound question is whether the delta scales with the iteration count.
final class ChaosListener: @unchecked Sendable {

    enum Behaviour: Sendable {
        /// Accept, read the request, write a well-formed response.
        case answer
        /// Accept and close immediately, before a byte is written.
        case hangUpOnAccept
        /// Write a four-byte length header and then close, so the reader is
        /// left waiting for a body that never comes.
        case truncateMidFrame
        /// Write bytes that are not a frame at all.
        case rubbish
        /// Accept and never write. The caller's own bound is the only way out.
        case silence
    }

    let path: String
    private var listenFD: Int32 = -1
    private let behaviour: Behaviour
    private var thread: Thread?
    private let accepted = NSCountedSet()
    private let lock = NSLock()

    init(behaviour: Behaviour) throws {
        self.behaviour = behaviour
        // A path under the per-test temporary directory, short enough for
        // sun_path — a long TMPDIR is a real cause of a bind failure that reads
        // as "the agent is down".
        self.path = "/tmp/proctor-chaos-\(UInt32.random(in: 0..<0xFFFFFF)).sock"
        try bind()
    }

    private func bind() throws {
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw Failure("socket() refused") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw Failure("path too long for sun_path")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listenFD, $0, size) }
        }
        guard ok == 0 else { throw Failure("bind() refused: \(errno)") }
        guard Darwin.listen(listenFD, 4) == 0 else { throw Failure("listen() refused") }
        chmod(path, 0o600)

        let t = Thread { [weak self] in self?.serve() }
        t.stackSize = 512 * 1024
        t.start()
        thread = t
    }

    private func serve() {
        while true {
            let client = Darwin.accept(listenFD, nil, nil)
            if client < 0 { return }
            lock.lock(); accepted.add("c"); lock.unlock()
            switch behaviour {
            case .hangUpOnAccept:
                close(client)
            case .rubbish:
                var junk = Array("not a frame at all".utf8)
                _ = write(client, &junk, junk.count)
                close(client)
            case .truncateMidFrame:
                // A header promising 4 KB, then nothing.
                var be = UInt32(4096).bigEndian
                withUnsafeBytes(of: &be) { _ = write(client, $0.baseAddress, 4) }
                close(client)
            case .silence:
                // Held open deliberately: the caller's bound is what must end it.
                // Long enough to outlast a 1s bound and short enough that a
                // suite is never waiting on this thread.
                Thread.sleep(forTimeInterval: 6)
                close(client)
            case .answer:
                var buf = [UInt8](repeating: 0, count: 65536)
                _ = read(client, &buf, buf.count)
                let response = AgentResponse(id: "1", ok: true, result: .object(["pong": .bool(true)]),
                                             error: nil)
                if let frame = try? FrameCodec.encode(response) {
                    frame.withUnsafeBytes { _ = write(client, $0.baseAddress, frame.count) }
                }
                close(client)
            }
        }
    }

    var acceptCount: Int {
        lock.lock(); defer { lock.unlock() }
        return accepted.count(for: "c")
    }

    func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }
}

/// How many file descriptors this process holds. The half of a chaos test
/// nobody writes: a client that reports the right error and leaks the socket
/// has failed, and only a count taken either side of the call shows it.
///
/// Read off `/dev/fd` rather than probed. A first version walked
/// `0..<getdtablesize()` calling `fcntl` on each, and on this machine
/// `getdtablesize()` returns the soft RLIMIT_NOFILE — **1,048,576** — so every
/// call made a million syscalls and the suite appeared to hang rather than to
/// fail. The directory is exact, costs one readdir, and cannot be surprised by
/// a raised limit.
func openDescriptorCount() -> Int {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd") else {
        return -1
    }
    // The readdir holds a descriptor of its own while it runs; it is closed by
    // the time this returns, so the count is one high and consistently so.
    return entries.count
}

@Suite("Socket boundary chaos: what the client does when the far end misbehaves")
struct SocketBoundaryChaosTests {

    private func request() -> AgentRequest {
        AgentRequest(id: "1", tool: "proctor_doctor", arguments: .object([:]))
    }

    @Test("a well-behaved listener answers, and the descriptor comes back")
    func happyPathLeaksNothing() throws {
        let listener = try ChaosListener(behaviour: .answer)
        defer { listener.stop() }
        let client = SocketClient(path: listener.path)
        client.ioTimeoutSeconds = 5
        try client.connect()
        let reply = try client.send(request())
        #expect(reply.ok)
        client.disconnect()
        #expect(!client.isConnected, "disconnect left the descriptor open on the happy path")
        #expect(listener.acceptCount == 1)
    }

    /// The defect this found, before it found anything about descriptors:
    /// writing to a socket whose peer has closed raises SIGPIPE, whose default
    /// disposition is to terminate. A probe measured exit **141** — 128 + 13 —
    /// with no error returned. For `proctor-shim` that means an agent dying
    /// mid-write takes the MCP server with it, silently. `SO_NOSIGPIPE` turns it
    /// into EPIPE, which every send path already handles.
    ///
    /// This test reaches that path: the listener closes on accept, and the
    /// client writes into the corpse. Without the fix the whole test process
    /// dies here and the suite reports nothing at all, which is how it presented.
    @Test("a listener that hangs up on accept is an error, not a signal")
    func hangUpOnAccept() throws {
        let listener = try ChaosListener(behaviour: .hangUpOnAccept)
        defer { listener.stop() }
        let client = SocketClient(path: listener.path)
        client.ioTimeoutSeconds = 3
        try client.connect()
        #expect(throws: (any Error).self) { _ = try client.send(self.request()) }
        client.disconnect()
        #expect(!client.isConnected, "a connection the far end dropped stayed open here")
    }

    @Test("a frame header with no body is refused rather than waited on forever")
    func truncatedFrame() throws {
        let listener = try ChaosListener(behaviour: .truncateMidFrame)
        defer { listener.stop() }
        let client = SocketClient(path: listener.path)
        client.ioTimeoutSeconds = 2
        try client.connect()
        #expect(throws: (any Error).self) { _ = try client.send(self.request()) }
        client.disconnect()
        #expect(!client.isConnected)
    }

    @Test("bytes that are not a frame produce a structured error, not a crash")
    func rubbishPayload() throws {
        let listener = try ChaosListener(behaviour: .rubbish)
        defer { listener.stop() }
        let client = SocketClient(path: listener.path)
        client.ioTimeoutSeconds = 2
        try client.connect()
        var caught: Error?
        do { _ = try client.send(request()) } catch { caught = error }
        client.disconnect()
        #expect(caught != nil, "eighteen bytes of prose were accepted as a response")
        // It matters that this is Proctor's own error rather than a decoding
        // crash: the shim forwards the message to a model, and a fatalError here
        // takes the MCP server down with the run.
        #expect(caught is AgentError || caught is DecodingError)
    }

    @Test("a silent peer is ended by the bound the caller asked for, not by luck")
    func silentPeerHitsTheBound() throws {
        let listener = try ChaosListener(behaviour: .silence)
        defer { listener.stop() }
        // The bound is a socket option, so what is asserted is that the kernel
        // was ASKED for it — a stopwatch here would measure the machine.
        // DEF-106's subject exactly.
        nonisolated(unsafe) var asked: [(Int32, Int)] = []
        let spy: SocketClient.BoundApplier = { fd, option, seconds in
            asked.append((option, seconds))
            return SocketClient.liveBound(fd, option, seconds)
        }
        let client = SocketClient(path: listener.path, applyBound: spy)
        client.ioTimeoutSeconds = 1
        try client.connect()
        #expect(throws: (any Error).self) { _ = try client.send(self.request()) }
        client.disconnect()
        #expect(asked.contains { $0.0 == SO_RCVTIMEO && $0.1 == 1 },
                "the receive bound was never asked for, so a wedged agent would hold the shim")
        #expect(asked.contains { $0.0 == SO_SNDTIMEO && $0.1 == 1 })
    }

    @Test("a path nothing is listening on refuses by name and creates no descriptor")
    func absentPeer() throws {
        let client = SocketClient(path: "/tmp/proctor-nothing-here-\(UInt32.random(in: 0..<9999)).sock")
        var caught: AgentError?
        do { try client.connect() } catch let e as AgentError { caught = e }
        #expect(caught?.code == .agentUnavailable)
        #expect(!client.isConnected,
                "a failed connect left its socket open, which is the leak that exhausts a long run")
    }

    /// The cascade this guards is descriptor exhaustion across a long run: one
    /// leaked descriptor per refused call is invisible until the process cannot
    /// open a file, and then everything fails at once for no reason.
    ///
    /// Measured by scaling. Ten refused calls and then forty more: a leak of one
    /// descriptor per call shows as a delta four times larger for the second
    /// batch, and the parallel-suite noise that broke an exact count does not
    /// scale with the batch at all.
    @Test("a dropping peer leaks no descriptors, measured by scaling not by count")
    func repeatedFailureDoesNotExhaust() throws {
        let listener = try ChaosListener(behaviour: .hangUpOnAccept)
        defer { listener.stop() }

        func refuse(_ times: Int) -> Int {
            let before = openDescriptorCount()
            for _ in 0..<times {
                let client = SocketClient(path: listener.path)
                client.ioTimeoutSeconds = 1
                try? client.connect()
                _ = try? client.send(request())
                client.disconnect()
            }
            return openDescriptorCount() - before
        }

        let small = refuse(10)
        let large = refuse(40)
        // Both deltas can be NEGATIVE: another suite closing a file between the
        // two readings takes the process-wide count down, and a first draft of
        // this assertion compared `large <= small + 5` with small at -9 and
        // failed on noise it was written to be immune to. Growth is what a leak
        // produces, so growth is what is measured.
        let smallGrowth = max(0, small)
        let largeGrowth = max(0, large)
        #expect(smallGrowth < 10, "ten refused calls grew the table by \(smallGrowth)")
        #expect(largeGrowth < 10, "forty refused calls grew the table by \(largeGrowth)")
        // A per-call leak makes the second batch's growth about four times the
        // first's — 10 and 40. The guard is on the SLOPE, so a quiet machine
        // cannot satisfy it by accident and a busy one cannot break it.
        #expect(largeGrowth <= smallGrowth + 5,
                "growth scaled with the batch — \(smallGrowth) over 10 calls and \(largeGrowth) over 40 — which is what a per-call leak looks like")
        #expect(listener.acceptCount == 50)
    }
}
