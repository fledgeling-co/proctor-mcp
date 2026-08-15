import Testing
import Foundation
@testable import ProctorCore

// PRO-0049. The Maestro flow lane's decision half, proved without Maestro, a
// simulator or a JVM — which is why every decision lives in a pure function.
//
// Two fixtures are Maestro's own bytes, captured from live runs on 2026-08-15
// (maestro 2.4.0, iPhone 16 Pro, iOS 18.2), so the parser is proved against what
// Maestro actually wrote rather than against what this build expects it to write.
// Every synthesised record in here is built to the shape those two established.

@Suite("PRO-0049 · Maestro flow lane")
struct MaestroRunTests {

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)"))
    }

    static func command(_ type: String, _ status: String, _ sequence: Int,
                        duration: Int = 100, parameters: JSONValue = .null) -> MaestroCommand {
        MaestroCommand(type: type, parameters: parameters, status: status,
                       sequenceNumber: sequence, durationMs: duration,
                       timestampMs: Double(1_786_798_296_000 + sequence))
    }

    /// The seven-command shape of the live passing run.
    static func passingRun(duration: Int = 100) -> [MaestroCommand] {
        [command("defineVariablesCommand", "COMPLETED", 0, duration: duration),
         command("applyConfigurationCommand", "COMPLETED", 1, duration: duration),
         command("launchAppCommand", "COMPLETED", 2, duration: duration),
         command("assertConditionCommand", "COMPLETED", 3, duration: duration,
                 parameters: .object(["condition": .string("General")])),
         command("tapOnElement", "COMPLETED", 4, duration: duration,
                 parameters: .object(["text": .string("General")])),
         command("backPressCommand", "COMPLETED", 5, duration: duration)]
    }

    // MARK: - AC1 · a flow runs and reports per-command

    @Test("Maestro's own passing record parses in sequence order, with injected commands marked")
    func parsesLivePassingRecord() throws {
        let commands = try MaestroRecord.parse(try Self.fixture("maestro-commands-pass.json"))
        #expect(commands.count == 7)
        // The live array arrived as sequence [2, 0, 1, ...]; reading it
        // positionally attributes each status to the wrong command.
        #expect(commands.map(\.sequenceNumber) == Array(0..<7))
        #expect(commands.allSatisfy { $0.status == "COMPLETED" })
        #expect(commands[0].isInjected)
        #expect(commands[1].isInjected)
        #expect(commands[2].isInjected == false)
        #expect(commands[2].type == "launchAppCommand")
        // Durations are read and carried; they are simply never hashed.
        #expect(commands.contains { $0.durationMs > 0 })
    }

    @Test("Maestro's own failing record carries the error and its hierarchy")
    func parsesLiveFailingRecord() throws {
        let commands = try MaestroRecord.parse(try Self.fixture("maestro-commands-fail.json"))
        let failed = commands.filter(\.didFail)
        #expect(failed.count == 1)
        #expect(failed[0].type == "assertConditionCommand")
        #expect(failed[0].errorMessage?.contains("Assertion is false") == true)
        // Maestro's own view tree — the fourth iOS channel PRO-0048 reserved.
        // Its presence travels; the tree itself never reaches a score.
        #expect(failed[0].hasHierarchy)
    }

    @Test("a record with no commands is a parse failure, not an empty run")
    func emptyRecordIsAFailure() {
        #expect(throws: MaestroParseFailure.empty) {
            _ = try MaestroRecord.parse(Data("[]".utf8))
        }
    }

    // MARK: - AC3 · what moves the score and what does not

    @Test("identical repeats fold to deterministic")
    func identicalRepeatsAreDeterministic() {
        let vectors = (0..<5).map { _ in MaestroScore.vector(for: Self.passingRun()) }
        let fold = StabilityScore.fold(perRun: vectors, stepCount: 6, runs: 5)
        #expect(fold.deterministic)
        #expect(fold.firstDivergence == nil)
    }

    @Test("a changed status diverges at that command's position")
    func changedStatusDiverges() {
        var altered = Self.passingRun()
        altered[4] = Self.command("tapOnElement", "FAILED", 4,
                                  parameters: .object(["text": .string("General")]))
        let vectors = [MaestroScore.vector(for: Self.passingRun()),
                       MaestroScore.vector(for: altered)]
        let fold = StabilityScore.fold(perRun: vectors, stepCount: 6, runs: 2)
        #expect(fold.firstDivergence == 4)
        #expect(fold.deterministic == false)
    }

    @Test("a changed command parameter diverges, because identity is not the type alone")
    func changedParameterDiverges() {
        var altered = Self.passingRun()
        altered[4] = Self.command("tapOnElement", "COMPLETED", 4,
                                  parameters: .object(["text": .string("About")]))
        let vectors = [MaestroScore.vector(for: Self.passingRun()),
                       MaestroScore.vector(for: altered)]
        #expect(StabilityScore.fold(perRun: vectors, stepCount: 6, runs: 2).firstDivergence == 4)
    }

    @Test("changed durations and timestamps do not diverge — measured 634/91/88/96/91 ms")
    func durationsNeverEnterTheScore() {
        // The measured spread on one unchanged command across five live repeats.
        let vectors = [634, 91, 88, 96, 91].map { MaestroScore.vector(for: Self.passingRun(duration: $0)) }
        let fold = StabilityScore.fold(perRun: vectors, stepCount: 6, runs: 5)
        #expect(fold.deterministic)
        #expect(fold.firstDivergence == nil)
        #expect(fold.stepInstability.allSatisfy { $0 == 0 })
    }

    @Test("an error message never enters the score")
    func errorTextNeverEntersTheScore() {
        var a = Self.passingRun(); var b = Self.passingRun()
        a[3].status = "FAILED"; a[3].errorMessage = "Assertion is false: \"General\" is visible"
        b[3].status = "FAILED"; b[3].errorMessage = "Assertion is false: \"About\" is visible"
        #expect(MaestroScore.cell(for: a[3]) == MaestroScore.cell(for: b[3]))
    }

    @Test("parameter canonicalisation is key-order independent")
    func parametersCanonicaliseStably() {
        let one = JSONValue.object(["b": .number(1), "a": .string("x")])
        let two = JSONValue.object(["a": .string("x"), "b": .number(1)])
        #expect(MaestroScore.canonicalParameters(one) == MaestroScore.canonicalParameters(two))
        // 1 and 1.0 are one command, not two.
        #expect(MaestroScore.canonicalParameters(.number(1)) == "1")
    }

    // MARK: - AC2, AC18 · the basis of the divergence, and the lane

    @Test("a single repeat cannot be deterministic")
    func oneRepeatIsNeverDeterministic() {
        let fold = StabilityScore.fold(perRun: [MaestroScore.vector(for: Self.passingRun())],
                                       stepCount: 6, runs: 1)
        #expect(fold.deterministic == false)
        #expect(fold.firstDivergence == nil)
    }

    @Test("the lane names itself")
    func laneIsNamed() {
        #expect(MaestroInvocation.lane == "maestro")
    }

    // MARK: - AC4, AC6, AC12 · the verdict ladder

    @Test("no per-command record is a driver failure, whatever the exit code said")
    func noRecordIsDriverFailure() {
        for exitCode in Int32(0)...1 {
            let outcome = MaestroVerdict.decide(
                MaestroEvidence(exitCode: exitCode, recordFound: false))
            #expect(outcome.verdict == .driverFailed)
            #expect(outcome.verdict.isScoreable == false)
        }
    }

    @Test("exit 1 with a failed app command is a flow failure, not a driver one")
    func exitOneWithRecordIsFlowFailure() {
        var commands = Self.passingRun()
        commands[3].status = "FAILED"
        let outcome = MaestroVerdict.decide(
            MaestroEvidence(exitCode: 1, recordFound: true, commands: commands,
                            targetRunningBefore: true, targetRunningAfter: true))
        #expect(outcome.verdict == .flowFailed)
        #expect(outcome.verdict.isScoreable)
        // The residue the ladder cannot separate is named rather than claimed away.
        #expect(outcome.note.contains("hit test"))
    }

    @Test("identical exit codes, opposite verdicts — the record is the discriminator")
    func exitCodeDoesNotDecide() {
        var failing = Self.passingRun()
        failing[3].status = "FAILED"
        let withRecord = MaestroVerdict.decide(
            MaestroEvidence(exitCode: 1, recordFound: true, commands: failing))
        let withoutRecord = MaestroVerdict.decide(
            MaestroEvidence(exitCode: 1, recordFound: false))
        #expect(withRecord.verdict == .flowFailed)
        #expect(withoutRecord.verdict == .driverFailed)
    }

    @Test("an app that went away outranks a failed assertion")
    func appGoneOutranksFlowFailed() {
        var commands = Self.passingRun()
        commands[3].status = "FAILED"
        let outcome = MaestroVerdict.decide(
            MaestroEvidence(exitCode: 1, recordFound: true, commands: commands,
                            targetRunningBefore: true, targetRunningAfter: false))
        #expect(outcome.verdict == .appGone)
        #expect(outcome.verdict.isAppFault)
    }

    @Test("a harness-only failure is a driver failure, not the app's")
    func harnessFailureIsDriverFailure() {
        for harness in ["launchAppCommand", "runScriptCommand", "evalScriptCommand",
                        "runFlowCommand"] {
            var commands = Self.passingRun()
            commands[2] = Self.command(harness, "FAILED", 2)
            let outcome = MaestroVerdict.decide(
                MaestroEvidence(exitCode: 1, recordFound: true, commands: commands,
                                targetRunningBefore: true, targetRunningAfter: true))
            #expect(outcome.verdict == .driverFailed, "\(harness) should not be the app's fault")
            #expect(outcome.verdict.isScoreable == false)
        }
    }

    @Test("a harness failure alongside an app failure stays the app's")
    func mixedFailureIsStillFlowFailed() {
        var commands = Self.passingRun()
        commands[2] = Self.command("launchAppCommand", "FAILED", 2)
        commands[3].status = "FAILED"
        let outcome = MaestroVerdict.decide(
            MaestroEvidence(exitCode: 1, recordFound: true, commands: commands,
                            targetRunningBefore: true, targetRunningAfter: true))
        #expect(outcome.verdict == .flowFailed)
    }

    @Test("a liveness channel that stopped answering is the device, not the app")
    func livenessGoneIsDriverFailure() {
        var commands = Self.passingRun()
        commands[3].status = "FAILED"
        let outcome = MaestroVerdict.decide(
            MaestroEvidence(exitCode: 1, recordFound: true, commands: commands,
                            targetRunningBefore: true, targetRunningAfter: nil))
        #expect(outcome.verdict == .driverFailed)
    }

    @Test("a clean run is flowPassed and claims only what the driver reported")
    func passClaimsOnlyWhatItCan() {
        let outcome = MaestroVerdict.decide(
            MaestroEvidence(exitCode: 0, recordFound: true, commands: Self.passingRun(),
                            targetRunningBefore: true, targetRunningAfter: true))
        #expect(outcome.verdict == .flowPassed)
        #expect(outcome.verdict.isAttributed)
        #expect(outcome.note.contains("does not say Proctor observed"))
    }

    @Test("a timeout is a driver failure and says so")
    func timeoutIsDriverFailure() {
        let outcome = MaestroVerdict.decide(
            MaestroEvidence(exitCode: -1, timedOut: true, recordFound: false))
        #expect(outcome.verdict == .driverFailed)
        #expect(outcome.note.contains("did not finish within the bound"))
    }

    // MARK: - AC19 · the record is found by glob, not by construction

    @Test("both observed record filenames are found, and nothing else is")
    func recordsAreFoundByGlob() {
        let listing = [
            "/d/.maestro/tests/2026-08-15_225126/commands-(settings).json",
            "/d/commands-(settings.yaml).json",
            "/d/maestro.log",
            "/d/ai-(settings).json",
            "/d/ai-report-settings.html",
            "/d/screenshot-x-(settings).png"
        ]
        let found = MaestroRecord.records(in: listing)
        #expect(found.count == 2)
        #expect(found.contains("/d/commands-(settings.yaml).json"))
        #expect(found.contains("/d/.maestro/tests/2026-08-15_225126/commands-(settings).json"))
    }

    // MARK: - AC5, AC13, AC14 · the argument vector and the disclosures

    @Test("the invocation flattens its debug output and never asks for the cloud")
    func invocationIsSafeAndFlat() {
        let arguments = MaestroInvocation.arguments(
            flowPath: "/f/x.yaml", udid: "UD-1", debugDirectory: "/tmp/d")
        #expect(arguments.contains("--flatten-debug-output"))
        #expect(arguments.contains("--debug-output"))
        #expect(arguments.contains("--no-ansi"))
        #expect(arguments.contains("--analyze") == false)
        #expect(arguments.contains { $0.contains("api-key") } == false)
    }

    @Test("the absence message explains without handing over a command to run")
    func absenceCarriesNoCommandText() {
        let text = MaestroInvocation.absence.missing + " " + MaestroInvocation.absence.askThePerson
        #expect(text.contains("proctor_doctor"))
        for shell in ["brew ", "curl ", "install.sh", "npm ", "sh -c", "|"] {
            #expect(text.contains(shell) == false, "absence text should not carry \(shell)")
        }
    }
}
