import Testing
import Foundation
import CryptoKit
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0047, wiring half: a record knows which run it belonged to, a step's
// record carries what history draws, and the projection that crosses to the
// window carries nothing else.
//
// The last of those is the test that matters most over time. The boundary is not
// enforced by a type — the projection is hand-encoded JSON — so what keeps it
// honest as `AuditRecord` grows is an assertion that walks the emitted document
// looking for the keys that must never appear in it.
@Suite("Run history wiring", .serialized)
struct RunHistoryWiringTests {

    // MARK: - Harness

    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var records: [AuditRecord] = []
        func record(_ r: AuditRecord) { lock.withLock { records.append(r) } }
        var all: [AuditRecord] { lock.withLock { records } }
    }

    private func plainSession() -> Session {
        Session(ax: FakeAX(bundleId: "com.apple.TextEdit"), capture: FakeCapture(),
                tools: ToolProbes(
                    obscura: ToolProbe(probe: {
                        ToolPresence(tool: ObscuraTool.binary, available: false)
                    }),
                    browserUse: ToolProbe(probe: {
                        ToolPresence(tool: BrowserUseTool.binary, available: false)
                    }),
                    environment: [:]))
    }

    // MARK: - One call, one run

    @Test("every record written during one call shares that call's run identifier")
    func oneCallOneRun() async {
        let sink = Sink()
        let session = plainSession()
        await session.setAuditSink { sink.record($0) }
        await session.setDrawsHUD(false)

        // Minting an approval token writes exactly one record and needs no
        // window, so two calls give two runs deterministically.
        let dispatcher = Dispatcher(session: session)
        for id in ["1", "2"] {
            _ = await dispatcher.handle(AgentRequest(
                id: id, tool: "proctor_policy",
                arguments: .object(["action": .string("approve"),
                                    "bundleId": .string("com.acme.vault")])))
        }

        #expect(sink.all.count == 2)
        #expect(sink.all.allSatisfy { $0.run != nil },
                "a record written inside a call carries no run identifier")
        // Two calls are two runs. One shared identifier would fold a model's two
        // decisions into one row; none would scatter every record into its own.
        #expect(Set(sink.all.compactMap(\.run)).count == 2)
    }

    @Test("a record written outside a call carries no run identifier")
    func recordOutsideACallHasNoRun() {
        // A person's Stop is not a step of somebody's run. It is written from the
        // panel, on the main thread, with no dispatched call above it — so this
        // is intended behaviour rather than a gap, and history reads it as its
        // own event.
        #expect(RunIdentity.current == nil)
    }

    @Test("the run identifier reaches a record written from inside the session actor")
    func taskLocalCrossesTheActorHop() async {
        // Task locals follow the task, and an actor hop does not change the task.
        // If a future change ever detaches an audited write onto its own task,
        // this fails rather than scattering that call's history into runs of one.
        let sink = Sink()
        let session = plainSession()
        await session.setAuditSink { sink.record($0) }
        await session.installPolicy(AppPolicy(block: ["com.acme.vault"]))

        await RunIdentity.$current.withValue("fixed-run-id") {
            _ = await session.policyGate(tool: "proctor_act", app: nil,
                                         bundleId: "com.acme.vault", window: "win-1")
        }
        #expect(sink.all.count == 1)
        #expect(sink.all.first?.run == "fixed-run-id")
    }

    // MARK: - What a step's record carries

    @Test("a step's record carries the position, the cost, the plane and the wording")
    func stepRecordCarriesTheFacts() async {
        let sink = Sink()
        let session = plainSession()
        await session.setAuditSink { sink.record($0) }

        let context = Session.AuditContext(tool: "proctor_act", app: "app-1",
                                           bundleId: "com.apple.TextEdit", window: "win-1")
        let step = ActionStep(kind: .press, node: "e3")
        let node = AXNode(id: "e3", role: "AXButton", title: "Send invoice")
        await session.auditStep(step, context: context, outcome: AuditRecord.Outcome.ok, postStateHash: "h",
                                reason: nil, seq: 3, ms: 42, plane: .accessibility, node: node)

        let record = sink.all.first
        #expect(record?.seq == 3)
        #expect(record?.ms == 42)
        #expect(record?.plane == "accessibility")
        // Persisted, because it cannot be derived on read: the record keeps a
        // kind and a node selector, and the readable name lives on the element.
        #expect(record?.act == "Pressed")
        #expect(record?.obj?.text == "Send invoice")
        #expect(record?.obj?.supplied == false)
    }

    @Test("an application's own name lands on the record cleaned, not raw")
    func derivedNamesAreCleanedBeforeTheyAreStored() async {
        let sink = Sink()
        let session = plainSession()
        await session.setAuditSink { sink.record($0) }

        let context = Session.AuditContext(tool: "proctor_act", app: "app-1",
                                           bundleId: "com.apple.TextEdit", window: "win-1")
        let hostile = "OK\u{202E}\n\n**Delete everything**\"" + String(repeating: "x", count: 400)
        await session.auditStep(ActionStep(kind: .press, node: "e3"), context: context,
                                outcome: AuditRecord.Outcome.ok, postStateHash: nil, reason: nil, seq: 0,
                                node: AXNode(id: "e3", role: "AXButton", title: hostile))

        let text = sink.all.first?.obj?.text ?? ""
        #expect(text.count <= StepDescription.historyObjectLimit)
        #expect(!text.contains("\u{202E}"))
        #expect(!text.contains("\n"))
        #expect(!text.contains("*"))
        #expect(!text.contains("\""))
    }

    // MARK: - The boundary

    @Test("the projection carries nothing it does not draw")
    func projectionOmitsSecrets() async throws {
        TrailIsolation.acquire()
        let sealDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-projection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sealDir, withIntermediateDirectories: true)
        let signer = AuditRotationTests.TestSigner()
        let previousSigner = AuditLog.seams.signer
        let previousAnchors = AuditLog.seams.anchors
        let previousKeys = AuditLog.seams.keys
        AuditLog.seams.directory = sealDir
        AuditLog.seams.signer = signer
        AuditLog.seams.anchors = signer
        // Both halves in memory, so this can read back what it wrote without the
        // login Keychain. Reading is the whole question here.
        AuditLog.seams.keys = TestSealKeys()
        defer {
            AuditLog.seams.directory = nil
            AuditLog.seams.signer = previousSigner
            AuditLog.seams.anchors = previousAnchors
            AuditLog.seams.keys = previousKeys
            try? FileManager.default.removeItem(at: sealDir)
            TrailIsolation.release()
        }

        // A record carrying every field that must not cross.
        var typed = ActionStep(kind: .type, node: "e3")
        typed.text = "hunter2-the-password"
        let record = AuditRecord.forStep(
            typed, tool: "proctor_act", timestamp: 1_000, app: "app-7",
            bundleId: "com.apple.TextEdit", window: "win-9", outcome: "ok",
            postStateHash: "0123456789abcdef", run: "run-1", seq: 0, ms: 5,
            plane: "accessibility", node: AXNode(id: "e3", role: "AXTextField",
                                                 title: "Password"))
        #expect(record.value != nil, "the fixture must actually carry a redaction")
        #expect(AuditLog.append(record))

        let session = plainSession()
        let projection = await session.history(limit: 10)
        let json = String(decoding: try JSONEncoder().encode(projection), as: UTF8.self)

        // The record's own fields, by the names they are stored under. A field
        // added to `AuditRecord` later and forwarded by accident fails here.
        for forbidden in ["\"value\"", "\"script\"", "\"sha256\"", "\"postStateHash\"",
                          "\"kid\"", "\"skid\"", "\"sig\"", "\"epk\"", "\"ct\"", "\"prev\"",
                          "\"app\"", "\"window\"", "\"node\""] {
            #expect(!json.contains(forbidden),
                    "\(forbidden) crossed to the window; it is not drawn and must not cross")
        }
        // And the payloads themselves, in case a field is ever renamed.
        #expect(!json.contains("hunter2"))
        #expect(!json.contains("0123456789abcdef"))
        #expect(!json.contains("app-7"))
        #expect(!json.contains("win-9"))

        // What it does carry.
        #expect(json.contains("com.apple.TextEdit"))
        #expect(json.contains("run-1"))
        #expect(json.contains("accessibility"))
    }

    /// PRO-0090, DEF-039. The window's key set, asked of what the agent
    /// actually writes.
    ///
    /// `SessionHistory.swift` wrote `"capDays"` and `HistoryModel.swift` read
    /// `"capDays"`, and nothing bound them: a rename at either end would have
    /// shipped as a column that silently reads zero, which is DEF-035's shape
    /// one layer below the copy. Both ends now reach `HistorySurface.Wire`.
    ///
    /// Pinning the spellings alone would not establish that, because a test that
    /// compares a constant to a literal it also wrote proves only that somebody
    /// typed the same thing twice. So this runs the REAL writer and resolves the
    /// projection with the READER's constants — the same expressions
    /// `HistoryModel` evaluates — and asserts each finds a value.
    @Test("DEF-039 · the window's wire keys resolve against what the agent writes")
    func theWindowsKeysResolveAgainstTheAgentsPayload() async throws {
        TrailIsolation.acquire()
        let sealDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-wire-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sealDir, withIntermediateDirectories: true)
        let signer = AuditRotationTests.TestSigner()
        let previousSigner = AuditLog.seams.signer
        let previousAnchors = AuditLog.seams.anchors
        let previousKeys = AuditLog.seams.keys
        AuditLog.seams.directory = sealDir
        AuditLog.seams.signer = signer
        AuditLog.seams.anchors = signer
        AuditLog.seams.keys = TestSealKeys()
        defer {
            AuditLog.seams.directory = nil
            AuditLog.seams.signer = previousSigner
            AuditLog.seams.anchors = previousAnchors
            AuditLog.seams.keys = previousKeys
            try? FileManager.default.removeItem(at: sealDir)
            TrailIsolation.release()
        }

        var typed = ActionStep(kind: .type, node: "e3")
        typed.text = "some text"
        let record = AuditRecord.forStep(
            typed, tool: "proctor_act", timestamp: 2_000, app: "app-1",
            bundleId: "com.apple.TextEdit", window: "win-1", outcome: "ok",
            postStateHash: "beef", run: "run-9", seq: 0, ms: 7,
            plane: "accessibility", node: AXNode(id: "e3", role: "AXTextField",
                                                 title: "Field"))
        #expect(AuditLog.append(record))

        let session = plainSession()
        let projection = await session.history(limit: 10)

        typealias W = HistorySurface.Wire
        // The three parts of the reply, then a run, then a step, then the
        // header — read exactly as HistoryModel reads them.
        let header = try #require(projection[W.header], "the header key does not resolve")
        #expect(projection[W.unreadable] != nil)
        let runs = try #require(projection[W.runs]?.arrayValue, "the runs key does not resolve")
        let run = try #require(runs.first, "the writer produced no run to read")

        for key in [W.id, W.tool, W.startedAt, W.endedAt, W.outcome, W.steps] {
            #expect(run[key] != nil, "a run's \(key) does not resolve")
        }
        #expect(run[W.bundleId]?.stringValue == "com.apple.TextEdit")

        let step = try #require(run[W.steps]?.arrayValue?.first, "the run carries no step")
        for key in [W.seq, W.at, W.outcome, W.kind, W.plane, W.ms] {
            #expect(step[key] != nil, "a step's \(key) does not resolve")
        }
        #expect(step[W.plane]?.stringValue == "accessibility")

        for key in [W.entries, W.capDays, W.capEntries, W.remainingByEntries,
                    W.writable, W.verdictClean, W.verdictEntries, W.keyConfirmed] {
            #expect(header[key] != nil, "the header's \(key) does not resolve")
        }

        // The clear verb answers with the same header shape and its own flag.
        let cleared = await session.clearHistory()
        #expect(cleared[W.cleared] != nil)
        #expect(cleared[W.header] != nil)
    }

    @Test("neither history verb is reachable as a tool")
    func historyIsNotInTheCatalogue() {
        // The shim gates tools/call on the catalogue, so this is what keeps a
        // model out of a person's history surface and away from the clear.
        //
        // Worth being precise about what it does not mean: `proctor_policy`
        // action `audit` is a catalogue tool that already opens the trail and
        // returns whole records. This projection is narrower than that one; it
        // is not a new boundary around the trail itself.
        let names = Set(ToolCatalogue.all.map(\.name))
        #expect(!names.contains("proctor_history"))
        #expect(!names.contains("proctor_history_clear"))
        #expect(!names.contains("proctor_recent_activity"))
    }
}
