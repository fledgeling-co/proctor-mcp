import Testing
import Foundation
import Darwin
import CryptoKit
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0077. Four effect witnesses for the four effects that need no window server.
//
// The 0.9.2 effect-boundary census read `0 of 22 witnessed`: every external
// guarantee in this product rested on a test that called a function and read the
// value the function returned. These four ask instead.
//
// **What a witness owes, and what each of these carries.** A recorder, an effect
// class, and a non-zero count. The causal shape is four parts, each separately
// checkable: the effect is driven from a production entry point rather than by
// calling the adapter directly; the attempt is recorded at the boundary;
// completion is confirmed by something other than the code under test; and
// sabotage flips it. The fourth is the one that is easy to skip and hardest to
// fake, so it lives inside each test rather than beside it — the arming run and
// the passing run are then the same measurement taken twice, on one build.
//
// **The lane's ceiling is the portable floor, and that is recorded rather than
// left silent.** `dtrace` and `eslogger` need privilege this suite does not have.
// So: a real spawned process that writes a sentinel the test reads back, a real
// file read with a fresh descriptor rather than through the writer's own API, and
// a real loopback listener answering real connections. No kernel, no privilege,
// and none of the four can pass when nothing runs.
//
// Serialized because W3 redirects `AuditLog`'s process-wide seams and W4 binds a
// socket and starts threads.
@Suite("Effect witnesses: subprocess, filesystem-write, ipc", .serialized)
struct EffectWitnessTests {

    // MARK: - Shared apparatus

    /// A directory that lives for one witness and is removed after it.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("effect-witness-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("effect-witness-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    /// The recorder for both subprocess witnesses: an executable `/bin/sh` script
    /// that writes down its **own** pid and then prints a payload the production
    /// parser accepts.
    ///
    /// `$$` is expanded by the shell in the child, so the number in the file is a
    /// value no Swift in this process produced and no test wrote. That is what
    /// makes the sentinel a witness rather than a receipt: a spawn that did not
    /// happen leaves no file, and a spawn that happened cannot leave the parent's
    /// pid.
    @discardableResult
    private func writeWitnessScript(into directory: URL, named name: String,
                                    sentinels: URL, printing payload: String) throws -> String {
        let script = """
        #!/bin/sh
        echo $$ > "\(sentinels.path)/sentinel-$$"
        cat <<'PROCTOR_WITNESS_PAYLOAD'
        \(payload)
        PROCTOR_WITNESS_PAYLOAD
        """
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: url.path)
        return url.path
    }

    /// Every pid a spawned child left behind, read back off the filesystem.
    ///
    /// Read with `FileManager` and `Data(contentsOf:)` — nothing in the code under
    /// test participates in the reading.
    private func sentinelPIDs(in directory: URL) -> [Int32] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("sentinel-") }.compactMap { name in
            let url = directory.appendingPathComponent(name, isDirectory: false)
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }.sorted()
    }

    /// How many times each subprocess witness drives its entry point. Two rather
    /// than one, so the recorder reports a count rather than a boolean and a
    /// second child has to be distinguishable from the first.
    static let drives = 2

    /// One line of what a tool answered, for a failure that has to explain itself.
    static func describe(_ value: JSONValue) -> String {
        let count = value["count"]?.doubleValue
            ?? value["devices"]?.arrayValue.map { Double($0.count) }
        let errors = value["providerErrors"]?.arrayValue?
            .compactMap(\.stringValue).joined(separator: "; ") ?? ""
        return "count=\(count.map { String(Int($0)) } ?? "nil")"
            + (errors.isEmpty ? "" : " errors=\(errors)")
    }

    private func makeSession(tools: ToolProbes = ToolProbes(environment: [:])) -> Session {
        Session(ax: FakeAX(bundleId: "com.fledgeling.witness"),
                capture: FakeCapture(),
                tools: tools,
                screenRecordingProbe: .fake(.granted),
                accessibilityProbe: { true },
                secureInputProbe: { false })
    }

    // MARK: - W1 · REQ-017 · subprocess · guest routing

    /// A lume listing prlctl and tart share the parser for. One row is enough:
    /// the claim under test is that a process ran, not that the inventory is rich.
    private static let lumePayload =
        #"[{"name":"witness-guest","os":"macOS","state":"stopped"}]"#

    @Test("REQ-017 effect witness: proctor_guest spawns a real child, and a missing binary spawns none")
    func guestRoutingSpawnsRealProcesses() async throws {
        // --- The witness -----------------------------------------------------
        var livePIDs: [Int32] = []
        try await withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)
            let script = try writeWitnessScript(into: dir, named: "lume-witness.sh",
                                                sentinels: sentinels,
                                                printing: Self.lumePayload)

            let session = makeSession()
            // The CONVENIENCE initialiser, deliberately. `init(executable:timeoutMs:run:)`
            // is the fake seam and proves nothing about spawning; this one binds
            // `run` to `Self.liveRun`, which goes through `Session.runBounded` to a
            // real `Process()`.
            await session.setGuestProviders([LumeProvider(executable: script)])

            // Driven through the tool's own entry point, never through `invoke`.
            // Twice, so the count is a count rather than a boolean.
            var reported: [String] = []
            for _ in 0..<Self.drives {
                let listed = try await session.guest(action: "list", guest: nil,
                                                     provider: nil, newName: nil)
                reported.append(Self.describe(listed))
            }

            livePIDs = sentinelPIDs(in: sentinels)
            // One sentinel per drive: every call reached `Process()`, and each
            // child lived long enough to write its own pid down.
            let w1 = reported.joined(separator: " | ")
            #expect(livePIDs.count == Self.drives,
                    "\(Self.drives) drives left \(livePIDs.count) sentinels · \(w1)")
            // Each entry is a distinct child, and none of them is this process.
            #expect(Set(livePIDs).count == livePIDs.count)
            let mine = ProcessInfo.processInfo.processIdentifier
            #expect(!livePIDs.contains(mine),
                    "a sentinel names this process, so nothing forked")
        }

        // --- The sabotage ----------------------------------------------------
        // Point `executable` at a path that does not exist. `Session.runBounded`
        // catches the spawn failure and answers `exitCode: -1`, so the call still
        // returns a result — and the witness goes to zero.
        try await withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)
            let absent = dir.appendingPathComponent("no-such-lume", isDirectory: false).path
            #expect(!FileManager.default.fileExists(atPath: absent))

            let session = makeSession()
            await session.setGuestProviders([LumeProvider(executable: absent)])

            for _ in 0..<Self.drives {
                let listed = try await session.guest(action: "list", guest: nil,
                                                     provider: nil, newName: nil)
                #expect(listed["count"]?.doubleValue == 0)
                #expect(listed["providerErrors"]?.arrayValue?.isEmpty == false,
                        "the lane reported no provider error, so the sabotage did not land")
            }
            #expect(sentinelPIDs(in: sentinels).isEmpty,
                    "a sentinel appeared with no binary to spawn")
        }
    }

    // MARK: - W2 · REQ-020 · subprocess · iOS simulator driving

    /// What `simctl list -j devices` emits, reduced to one runtime and one device.
    private static let simctlPayload = #"""
    {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"udid":"E1E1E1E1-1111-2222-3333-444444444444","name":"Witness iPhone","state":"Shutdown","isAvailable":true}]}}
    """#

    private func toolsWithSimctl(at path: String) -> ToolProbes {
        ToolProbes(simctl: ToolProbe(probe: { ToolPresence(tool: "simctl", available: true,
                                                           path: path, searched: [path]) },
                                     presentTTL: ToolProbe.presentTTL,
                                     absentTTL: ToolProbe.presentTTL),
                   environment: [:])
    }

    @Test("REQ-020 effect witness: proctor_ios spawns a real simctl child, and a missing simctl spawns none")
    func iosLaneSpawnsRealProcesses() async throws {
        // --- The witness -----------------------------------------------------
        try await withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)
            let script = try writeWitnessScript(into: dir, named: "simctl-witness.sh",
                                                sentinels: sentinels,
                                                printing: Self.simctlPayload)

            let session = makeSession(tools: toolsWithSimctl(at: script))
            var reported: [String] = []
            for _ in 0..<Self.drives {
                do {
                    let listed = try await session.ios(action: "list", device: nil, url: nil,
                                                       bundleId: nil, pixelEvidence: false,
                                                       changeThreshold: nil, path: nil,
                                                       timeoutMs: nil, settleMs: nil)
                    reported.append(Self.describe(listed))
                } catch {
                    reported.append("threw: \(error)")
                }
            }

            let pids = sentinelPIDs(in: sentinels)
            let w2 = reported.joined(separator: " | ")
            #expect(pids.count == Self.drives,
                    "\(Self.drives) drives left \(pids.count) sentinels · \(w2)")
            #expect(Set(pids).count == pids.count)
            #expect(!pids.contains(ProcessInfo.processInfo.processIdentifier),
                    "a sentinel names this process, so nothing forked")
        }

        // --- The sabotage ----------------------------------------------------
        try await withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)
            let absent = dir.appendingPathComponent("no-such-simctl", isDirectory: false).path
            #expect(!FileManager.default.fileExists(atPath: absent))

            let session = makeSession(tools: toolsWithSimctl(at: absent))
            await #expect(throws: AgentError.self) {
                _ = try await session.ios(action: "list", device: nil, url: nil,
                                          bundleId: nil, pixelEvidence: false,
                                          changeThreshold: nil, path: nil,
                                          timeoutMs: nil, settleMs: nil)
            }
            #expect(sentinelPIDs(in: sentinels).isEmpty,
                    "a sentinel appeared with no binary to spawn")
        }
    }

    // MARK: - W3 · REQ-015 · filesystem-write · the audit trail

    /// An in-process signer standing in for the secure element. Its own rather
    /// than borrowed from another suite: three items in this wave write this tree,
    /// and a witness that depends on a neighbour's nested type breaks for a reason
    /// that has nothing to do with the effect it measures.
    final class WitnessSigner: AuditSigning, AuditAnchoring, @unchecked Sendable {
        private let lock = NSLock()
        private let key = P256.Signing.PrivateKey()
        private var anchor: AuditChain.Anchor?

        var signingKeyId: String? {
            AuditChain.keyId(forPublicKey: key.publicKey.rawRepresentation)
        }
        var signingKeyClass: AuditChain.KeyClass? { .software }
        func sign(_ material: Data) -> Data? {
            try? key.signature(for: material).rawRepresentation
        }
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

    /// Everything the trail needs redirected, restored afterwards, on a thread of
    /// its own.
    ///
    /// **The dedicated thread is not tidiness, it is the whole reason this
    /// compiles into a suite that finishes.** `AuditLog`'s seams are process-wide,
    /// so `TrailIsolation` has to be held across the drive — and every other
    /// trail-touching suite in this target holds the same lock from a
    /// *synchronous* body, which never suspends. An `async` body that takes it
    /// suspends at the first `await` while still holding it, and by then the
    /// cooperative pool is full of other tests blocking on that same lock, so the
    /// holder can never be scheduled again and the whole run wedges. Measured on
    /// 2026-08-21: 17 threads, every cooperative one blocked, two of them inside
    /// `TrailIsolation.acquire()` from `AuditRotationTests` and
    /// `AuditChainWiringTests`, no progress in 40 minutes.
    ///
    /// So the lock and the drive both live on a `Thread` this function owns —
    /// blocking *it* on a semaphore costs the cooperative pool nothing, which is
    /// the same reason `Server.dispatchBlocking` gives every connection its own
    /// thread rather than a cooperative one.
    private func withRedirectedTrail(
        _ body: @escaping @Sendable (URL, TestSealKeys) async throws -> Void
    ) async throws {
        let outcome = ThrownBox()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let worker = Thread {
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("effect-witness-trail-\(UUID().uuidString)",
                                            isDirectory: true)
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

                let done = DispatchSemaphore(value: 0)
                Task.detached {
                    do { try await body(dir, keys) } catch { outcome.set(error) }
                    done.signal()
                }
                done.wait()

                AuditLog.seams.directory = nil
                AuditLog.seams.signer = previousSigner
                AuditLog.seams.anchors = previousAnchors
                AuditLog.seams.keys = previousKeys
                try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                       ofItemAtPath: dir.path)
                try? FileManager.default.removeItem(at: dir)
                TrailIsolation.release()
                continuation.resume()
            }
            worker.name = "effect-witness.trail"
            worker.stackSize = 1024 * 1024
            worker.start()
        }
        if let error = outcome.value { throw error }
    }

    /// Carries whatever the body threw back across the thread boundary.
    final class ThrownBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Error?
        func set(_ error: Error) { lock.withLock { stored = error } }
        var value: Error? { lock.withLock { stored } }
    }

    /// Drive three real steps through `proctor_act`, with the session's sink set
    /// to the production `AuditLog.append`.
    ///
    /// The seam is the *test-process interlock* in `Session.auditSink`, not the
    /// write path: `AuditLog.append` still seals with CryptoKit, chains, signs and
    /// lands the bytes with `Darwin.open(O_WRONLY|O_APPEND|O_CREAT)`,
    /// `Darwin.write` and `fsync` in `PolicyStore.swift`, unchanged.
    private func driveAuditedRun() async throws -> Int {
        let ax = FakeAX(bundleId: "com.fledgeling.witness")
        let session = Session(ax: ax, capture: FakeCapture(),
                              tools: ToolProbes(environment: [:]),
                              screenRecordingProbe: .fake(.granted),
                              accessibilityProbe: { true },
                              secureInputProbe: { false })
        let emitted = EmissionCounter()
        await session.setAuditSink { record in
            emitted.bump()
            _ = AuditLog.append(record)
        }
        await session.setDrawsHUD(false)
        _ = try await session.attachResolved(bundleId: "com.fledgeling.witness",
                                             pid: nil, name: nil)
        _ = try await session.act(window: ax.window.id,
                                  steps: [
                                    ActionStep(kind: .setValue, node: "node-1",
                                               value: .string("one")),
                                    ActionStep(kind: .press, node: "node-1"),
                                    ActionStep(kind: .setValue, node: "node-1",
                                               value: .string("two"))
                                  ],
                                  settle: .default, foreground: false,
                                  captureEach: false, diffEach: false, record: nil)
        return emitted.value
    }

    final class EmissionCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    @Test("REQ-015 effect witness: an audited run lands sealed bytes on disk, and a read-only directory lands none")
    func auditTrailWritesRealBytes() async throws {
        // --- The witness -----------------------------------------------------
        try await withRedirectedTrail { dir, keys in
            let trail = dir.appendingPathComponent("audit.jsonl", isDirectory: false)
            #expect(!FileManager.default.fileExists(atPath: trail.path),
                    "the trail existed before anything was written to it")

            let before = try FileManager.default.attributesOfItem(atPath: dir.path)
            let beforeStamp = before[.modificationDate] as? Date

            let emitted = try await driveAuditedRun()
            #expect(emitted >= 3, "the run emitted \(emitted) records, so it audited nothing")

            // Read back with a FRESH descriptor. Never `AuditLog.readTrail` or
            // `openedTail`: those are the code under test confirming itself, which
            // is the exact shape of DEF-019.
            let handle = try FileHandle(forReadingFrom: trail)
            defer { try? handle.close() }
            let bytes = try handle.readToEnd() ?? Data()
            #expect(bytes.count > 0, "the trail file is empty")

            let text = String(data: bytes, encoding: .utf8) ?? ""
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            #expect(lines.count == emitted,
                    "the agent emitted \(emitted) records and \(lines.count) reached the disk")

            // Opened with ProctorCore's seal and the injected private half — a
            // different module from the reader under test.
            let priv = try #require(keys.privateKey())
            let opened = lines.compactMap { AuditSeal.open($0, with: priv) }
            #expect(opened.count == lines.count,
                    "\(lines.count - opened.count) of \(lines.count) lines would not open")
            #expect(opened.allSatisfy { $0.contains("proctor_act") },
                    "the opened records do not name the tool that was driven")

            let after = try FileManager.default.attributesOfItem(atPath: trail.path)
            #expect((after[.size] as? Int ?? 0) == bytes.count)
            let afterStamp = try #require(after[.modificationDate] as? Date)
            if let beforeStamp {
                #expect(afterStamp >= beforeStamp)
            }
        }

        // --- The sabotage ----------------------------------------------------
        // A directory nothing may create a file in. `withAuditFileLock` cannot
        // open `audit.lock` and `appendRawLocked` cannot `O_CREAT` the trail, so
        // the append refuses and the count stays at zero.
        try await withRedirectedTrail { dir, _ in
            try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                                  ofItemAtPath: dir.path)
            let emitted = try await driveAuditedRun()
            #expect(emitted >= 3, "the run emitted nothing, so the sabotage proved nothing")

            try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                  ofItemAtPath: dir.path)
            let trail = dir.appendingPathComponent("audit.jsonl", isDirectory: false)
            let landed = (try? Data(contentsOf: trail))?.count ?? 0
            #expect(landed == 0,
                    "\(landed) bytes reached a directory nothing may write to")
        }
    }

    // MARK: - W4 · REQ-009 · ipc · the agent socket

    /// What the server read off each accepted descriptor.
    ///
    /// `SessionIdentity.fromPeer` asks the kernel — `getsockopt(SOL_LOCAL,
    /// LOCAL_PEERPID)` and `proc_pidinfo` — and binds the answer as a task-local
    /// for the whole request, so this records inside the server process, on the
    /// dispatching task. The client never puts any of it on the wire.
    final class PeerLog: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [RunSessionIdentity] = []
        func record(_ identity: RunSessionIdentity) { lock.withLock { seen.append(identity) } }
        var identities: [RunSessionIdentity] { lock.withLock { seen } }
    }

    /// Short, because `sockaddr_un.sun_path` is 104 bytes and a nested temporary
    /// path overruns it.
    private func temporarySocketPath() -> String {
        "/tmp/pw-\(UUID().uuidString.prefix(8).lowercased()).sock"
    }

    private func makeServer(at path: String, log: PeerLog) -> Server {
        let session = Session(ax: FakeAX(bundleId: "com.fledgeling.witness"),
                              capture: FakeCapture(),
                              tools: ToolProbes(environment: [:]),
                              screenRecordingProbe: .fake(.granted),
                              accessibilityProbe: {
                                  log.record(SessionIdentity.current)
                                  return true
                              },
                              secureInputProbe: { false })
        return Server(dispatcher: Dispatcher(session: session), path: path)
    }

    @Test("REQ-009 effect witness: a real AF_UNIX server answers real connections, and an unlinked socket answers none")
    func agentSocketAcceptsRealConnections() async throws {
        let connections = 3

        // --- The witness -----------------------------------------------------
        do {
            let path = temporarySocketPath()
            let log = PeerLog()
            let server = makeServer(at: path, log: log)
            defer { server.stop() }
            try server.start()
            #expect(FileManager.default.fileExists(atPath: path),
                    "bind left no socket at \(path)")

            // The count is ANSWERED CONNECTIONS, not recorded requests. `serve`
            // reads many frames from one accepted descriptor, so a per-request
            // count would report three for one client sending three frames. A
            // reply cannot arrive on a descriptor the accept loop never took, so
            // an answered connection is an accept.
            var answered = 0
            for index in 0..<connections {
                let client = SocketClient(path: path)
                defer { client.disconnect() }
                try client.connect()
                let reply = try client.send(AgentRequest(id: "witness-\(index)",
                                                         tool: "proctor_doctor",
                                                         arguments: .object([:])))
                if reply.ok, reply.id == "witness-\(index)" { answered += 1 }
            }
            #expect(answered == connections,
                    "\(answered) of \(connections) connections were answered")

            let identities = log.identities
            #expect(identities.count == connections,
                    "the server read \(identities.count) peers off \(connections) connections")
            // The pid the kernel reported for the far end. This process's, because
            // this process is the client — and the client never sent it.
            let mine = ProcessInfo.processInfo.processIdentifier
            let keys = identities.map(\.key).joined(separator: ", ")
            #expect(identities.allSatisfy { $0.key.hasPrefix("\(mine):") },
                    "a peer identity does not name this process \(mine): \(keys)")
            #expect(identities.allSatisfy { !$0.project.isEmpty && $0.project != "unknown" },
                    "the kernel described no working directory for the peer")
        }

        // --- The sabotage ----------------------------------------------------
        // Unlink the socket between bind and connect. `Darwin.connect` has nothing
        // to reach, the accept loop takes nothing, and both counts go to zero.
        do {
            let path = temporarySocketPath()
            let log = PeerLog()
            let server = makeServer(at: path, log: log)
            defer { server.stop() }
            try server.start()
            #expect(unlink(path) == 0, "the socket could not be unlinked")

            let client = SocketClient(path: path)
            defer { client.disconnect() }
            #expect(throws: AgentError.self) { try client.connect() }
            #expect(log.identities.isEmpty,
                    "the server read a peer with no socket to accept on")
        }
    }
}
