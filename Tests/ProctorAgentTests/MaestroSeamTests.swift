import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0049 — the seam half of the Maestro flow lane.
//
// The verdict ladder, the score basis, the flow scan and the gate are pure and
// tested in ProctorCoreTests. What is tested here is what reaches the agent, and
// three of these are source-level assertions in the style of PRO-0048's
// no-shutdown test, because the promises are about what the code does NOT do and
// a promise is only worth what enforces it.
//
// Not testable here: anything that needs Maestro and a booted simulator. Those
// paths were run by hand against maestro 2.4.0 and an iPhone 16 Pro on
// 2026-08-15 and the numbers are in the spec, rather than committed as a gate a
// machine without Xcode would fail for the absence of Xcode.

@Suite("PRO-0049 · Maestro seam")
struct MaestroSeamTests {

    static func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ProctorAgentTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// The source with its comment lines removed.
    ///
    /// Every assertion below is about what the code DOES, and these files
    /// document at length why they do not do these things — so a check run over
    /// the prose fails on the sentence explaining the rule it is enforcing. That
    /// happened on the first run of this suite, which is the argument for
    /// stripping rather than for softening the assertion.
    static func code(_ relative: String) throws -> String {
        try source(relative)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    static let decisionLayer = "Sources/ProctorCore/MaestroRun.swift"
    static let runner = "Sources/ProctorAgent/Session/SessionMaestro.swift"

    // MARK: - AC15 · no Maestro command becomes a Proctor step

    @Test("neither new source turns a Maestro command into an actuation step")
    func noMaestroCommandBecomesAnActionStep() throws {
        // PRO-0020's conclusion, transferred: a tool driving its own engine is
        // not driving the window Proctor is attached to, so a routed step would
        // report success against something Proctor never touched. The unit here
        // is the file, and this is what holds it that way.
        for path in [Self.decisionLayer, Self.runner] {
            let text = try Self.code(path)
            #expect(text.contains("ActionStep(") == false,
                    "\(path) must not construct an actuation step from a Maestro command")
        }
    }

    @Test("the Maestro lane registers no actuation backend")
    func maestroIsNotAnActuationBackend() throws {
        // PRO-0044 left this item the warning and it is the shape of the whole
        // design: ActuationBackend performs a step, and Maestro executes a file.
        for path in [Self.decisionLayer, Self.runner] {
            let text = try Self.code(path)
            #expect(text.contains(": ActuationBackend") == false)
            #expect(text.contains("ActuationBackendID(") == false)
        }
    }

    @Test("the cloud analysis flag is never constructed")
    func neverAsksForCloudAnalysis() throws {
        // --analyze is Maestro's cloud AI feature. Absent from the argument
        // vector by test, and absent from the sources by construction.
        for path in [Self.decisionLayer, Self.runner] {
            #expect(try Self.code(path).contains("--analyze") == false)
        }
    }

    @Test("Maestro's own configuration is read and never written")
    func maestroConfigurationIsNeverRewritten() throws {
        // PRO-0023's rule: the analytics file belongs to whoever set it up.
        // Saying what the invocation carries is the part Proctor owes; changing
        // a third party's configuration is not.
        let text = try Self.code(Self.runner)
        let configReferences = text.components(separatedBy: "analytics.json").count - 1
        #expect(configReferences > 0, "the telemetry disclosure should reference the file")
        for writer in ["write(to:", "createFile(atPath: NSHomeDirectory() + \"/.maestro",
                       "removeItem(atPath: NSHomeDirectory() + \"/.maestro"] {
            #expect(text.contains(writer) == false, "must not write \(writer)")
        }
    }

    // MARK: - AC16 · absent Maestro is a clean refusal

    @Test("with Maestro absent the action refuses without handing over a command")
    func absentMaestroRefusesCleanly() async throws {
        // The probe reads the filesystem and runs nothing, so an absent answer is
        // reachable on any machine — including one where Maestro IS installed,
        // which is the machine this was written on.
        let absent = ToolProbe(probe: {
            ToolPresence(tool: MaestroTool.binary, available: false, path: nil,
                         searched: ["/opt/homebrew/bin", "/usr/local/bin"],
                         missingCompanions: [])
        })
        let session = Session(ax: FakeAX(bundleId: "com.example.fake"), capture: FakeCapture(),
                              tools: ToolProbes(maestro: absent))
        do {
            _ = try await session.maestroFlow(path: "/tmp/does-not-matter.yaml", device: nil,
                                              runs: 1, pixelEvidence: false, timeoutMs: 1000)
            Issue.record("an absent Maestro must refuse rather than proceed")
        } catch let error as AgentError {
            #expect(error.code == .notImplemented)
            #expect(error.message.contains("Maestro is not installed"))
            let remedy = try #require(error.remedy)
            #expect(remedy.contains("proctor_doctor"))
            // PRO-0023: a tool result carries no command text for a model to
            // paste into a shell.
            for shell in ["brew ", "curl ", "npm ", "sh -c", "sudo "] {
                #expect(!remedy.contains(shell), "remedy should not carry \(shell)")
                #expect(!error.message.contains(shell))
            }
        }
    }

    // MARK: - AC17 · the lane's own conventions

    @Test("the audit trail names the flow and its repeats apart from every drive path")
    func auditNamesAreDistinct() {
        #expect(AuditTool.all.contains(AuditTool.maestroFlow))
        #expect(AuditTool.all.contains(AuditTool.maestroRepeat))
        #expect(Set(AuditTool.all).count == AuditTool.all.count,
                "every audited path needs its own name")
        // Named apart from proctor_ios.open because the claim differs: that one
        // gates on the app a device resolved, and this one on what a file
        // declares.
        #expect(AuditTool.maestroFlow != "proctor_ios.open")
    }

    @Test("the flow action is in the catalogue and carries what it does not prove")
    func catalogueDescribesTheCeiling() throws {
        let tool = try #require(ToolCatalogue.spec(named: "proctor_ios"))
        let schema = try #require(tool.inputSchema.objectValue)
        let properties = try #require(schema["properties"]?.objectValue)
        let actions = try #require(properties["action"]?.objectValue?["enum"]?.arrayValue)
        #expect(actions.contains(JSONValue.string("flow")))
        #expect(properties["runs"] != nil)

        // The description must not let a reader take flowPassed for an
        // observation Proctor made.
        #expect(tool.description.contains("not that Proctor observed"))
        #expect(tool.description.contains("declares"))
        #expect(tool.description.contains("never routed through proctor_act"))
    }

    @Test("an adjacent workspace config is found beside a flow, and its absence is not an error")
    func adjacentConfigIsLocated() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pro0049-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let flow = directory.appendingPathComponent("main.yaml")
        try "---\n- launchApp\n".write(to: flow, atomically: true, encoding: .utf8)
        #expect(Session.adjacentConfig(of: flow.path) == nil)

        try "appId: com.workspace.app\n".write(
            to: directory.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let found = try #require(Session.adjacentConfig(of: flow.path))
        #expect(found.contains("com.workspace.app"))
    }

    @Test("a directory with no record reads as a driver failure rather than an empty run")
    func missingRecordIsADriverFailure() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pro0049-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // What a bad device or an unparseable flow leaves behind: a log, and no
        // per-command record. Measured — one failing run left two timestamped
        // directories and only the second held a record.
        try "some log output\n".write(to: directory.appendingPathComponent("maestro.log"),
                                      atomically: true, encoding: .utf8)

        let read = Session.readMaestroRecord(in: directory.path)
        #expect(read.commands == nil)
        #expect(read.failureReason != nil)
        #expect(MaestroVerdict.decide(MaestroEvidence(exitCode: 1, recordFound: false,
                                                      failureReason: read.failureReason))
                    .verdict == .driverFailed)
    }

    @Test("a record nested below the debug directory is still found")
    func nestedRecordIsFound() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pro0049-\(UUID().uuidString)")
        let nested = directory.appendingPathComponent(".maestro/tests/2026-08-15_225126")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // --flatten-debug-output is passed, but the walk is recursive anyway: a
        // Maestro that stops honouring the flag must not turn every run into a
        // driver failure.
        let record = """
        [{"command":{"launchAppCommand":{"appId":"com.a.b"}},
          "metadata":{"status":"COMPLETED","sequenceNumber":0,"duration":10,"timestamp":1}}]
        """
        try record.write(to: nested.appendingPathComponent("commands-(x).json"),
                         atomically: true, encoding: .utf8)

        let read = Session.readMaestroRecord(in: directory.path)
        let commands = try #require(read.commands)
        #expect(commands.count == 1)
        #expect(commands[0].type == "launchAppCommand")
    }
}
