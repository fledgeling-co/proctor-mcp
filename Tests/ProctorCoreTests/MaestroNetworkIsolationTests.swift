import Foundation
import Testing
@testable import ProctorCore

@Suite("The Maestro lane's boundary, stated as measured rather than as hoped")
struct MaestroNetworkIsolationTests {

    @Test("the invocation carries no cloud flag, and the absence is asserted rather than assumed")
    func noCloudFlag() {
        let args = MaestroInvocation.arguments(flowPath: "/tmp/flow.yaml", udid: "UDID-1",
                                               debugDirectory: "/tmp/debug")
        // `--analyze` is Maestro's cloud AI feature and would send the run
        // somewhere. Its absence is a property of the vector, so it is checked
        // against the vector rather than trusted to a comment.
        #expect(!args.contains("--analyze"))
        #expect(!args.contains("--api-key"))
        #expect(!args.contains("--upload"))
        #expect(args.contains("--device"))
        #expect(args.contains("UDID-1"))
        #expect(args.contains("/tmp/flow.yaml"))
        // --flatten-debug-output, because the measured default nests artefacts
        // under a timestamp and one failing invocation left two such directories
        // where only the second held a record.
        #expect(args.contains("--flatten-debug-output"))
    }

    @Test("Proctor sets the analytics variable on its own subprocess, and nothing else")
    func environmentIsScopedToTheSubprocess() {
        let env = MaestroInvocation.environment
        #expect(env["MAESTRO_CLI_NO_ANALYTICS"] == "1")
        // Exactly one variable. A growing env block is how a tool ends up
        // configured by the thing that launches it rather than by its operator,
        // and each addition would owe its own measurement.
        #expect(env.count == 1)
        // And it is an environment variable, not a file. ~/.maestro/analytics.json
        // is the operator's configuration; silently rewriting third-party config
        // is the overreach PRO-0023 rules out, and setting a variable on a
        // process about to be launched is not the same act.
        #expect(!env.keys.contains { $0.contains("PATH") },
                "the block reaches beyond analytics")
    }

    @Test("the disclosure states the measurement, not a condition")
    func disclosureCarriesTheMeasurement() {
        let note = MaestroInvocation.telemetryNote
        // The previous wording said telemetry runs "when it is enabled in its
        // configuration". True, and it understates: measured 2026-08-25,
        // `maestro --version` opens two outbound TLS connections before running
        // any flow, and one persists whatever the analytics setting says. A lane
        // described as network-isolated that reaches the network on --version is
        // exactly the claim this campaign exists to catch, and it was Proctor's.
        #expect(note.contains("not network-isolated"),
                "the note still reads as a conditional rather than a measurement")
        #expect(note.contains("--version"), "the note does not say what was measured")
        #expect(note.contains("MAESTRO_CLI_NO_ANALYTICS"),
                "the note does not say what Proctor did about it")
        #expect(note.contains("the other still happens"),
                "the note claims the problem is solved when one connection remains")
        #expect(note.contains("analytics.json"),
                "the note does not say what Proctor deliberately did NOT touch")
    }

    @Test("a flow record parses, and an injected command is told from one the file asked for")
    func recordParsesAndMarksInjected() throws {
        // Maestro's own record is what Proctor reads; the YAML is Maestro's to
        // parse. Two of the commands in every record are injected by the
        // harness rather than written by the caller, and conflating them makes
        // a four-step flow report six steps the author did not write.
        let json = Data("""
        [{"command":{"launchAppCommand":{"appId":"com.apple.Preferences"}},
          "metadata":{"status":"COMPLETED","sequenceNumber":0,"duration":812}},
         {"command":{"assertConditionCommand":{"condition":{"visible":{"text":"General"}}}},
          "metadata":{"status":"COMPLETED","sequenceNumber":1,"duration":143}},
         {"command":{"tapOnElementCommand":{"selector":{"textRegex":"General"}}},
          "metadata":{"status":"FAILED","sequenceNumber":2,"duration":5011,
                      "error":{"message":"Element not found"}}}]
        """.utf8)
        let commands = try MaestroRecord.parse(json)
        #expect(commands.count == 3)
        #expect(commands[0].status == "COMPLETED")
        #expect(!commands[0].didFail)
        let failed = try #require(commands.last)
        #expect(failed.didFail, "a FAILED command did not report as a failure")
        #expect(failed.errorMessage?.contains("Element not found") == true,
                "the failure carries no reason, so a report of it says only that it failed")
        #expect(failed.durationMs == 5011, "timing was lost, and a 5s failure reads like a fast one")
        // The status vector is what repeats are scored on, so it has to be
        // derivable from the record alone.
        let vector = MaestroScore.vector(for: commands)
        #expect(vector.count == 3)
        #expect(vector.last?.isEmpty == false)
    }

    @Test("a record that is not a record is a named failure, not an empty flow")
    func rubbishRecordIsNamed() {
        // An unreadable record reported as zero commands is a flow that passed
        // by having nothing in it, which is the empty-denominator failure at the
        // scale of one run.
        var caught: Error?
        do { _ = try MaestroRecord.parse(Data("not json at all".utf8)) } catch { caught = error }
        #expect(caught != nil, "sixteen bytes of prose parsed as a flow record")
    }
}
