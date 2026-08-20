import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0076 — the tart adapter, against an injected runner.
//
// The fixtures are the exact bytes tart 2.32.1 printed on this machine on
// 2026-08-20, not a shape read from its docs. Nothing here starts a process
// and nothing here touches `anvil-mac-node`.

@Suite("PRO-0076 · tart adapter")
struct TartProviderTests {

    // The measured listing. Note what it does NOT carry: an OS field.
    static let listJSON = """
    [
      { "Size": 17, "State": "stopped", "Source": "local", "Name": "anvil-linux-node",
        "Running": false, "Accessed": "2026-08-19T08:39:28Z", "Disk": 17 },
      { "Source": "local", "Disk": 50, "Size": 29, "State": "stopped",
        "Running": false, "Name": "anvil-mac-node", "Accessed": "2026-08-20T06:35:28Z" }
    ]
    """

    static let macGetJSON = """
    { "OS": "darwin", "CPU": 8, "Size": "29.231", "State": "stopped",
      "Display": "1024x768", "Memory": 16384, "DiskFormat": "raw",
      "Disk": 50, "Running": false }
    """

    static let linuxGetJSON = """
    { "OS": "linux", "CPU": 4, "State": "stopped", "Memory": 4096,
      "Disk": 17, "Running": false }
    """

    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [[String]] = []
        private var spawns: [[String]] = []
        /// Keyed by the first argument, so `get` can answer differently per
        /// guest without the test having to count call order.
        var listReply: GuestProcessResult
        var getReplies: [String: GuestProcessResult]
        var getFailures: Set<String> = []
        var stopReply: GuestProcessResult
        /// Flipped by a test that wants the boot to succeed on the Nth poll.
        var runningAfterPolls: Int?
        private var polls = 0

        init(listReply: GuestProcessResult,
             getReplies: [String: GuestProcessResult] = [:],
             stopReply: GuestProcessResult? = nil) {
            self.listReply = listReply
            self.getReplies = getReplies
            self.stopReply = stopReply ?? GuestProcessResult(exitCode: 0, stdout: Data(),
                                                             stderr: "", timedOut: false,
                                                             truncated: false)
        }

        var recorded: [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
        var spawned: [[String]] { lock.lock(); defer { lock.unlock() }; return spawns }

        func run(_ path: String, _ arguments: [String], _ timeout: Int) -> GuestProcessResult {
            lock.lock(); calls.append(arguments)
            let verb = arguments.first ?? ""
            let name = arguments.count > 1 ? arguments[1] : ""
            defer { lock.unlock() }
            switch verb {
            case "list": return listReply
            case "stop": return stopReply
            case "get":
                if getFailures.contains(name) {
                    return GuestProcessResult(exitCode: 1, stdout: Data(), stderr: "no such vm",
                                              timedOut: false, truncated: false)
                }
                if let threshold = runningAfterPolls {
                    polls += 1
                    if polls >= threshold {
                        return ok("{ \"OS\": \"darwin\", \"State\": \"running\", \"Running\": true }")
                    }
                    return ok("{ \"OS\": \"darwin\", \"State\": \"stopped\", \"Running\": false }")
                }
                return getReplies[name] ?? ok(TartProviderTests.macGetJSON)
            default:
                return GuestProcessResult(exitCode: 0, stdout: Data(), stderr: "",
                                          timedOut: false, truncated: false)
            }
        }

        func spawn(_ path: String, _ arguments: [String]) {
            lock.lock(); spawns.append(arguments); lock.unlock()
        }
    }

    private static func ok(_ body: String) -> GuestProcessResult {
        GuestProcessResult(exitCode: 0, stdout: Data(body.utf8), stderr: "",
                           timedOut: false, truncated: false)
    }
    private func ok(_ body: String) -> GuestProcessResult { Self.ok(body) }

    private func provider(_ script: Script, startTimeoutMs: Int = 6_000,
                          pollIntervalMs: Int = 1_000) -> TartProvider {
        TartProvider(executable: "/opt/homebrew/bin/tart",
                     startTimeoutMs: startTimeoutMs,
                     pollIntervalMs: pollIntervalMs,
                     run: script.run, spawn: script.spawn,
                     sleep: { _ in })   // no wall clock in a test
    }

    @Test("list is list --format json, and the listing itself carries no platform")
    func listShape() async throws {
        // The whole reason the adapter enriches: tart's inventory does not say
        // which OS a guest runs, so a parse of it alone cannot answer the cap.
        let bare = try TartInventory.parse(Data(Self.listJSON.utf8))
        #expect(bare.count == 2)
        #expect(bare.allSatisfy { $0.platform == nil })
        #expect(bare.map(\.name) == ["anvil-linux-node", "anvil-mac-node"])
        #expect(bare.allSatisfy { $0.provider == "tart" })
        #expect(bare.allSatisfy { !$0.running })
        #expect(bare.first?.state == "stopped")
    }

    @Test("the adapter fills the platform from get, per guest, and never from the name")
    func platformComesFromGet() async throws {
        let script = Script(listReply: ok(Self.listJSON),
                            getReplies: ["anvil-mac-node": ok(Self.macGetJSON),
                                         "anvil-linux-node": ok(Self.linuxGetJSON)])
        let records = try await provider(script).list()
        #expect(records.first { $0.name == "anvil-mac-node" }?.platform == .macos)
        #expect(records.first { $0.name == "anvil-linux-node" }?.platform == .linux)
        // One list plus one get per row. The get is what buys the platform.
        #expect(script.recorded.first == ["list", "--format", "json"])
        #expect(script.recorded.contains(["get", "anvil-mac-node", "--format", "json"]))
        #expect(script.recorded.contains(["get", "anvil-linux-node", "--format", "json"]))
    }

    @Test("darwin is macOS — the only live target's classification, pinned")
    func darwinIsMacOS() {
        // Read at GuestInventory.swift's macOS branch, which tests for
        // "darwin". tart says `darwin`, not `macos`, so this is the word that
        // actually decides the witness tier and the cap on this machine.
        #expect(TartInventory.platform(fromGet: Data(Self.macGetJSON.utf8)) == .macos)
        #expect(TartInventory.platform(fromGet: Data(Self.linuxGetJSON.utf8)) == .linux)
    }

    @Test("a name that looks like a platform is not one — only the provider's word counts")
    func nameIsNeverTheSource() async throws {
        // `anvil-mac-node` would infer macOS from its NAME alone, and on this
        // machine that would even be right, which is what makes it a trap: a
        // guest called `build-box` would then be counted against Apple's two,
        // or excused from it, by what somebody typed.
        let script = Script(listReply: ok(Self.listJSON))
        script.getFailures = ["anvil-mac-node", "anvil-linux-node"]
        let records = try await provider(script).list()
        #expect(records.allSatisfy { $0.platform == nil },
                "a get that failed must leave the platform absent, never guess it from the name")
    }

    @Test("start launches detached, polls get, and re-reads")
    func startPollsRatherThanBlocking() async throws {
        // `tart run` lives as long as the VM does, so a bounded run would
        // report a timeout on every successful boot.
        let script = Script(listReply: ok(Self.listJSON))
        script.runningAfterPolls = 2
        _ = try await provider(script).start(name: "anvil-mac-node")
        #expect(script.spawned == [["run", "anvil-mac-node"]],
                "the VM is launched and left; it is not waited on")
        #expect(script.recorded.filter { $0.first == "get" }.count >= 2)
    }

    @Test("a start that never comes up reports the timeout and leaves the stop to its caller")
    func startTimeoutReportsRatherThanStopping() async throws {
        // The orphan still has to be stopped — a macOS guest that is up,
        // uncounted and unowned makes the cap, the start record and the
        // never-evict rule false at once. It is stopped one layer up, by
        // `Session.guestMutate`, because that is where the audit sink is and A9
        // says a stop stays gated and recorded. This adapter holds no sink, and
        // a bare `tart stop` here changed somebody's machine with nothing on the
        // trail to show for it. `aBootThatTimesOutIsStoppedAndRecorded` in
        // GuestAttachWiringTests is the other half of this pair.
        let script = Script(listReply: ok(Self.listJSON))
        script.runningAfterPolls = 9_999   // never
        await #expect(throws: GuestProviderError.timedOut(tool: "tart", action: "start")) {
            _ = try await self.provider(script).start(name: "anvil-mac-node")
        }
        #expect(script.spawned == [["run", "anvil-mac-node"]])
        #expect(!script.recorded.contains(["stop", "anvil-mac-node"]),
                "the adapter no longer stops around the audited path")
    }

    @Test("a guest already running is not started again")
    func alreadyRunningIsLeftAlone() async throws {
        // The exact row tart printed for anvil-mac-node while it was up,
        // measured 2026-08-20 rather than written to match the parser.
        let running = """
        [{ "Size": 29, "Running": true, "Disk": 50, "State": "running",
           "Source": "local", "Name": "anvil-mac-node",
           "Accessed": "2026-08-20T07:22:47Z" }]
        """
        let script = Script(listReply: ok(running))
        let record = try await provider(script).start(name: "anvil-mac-node")
        #expect(record.running)
        #expect(script.spawned.isEmpty, "nothing is launched for a guest that is already up")
    }

    @Test("stop and clone use tart's own verbs")
    func stopAndCloneShape() async throws {
        let script = Script(listReply: ok(Self.listJSON))
        _ = try? await provider(script).stop(name: "anvil-mac-node")
        #expect(script.recorded.contains(["stop", "anvil-mac-node"]))

        let cloneScript = Script(listReply: ok("""
        [{ "Name": "copy", "State": "stopped", "Running": false, "Disk": 50 }]
        """))
        _ = try? await provider(cloneScript).clone(name: "anvil-mac-node", as: "copy")
        #expect(cloneScript.recorded.contains(["clone", "anvil-mac-node", "copy"]))
    }

    @Test("the adapter has no verb that could destroy a guest")
    func nothingDestructive() {
        // anvil-mac-node belongs to another project: driving it is authorised,
        // changing it is not. delete / prune / rename / export are absent from
        // the protocol, so there is no path to them rather than a rule about
        // not taking one.
        let source = try? String(contentsOfFile:
            #filePath.replacingOccurrences(of: "Tests/ProctorAgentTests/TartProviderTests.swift",
                                           with: "Sources/ProctorAgent/Guest/GuestProvider.swift"),
            encoding: .utf8)
        let tart = source?.components(separatedBy: "final class TartProvider").last ?? ""
        #expect(!tart.isEmpty, "the adapter source must be readable for this guard to mean anything")
        for verb in ["\"delete\"", "\"prune\"", "\"rename\"", "\"export\""] {
            #expect(!tart.contains(verb), "the tart adapter must carry no \(verb) verb")
        }
    }

    @Test("a truncated listing is refused rather than parsed short")
    func truncationIsRefused() async throws {
        let script = Script(listReply: GuestProcessResult(exitCode: 0, stdout: Data("[".utf8),
                                                          stderr: "", timedOut: false,
                                                          truncated: true))
        await #expect(throws: GuestProviderError.truncated(tool: "tart", action: "list")) {
            _ = try await self.provider(script).list()
        }
    }
}
