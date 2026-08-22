import Testing
import Foundation
import Darwin
import CryptoKit
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0083. Effect witnesses for the ten external requirements no item in wave 11
// named, because `campaign.py check` prints at most twelve unwitnessed
// requirements and twelve was read as the population. The real external set is
// twenty-two, and the denominator was one `len()` away the whole time.
//
// **What a witness owes.** A recorder, an effect class and a non-zero count, plus
// the four-part causal shape: driven from a production entry point, recorded at
// the boundary, confirmed by something that is not the code under test, and
// flipped by its own sabotage. The sabotage lives inside each test body rather
// than beside it, so the arming run and the passing run are one measurement taken
// twice on one build.
//
// **One case per requirement, never one case over two.** These are different
// guarantees over shared providers — six of them over the agent's single
// `AF_UNIX` socket — and a shared case would let one guarantee's silence hide
// behind another's noise.
//
// **The lane's ceiling is the portable floor.** `dtrace` and `eslogger` need
// privilege this suite does not have. So: real child processes that are real
// front ends, real sockets answering real connections, and files read back with
// fresh descriptors. No kernel, no privilege, and none of these can pass when
// nothing runs.
//
// Serialized because W1 redirects `AuditLog`'s process-wide seams, W3 writes the
// process-wide `RunControl.shared` latch, and several bind sockets and start
// threads.

/// An Objective-C class purely so `Bundle(for:)` can name the bundle this code
/// was loaded from. `swift build --build-tests` puts `proctor-cli`,
/// `proctor-shim` and the `.xctest` bundle in one directory, so the bundle's
/// parent is where the real front ends are.
final class WitnessBundleAnchor: NSObject {}

@Suite("External effect witnesses: the ten a capped gate hid", .serialized)
struct ExternalWitnessTests {

    // MARK: - Apparatus: the product directory and the real front ends

    /// Where `swift build --build-tests` left this package's executables.
    static var productDirectory: URL {
        Bundle(for: WitnessBundleAnchor.self).bundleURL.deletingLastPathComponent()
    }

    /// A shipped front end, by the name the kernel will report for it.
    ///
    /// Absent is a FAILURE and never a skip: a check that could not run is not a
    /// check that passed, and this suite's whole subject is that the peer's
    /// executable name is what decides attribution.
    static func frontEnd(_ name: String) throws -> URL {
        let url = productDirectory.appendingPathComponent(name, isDirectory: false)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: productDirectory.path))?
            .filter { $0.hasPrefix("proctor") }.sorted().joined(separator: ", ") ?? "unreadable"
        try #require(FileManager.default.isExecutableFile(atPath: url.path),
                     "no executable \(name) in \(productDirectory.path) · holds: \(contents)")
        return url
    }

    /// What a real child process did, read from the kernel rather than from the
    /// child's own report of itself.
    struct ChildOutcome: Sendable {
        var status: Int32
        var out: String
        var err: String
        var timedOut: Bool
        var summary: String { "exit \(status)\(timedOut ? " (timed out)" : "") · \(out.prefix(160))" }
    }

    /// Run a blocking body on a `Thread` this function owns, never on a
    /// cooperative one.
    ///
    /// **This is not tidiness, it is the difference between a suite that finishes
    /// and one that does not.** Swift's cooperative pool has exactly
    /// `activeProcessorCount` threads and never grows. Everything this suite does
    /// blocks for a long time — it waits on child processes, on sockets that
    /// deliberately never answer, and on servers whose handlers are themselves
    /// `Task.detached` onto the same pool. Measured on 2026-08-21: with these
    /// waits on cooperative threads the full suite wedged at 16 of 16 threads
    /// blocked, fifteen of them inside `SecStaticCodeCheckValidity` in unrelated
    /// `Session.doctor` tests whose dispatch group could no longer be granted a
    /// worker. The same suite with these two files skipped passed in 12.5
    /// seconds, and these files alone passed in 11.4. Blocking a thread this
    /// function owns costs the pool nothing, which is the same reason
    /// `Server.dispatchBlocking` gives every connection its own `Thread`.
    static func offPool<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        let box = OutcomeBox<T>()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let worker = Thread {
                do { box.set(.success(try body())) } catch { box.set(.failure(error)) }
                continuation.resume()
            }
            worker.name = "pro83.offpool"
            worker.stackSize = 1024 * 1024
            worker.start()
        }
        // PRO-0100, DEF-140, GROUP 1 — unfailable by construction, kept.
        // Input space: the states in which this line is reached. The
        // continuation resumes only from inside the worker's `do`/`catch`, and
        // both arms call `box.set` before `resume`. There is no path that
        // reaches here with the box unwritten — a worker that never started
        // would hang rather than trap. Reason recorded in
        // docs/test-campaign/evidence/PRO-0100/unwrap-census.md.
        return try box.value!.get()
    }

    final class OutcomeBox<V>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Result<V, Error>?
        func set(_ value: Result<V, Error>) { lock.withLock { stored = value } }
        var value: Result<V, Error>? { lock.withLock { stored } }
    }

    /// Run a blocking body off the pool and report the refusal it raised, or
    /// `nil` if it did not raise one. `#expect(throws:)` cannot span an `await`.
    static func offPoolRefusal(_ body: @escaping @Sendable () throws -> Void) async -> String? {
        do { _ = try await offPool { try body(); return true }; return nil }
        catch { return (error as? AgentError)?.message ?? "\(error)" }
    }

    /// A pause that yields the thread instead of holding it.
    static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Run one front end against a private socket and wait for it, bounded.
    ///
    /// `PROCTOR_SOCKET` is read first by `Wire.socketPath`, so a child spawned
    /// here talks to the server this test bound and never to the installed agent.
    /// The async face of `driveBlocking`. Every call site uses this one: a child
    /// process lives for seconds, and a cooperative thread spent waiting on it is
    /// a thread the server answering that same child cannot have.
    @discardableResult
    static func drive(_ executable: URL, _ arguments: [String], socket: String,
                      stdin: String? = nil,
                      seconds: TimeInterval = childPatience) async throws -> ChildOutcome {
        try await offPool {
            try driveBlocking(executable, arguments, socket: socket,
                              stdin: stdin, seconds: seconds)
        }
    }

    /// How long this suite waits for a real child before killing it.
    ///
    /// Apparatus patience, not a product bound: nothing is asserted about how
    /// long the CLI takes, and a child that hits this is reported as
    /// `(timed out)` and fails the witness rather than passing quietly. It is
    /// 120 seconds because 30 was measured too short on this machine — a
    /// `proctor-cli` child at load average 589 was still starting when it
    /// expired, which cost the witness a row it otherwise never fails to get.
    /// Sizing the wait is not moving a finish line; the finish line is
    /// `status == 0` and the trail row, and neither moved.
    static let childPatience: TimeInterval = 120

    @discardableResult
    static func driveBlocking(_ executable: URL, _ arguments: [String], socket: String,
                              stdin: String? = nil,
                              seconds: TimeInterval = childPatience) throws -> ChildOutcome {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PROCTOR_SOCKET"] = socket
        process.environment = environment

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let input = Pipe()
        process.standardInput = input
        try process.run()
        if let stdin { try? input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8)) }
        try? input.fileHandleForWriting.close()

        // Drained on threads this function owns, never on the global queue: a
        // child that fills a 64K pipe buffer while the parent waits on
        // `waitUntilExit` deadlocks, so the drains are mandatory — but each one
        // blocks until the child exits, and `DispatchQueue.global()` is the same
        // libdispatch worker pool that `SecStaticCodeCheckValidity` needs a thread
        // from. Fourteen `Session.doctor` tests are inside that call at any moment
        // in this suite's neighbourhood; two blocked workers per child, over
        // fourteen children, is enough that the workqueue stops granting them one.
        let outBox = TextBox(), errBox = TextBox()
        let drains = [
            Thread { outBox.set(String(decoding: out.fileHandleForReading.readDataToEndOfFile(),
                                       as: UTF8.self)) },
            Thread { errBox.set(String(decoding: err.fileHandleForReading.readDataToEndOfFile(),
                                       as: UTF8.self)) }
        ]
        for drain in drains {
            drain.name = "pro83.drain"
            drain.stackSize = 512 * 1024
            drain.start()
        }

        let deadline = Date().addingTimeInterval(seconds)
        var timedOut = false
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning {
            timedOut = true
            process.terminate()
            usleep(200_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        // Give the drains a moment to finish now that the writer has gone.
        let drainDeadline = Date().addingTimeInterval(2)
        while (outBox.value == nil || errBox.value == nil) && Date() < drainDeadline {
            usleep(20_000)
        }
        return ChildOutcome(status: process.terminationStatus,
                            out: outBox.value ?? "", err: errBox.value ?? "",
                            timedOut: timedOut)
    }

    final class TextBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        func set(_ text: String) { lock.withLock { stored = text } }
        var value: String? { lock.withLock { stored } }
    }

    // MARK: - Apparatus: sockets and servers

    /// Short, because `sockaddr_un.sun_path` is 104 bytes and a nested temporary
    /// path overruns it.
    static func temporarySocketPath() -> String {
        "/tmp/pw83-\(UUID().uuidString.prefix(8).lowercased()).sock"
    }

    /// Tool probes that answer from this table rather than from this machine.
    ///
    /// **Not tidiness — this is what keeps the suite finishing.** The default
    /// `ToolProbes` locates the real `cua-driver` on this Mac, and
    /// `Session.doctor` then runs `SecStaticCodeCheckValidity` against it inside
    /// the session actor, on a cooperative thread. Every `proctor-cli doctor`
    /// child this suite drives makes the SERVER do that too, through
    /// `Server.dispatchBlocking`'s `Task.detached`. Measured on 2026-08-21: with
    /// fifteen unrelated `Session.doctor` tests already inside that call, one more
    /// from this suite took the cooperative pool to sixteen of sixteen and the run
    /// never came back; the same run with this suite skipped finished in 26
    /// seconds. It is also simply the right probe: a witness that a CLI call
    /// crosses a socket has no business validating a third-party binary's
    /// signature, and a test whose result depends on what is installed on the
    /// machine is not a measurement of the product.
    static func offMachineTools() -> ToolProbes {
        func absent(_ name: String) -> ToolProbe {
            ToolProbe(probe: { ToolPresence(tool: name, available: false,
                                            path: nil, searched: []) },
                      presentTTL: ToolProbe.presentTTL,
                      absentTTL: ToolProbe.presentTTL)
        }
        return ToolProbes(obscura: absent("obscura"), browserUse: absent("browser-use"),
                          simctl: absent("simctl"), cuaDriver: absent("cua-driver"),
                          maestro: absent("maestro"), lume: absent("lume"),
                          prlctl: absent("prlctl"), environment: [:])
    }

    static func makeSession(ax: FakeAX = FakeAX(bundleId: "com.fledgeling.witness"),
                            tools: ToolProbes? = nil) -> Session {
        let tools = tools ?? offMachineTools()
        return Session(ax: ax, capture: FakeCapture(), tools: tools,
                screenRecordingProbe: .fake(.granted),
                accessibilityProbe: { true },
                secureInputProbe: { false })
    }

    static func withTemporaryDirectory(_ body: (URL) async throws -> Void) async rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pro83-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    static func withTemporaryDirectory(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pro83-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    // MARK: - Apparatus: the redirected trail

    /// An in-process signer standing in for the secure element. Its own rather
    /// than borrowed from a neighbouring suite: a witness that depends on another
    /// file's nested type breaks for a reason that has nothing to do with the
    /// effect it measures.
    final class WitnessSigner: AuditSigning, AuditAnchoring, @unchecked Sendable {
        private let lock = NSLock()
        private let key = P256.Signing.PrivateKey()
        private var anchor: AuditChain.Anchor?

        var signingKeyId: String? {
            AuditChain.keyId(forPublicKey: key.publicKey.rawRepresentation)
        }
        var signingKeyClass: AuditChain.KeyClass? { .software }
        func sign(_ material: Data) -> Data? { try? key.signature(for: material).rawRepresentation }
        func verifySignature(_ signature: Data, over material: Data) -> Bool {
            guard let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
            else { return false }
            return key.publicKey.isValidSignature(parsed, for: material)
        }
        func loadAnchor() -> AuditChain.Anchor? { lock.withLock { anchor } }
        @discardableResult
        func saveAnchor(_ anchor: AuditChain.Anchor) -> Bool {
            lock.withLock { self.anchor = anchor }
            return true
        }
    }

    /// A one-way valve on a test's audit sink.
    ///
    /// **`server.stop()` is not enough, and this is why.** A child that hit its
    /// bound has already had its request dispatched, and `Server.dispatchBlocking`
    /// hands the work to a `Task.detached`. Stopping the server closes the
    /// listener and the connections; it cannot cancel a task already queued on the
    /// cooperative pool. When that task finally runs — after this test has
    /// restored `AuditLog.seams` and released `TrailIsolation` — its record lands
    /// in whatever trail is current, which is another suite's. Measured twice on
    /// 2026-08-21 at load average 589 and above: `AuditRotationTests` counting 100
    /// lines where its own cap says 99.
    ///
    /// `TrailIsolation` is mutual exclusion between HOLDERS. It cannot exclude a
    /// write from a session this test has already let go of. So the sink itself is
    /// shut, inside the redirect, before anything is restored: a late reply then
    /// writes nothing at all, and this test's own row count fails honestly rather
    /// than a neighbour's passing dishonestly.
    final class SinkGate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = true
        func close() { lock.withLock { open = false } }
        var isOpen: Bool { lock.withLock { open } }
    }

    final class ThrownBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Error?
        func set(_ error: Error) { lock.withLock { stored = error } }
        var value: Error? { lock.withLock { stored } }
    }

    /// Hold the trail for a body that never suspends.
    ///
    /// **The lock is taken, used and released without the cooperative pool being
    /// needed once**, which is the property that matters. Every other trail suite
    /// in this target blocks in `TrailIsolation.acquire()` from a cooperative
    /// thread, so a holder that suspends is a holder betting it can get a pool
    /// slot back while two of the sixteen are blocked waiting on it. Measured on
    /// 2026-08-21: it could not. The full suite with this item's two trail tests
    /// skipped passed at 1,825 tests in 20.7 seconds; with them holding the lock
    /// across an `await`, fourteen unrelated `Session.doctor` tests sat inside
    /// `SecStaticCodeCheckValidity` and the run never came back.
    ///
    /// So the async setup — building the session, setting its sink, starting the
    /// server — happens BEFORE the call, and everything inside is ordinary
    /// blocking code: child processes, sockets and file reads.
    static func withRedirectedTrailBlocking<T: Sendable>(
        _ body: @escaping @Sendable (URL, TestSealKeys) throws -> T
    ) async throws -> T {
        try await offPool {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("pro83-trail-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            TrailIsolation.acquire()
            let keys = TestSealKeys()
            let signer = WitnessSigner()
            let previousSigner = AuditLog.seams.signer
            let previousAnchors = AuditLog.seams.anchors
            let previousKeys = AuditLog.seams.keys
            AuditLog.seams.directory = dir
            AuditLog.seams.signer = signer
            AuditLog.seams.anchors = signer
            AuditLog.seams.keys = keys
            defer {
                AuditLog.seams.directory = nil
                AuditLog.seams.signer = previousSigner
                AuditLog.seams.anchors = previousAnchors
                AuditLog.seams.keys = previousKeys
                try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                       ofItemAtPath: dir.path)
                try? FileManager.default.removeItem(at: dir)
                TrailIsolation.release()
            }
            return try body(dir, keys)
        }
    }

    /// Every sealed record on the trail, opened with ProctorCore's seal and the
    /// injected private half.
    ///
    /// Read with a FRESH `FileHandle` and never through `AuditLog.readTrail` or
    /// `openedTail`, which are the reader under test confirming itself — the exact
    /// shape this repo shipped once as DEF-019.
    static func openedTrail(at directory: URL, keys: TestSealKeys) throws -> [String] {
        let trail = directory.appendingPathComponent("audit.jsonl", isDirectory: false)
        guard FileManager.default.fileExists(atPath: trail.path) else { return [] }
        let handle = try FileHandle(forReadingFrom: trail)
        defer { try? handle.close() }
        let bytes = try handle.readToEnd() ?? Data()
        let text = String(decoding: bytes, as: UTF8.self)
        guard let priv = keys.privateKey() else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { AuditSeal.open(String($0), with: priv) }
    }

    /// The `via` field of every opened record, in order. `nil` for a record that
    /// carries none, which is the answer for a peer the kernel does not name as a
    /// shipped front end.
    static func attributions(in records: [String]) -> [String?] {
        records.map { line -> String? in
            guard let data = line.data(using: .utf8),
                  let record = try? JSONDecoder().decode(AuditRecord.self, from: data)
            else { return nil }
            return record.via
        }
    }

    // MARK: - W1 · REQ-035 · ipc · which front end called, read from the peer

    /// What three real front ends left behind, in a shape that can leave the
    /// thread that held the trail.
    struct DrivenTrail: Sendable {
        var cli: ChildOutcome
        var mcp: ChildOutcome
        var forger: ForgedCall
        var records: [String]
    }

    /// What one forging peer got back, in a shape that can leave the thread that
    /// held the trail.
    struct ForgedCall: Sendable {
        var answered = false
        var ok = false
        var sent = ""
        /// Where the forging peer stopped, for a failure that has to name a
        /// cause. Diagnostic only: nothing asserts on it.
        var stage = "unstarted"
        /// Wall-clock seconds the peer spent in `read`, so a bound that was hit
        /// is distinguishable from a socket that answered nothing.
        var readSeconds: Double = 0
    }

    /// The MCP front end's real job, as one stdio conversation.
    static func mcpConversation(bundleId: String) -> String {
        let initialise = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"pro83-witness","version":"1"}}}"#
        let call = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"proctor_policy","arguments":{"action":"approve","bundleId":"\#(bundleId)","ttlMs":1000}}}"#
        return initialise + "\n" + call + "\n"
    }

    /// One request from a peer that is neither shipped front end, carrying an
    /// explicit `via` inside the request object the server decodes.
    ///
    /// The peer is THIS PROCESS. `proc_pidpath` reports `proctor-mcpPackageTests`
    /// for it, which `SessionIdentity.frontEnd(named:)` maps to nil, so it is a
    /// third peer in exactly the sense the requirement is about — and no binary
    /// is launched to get it.
    ///
    /// A launched imposter was the first shape of this arm and it does not
    /// survive the full suite. A hard link at a fresh path is still a first
    /// launch for `syspolicyd`, and this suite runs beside seven wiring suites
    /// that put fifteen of the sixteen cooperative threads inside
    /// `SecStaticCodeCheckValidity` at once. Measured 2026-08-21: the imposter
    /// took 0.1s with this test run alone and overran a 120-second bound in the
    /// full run, twice, deterministically. DEF-044.
    ///
    /// `AgentRequest` carries three fields — id, tool, arguments — and `via` is
    /// not among them, so this puts the ask at the top level of the very object
    /// the server decodes. That is a stronger ask than the CLI can make: a
    /// `--via` flag is not a flag `proctor-cli` parses, so it never reaches the
    /// wire at all.
    static func forgeBlocking(path: String, bundleId: String) -> ForgedCall {
        var call = ForgedCall()
        let body = """
            {"id":"w35-forged","tool":"proctor_policy","via":"cli",\
            "arguments":{"action":"approve","bundleId":"\(bundleId)","ttlMs":1000}}
            """
        call.sent = body
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { call.stage = "socket(errno \(Darwin.errno))"; return call }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, size)
            }
        }
        guard rc == 0 else { call.stage = "connect(errno \(Darwin.errno))"; return call }
        var bound = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &bound, socklen_t(MemoryLayout<timeval>.size))
        let payload = Data(body.utf8)
        var frame = Data(capacity: payload.count + 4)
        var declared = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &declared) { frame.append(contentsOf: $0) }
        frame.append(payload)
        // PRO-0100, DEF-140, GROUP 1 — unfailable by construction, kept.
        // Input space: every value `frame` can hold here. The four length-prefix
        // bytes are appended unconditionally two lines up, so `frame` is never
        // empty, and `baseAddress` is nil only for an empty buffer.
        let sent = frame.withUnsafeBytes { raw in write(fd, raw.baseAddress!, raw.count) }
        guard sent == frame.count else {
            call.stage = "write(\(sent) of \(frame.count), errno \(Darwin.errno))"
            return call
        }
        var chunk = [UInt8](repeating: 0, count: 16384)
        let began = Date()
        let read = Darwin.read(fd, &chunk, chunk.count)
        call.readSeconds = Date().timeIntervalSince(began)
        guard read > 4 else {
            call.stage = "read(\(read) bytes, errno \(Darwin.errno), after \(String(format: "%.1f", call.readSeconds))s)"
            return call
        }
        call.stage = "answered"
        call.answered = true
        if let decoded = try? JSONDecoder().decode(AgentResponse.self,
                                                   from: Data(chunk[4..<read])) {
            call.ok = decoded.ok
        }
        return call
    }

    @Test("REQ-035 effect witness: the trail names the front end the kernel saw, not the one the request claimed")
    func theTrailNamesTheRealFrontEnd() async throws {
        let cli = try Self.frontEnd("proctor-cli")
        let shim = try Self.frontEnd("proctor-shim")

        // --- The witness -----------------------------------------------------
        // The session, its sink and the server are built BEFORE the trail is
        // held. Everything held under `TrailIsolation` below is blocking code on
        // a thread this test owns, so the lock never waits on a pool slot.
        let path = Self.temporarySocketPath()
        let session = Self.makeSession()
        await session.setDrawsHUD(false)
        // The PRODUCTION write path. The seam is the test-process interlock in
        // `Session.auditSink`, not the write: `AuditLog.append` still seals,
        // chains, signs and lands the bytes with Darwin open/write/fsync.
        let gate = SinkGate()
        await session.setAuditSink { record in
            guard gate.isOpen else { return }
            _ = AuditLog.append(record)
        }
        let server = Server(dispatcher: Dispatcher(session: session), path: path)
        defer { server.stop() }
        try server.start()
        #expect(FileManager.default.fileExists(atPath: path), "bind left no socket at \(path)")

        let drives = try await Self.withRedirectedTrailBlocking { directory, keys -> DrivenTrail in
            // THE SERVER IS STOPPED INSIDE THE REDIRECT, at the end of this
            // closure. A child that hit its bound has already had its request
            // dispatched, and the reply audits through `AuditLog.append` whenever
            // the session actor gets to it. If that lands after the seams are
            // restored it writes whatever trail is current — which, measured on
            // 2026-08-21 at load average 589, was `AuditRotationTests`'s, and
            // showed up there as a line count one too high. `TrailIsolation` is
            // mutual exclusion between HOLDERS; it cannot exclude a write from a
            // server this test left running after it let go — so the sink is shut
            // first, and shutting it is what actually makes a late reply harmless.
            defer { gate.close(); server.stop() }
            // Front end one: the operator CLI, its own executable, its own name.
            let fromCLI = try Self.driveBlocking(cli, ["policy", "--action", "approve",
                                                       "--bundleId", "com.fledgeling.w35-cli",
                                                       "--ttlMs", "1000"], socket: path)

            // Front end two: the MCP shim, speaking MCP over its stdio, which is
            // the whole of its real job.
            let fromMCP = try Self.driveBlocking(
                shim, ["serve"], socket: path,
                stdin: Self.mcpConversation(bundleId: "com.fledgeling.w35-mcp"))

            // Front end three: a peer neither shipped front end owns, ASKING to
            // be recorded as the CLI — the security clause, and the reason this
            // requirement is worth a witness at all. Same socket, same tool, same
            // arguments as the CLI's call above; the one difference is who the
            // kernel says is on the other end.
            let forger = Self.forgeBlocking(path: path,
                                            bundleId: "com.fledgeling.w35-forged")

            // The recorder: the bytes on disk, opened with the seal, read before
            // the redirect is undone.
            return DrivenTrail(cli: fromCLI, mcp: fromMCP, forger: forger,
                               records: try Self.openedTrail(at: directory, keys: keys))
        }

        #expect(drives.cli.status == 0,
                "the CLI front end reported \(drives.cli.summary) · \(drives.cli.err)")
        #expect(drives.mcp.out.contains("\"id\":2"),
                "the shim answered nothing for the call · \(drives.mcp.summary)")
        #expect(drives.forger.answered,
                "the forging peer stopped at \(drives.forger.stage) sending \(drives.forger.sent)")
        #expect(drives.forger.ok,
                "the forging peer's call was refused, so it left no row to read")

        let records = drives.records
        let seen = Self.attributions(in: records)
        let named = seen.compactMap { $0 }
        #expect(records.count >= 3,
                "three front ends drove the socket and \(records.count) records reached the disk")

        // Every `via` here was produced by `SessionIdentity.frontEnd(for:)` from
        // `proc_pidpath` of the pid `getsockopt(SOL_LOCAL, LOCAL_PEERPID)` gave
        // for the accepted descriptor. None of it was on the wire.
        let cliRows = records.filter { $0.contains("com.fledgeling.w35-cli") }
        let mcpRows = records.filter { $0.contains("com.fledgeling.w35-mcp") }
        let forgedRows = records.filter { $0.contains("com.fledgeling.w35-forged") }
        #expect(Self.attributions(in: cliRows) == ["cli"],
                "the CLI's row reads \(Self.attributions(in: cliRows))")
        #expect(Self.attributions(in: mcpRows) == ["mcp"],
                "the shim's row reads \(Self.attributions(in: mcpRows))")
        // The security clause. A request asking to be recorded as the CLI is
        // recorded as nothing, because the field is not readable from a request.
        #expect(Self.attributions(in: forgedRows) == [String?.none],
                "a request claimed a front end and got it: \(Self.attributions(in: forgedRows))")
        #expect(named.count >= 2, "\(named.count) rows named a front end")

        // --- The sabotage ----------------------------------------------------
        // Unlink the socket between bind and the children. Nothing connects, no
        // descriptor is accepted, no peer is read, and the trail holds nothing.
        let deadPath = Self.temporarySocketPath()
        let deadSession = Self.makeSession()
        await deadSession.setDrawsHUD(false)
        let deadGate = SinkGate()
        await deadSession.setAuditSink { record in
            guard deadGate.isOpen else { return }
            _ = AuditLog.append(record)
        }
        let deadServer = Server(dispatcher: Dispatcher(session: deadSession), path: deadPath)
        defer { deadServer.stop() }
        try deadServer.start()
        #expect(unlink(deadPath) == 0, "the socket could not be unlinked")

        let sabotage = try await Self.withRedirectedTrailBlocking { directory, keys -> (ChildOutcome, Int) in
            defer { deadGate.close(); deadServer.stop() }
            let dead = try Self.driveBlocking(cli, ["policy", "--action", "approve",
                                                    "--bundleId", "com.fledgeling.w35-cli",
                                                    "--ttlMs", "1000"], socket: deadPath)
            return (dead, try Self.openedTrail(at: directory, keys: keys).count)
        }
        // Exit 3 is `CLISurface.Exit.agentUnreachable`: nothing was measured.
        #expect(sabotage.0.status == CLISurface.Exit.agentUnreachable.rawValue,
                "the CLI reported \(sabotage.0.summary)")
        #expect(sabotage.1 == 0,
                "\(sabotage.1) records reached a trail no connection was accepted for")
    }

    // MARK: - W2 · REQ-034 · ipc · the operator CLI on the agent's socket

    /// What the server read off each accepted descriptor.
    ///
    /// Server-side, and no `onAccept` seam is added: a hook the product fires is
    /// the product logging its own accept. `SessionIdentity.fromPeer` asks the
    /// kernel and binds the answer as a task-local for the request, so an injected
    /// probe that fires inside the request records what the server saw.
    final class PeerLog: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [RunSessionIdentity] = []
        func record(_ identity: RunSessionIdentity) { lock.withLock { seen.append(identity) } }
        var identities: [RunSessionIdentity] { lock.withLock { seen } }
        var count: Int { lock.withLock { seen.count } }
    }

    static func makeServer(at path: String, log: PeerLog,
                           screenRecording: ScreenRecordingProbe = .fake(.granted),
                           ax: FakeAX = FakeAX(bundleId: "com.fledgeling.witness"))
    -> (Server, Session) {
        let session = Session(ax: ax, capture: FakeCapture(),
                              tools: offMachineTools(),
                              screenRecordingProbe: screenRecording,
                              accessibilityProbe: {
                                  log.record(SessionIdentity.current)
                                  return true
                              },
                              secureInputProbe: { false })
        return (Server(dispatcher: Dispatcher(session: session), path: path), session)
    }

    @Test("REQ-034 effect witness: real CLI children earn real exit codes over a real socket")
    func theOperatorCLIEarnsItsExitCodesOverTheSocket() async throws {
        let cli = try Self.frontEnd("proctor-cli")

        // The specification half. `CLISurface.verbs` is derived from
        // `ToolCatalogue`, never listed by hand, so a tool without a verb is a red
        // test rather than a gap somebody notices later. This is the claim the
        // measurement below is checked against — it is not itself the measurement.
        #expect(CLISurface.verbs.count == ToolCatalogue.all.count)
        #expect(CLISurface.verbs.count == 21,
                "the catalogue derives \(CLISurface.verbs.count) verbs, not 21")
        #expect(CLISurface.Exit.allCases.count == 6)

        var codes: [String: Int32] = [:]

        // --- The witness -----------------------------------------------------
        let path = Self.temporarySocketPath()
        let log = PeerLog()
        let (server, session) = Self.makeServer(at: path, log: log)
        defer { server.stop() }
        await session.setDrawsHUD(false)
        try server.start()

        // Three doctor calls. `proctor_doctor` is what makes the server's injected
        // accessibility probe fire, so these are the requests the server records
        // having answered — three children, three accepted descriptors, three
        // kernel-read peers.
        for _ in 0..<3 { codes["ok"] = try await Self.drive(cli, ["doctor"], socket: path).status }
        // ok, again through a gated verb.
        codes["okPolicy"] = try await Self.drive(cli, ["policy", "--action", "approve",
                                           "--bundleId", "com.fledgeling.w34",
                                           "--ttlMs", "1000"], socket: path).status
        // usage — a verb the catalogue does not derive.
        codes["usage"] = try await Self.drive(cli, ["notaverb"], socket: path).status
        // reflectorUnavailable — `proctor_inspect` against a target with no
        // reflector in it.
        codes["reflector"] = try await Self.drive(cli, ["inspect", "--window", "win-1"],
                                            socket: path).status
        // verdictFailed — an assertion the fake window does not satisfy.
        codes["verdictFailed"] = try await Self.drive(
            cli, ["assert", "--window", "win-1", "--kind", "text",
                  "--text", "a string this window does not contain"], socket: path).status
        // An actuating verb over the same socket. It was originally preceded by a
        // `policy --action configure --block` to reach `refused` (4), and that
        // configure IS NOT MADE, for a reason worth naming rather than dropping:
        // `PolicyStore` has no test seam. `configurePolicy` calls
        // `PolicyStore.save`, which writes
        // ~/Library/Application Support/app.fledgeling.procter/policy/policy.json —
        // the OPERATOR'S real file, not a redirected one. Measured on 2026-08-21:
        // this test created that file with `block: ["com.fledgeling.witness"]`,
        // and PRO-0077's REQ-015 witness then failed across the whole process
        // with `policyDenied`, in a run where this suite was skipped, because the
        // block had outlived it on disk. Recorded as DEF-042 rather than worked
        // around by choosing a different bundle id, because `configure` replaces
        // the whole block set and the contamination is the write, not the value.
        codes["actNoHandle"] = try await Self.drive(
            cli, ["act", "--window", "win-1",
                  "--steps", #"[{"kind":"key","key":"escape"}]"#], socket: path).status

        // notReady — a grant this agent does not hold. Its own server, because the
        // probe is fixed at construction and the arm is about what the agent
        // answers when a capability is missing rather than about policy.
        let deniedPath = Self.temporarySocketPath()
        let deniedLog = PeerLog()
        let (deniedServer, deniedSession) = Self.makeServer(at: deniedPath, log: deniedLog,
                                                            screenRecording: .fake(.denied))
        defer { deniedServer.stop() }
        await deniedSession.setDrawsHUD(false)
        try deniedServer.start()
        codes["notReady"] = try await Self.drive(cli, ["capture", "--window", "win-1"],
                                           socket: deniedPath).status

        // The completion script, generated by a real child from the same
        // catalogue rather than read out of this process.
        let completion = try await Self.drive(cli, ["completion", "--shell", "zsh"], socket: path)
        #expect(completion.status == 0)
        for verb in CLISurface.allVerbNames {
            #expect(completion.out.contains(verb),
                    "the generated completion omits \(verb)")
        }

        // The server counted what it answered. A reply cannot arrive on a
        // descriptor the accept loop never took.
        let answered = log.count
        #expect(answered == 3, "the server answered \(answered) of 3 doctor requests from real CLI children")
        let mine = ProcessInfo.processInfo.processIdentifier
        #expect(log.identities.allSatisfy { $0.frontEnd == "cli" },
                "a peer was not read as the CLI: \(log.identities.map { $0.frontEnd ?? "nil" })")
        #expect(log.identities.allSatisfy { !$0.key.hasPrefix("\(mine):") },
                "a peer identity names THIS process, so no child made the call")

        // --- The sabotage ----------------------------------------------------
        server.stop()
        let deadPath = Self.temporarySocketPath()
        let dead = try await Self.drive(cli, ["policy", "--action", "approve",
                                        "--bundleId", "com.fledgeling.w34",
                                        "--ttlMs", "1000"], socket: deadPath)
        codes["agentUnreachable"] = dead.status
        #expect(dead.status == CLISurface.Exit.agentUnreachable.rawValue,
                "with no socket the CLI reported \(dead.summary)")

        // Every code came off a real child, read through `waitpid` rather than out
        // of the child's own report of itself.
        let distinct = Set(codes.values)
        #expect(distinct.count >= 4,
                "real children produced \(distinct.count) distinct exit codes: \(codes.sorted { $0.key < $1.key })")
        // What was NOT produced from a child, said out loud rather than left as a
        // number that reads as six. `refused` (4) and `notReady` (5) both sit
        // behind a resolved window handle, and a handle is minted per session by
        // an attach the child would have to perform first — so every gated arm
        // here failed at handle resolution and mapped to `verdictFailed`. The
        // policy gate itself is additionally unreachable from this lane at all,
        // because driving it writes the operator's real policy file: DEF-042. The
        // six-code surface is carried by `CLISurface.Exit.allCases` and the pure
        // `exit(for:)` mapping, which is a different rung from this one.
        #expect(Set([CLISurface.Exit.ok, .verdictFailed, .usage, .agentUnreachable]
                    .map(\.rawValue)) == distinct,
                "the codes real children produced were \(distinct.sorted())")
        #expect(codes["ok"] == CLISurface.Exit.ok.rawValue, "ok arm: \(codes)")
        #expect(codes["usage"] == CLISurface.Exit.usage.rawValue, "usage arm: \(codes)")
    }

    // MARK: - W3 · REQ-029 · ipc · an operator watches and halts, with no window server

    final class FrameSink: @unchecked Sendable {
        private let lock = NSLock()
        private var frames: [SupervisionFrame] = []
        private var failure: String?
        func append(_ frame: SupervisionFrame) { lock.withLock { frames.append(frame) } }
        func fail(_ reason: String) { lock.withLock { failure = reason } }
        var count: Int { lock.withLock { frames.count } }
        var reason: String? { lock.withLock { failure } }
    }

    /// Hold a `watch` open on a thread of its own. `SocketClient.watch` blocks in
    /// `read()` until the agent closes, so it must never run on a cooperative
    /// thread — the same reason `Server.dispatchBlocking` gives every connection
    /// its own `Thread`.
    static func startWatch(at path: String, wanted: Int, sink: FrameSink) -> Thread {
        let worker = Thread {
            let client = SocketClient(path: path)
            defer { client.disconnect() }
            do {
                try client.watch { frame in
                    sink.append(frame)
                    return sink.count >= wanted
                }
            } catch {
                sink.fail((error as? AgentError)?.message ?? "\(error)")
            }
        }
        worker.name = "pro83.watch"
        worker.stackSize = 1024 * 1024
        worker.start()
        return worker
    }

    /// Poll by yielding rather than by holding the thread. `usleep` on a
    /// cooperative thread keeps the thread; `Task.sleep` hands it back.
    static func waitUntil(_ seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            await pause(0.02)
        }
        return await condition()
    }

    @Test("REQ-029 effect witness: frames reach a remote watcher over the socket, and a halt over it moves the one latch")
    func anOperatorWatchesAndHaltsOverTheSocket() async throws {
        // The latch is process-wide and this is the one test in the wave that
        // writes it over a socket, because `Server.serve` routes `proctor.control`
        // to `SupervisionControl.perform(request)` with its DEFAULT control — and
        // the default is the claim. Read, restore, and assert the restore.
        let stoppedBefore = RunControl.shared.isStopped
        let pausedBefore = RunControl.shared.isPaused
        defer {
            // `begin(run:)` is the product's own reset: it clears `stopped`,
            // `pausedByPerson` and the run's yields under one lock.
            if !stoppedBefore && !pausedBefore { RunControl.shared.begin(run: Int.max) }
        }
        try #require(!stoppedBefore, "the latch was already stopped before this test ran")

        // --- The witness -----------------------------------------------------
        let path = Self.temporarySocketPath()
        let log = PeerLog()
        let (server, session) = Self.makeServer(at: path, log: log)
        defer { server.stop() }
        await session.setDrawsHUD(false)
        try server.start()

        let sink = FrameSink()
        let watcher = Self.startWatch(at: path, wanted: 3, sink: sink)

        // Publish real frames through the product's own broadcaster until the
        // remote watcher has them. Pushed, never polled: a supervision surface
        // that polled would show stale state exactly when a run is moving fastest.
        var published = 0
        _ = await Self.waitUntil(10) {
            SupervisionBroadcast.shared.publish(
                SupervisionFrame(at: Date().timeIntervalSince1970,
                                 run: SupervisionFrame.Run(summary: "witness run",
                                                           held: false, seconds: 1,
                                                           machine: "this Mac"),
                                 lanes: [], queueHeld: false, waiting: 0))
            published += 1
            await Self.pause(0.06)
            return sink.count >= 3
        }
        #expect(sink.reason == nil, "the watch failed: \(sink.reason ?? "")")
        #expect(sink.count >= 3,
                "\(published) frames were published and \(sink.count) crossed the socket")

        // The halt, over a second real connection.
        let reply = try await Self.offPool { () -> AgentResponse in
            let control = SocketClient(path: path)
            defer { control.disconnect() }
            try control.connect()
            return try control.send(AgentRequest(id: "w3-stop",
                                                 tool: SupervisionControl.tool,
                                                 arguments: .object(["action": .string("stop")])))
        }
        #expect(reply.ok, "the control was refused: \(reply.error?.message ?? "")")
        #expect(reply.result?["stopped"]?.boolValue == true)
        // The recorder for the halt is neither the client nor the transport: it is
        // the latch the run loop reads and the HUD panel writes.
        #expect(RunControl.shared.isStopped,
                "a stop crossed the socket and the run loop's latch did not move")
        _ = await Self.waitUntil(5) { watcher.isFinished || sink.count >= 3 }
        RunControl.shared.begin(run: Int.max)
        #expect(!RunControl.shared.isStopped, "the latch was not restored")

        // --- The sabotage ----------------------------------------------------
        server.stop()
        let deadPath = Self.temporarySocketPath()
        let deadSink = FrameSink()
        _ = Self.startWatch(at: deadPath, wanted: 3, sink: deadSink)
        _ = await Self.waitUntil(3) { deadSink.reason != nil }
        SupervisionBroadcast.shared.publish(
            SupervisionFrame(at: Date().timeIntervalSince1970, run: nil,
                             lanes: [], queueHeld: false, waiting: 0))
        await Self.pause(0.2)
        #expect(deadSink.count == 0,
                "\(deadSink.count) frames crossed a socket nothing was listening on")
        #expect(deadSink.reason != nil, "the watch of an absent agent reported no reason")

        let deadConnect = await Self.offPoolRefusal {
            let deadControl = SocketClient(path: deadPath)
            defer { deadControl.disconnect() }
            try deadControl.connect()
        }
        #expect(deadConnect != nil,
                "connect() succeeded against a path nothing is bound to")
        #expect(!RunControl.shared.isStopped, "the latch moved with no agent to move it")
    }

    // MARK: - W4 · REQ-033 · ipc · readiness, switches and history, not only run and queue

    @Test("REQ-033 effect witness: a supervision client reads readiness, switches and history off the socket")
    func aSupervisionClientReadsMoreThanRunAndQueue() async throws {
        // The trail is redirected because `proctor_history` projects the trail,
        // and this must never read or write the operator's own. The session and
        // the server are built BEFORE it is held: everything under the lock below
        // is blocking socket code on a thread this test owns, so holding it never
        // waits on a cooperative slot two other trail suites are already blocked
        // for.
        let path = Self.temporarySocketPath()
        let log = PeerLog()
        let (server, session) = Self.makeServer(at: path, log: log)
        defer { server.stop() }
        await session.setDrawsHUD(false)
        let gate = SinkGate()
        await session.setAuditSink { record in
            guard gate.isOpen else { return }
            _ = AuditLog.append(record)
        }
        try server.start()

        let exchange = try await Self.withRedirectedTrailBlocking { _, _ -> [AgentResponse] in
            // Shut inside the redirect, for the reason `SinkGate` spells out: a
            // reply that audits after the seams are restored writes another
            // suite's trail.
            defer { gate.close(); server.stop() }
            // Something for the history pane to project. Driven through the
            // socket, so what lands on the trail arrives the way a real call does.
            let client = SocketClient(path: path)
            defer { client.disconnect() }
            try client.connect()
            for index in 0..<3 {
                _ = try client.send(AgentRequest(
                    id: "w4-seed-\(index)", tool: "proctor_policy",
                    arguments: .object(["action": .string("approve"),
                                        "bundleId": .string("com.fledgeling.w33-\(index)"),
                                        "ttlMs": .number(1000)])))
            }
            // The TUI's own two calls, in the TUI's own order.
            return [
                try client.send(AgentRequest(id: "w4-doctor", tool: "proctor_doctor",
                                             arguments: .object([:]))),
                try client.send(AgentRequest(id: "w4-history", tool: "proctor_history",
                                             arguments: .object(["limit": .number(20)])))
            ]
        }
        let report = try #require(exchange[0].result, "proctor_doctor answered nothing")
        let runs = try #require(exchange[1].result, "proctor_history answered nothing")

        // The three projections the requirement names, over bytes that came off
        // the socket rather than out of this process's own session object.
        let readiness = TUISurface.readiness(from: report)
        let switches = TUISurface.switches(from: report)
        let projected = TUISurface.history(from: runs)

        #expect(!readiness.grants.isEmpty, "readiness drew \(readiness.grants.count) grants")
        #expect(!readiness.lanes.isEmpty, "readiness drew \(readiness.lanes.count) lanes")
        #expect(!switches.isEmpty, "switches drew \(switches.count) rows")
        #expect(!projected.rows.isEmpty,
                "history drew \(projected.rows.count) rows, unreadable \(projected.unreadable)")

        let sections = [readiness.grants.count, readiness.lanes.count,
                        switches.count, projected.rows.count]
        #expect(sections.allSatisfy { $0 > 0 },
                "a supervision client read \(sections) across grants, lanes, switches, history")

        // --- The sabotage ------------------------------------------------
        // The same three projections over a refusal. Zero rows everywhere, and
        // an empty projection is then a measurement rather than a default.
        let refusal = JSONValue.object(["error": .string("the agent refused")])
        #expect(TUISurface.readiness(from: refusal).grants.isEmpty)
        #expect(TUISurface.readiness(from: refusal).lanes.isEmpty)
        #expect(TUISurface.switches(from: refusal).isEmpty)
        #expect(TUISurface.history(from: refusal).rows.isEmpty)
    }

    // MARK: - W5 · REQ-027 · ipc · a socket that accepts and never answers

    /// A listener that binds, accepts and deliberately never writes.
    ///
    /// Not the code under test: forty lines of `Darwin` in the test, so a client
    /// blocking here is blocking on the kernel's socket buffer rather than on
    /// anything Proctor decided.
    final class StallingListener: @unchecked Sendable {
        let path: String
        private let lock = NSLock()
        private var listenFD: Int32 = -1
        private var accepted: [Int32] = []
        private var stopped = false

        init(path: String) { self.path = path }

        var acceptedCount: Int { lock.withLock { accepted.count } }

        func start() throws {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw AgentError(code: .internalError, message: "no socket") }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
            withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
            let size = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, size)
                }
            }
            guard bound == 0, listen(fd, 8) == 0 else {
                close(fd); unlink(path)
                throw AgentError(code: .internalError, message: "bind/listen failed")
            }
            lock.withLock { listenFD = fd }
            let worker = Thread { [weak self] in
                while let self, !self.lock.withLock({ self.stopped }) {
                    let client = accept(fd, nil, nil)
                    if client < 0 { break }
                    // Accepted and held. Nothing is ever written back, which is
                    // exactly the state a SIGSTOPped agent leaves behind.
                    self.lock.withLock { self.accepted.append(client) }
                }
            }
            worker.name = "pro83.stall"
            worker.start()
        }

        func stop() {
            let fd: Int32 = lock.withLock {
                stopped = true
                for client in accepted { close(client) }
                accepted.removeAll()
                let f = listenFD
                listenFD = -1
                return f
            }
            if fd >= 0 { close(fd) }
            unlink(path)
        }
    }

    /// Connect and ask, with a receive bound applied by the CALLER.
    ///
    /// The bound is the test's own `SO_RCVTIMEO` and not the product's. On this
    /// branch `SocketClient.send` blocks in `read()` for ever: the opt-in
    /// `ioTimeoutSeconds` that bounds the status window's poll landed in commit
    /// `10285df` on `main`, and this item's base `ai/wave-9` is eight commits
    /// behind it and does not carry it. So what this measures is the BOUNDARY —
    /// that a held socket is a real state distinct from an absent one — and the
    /// product's own remedy is recorded as unavailable on this base rather than
    /// asserted as present.
    static func askWithBound(path: String, seconds: Int) async -> (connected: Bool, answered: Bool) {
        // A bound of `seconds` spent on a cooperative thread is `seconds` the
        // server answering the two-way arm cannot be scheduled in.
        ((try? await offPool { askWithBoundBlocking(path: path, seconds: seconds) })
            ?? (false, false))
    }

    static func askWithBoundBlocking(path: String, seconds: Int) -> (connected: Bool, answered: Bool) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return (false, false) }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, size)
            }
        }
        guard rc == 0 else { return (false, false) }
        var bound = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &bound, socklen_t(MemoryLayout<timeval>.size))
        guard let frame = try? FrameCodec.encode(
            AgentRequest(id: "w5", tool: "proctor_doctor", arguments: .object([:])))
        else { return (true, false) }
        // PRO-0100, DEF-140, GROUP 1 — unfailable by construction, kept, and for
        // a DIFFERENT reason from the site above, which is why it is written out
        // rather than cross-referenced. `frame` here comes from
        // `FrameCodec.encode` (Sources/ProctorCore/Transport.swift:10-22) behind
        // a `try?`/`else return`, not from a local append. The guarantee is the
        // encoder's: it prepends four length bytes before appending the body, so
        // every Data it returns is at least four bytes and `baseAddress` is
        // never nil. The first draft of this census claimed "same construction"
        // and an out-of-family review caught it.
        let sent = frame.withUnsafeBytes { raw in write(fd, raw.baseAddress!, raw.count) }
        guard sent > 0 else { return (true, false) }
        var chunk = [UInt8](repeating: 0, count: 4096)
        let read = Darwin.read(fd, &chunk, chunk.count)
        return (true, read > 0)
    }

    @Test("REQ-027 effect witness: a socket that accepts and never answers is a state of its own, distinct from an absent one")
    func aHeldSocketIsItsOwnState() async throws {
        // --- The witness -----------------------------------------------------
        // The state the requirement is about: connect() SUCCEEDS and the reply
        // never comes. A killed agent was never the problem.
        let stallPath = Self.temporarySocketPath()
        let stall = StallingListener(path: stallPath)
        defer { stall.stop() }
        try stall.start()

        var held: [(connected: Bool, answered: Bool)] = []
        for _ in 0..<3 { held.append(await Self.askWithBound(path: stallPath, seconds: 2)) }
        #expect(held.allSatisfy { $0.connected },
                "connect() failed against a bound listener, so this is the killed case, not the held one")
        #expect(held.allSatisfy { !$0.answered },
                "a listener that never writes answered something")
        // The recorder is the listener's own accept count — a descriptor it took
        // and deliberately never wrote to.
        let acceptedAndUnanswered = stall.acceptedCount
        #expect(acceptedAndUnanswered == 3,
                "the stalling listener accepted \(acceptedAndUnanswered) of 3 connections")

        // --- The two-way -----------------------------------------------------
        // A REAL agent on a real socket answers inside the same bound. Same client
        // code, same bound, opposite outcome — so the silence above is the peer's
        // and not the clock's.
        let livePath = Self.temporarySocketPath()
        let log = PeerLog()
        let (server, session) = Self.makeServer(at: livePath, log: log)
        defer { server.stop() }
        await session.setDrawsHUD(false)
        try server.start()
        let live = await Self.askWithBound(path: livePath, seconds: 2)
        #expect(live.connected && live.answered,
                "a real agent did not answer inside the same bound the stall did not")

        // --- The sabotage ----------------------------------------------------
        // With nothing bound at all, connect() fails outright — the killed case,
        // which is a different state and named as one.
        let absentPath = Self.temporarySocketPath()
        let absent = await Self.askWithBound(path: absentPath, seconds: 2)
        #expect(!absent.connected, "connect() succeeded against a path nothing is bound to")

        stall.stop()
        let afterStop = await Self.askWithBound(path: stallPath, seconds: 1)
        #expect(!afterStop.connected,
                "the stalling listener still accepted after it was stopped")
    }

    // MARK: - W6 · REQ-037 · ipc · steps executed inside a guest

    /// What one forwarded conversation produced, in a shape that can leave the
    /// thread it happened on. Every field is `Sendable` wire data.
    struct Forwarded: Sendable {
        var attach: AgentResponse
        var inside: AgentResponse
        var dead: AgentResponse
        var answeredByGuest: Int
        var reported: [String]
    }

    @Test("REQ-037 effect witness: a forwarded call crosses a real socket into a guest, and the host actuates nothing")
    func aSessionExecutesItsStepsInsideTheGuest() async throws {
        // --- The witness -----------------------------------------------------
        // Two real servers. The second plays the guest's own Proctor, on the end
        // of the socket a person forwarded.
        let guestPath = Self.temporarySocketPath()
        let guestAX = FakeAX(bundleId: "com.fledgeling.inside-the-guest")
        let guestLog = PeerLog()
        let (guestServer, guestSession) = Self.makeServer(at: guestPath, log: guestLog, ax: guestAX)
        defer { guestServer.stop() }
        await guestSession.setDrawsHUD(false)
        try guestServer.start()

        let hostPath = Self.temporarySocketPath()
        let hostAX = FakeAX(bundleId: "com.fledgeling.the-host")
        let hostLog = PeerLog()
        let (hostServer, hostSession) = Self.makeServer(at: hostPath, log: hostLog, ax: hostAX)
        defer { hostServer.stop() }
        await hostSession.setDrawsHUD(false)
        await hostSession.setGuestProviders([
            FakeGuestProvider(id: "tart", records: [
                GuestRecord(name: "witness-guest", provider: "tart", state: "running",
                            running: true, platform: .macos, identifier: "witness-guest")])
        ])
        try hostServer.start()

        // Everything on ONE client connection, so the peer key the host reads is
        // the same for the attach and for the call that follows it — which is what
        // `guestAttachments[key]` is keyed on. And all of it OFF THE COOPERATIVE
        // POOL: every one of these sends blocks in `read()` while two servers
        // answer on `Task.detached`, which need cooperative threads of their own.
        let windowId = guestAX.window.id
        let forwarded = try await Self.offPool { () -> Forwarded in
            let client = SocketClient(path: hostPath)
            defer { client.disconnect() }
            try client.connect()

            // The link is the DEFAULT `SocketGuestLink`, not the injected fake
            // seam: it holds a real `SocketClient` on the forwarded path and
            // probes it.
            let attach = try client.send(AgentRequest(
                id: "w6-attach", tool: "proctor_guest",
                arguments: .object(["action": .string("attach"),
                                    "guest": .string("witness-guest"),
                                    "localSocket": .string(guestPath)])))

            // A forwardable tool. `proctor_apps` is not on
            // `GuestForwarding.hostOnly`, so it goes over the forwarded socket
            // verbatim and the GUEST's Proctor answers it.
            let inside = try client.send(AgentRequest(
                id: "w6-attach-inside", tool: "proctor_apps",
                arguments: .object(["action": .string("attach"),
                                    "bundleId": .string("com.fledgeling.inside-the-guest")])))

            // Steps, executed inside.
            var answered = 0
            var reported: [String] = []
            for index in 0..<3 {
                let reply = try client.send(AgentRequest(
                    id: "w6-act-\(index)", tool: "proctor_act",
                    arguments: .object([
                        "window": .string(windowId),
                        "steps": .array([.object(["kind": .string("press"),
                                                  "node": .string("node-1")])])])))
                if reply.ok { answered += 1 }
                else { reported.append(reply.error?.message ?? "no message") }
            }

            // --- The sabotage ---------------------------------------------
            // The forwarded socket, gone. The link refuses by name rather than
            // falling back to the host, which would be the
            // verdict-about-the-wrong-machine this whole feature exists to
            // prevent.
            _ = try client.send(AgentRequest(id: "w6-detach", tool: "proctor_guest",
                                             arguments: .object(["action": .string("detach")])))
            guestServer.stop()
            let dead = try client.send(AgentRequest(
                id: "w6-dead", tool: "proctor_guest",
                arguments: .object(["action": .string("attach"),
                                    "guest": .string("witness-guest"),
                                    "localSocket": .string(guestPath)])))

            return Forwarded(attach: attach, inside: inside, dead: dead,
                             answeredByGuest: answered, reported: reported)
        }

        let insideText = (try? String(decoding: JSONEncoder().encode(forwarded.inside.result),
                                      as: UTF8.self)) ?? ""
        #expect(forwarded.attach.ok,
                "the attach was refused: \(forwarded.attach.error?.message ?? "")")
        #expect(forwarded.inside.ok,
                "the forwarded attach failed: \(forwarded.inside.error?.message ?? "")")
        #expect(insideText.contains("com.fledgeling.inside-the-guest"),
                "the forwarded reply names \(insideText.prefix(160))")

        // The count is steps the guest's own Proctor actuated, read off the guest's
        // actuator rather than off the reply the host relayed.
        #expect(forwarded.answeredByGuest == 3,
                "\(forwarded.answeredByGuest) of 3 calls were answered inside the guest · \(forwarded.reported)")
        #expect(guestAX.performed.count == 3,
                "the guest actuated \(guestAX.performed.count) steps · \(forwarded.reported)")
        // The second half of the claim, and the reason this is not one case with
        // W7: the host routes and actuates NOTHING on the guest's behalf.
        #expect(hostAX.performed.isEmpty,
                "the host actuated \(hostAX.performed.count) steps for a guest session")

        #expect(!forwarded.dead.ok, "an attach onto a dead socket succeeded")
        #expect(forwarded.dead.error?.message.contains(guestPath) == true,
                "the refusal does not name the socket: \(forwarded.dead.error?.message ?? "")")
        #expect(hostAX.performed.isEmpty,
                "the host actuated \(hostAX.performed.count) steps after the guest went away")
    }

    // MARK: - W7 · REQ-039 · subprocess · the pool never evicts

    /// A `/bin/sh` guest tool that writes down its own pid AND the verb it was
    /// given, then prints a listing the production parser accepts.
    ///
    /// `$$` and `$1` are expanded by the shell in the child, so both values are
    /// ones no Swift in this process produced. A stop that never happened leaves
    /// no `stop` sentinel, and that absence is the whole of the never-evict claim.
    static func writeGuestScript(into directory: URL, named name: String,
                                 sentinels: URL, state: String) throws -> String {
        let script = """
        #!/bin/sh
        echo "$$ $1" > "\(sentinels.path)/sentinel-$1-$$"
        cat <<'PROCTOR_WITNESS_PAYLOAD'
        [{"name":"witness-guest","os":"macOS","state":"\(state)"}]
        PROCTOR_WITNESS_PAYLOAD
        """
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: url.path)
        return url.path
    }

    /// Every verb a spawned child was given, read back off the filesystem with
    /// `FileManager` — nothing in the code under test participates in the reading.
    static func spawnedVerbs(in directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("sentinel-") }.compactMap { name in
            let url = directory.appendingPathComponent(name, isDirectory: false)
            guard let data = try? Data(contentsOf: url) else { return nil }
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.split(separator: " ").dropFirst().first.map(String.init)
        }.sorted()
    }

    /// Attach and detach one guest, driven through the tool's own entry point.
    static func attachThenDetach(_ session: Session, guestSocket: String) async throws -> Bool {
        let identity = RunSessionIdentity(project: "pro83", connection: "w7ss",
                                          key: "pro83-w7-\(UUID().uuidString.prefix(6))")
        return try await SessionIdentity.$current.withValue(identity) {
            _ = try await session.guest(action: "attach", guest: "witness-guest",
                                        provider: nil, newName: nil, localSocket: guestSocket)
            let detached = try await session.guest(action: "detach", guest: nil,
                                                   provider: nil, newName: nil)
            return detached["guestStopped"]?.boolValue ?? false
        }
    }

    @Test("REQ-039 effect witness: a guest this agent started is stopped by a real child, and one a person started is not")
    func thePoolNeverEvictsAGuestItDidNotStart() async throws {
        var evictableVerbs: [String] = []
        var protectedVerbs: [String] = []

        // --- Arm A: a guest THIS AGENT started -------------------------------
        // The listing says `stopped`, so the attach starts it and
        // `startedByThisAgent` is true. The detach may then stop it, and does.
        try await Self.withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)
            let script = try Self.writeGuestScript(into: dir, named: "lume-stopped.sh",
                                                   sentinels: sentinels, state: "stopped")
            let guestPath = Self.temporarySocketPath()
            let log = PeerLog()
            let (guestServer, guestSession) = Self.makeServer(at: guestPath, log: log)
            defer { guestServer.stop() }
            await guestSession.setDrawsHUD(false)
            try guestServer.start()

            let session = Self.makeSession()
            await session.setDrawsHUD(false)
            // The CONVENIENCE initialiser, deliberately: it binds `run` to
            // `Self.liveRun`, which reaches a real `Process()` through
            // `Session.runBounded`. The three-argument one is the fake seam.
            await session.setGuestProviders([LumeProvider(executable: script)])
            _ = try? await Self.attachThenDetach(session, guestSocket: guestPath)
            evictableVerbs = Self.spawnedVerbs(in: sentinels)
        }

        // --- Arm B: a guest A PERSON started ---------------------------------
        // The listing says `running`, so the attach starts nothing and
        // `startedByThisAgent` is false. IDENTICAL call, one field different.
        try await Self.withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)
            let script = try Self.writeGuestScript(into: dir, named: "lume-running.sh",
                                                   sentinels: sentinels, state: "running")
            let guestPath = Self.temporarySocketPath()
            let log = PeerLog()
            let (guestServer, guestSession) = Self.makeServer(at: guestPath, log: log)
            defer { guestServer.stop() }
            await guestSession.setDrawsHUD(false)
            try guestServer.start()

            let session = Self.makeSession()
            await session.setDrawsHUD(false)
            await session.setGuestProviders([LumeProvider(executable: script)])
            _ = try? await Self.attachThenDetach(session, guestSocket: guestPath)
            protectedVerbs = Self.spawnedVerbs(in: sentinels)
        }

        // The recorder is the sentinels, and the count is real children that were
        // handed the `stop` verb. Non-zero on the arm the agent owns.
        let evictableStops = evictableVerbs.filter { $0 == "stop" }.count
        let protectedStops = protectedVerbs.filter { $0 == "stop" }.count
        #expect(!evictableVerbs.isEmpty,
                "arm A spawned nothing at all, so the provider never reached Process()")
        #expect(evictableStops > 0,
                "a guest this agent started left \(evictableStops) stop children · \(evictableVerbs)")
        // The whole guarantee. Same call, opposite outcome, read off the disk.
        #expect(protectedStops == 0,
                "a guest a person started left \(protectedStops) stop children · \(protectedVerbs)")
        #expect(!protectedVerbs.isEmpty,
                "arm B spawned nothing at all, so its zero is structural rather than a measurement")

        // --- The sabotage ----------------------------------------------------
        // Point the executable at a path that does not exist. `runBounded` catches
        // the spawn failure and answers exitCode -1, so the call still returns —
        // and the count goes to zero.
        try await Self.withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)
            let absent = dir.appendingPathComponent("no-such-lume", isDirectory: false).path
            #expect(!FileManager.default.fileExists(atPath: absent))
            let guestPath = Self.temporarySocketPath()
            let log = PeerLog()
            let (guestServer, guestSession) = Self.makeServer(at: guestPath, log: log)
            defer { guestServer.stop() }
            await guestSession.setDrawsHUD(false)
            try guestServer.start()

            let session = Self.makeSession()
            await session.setDrawsHUD(false)
            await session.setGuestProviders([LumeProvider(executable: absent)])
            _ = try? await Self.attachThenDetach(session, guestSocket: guestPath)
            #expect(Self.spawnedVerbs(in: sentinels).isEmpty,
                    "a sentinel appeared with no binary to spawn")
        }
    }

    // MARK: - W8 · REQ-024 · the boundary the browser lane actually crosses

    /// A file on disk that is executable and does nothing. What matters is that it
    /// exists, is a regular file, and carries the execute bit — the three things
    /// `ToolProbe.executableRegularFile` reads.
    static func placeExecutable(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test("REQ-024: the browser lane's only boundary crossing is a filesystem read, and the census names a provider it never reaches")
    func theBrowserLaneReadsTheDiskAndSpawnsNothing() throws {
        // **What was measured, and why this case is `inconclusive` rather than a
        // witness.** REQ-024 declares effect `subprocess` and the census names
        // `Process()` in `Actuation/CuaClients.swift` as its provider. The browser
        // routing path reaches neither: `BrowserTarget` is pure by its own header,
        // `Session.browserHandoff` returns a disclosure that six call sites attach
        // to a reply, `ToolProbe`'s header reads "cached, and never executed", and
        // `ToolLocator.locate` decides availability with a stat. The only boundary
        // this capability crosses is a filesystem READ, and the campaign's closed
        // class list has no member for it — `filesystem-write` is the only
        // filesystem class. So the measurement is recorded and the requirement's
        // row is left exactly as it stands.

        try Self.withTemporaryDirectory { root in
            let incomplete = root.appendingPathComponent("incomplete", isDirectory: true)
            let complete = root.appendingPathComponent("complete", isDirectory: true)
            for dir in [incomplete, complete] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            // One directory holds the tool alone; the other holds it with the
            // companion the release ships beside it.
            let lonely = try Self.placeExecutable(ObscuraTool.binary, in: incomplete)
            _ = try Self.placeExecutable(ObscuraTool.binary, in: complete)
            _ = try Self.placeExecutable(ObscuraTool.companions[0], in: complete)

            // The PRODUCTION locator, with the production `isExecutable`. Only the
            // path list is the test's, which is the one thing `obscuraOnDisk` takes
            // from the process environment.
            func locate(_ directories: [URL]) -> ToolPresence {
                ToolLocator.locate(binary: ObscuraTool.binary,
                                   companions: ObscuraTool.companions,
                                   pathEnvironment: directories.map(\.path).joined(separator: ":"),
                                   home: root.path, extraDirectories: [],
                                   isExecutable: ToolProbe.executableRegularFile)
            }

            // The answer changes with what is on disk in a way no input can compute.
            let onlyIncomplete = locate([incomplete])
            #expect(onlyIncomplete.available)
            #expect(onlyIncomplete.missingCompanions == ObscuraTool.companions,
                    "the incomplete directory reported \(onlyIncomplete.missingCompanions)")

            // Both offered, incomplete FIRST. The locator walks past the first hit
            // to the directory that holds the companion too — which it can only
            // know by stat-ing both.
            let both = locate([incomplete, complete])
            #expect(both.available)
            #expect(both.missingCompanions.isEmpty,
                    "the complete directory reported \(both.missingCompanions)")
            #expect(both.path?.hasPrefix(complete.path) == true,
                    "the locator chose \(both.path ?? "nothing") over the complete directory")

            // The count: files on disk whose presence the answer demonstrably
            // depended on. Three placed, and removing the companion moves the
            // answer, which is what makes each of them load-bearing rather than
            // merely present.
            let placed = 3

            // --- The sabotage -------------------------------------------------
            // Take the execute bit off, and the same call over the same paths
            // reports the tool absent. A read that is not happening cannot notice.
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: lonely.path)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: complete.appendingPathComponent(ObscuraTool.binary).path)
            let sabotaged = locate([incomplete, complete])
            #expect(!sabotaged.available,
                    "the locator still reports obscura at \(sabotaged.path ?? "nowhere")")
            #expect(sabotaged.searched.count == 2,
                    "the locator reported \(sabotaged.searched.count) candidate paths")
            #expect(placed == 3)
        }

        // And the claim the census makes, checked where it is checkable: no source
        // file in this package spawns either browser engine. Asserted against the
        // production constants rather than against a hard-coded string.
        #expect(ObscuraTool.binary == "obscura")
        #expect(BrowserUseTool.binary == "browser-use")
    }
}
