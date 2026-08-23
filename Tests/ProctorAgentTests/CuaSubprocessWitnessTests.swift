import CoreGraphics
import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

@Suite("Cua subprocess actuation witness and lifecycle interlock (REQ-024 / REQ-180)")
struct CuaSubprocessWitnessTests {

    private static func withTemporaryDirectory(_ body: (URL) async throws -> Void) async rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cua-subproc-witness-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    /// Helper to write an executable witness script that records its own execution into sentinels.
    private static func writeWitnessScript(
        into directory: URL,
        named name: String,
        sentinels: URL,
        behavior: String
    ) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        let content = """
        #!/bin/sh
        # Record child PID and arguments into sentinel
        echo "$$" > "\(sentinels.path)/spawn-$$"
        echo "$*" > "\(sentinels.path)/args-$$"
        \(behavior)
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test("REQ-180: CuaEndpointTransport spawns child, verifies args, exchanges stdio, and terminates cleanly on stop without orphans")
    func endpointTransportLifecycleAndShutdownInterlock() async throws {
        try await Self.withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)

            let scriptURL = try Self.writeWitnessScript(
                into: dir,
                named: "mock-cua-driver.sh",
                sentinels: sentinels,
                behavior: """
                if [ "$1" = "serve" ] && [ "$2" = "--stdio" ]; then
                    while IFS= read -r line; do
                        echo '{"ok":true,"message":"endpoint-ready","version":"0.13.2"}'
                    done
                    exit 0
                else
                    echo "unexpected args: $*" >&2
                    exit 1
                fi
                """
            )

            let transport = CuaEndpointTransport(path: scriptURL.path)
            let request = CuaRequest(verb: .health)
            let response = try await transport.send(request)
            #expect(response.ok)
            #expect(response.message == "endpoint-ready")

            // Witness check: verify child process sentinel was created
            let spawnFiles = try FileManager.default.contentsOfDirectory(atPath: sentinels.path)
                .filter { $0.hasPrefix("spawn-") }
            #expect(!spawnFiles.isEmpty, "child process spawned and created sentinel")

            let childPidString = try String(contentsOf: sentinels.appendingPathComponent(spawnFiles[0]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let childPid = Int32(childPidString) else {
                Issue.record("invalid child PID: \(childPidString)")
                return
            }
            #expect(childPid > 0)
            #expect(childPid != ProcessInfo.processInfo.processIdentifier)

            // Argument verification witness
            let argFiles = try FileManager.default.contentsOfDirectory(atPath: sentinels.path)
                .filter { $0.hasPrefix("args-") }
            #expect(!argFiles.isEmpty)
            let argContent = try String(contentsOf: sentinels.appendingPathComponent(argFiles[0]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(argContent == "serve --stdio")

            // Process table inspection: process is active before stop
            var procStateBefore = kill(childPid, 0)
            #expect(procStateBefore == 0, "child process is alive before stop()")

            // Trigger stop() interlock
            transport.stop()

            // Small settle window for SIGTERM / wait
            try await Task.sleep(nanoseconds: 100_000_000)

            // Process table inspection: process is dead after stop (no orphaned daemon)
            var procStateAfter = kill(childPid, 0)
            #expect(procStateAfter != 0 || errno == ESRCH, "child daemon was terminated cleanly on stop")
        }
    }

    @Test("REQ-180: CuaOneShotTransport executes child per call and captures exit code & stderr on failure")
    func oneShotTransportLifecycleAndStderrCapture() async throws {
        try await Self.withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)

            let scriptURL = try Self.writeWitnessScript(
                into: dir,
                named: "mock-cua-oneshot.sh",
                sentinels: sentinels,
                behavior: """
                if [ "$1" = "call" ] && [ "$2" = "--json" ]; then
                    if echo "$3" | grep -q "fail-mode"; then
                        echo "driver error: invalid element token" >&2
                        exit 2
                    fi
                    echo '{"ok":true,"message":"oneshot-success"}'
                    exit 0
                else
                    echo "bad arguments: $*" >&2
                    exit 3
                fi
                """
            )

            let transport = CuaOneShotTransport(path: scriptURL.path)

            // Success path
            let okRequest = CuaRequest(verb: .health)
            let okResponse = try await transport.send(okRequest)
            #expect(okResponse.ok)
            #expect(okResponse.message == "oneshot-success")

            // Failure path with nonzero exit and stderr capture
            var failRequest = CuaRequest(verb: .act)
            failRequest.elementToken = "fail-mode"
            do {
                _ = try await transport.send(failRequest)
                Issue.record("expected failure not thrown")
            } catch let err as AgentError {
                #expect(err.code == .backendUnavailable)
                #expect(err.message.contains("2"))
                #expect(err.message.contains("driver error: invalid element token"),
                        "stderr was captured and surfaced in error message: \(err.message)")
            }
        }
    }

    @Test("REQ-024 / REQ-180 effect witness: subprocess actuation executes real children and records non-zero witness count")
    func subprocessActuationEffectWitness() async throws {
        try await Self.withTemporaryDirectory { dir in
            let sentinels = dir.appendingPathComponent("sentinels", isDirectory: true)
            try FileManager.default.createDirectory(at: sentinels, withIntermediateDirectories: true)

            let scriptURL = try Self.writeWitnessScript(
                into: dir,
                named: "cua-driver-witness.sh",
                sentinels: sentinels,
                behavior: """
                if [ "$1" = "call" ] && [ "$2" = "--json" ]; then
                    echo '{"ok":true,"message":"actuated"}'
                    exit 0
                fi
                echo "unknown command" >&2
                exit 1
                """
            )

            let transport = CuaOneShotTransport(path: scriptURL.path)

            // Actuate three times
            for i in 1...3 {
                var req = CuaRequest(verb: .act)
                req.action = "click"
                req.windowID = CGWindowID(100 + i)
                let resp = try await transport.send(req)
                #expect(resp.ok)
            }

            // Independent witness check: exactly 3 distinct child processes ran and wrote sentinels
            let spawnFiles = try FileManager.default.contentsOfDirectory(atPath: sentinels.path)
                .filter { $0.hasPrefix("spawn-") }
            #expect(spawnFiles.count == 3, "witness recorded exactly 3 subprocess executions")

            var pids: Set<Int32> = []
            for file in spawnFiles {
                let text = try String(contentsOf: sentinels.appendingPathComponent(file))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let pid = Int32(text) {
                    pids.insert(pid)
                }
            }
            #expect(pids.count == 3, "all 3 subprocesses had distinct PIDs")
            #expect(!pids.contains(ProcessInfo.processInfo.processIdentifier), "no subprocess was parent process")
        }
    }
}
