import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0058 — the adapters, against an injected runner.
//
// Nothing here starts a process. The runner records the argv it was given
// and returns whatever fixture the test planted, so the argument shape and
// the decode path are both pinned without lume or a working Parallels VM.

@Suite("PRO-0058 · lume adapter")
struct LumeProviderTests {

    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(String, [String])] = []
        var replies: [GuestProcessResult]
        init(replies: [GuestProcessResult]) { self.replies = replies }
        var recorded: [(String, [String])] {
            lock.lock(); defer { lock.unlock() }; return calls
        }
        func run(_ path: String, _ arguments: [String], _ timeout: Int) -> GuestProcessResult {
            lock.lock(); calls.append((path, arguments)); lock.unlock()
            lock.lock(); defer { lock.unlock() }
            if replies.isEmpty {
                return GuestProcessResult(exitCode: 1, stdout: Data(), stderr: "exhausted",
                                          timedOut: false, truncated: false)
            }
            return replies.removeFirst()
        }
    }

    private func ok(_ body: String) -> GuestProcessResult {
        GuestProcessResult(exitCode: 0, stdout: Data(body.utf8), stderr: "",
                           timedOut: false, truncated: false)
    }

    private func fail(_ code: Int32, _ stderr: String) -> GuestProcessResult {
        GuestProcessResult(exitCode: code, stdout: Data(), stderr: stderr,
                           timedOut: false, truncated: false)
    }

    @Test("list asks lume 0.5.x first, then the older spellings")
    func listArgvAndFallback() async throws {
        let script = Script(replies: [
            fail(1, "Error: Unknown option '--format'"),
            fail(1, "unknown command ls"),
            ok("[{\"name\":\"sequoia-seed\",\"os\":\"macOS\",\"status\":\"stopped\"}]")
        ])
        let provider = LumeProvider(executable: "/opt/homebrew/bin/lume",
                                    run: script.run)
        let records = try await provider.list()
        #expect(records.map(\.name) == ["sequoia-seed"])
        #expect(script.recorded.map(\.1) == LumeProvider.listLadder)
        #expect(script.recorded.allSatisfy { $0.0 == "/opt/homebrew/bin/lume" })
    }

    // The defect this pins: lume 0.5.3 rejects `--json` by name, so a first
    // rung spelled that way took the whole guest lane down with
    // "no guest matches" while the guest was listed and running. Measured
    // against lume 0.5.3 on 2026-08-20.
    @Test("a lume that only knows --format json is listed, not reported missing")
    func lume05xIsListed() async throws {
        let script = Script(replies: [
            ok("[{\"name\":\"proctor-guest\",\"os\":\"macOS\",\"status\":\"running\"}]")
        ])
        let provider = LumeProvider(executable: "/opt/homebrew/bin/lume", run: script.run)
        let records = try await provider.list()
        #expect(records.map(\.name) == ["proctor-guest"])
        #expect(script.recorded.map(\.1) == [["ls", "--format", "json"]])
    }

    @Test("a lume that rejects every spelling reports lume's own words")
    func everySpellingRefused() async throws {
        let script = Script(replies: [
            fail(64, "Error: Unknown option '--format'"),
            fail(64, "Error: Unknown option '--json'"),
            fail(64, "Error: Unknown subcommand 'list'")
        ])
        let provider = LumeProvider(executable: "/x/lume", run: script.run)
        await #expect(throws: GuestProviderError.commandFailed(
            tool: "lume", action: "list", exit: 64,
            stderr: "Error: Unknown option '--format'")) {
            _ = try await provider.list()
        }
        #expect(script.recorded.count == LumeProvider.listLadder.count)
    }

    @Test("start / stop / clone use the published verbs and then re-read")
    func mutatingArgv() async throws {
        let listing = ok("[{\"name\":\"sequoia-seed\",\"os\":\"macOS\",\"status\":\"running\"}]")
        let script = Script(replies: [
            ok(""), listing,            // start + status (get)
            ok(""), listing,            // stop + status
            ok(""), listing             // clone + status of the new name
        ])
        let provider = LumeProvider(executable: "/x/lume", run: script.run)
        _ = try await provider.start(name: "sequoia-seed")
        _ = try await provider.stop(name: "sequoia-seed")
        _ = try await provider.clone(name: "sequoia-seed", as: "sequoia-copy")
        let argv = script.recorded.map(\.1)
        #expect(argv.contains(["run", "sequoia-seed"]))
        #expect(argv.contains(["stop", "sequoia-seed"]))
        #expect(argv.contains(["clone", "sequoia-seed", "sequoia-copy"]))
        #expect(argv.contains(["get", "sequoia-copy", "--format", "json"]))
    }

    @Test("a missing guest is refused by name")
    func missingGuest() async throws {
        let script = Script(replies: [
            fail(1, "no such vm"),
            fail(1, "no such vm"),
            ok("[]"),
            ok("[]")
        ])
        let provider = LumeProvider(executable: "/x/lume", run: script.run)
        await #expect(throws: GuestProviderError.notFound(name: "ghost", provider: "lume")) {
            _ = try await provider.status(name: "ghost")
        }
    }
}

@Suite("PRO-0058 · prlctl adapter")
struct PrlctlProviderTests {

    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        var calls: [[String]] = []
        var replies: [GuestProcessResult]
        init(replies: [GuestProcessResult]) { self.replies = replies }
        func run(_ path: String, _ arguments: [String], _ timeout: Int) -> GuestProcessResult {
            lock.lock(); calls.append(arguments); lock.unlock()
            lock.lock(); defer { lock.unlock() }
            if replies.isEmpty {
                return GuestProcessResult(exitCode: 1, stdout: Data(), stderr: "exhausted",
                                          timedOut: false, truncated: false)
            }
            return replies.removeFirst()
        }
    }

    private func ok(_ body: String) -> GuestProcessResult {
        GuestProcessResult(exitCode: 0, stdout: Data(body.utf8), stderr: "",
                           timedOut: false, truncated: false)
    }

    @Test("list is list -a -j, the shape measured on this machine")
    func listArgv() async throws {
        let script = Script(replies: [ok("""
        [{"uuid":"01732d18-5897-4550-b905-6fb947678c68","status":"invalid",
          "ip_configured":"-","name":"Windows 11"}]
        """)])
        let provider = PrlctlProvider(executable: "/usr/local/bin/prlctl",
                                      run: script.run)
        let records = try await provider.list()
        #expect(script.calls == [["list", "-a", "-j"]])
        #expect(records[0].name == "Windows 11")
        #expect(records[0].platform == .windows)
        #expect(records[0].machine.tier == .delegated)
    }

    @Test("clone uses --name, matching prlctl's own flag")
    func cloneArgv() async throws {
        let listing = ok("[{\"uuid\":\"x\",\"name\":\"Win-copy\",\"status\":\"stopped\"}]")
        let script = Script(replies: [ok(""), listing])
        let provider = PrlctlProvider(executable: "/usr/local/bin/prlctl",
                                      run: script.run)
        let cloned = try await provider.clone(name: "Windows 11", as: "Win-copy")
        #expect(script.calls[0] == ["clone", "Windows 11", "--name", "Win-copy"])
        #expect(cloned.name == "Win-copy")
    }

    @Test("truncated output is refused rather than parsed as a short listing")
    func truncatedIsRefused() async throws {
        let script = Script(replies: [
            GuestProcessResult(exitCode: 0, stdout: Data("[{\"name\":\"x\"}]".utf8),
                               stderr: "", timedOut: false, truncated: true)
        ])
        let provider = PrlctlProvider(executable: "/usr/local/bin/prlctl",
                                      run: script.run)
        await #expect(throws: GuestProviderError.truncated(tool: "prlctl", action: "list")) {
            _ = try await provider.list()
        }
    }
}

@Suite("PRO-0058 · doctor names the providers and starts none of them")
struct GuestDoctorWiringTests {

    @Test("a session with prlctl present reports the guest lane ready")
    func presentProviderMakesTheLaneReady() async throws {
        let session = Session(
            ax: FakeAX(bundleId: "com.example.app"), capture: FakeCapture(),
            tools: ToolProbes(
                lume: ToolProbe(probe: {
                    ToolPresence(tool: "lume", available: false, searched: ["/x/lume"])
                }, presentTTL: 300, absentTTL: 300),
                prlctl: ToolProbe(probe: {
                    ToolPresence(tool: "prlctl", available: true,
                                 path: "/usr/local/bin/prlctl",
                                 searched: ["/usr/local/bin/prlctl"])
                }, presentTTL: 300, absentTTL: 300)),
            screenRecordingProbe: .fake(), accessibilityProbe: { true },
            secureInputProbe: { false })
        await session.setAuditSink({ _ in })
        let report = await session.doctor(verbose: false)
        #expect(report.tools.contains { $0.tool == "lume" })
        #expect(report.tools.contains { $0.tool == "prlctl" && $0.usability == .usable })
        #expect(report.lanes?.first { $0.lane == "guest" }?.state == "ready")
        #expect(report.ready == true)
    }

    @Test("if prlctl is on this machine, detection finds it without running it")
    func realPrlctlIsAFilesystemRead() {
        let presence = ToolProbe.prlctlOnDisk()
        // This machine has /usr/local/bin/prlctl. The assertion is about the
        // shape of the answer, not that every Mac has Parallels: if it is
        // here, the path is an executable regular file and nothing was run
        // to learn that.
        if presence.available {
            #expect(presence.path?.hasSuffix("/prlctl") == true)
            #expect(presence.usability == nil)   // a probe, not a verdict
        }
    }
}
