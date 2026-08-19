import Foundation
import Testing
@testable import ProctorCore

// PRO-0073. The operator CLI's surface, judged without a shell.

@Suite("CLI surface")
struct CLISurfaceTests {

    @Test("A1 · every tool in the catalogue has a verb")
    func everyToolHasAVerb() {
        // Derived rather than listed, so a 22nd tool is a red test rather than a
        // gap somebody notices later.
        #expect(CLISurface.verbs.count == ToolCatalogue.all.count)
        for spec in ToolCatalogue.all {
            let verb = CLISurface.verbs.first { $0.tool == spec.name }
            #expect(verb != nil, "\(spec.name) has no verb")
        }
        #expect(CLISurface.verb(named: "snapshot")?.tool == "proctor_snapshot")
        #expect(CLISurface.verb(named: "doctor")?.tool == "proctor_doctor")
    }

    @Test("A1 · verb names are unique and do not collide with the service verbs")
    func namesUnique() {
        let all = CLISurface.allVerbNames
        #expect(Set(all).count == all.count, "a verb name is claimed twice: \(all.sorted())")
    }

    @Test("A5 · reads do not queue, and everything that actuates does")
    func readsDoNotQueue() {
        // The three-lane model: a read never reaches the step loop, so a
        // `proctor snapshot` cannot serialise a person's debugging behind a
        // model's run.
        for name in ["snapshot", "find", "capture", "zoom", "wait", "assert", "menu", "inspect"] {
            #expect(CLISurface.verb(named: name)?.queues == false,
                    "\(name) is a read and must not take a lane")
        }
        for name in ["act", "flow", "stability", "kill", "guest"] {
            #expect(CLISurface.verb(named: name)?.queues == true,
                    "\(name) actuates and must take a lane")
        }
    }

    @Test("A3 · exit 1 and exit 3 are never the same answer")
    func verdictAndUnreachableAreDistinct() {
        // CI reads an exit code rather than prose. Collapsing these turns "the
        // app is broken" and "the agent is not running" into one signal.
        #expect(CLISurface.exit(for: .agentUnavailable) == .agentUnreachable)
        #expect(CLISurface.exit(for: .actionFailed) == .verdictFailed)
        #expect(CLISurface.Exit.agentUnreachable.rawValue == 3)
        #expect(CLISurface.Exit.verdictFailed.rawValue == 1)
    }

    @Test("A3 · a gate's refusal exits 4, and a missing grant exits 5")
    func refusalsAndGrants() {
        for code in [AgentError.Code.policyDenied, .queueBusy, .haltedByPerson] {
            #expect(CLISurface.exit(for: code) == .refused, "\(code.rawValue) should exit 4")
        }
        for code in [AgentError.Code.permissionAccessibility, .permissionScreenRecording,
                     .reflectorUnavailable, .secureInputActive] {
            #expect(CLISurface.exit(for: code) == .notReady, "\(code.rawValue) should exit 5")
        }
    }

    @Test("every exit code carries a distinct meaning")
    func exitCodesWellFormed() {
        let codes = CLISurface.Exit.allCases
        #expect(Set(codes.map(\.rawValue)).count == codes.count)
        #expect(Set(codes.map(\.meaning)).count == codes.count)
        #expect(CLISurface.Exit.ok.rawValue == 0)
    }

    @Test("A8 · completion is generated from the catalogue, for the shells that have one")
    func completion() {
        for shell in ["zsh", "bash"] {
            let script = CLISurface.completionScript(shell: shell)
            #expect(script != nil)
            // It lists what the binary actually accepts, so it cannot drift.
            #expect(script?.contains("snapshot") == true)
            #expect(script?.contains("doctor") == true)
            #expect(script?.contains("tui") == true)
        }
        #expect(CLISurface.completionScript(shell: "fish") == nil,
                "an unsupported shell returns nothing rather than a broken script")
    }

    @Test("A7 · nothing the CLI prints carries an install command")
    func installsNothing() {
        // The surface where this rule is easiest to break. Proctor prints
        // commands for a person to run; it never runs them, and it never ships
        // one inside its own output.
        var text = CLISurface.Exit.allCases.map(\.meaning).joined(separator: " ")
        text += CLISurface.allVerbNames.joined(separator: " ")
        text += CLISurface.completionScript(shell: "zsh") ?? ""
        text += CLISurface.completionScript(shell: "bash") ?? ""
        for marker in CLISurface.forbiddenInstallMarkers {
            #expect(!text.contains(marker), "the CLI surface carries “\(marker)”")
        }
    }

    @Test("the destructive tools keep their annotation through the verb table")
    func destructiveCarried() {
        // A wrapper script gates on this without parsing English, so it must
        // survive the translation from tool to verb.
        for name in ["act", "flow", "stability", "kill", "guest", "unlock"] {
            #expect(CLISurface.verb(named: name)?.destructive == true,
                    "\(name) lost its destructive annotation")
        }
        #expect(CLISurface.verb(named: "snapshot")?.destructive == false)
    }
}

@Suite("Shipped binary names")
struct CLIBinaryNameTests {

    // The defect this suite exists for: `swift build` linked a product named
    // `proctor` over the UI product `Proctor` on a case-insensitive volume,
    // reported success, and left a binary that launched a SwiftUI window when
    // asked for usage. Neither SwiftPM nor codesign nor the app bundle notices.
    @Test("no two shipped binaries differ only by case, because the volume does not")
    func namesAreDistinctCaseInsensitively() {
        let folded = CLISurface.shippedBinaries.map { $0.lowercased() }
        #expect(Set(folded).count == CLISurface.shippedBinaries.count)
    }

    @Test("the CLI ships under a different filename from the name it is invoked under")
    func invokedNameIsNotAShippedName() {
        #expect(!CLISurface.shippedBinaries.contains(CLISurface.invokedAs))
        #expect(CLISurface.shippedBinaries.contains("proctor-cli"))
    }

    @Test("every shipped binary is signed and copied by the build script")
    func buildScriptCarriesEveryBinary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appending(path: "scripts/build-app.sh"),
                                encoding: .utf8)
        for name in CLISurface.shippedBinaries {
            #expect(script.contains("$MACOS_DIR/\(name)"),
                    "build-app.sh never places or signs \(name)")
        }
    }
}

@Suite("Reading a verdict out of a reply")
struct CLIVerdictTests {

    private func lanes(_ pairs: [(String, String)]) -> JSONValue {
        .object(["lanes": .array(pairs.map { .object(["lane": .string($0.0),
                                                     "state": .string($0.1)]) })])
    }

    @Test("A6 · a named lane that is not ready exits 5, whatever the rest of the reply says")
    func namedLaneNotReady() {
        let reply = lanes([("mac", "missing-grant"), ("ios", "ready")])
        #expect(CLISurface.exit(forReply: reply, lane: "mac") == .notReady)
        #expect(CLISurface.laneState(reply, lane: "mac") == "missing-grant")
    }

    @Test("A6 · a named lane that is ready exits 0 even when another lane is not")
    func namedLaneNarrowsTheQuestion() {
        let reply = lanes([("mac", "ready"), ("ios", "no-simulator")])
        #expect(CLISurface.exit(forReply: reply, lane: "mac") == .ok)
        // Without the flag the same reply is read as a whole-machine question.
        #expect(CLISurface.exit(forReply: reply, lane: "ios") == .notReady)
    }

    @Test("A6 · a lane the reply never mentions reads as absent, not as not-ready-for-a-reason")
    func anAbsentLaneIsNamedAsAbsent() {
        let reply = lanes([("mac", "ready")])
        #expect(CLISurface.exit(forReply: reply, lane: "vision") == .notReady)
        #expect(CLISurface.laneState(reply, lane: "vision") == "absent")
    }

    @Test("a failed assertion exits 1 — the call worked and the check did not")
    func aFailedCheckIsNotAFailedCall() {
        let reply = JSONValue.object(["assertions": .array([
            .object(["ok": .bool(true)]), .object(["ok": .bool(false)]),
        ])])
        #expect(CLISurface.exit(forReply: reply, lane: nil) == .verdictFailed)
    }

    @Test("a batch that stopped part way exits 1")
    func aHaltedBatchIsAVerdict() {
        #expect(CLISurface.exit(forReply: .object(["failedAt": .number(2)]), lane: nil)
                == .verdictFailed)
        // An explicit null is the wire saying nothing failed, not a failure at
        // step nil. Reading it as a failure would fail every clean batch.
        #expect(CLISurface.exit(forReply: .object(["failedAt": .null]), lane: nil) == .ok)
    }

    @Test("a clean reply exits 0, and an empty one is not read as a failure")
    func silenceIsNotAVerdict() {
        #expect(CLISurface.exit(forReply: .object([:]), lane: nil) == .ok)
        #expect(CLISurface.exit(forReply: .object(["assertions": .array([
            .object(["ok": .bool(true)])])]), lane: nil) == .ok)
    }
}
