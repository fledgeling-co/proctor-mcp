import Testing
import Foundation
import CryptoKit
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0032, agent half: the trail actually gets signed on the way to disk, and a
// lane recommendation is recorded without becoming a browsing history.
//
// **Nothing here touches the operator's trail, the keychain or the secure
// element.** The trail is redirected into a per-test temporary directory, and the
// signer and the end-mark are injected in-process. That is not tidiness: an
// earlier wave's suite drove a real `Session` without redirecting its sink, wrote
// 17 entries into the live trail and fired PRO-0013's deliberately irreversible
// plaintext-to-sealed conversion on real history. The interlock in `AuditLog`
// exists because of that, and this suite adds its own directory on top.
//
// Serialized because `AuditLog`'s state, seams and file lock are process-wide.
@Suite("Audit chain wiring", .serialized)
struct AuditChainWiringTests {

    // MARK: - An in-process signer, standing in for the secure element

    final class TestSigner: AuditSigning, AuditAnchoring, @unchecked Sendable {
        private let lock = NSLock()
        private var key: P256.Signing.PrivateKey?
        private var anchor: AuditChain.Anchor?
        var keyClass: AuditChain.KeyClass = .software

        init(available: Bool = true) { key = available ? P256.Signing.PrivateKey() : nil }

        /// The one failure that must never produce an unsigned entry.
        func makeUnreachable() { lock.withLock { key = nil } }

        var signingKeyId: String? {
            lock.withLock { key.map { AuditChain.keyId(forPublicKey: $0.publicKey.rawRepresentation) } }
        }
        var signingKeyClass: AuditChain.KeyClass? { lock.withLock { key == nil ? nil : keyClass } }

        func sign(_ material: Data) -> Data? {
            lock.withLock { try? key?.signature(for: material).rawRepresentation }
        }

        func verifySignature(_ signature: Data, over material: Data) -> Bool {
            lock.withLock {
                guard let key, let parsed = try? P256.Signing.ECDSASignature(
                    rawRepresentation: signature) else { return false }
                return key.publicKey.isValidSignature(parsed, for: material)
            }
        }

        func loadAnchor() -> AuditChain.Anchor? { lock.withLock { anchor } }
        @discardableResult
        func saveAnchor(_ anchor: AuditChain.Anchor) -> Bool {
            lock.withLock { self.anchor = anchor }
            return true
        }
    }

    /// A trail of its own, and the seams pointed at it. Restores everything after,
    /// because these are process-wide.
    private func withTrail(signer: TestSigner = TestSigner(),
                           seed: [String] = [],
                           _ body: (URL, TestSigner) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-wiring-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        TrailIsolation.acquire()
        let previousSigner = AuditLog.seams.signer
        let previousAnchors = AuditLog.seams.anchors
        AuditLog.seams.directory = dir
        AuditLog.seams.signer = signer
        AuditLog.seams.anchors = signer
        // The sealing key is read from a file beside the trail before anything
        // reaches the key store — that is PRO-0013's design, and here it is also
        // what keeps this suite off the operator's keychain entirely. Without a
        // key on disk the first seal would fall through to `SecItemAdd`.
        try? Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
            .write(to: dir.appendingPathComponent("audit.pub"), options: .atomic)
        if !seed.isEmpty {
            try? (seed.joined(separator: "\n") + "\n")
                .write(to: dir.appendingPathComponent("audit.jsonl"), atomically: true,
                       encoding: .utf8)
        }
        defer {
            AuditLog.seams.directory = nil
            AuditLog.seams.signer = previousSigner
            AuditLog.seams.anchors = previousAnchors
            try? FileManager.default.removeItem(at: dir)
            TrailIsolation.release()
        }
        try body(dir, signer)
    }

    /// The same, for a test that has to await a Session.
    private func withTrailAsync(signer: TestSigner = TestSigner(),
                                _ body: (URL, TestSigner) async throws -> Void) async rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-wiring-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        TrailIsolation.acquire()
        let previousSigner = AuditLog.seams.signer
        let previousAnchors = AuditLog.seams.anchors
        AuditLog.seams.directory = dir
        AuditLog.seams.signer = signer
        AuditLog.seams.anchors = signer
        try? Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
            .write(to: dir.appendingPathComponent("audit.pub"), options: .atomic)
        defer {
            AuditLog.seams.directory = nil
            AuditLog.seams.signer = previousSigner
            AuditLog.seams.anchors = previousAnchors
            try? FileManager.default.removeItem(at: dir)
            TrailIsolation.release()
        }
        try await body(dir, signer)
    }

    /// A session with neither browser tool and no ambient environment, so nothing
    /// here depends on what happens to be installed on the machine running it.
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

    private func record(_ n: Int) -> AuditRecord {
        AuditRecord(timestamp: 1_000 + Double(n), tool: "proctor_act", outcome: "ok")
    }

    // MARK: - Clause 1 and 10, through the real write path

    @Test("entries written through the agent's own append verify clean")
    func theWritePathProducesAVerifiableTrail() {
        withTrail { _, _ in
            for i in 0..<5 { #expect(AuditLog.append(record(i))) }
            let verdict = AuditLog.verify()
            #expect(verdict.total == 5)
            #expect(verdict.verified == 5)
            #expect(verdict.faults.isEmpty)
            #expect(verdict.completeness.state == .proven)
            #expect(verdict.isClean)
        }
    }

    @Test("with the signing key unreachable, nothing is written at all")
    func thereIsNoUnsignedEntry() {
        let signer = TestSigner()
        withTrail(signer: signer) { dir, _ in
            #expect(AuditLog.append(record(0)))
            signer.makeUnreachable()
            #expect(!AuditLog.append(record(1)))
            #expect(!AuditLog.append(record(2)))
            let text = (try? String(contentsOf: dir.appendingPathComponent("audit.jsonl"),
                                    encoding: .utf8)) ?? ""
            #expect(text.split(separator: "\n").count == 1,
                    "the two entries that could not be signed were dropped, not written unsigned")
            let status = AuditLog.status()
            #expect(!status.writable)
            #expect(status.dropped >= 2)
            #expect(status.error?.contains("signing key") == true)
        }
    }

    @Test("a dropped entry never fails the action it was recording")
    func aDroppedEntryDoesNotThrow() {
        let signer = TestSigner(available: false)
        withTrail(signer: signer) { _, _ in
            // Every call site discards this result, and none of them throws. The
            // trail is best-effort in one direction only: it must not become a
            // reason the machine stops doing what it was told.
            #expect(!AuditLog.append(record(0)))
        }
    }

    // MARK: - Clause 6, against a trail that predates signing

    @Test("a trail sealed before this feature keeps working and is pinned by the first new entry")
    func anExistingSealedTrailIsPreChain() {
        // Exactly the reader's own machine: 467 entries sealed by PRO-0013 and
        // carrying no chain fields at all.
        let sealKey = Curve25519.KeyAgreement.PrivateKey()
        let old = (0..<3).map { AuditSeal.seal(line: "{\"old\":\($0)}", to: sealKey.publicKey)! }
        withTrail(seed: old) { _, _ in
            #expect(AuditLog.append(record(0)))
            #expect(AuditLog.append(record(1)))
            let verdict = AuditLog.verify()
            #expect(verdict.total == 5)
            #expect(verdict.preChain == 3)
            #expect(verdict.verified == 2)
            #expect(verdict.faults.isEmpty)
            #expect(verdict.isClean)
        }
    }

    @Test("editing that older history after the fact is detected by the first signed entry")
    func theGenesisLinkPinsHistoryThroughTheWritePath() {
        let sealKey = Curve25519.KeyAgreement.PrivateKey()
        let old = (0..<3).map { AuditSeal.seal(line: "{\"old\":\($0)}", to: sealKey.publicKey)! }
        withTrail(seed: old) { dir, _ in
            #expect(AuditLog.append(record(0)))
            let file = dir.appendingPathComponent("audit.jsonl")
            var lines = (try! String(contentsOf: file, encoding: .utf8))
                .split(separator: "\n").map(String.init)
            lines[1] = AuditSeal.seal(line: "{\"old\":\"rewritten\"}", to: sealKey.publicKey)!
            try! (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true,
                                                              encoding: .utf8)
            let verdict = AuditLog.verify()
            #expect(!verdict.isClean)
            #expect(verdict.faults.contains { $0.kind == .linkBroken })
        }
    }

    // MARK: - Clause 2 and 5, through the real file

    @Test("an entry appended straight into the file is reported as forged")
    func aForgedAppendThroughTheFileIsDetected() {
        withTrail { dir, _ in
            for i in 0..<3 { #expect(AuditLog.append(record(i))) }
            // The forger holds what PRO-0013 hands out freely: a sealing key. That
            // was enough to produce an entry that opened cleanly, and nothing could
            // tell it from a real one.
            let forged = AuditSeal.seal(line: "{\"tool\":\"forged\"}",
                                        to: Curve25519.KeyAgreement.PrivateKey().publicKey)!
            let file = dir.appendingPathComponent("audit.jsonl")
            let handle = try! FileHandle(forWritingTo: file)
            handle.seekToEndOfFile()
            handle.write(Data((forged + "\n").utf8))
            try! handle.close()
            let verdict = AuditLog.verify()
            #expect(!verdict.isClean)
            #expect(verdict.faults.contains { $0.kind == .unsigned && $0.position == 4 })
        }
    }

    @Test("entries cut from the end are reported against the end-mark")
    func truncationThroughTheFileIsDetected() {
        withTrail { dir, _ in
            for i in 0..<5 { #expect(AuditLog.append(record(i))) }
            let file = dir.appendingPathComponent("audit.jsonl")
            let lines = (try! String(contentsOf: file, encoding: .utf8))
                .split(separator: "\n").map(String.init)
            try! (lines.prefix(2).joined(separator: "\n") + "\n")
                .write(to: file, atomically: true, encoding: .utf8)
            let verdict = AuditLog.verify()
            #expect(verdict.completeness.state == .missingFromEnd)
            #expect(verdict.completeness.count == 3)
            #expect(!verdict.isClean)
        }
    }

    // MARK: - Clause 12

    @Test("two writers appending under the lock produce one chain, not a fork")
    func concurrentAppendsProduceOneChain() async {
        // The link is taken from the file under the append's own lock rather than
        // from memory. Taken from memory, two writers would both extend the same
        // record and the chain would fork.
        await withTrailAsync { _, _ in
            await withTaskGroup(of: Void.self) { taskGroup in
                for i in 0..<12 {
                    taskGroup.addTask {
                        _ = AuditLog.append(self.record(i))
                    }
                }
            }
            let verdict = AuditLog.verify()
            #expect(verdict.total == 12)
            #expect(verdict.verified == 12)
            #expect(!verdict.faults.contains { $0.kind == .fork })
            #expect(verdict.isClean)
        }
    }

    // MARK: - Clause 20

    @Test("the recommendation goes through the same path, so it is sealed, chained and signed")
    func recommendationsAreChainedLikeEverythingElse() async throws {
        // Not a separate channel: it is an audit record, and it gets the same
        // treatment as a record of a keystroke.
        let record = AuditRecord(timestamp: 1_000, tool: "proctor_snapshot",
                                 bundleId: "com.google.Chrome", outcome: "recommended",
                                 recommendation: LaneRecommendation(lane: "obscura",
                                                                    rule: "default",
                                                                    scheme: "https"))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-rec-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let signer = TestSigner()
        TrailIsolation.acquire()
        let previousSigner = AuditLog.seams.signer
        let previousAnchors = AuditLog.seams.anchors
        AuditLog.seams.directory = dir
        AuditLog.seams.signer = signer
        AuditLog.seams.anchors = signer
        try? Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
            .write(to: dir.appendingPathComponent("audit.pub"), options: .atomic)
        defer {
            AuditLog.seams.directory = nil
            AuditLog.seams.signer = previousSigner
            AuditLog.seams.anchors = previousAnchors
            try? FileManager.default.removeItem(at: dir)
            TrailIsolation.release()
        }
        #expect(AuditLog.append(record))
        let verdict = AuditLog.verify()
        #expect(verdict.verified == 1)
        #expect(verdict.isClean)
        // and the address is still nowhere in the file, sealed or not
        let raw = (try? String(contentsOf: dir.appendingPathComponent("audit.jsonl"),
                               encoding: .utf8)) ?? ""
        #expect(!raw.contains("example.com"))
    }

    // MARK: - Clause 13 — the verdict reaches the operator's surfaces

    @Test("proctor_policy status carries the verdict, and it leads with whether the trail is clean")
    func theVerdictReachesPolicyStatus() async throws {
        try await withTrailAsync { _, _ in
            for i in 0..<3 { #expect(AuditLog.append(record(i))) }
            let status = try #require(await plainSession().policyStatus().objectValue)
            #expect(status["auditSigned"]?.boolValue == true)
            let verdict = try #require(status["auditVerdict"]?.objectValue)
            #expect(verdict["clean"]?.boolValue == true)
            #expect(verdict["entries"]?.intValue == 3)
            #expect(verdict["verified"]?.intValue == 3)
            #expect(verdict["keyConfirmed"]?.boolValue == true)
            #expect(verdict["completeness"]?.stringValue == "proven")
            #expect(verdict["firstFault"] == nil)
        }
    }

    @Test("a trail with nothing wrong in it still says when entries went unrecorded")
    func theVerdictCarriesEntriesThatWereNeverWritten() async throws {
        // The completeness critic's real find: an entry that was dropped leaves no
        // hole in the chain, because an entry that was never written cannot break a
        // link. The file is genuinely clean and the run still knows that actions
        // went unrecorded, so the count has to travel with the verdict rather than
        // only beside it.
        let signer = TestSigner()
        try await withTrailAsync(signer: signer) { _, _ in
            #expect(AuditLog.append(record(0)))
            signer.makeUnreachable()
            #expect(!AuditLog.append(record(1)))
            let status = try #require(await plainSession().policyStatus().objectValue)
            let verdict = try #require(status["auditVerdict"]?.objectValue)
            let dropped = try #require(verdict["droppedThisRun"]?.intValue)
            #expect(dropped >= 1)
            #expect(verdict["droppedNote"]?.stringValue?.contains("not the same as a complete one")
                    == true)
        }
    }

    @Test("a broken trail names the first fault and its position, not every fault")
    func theVerdictNamesTheFirstFault() async throws {
        try await withTrailAsync { dir, _ in
            for i in 0..<4 { #expect(AuditLog.append(record(i))) }
            let file = dir.appendingPathComponent("audit.jsonl")
            var lines = (try! String(contentsOf: file, encoding: .utf8))
                .split(separator: "\n").map(String.init)
            lines.remove(at: 1)
            try! (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true,
                                                              encoding: .utf8)
            let status = try #require(await plainSession().policyStatus().objectValue)
            let verdict = try #require(status["auditVerdict"]?.objectValue)
            #expect(verdict["clean"]?.boolValue == false)
            let fault = try #require(verdict["firstFault"]?.objectValue)
            #expect(fault["kind"]?.stringValue == "linkBroken")
            #expect(fault["entry"]?.intValue == 2)
            #expect(fault["detail"]?.stringValue?.isEmpty == false)
        }
    }

}

// MARK: - PRO-0032, the other half: what Proctor recommended

/// The recommendation is Proctor's own act — the moment it told a model to go and
/// drive something outside its own accounting — and until now nothing recorded it.
///
/// The whole design tension is in one line of the brief: *a URL in an audit entry
/// is a person's browsing history in a file Proctor keeps.* So these tests spend
/// most of their weight on what is **not** written.
@Suite("Lane recommendation audit")
struct LaneRecommendationAuditTests {

    private static let chrome = "com.google.Chrome"
    private static let firefox = "org.mozilla.firefox"

    private func session(probe: WebContentProbe?, bundleId: String = chrome,
                         obscura: Bool = true, laneSet: Bool = false, browserUse: Bool = false)
    -> (Session, AuditCollector) {
        let ax = FakeAX(bundleId: bundleId)
        ax.webContentProbe = probe
        let collector = AuditCollector()
        let session = Session(
            ax: ax, capture: FakeCapture(),
            tools: ToolProbes(
                obscura: ToolProbe(probe: {
                    ToolPresence(tool: ObscuraTool.binary, available: obscura,
                                 path: obscura ? "/opt/homebrew/bin/obscura" : nil)
                }),
                browserUse: ToolProbe(probe: {
                    ToolPresence(tool: BrowserUseTool.binary, available: browserUse,
                                 path: browserUse ? "/opt/homebrew/bin/browser-use" : nil)
                }, presentTTL: ToolProbe.presentTTL, absentTTL: ToolProbe.presentTTL),
                environment: laneSet ? [BrowserUseTool.laneVariable: BrowserUseTool.binary] : [:]))
        return (session, collector)
    }

    private func page(_ url: String) -> WebContentProbe {
        WebContentProbe(areas: [WebArea(url: url, frame: Rect(x: 0, y: 0, w: 800, h: 600))])
    }

    private func recommendations(_ collector: AuditCollector) -> [AuditRecord] {
        collector.records.filter { $0.recommendation != nil }
    }

    // MARK: - Clause 14

    @Test("naming a lane writes one entry carrying the tool, the browser, the lane and the rule")
    func aRecommendationIsRecorded() async throws {
        let (session, collector) = session(probe: page("https://example.com/private/report?id=42"))
        await session.setAuditSink(collector.sink)
        _ = try await session.attachResolved(bundleId: Self.chrome, pid: nil, name: nil)
        _ = try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil)

        let entries = recommendations(collector)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.tool == "proctor_snapshot")
        #expect(entry.bundleId == Self.chrome)
        #expect(entry.outcome == "recommended")
        #expect(entry.recommendation?.lane == "obscura")
        #expect(entry.recommendation?.rule == "default")
        #expect(entry.recommendation?.scheme == "https")
    }

    // MARK: - Clause 15 — the one that matters most

    @Test("no part of the address is recorded, whatever the page")
    func noBrowsingHistoryIsRecorded() async throws {
        // Every field of a URL a person would not want in a file: the host, the
        // path, the query, the fragment. Asserted against the entry's whole
        // serialised form rather than field by field, so a future field that
        // quietly carries a URL fails this too.
        let urls = [
            "https://patient-portal.example.com/records/oncology?ref=abc#section-3",
            "chrome://settings/passwords",
            "file:///Users/someone/Documents/divorce.pdf",
            "http://192.168.1.4:3000/report.pdf?t=1"
        ]
        for url in urls {
            for laneOn in [false, true] {
                let (session, collector) = session(probe: page(url), laneSet: laneOn,
                                                   browserUse: laneOn)
                await session.setAuditSink(collector.sink)
                _ = try await session.attachResolved(bundleId: Self.chrome, pid: nil, name: nil)
                _ = try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil)
                for entry in collector.records {
                    let line = entry.jsonLine()
                    for fragment in ["patient-portal", "records/oncology", "abc", "section-3",
                                     "passwords", "divorce", "Documents", "192.168.1.4",
                                     "report.pdf", "example.com", url] {
                        #expect(!line.contains(fragment),
                                "\(fragment) reached the trail from \(url)")
                    }
                }
            }
        }
    }

    @Test("an app-level handoff with no address at all records no scheme")
    func noAddressMeansNoScheme() async throws {
        let (session, collector) = session(probe: nil)
        await session.setAuditSink(collector.sink)
        _ = try await session.attach(bundleId: Self.chrome, pid: nil, name: nil)
        let entry = try #require(recommendations(collector).first)
        #expect(entry.recommendation?.scheme == nil)
        #expect(entry.recommendation?.lane == "obscura")
        #expect(entry.tool == "proctor_apps")
    }

    // MARK: - Clause 16

    @Test("a handoff that names no lane records nothing")
    func noLaneMeansNoRecord() async throws {
        // Three ways to arrive at no recommendation, including the one where
        // Proctor most visibly decided: declining to point any lane at the
        // browser's own password surface. Recording that refusal would say where
        // the person was, which is exactly what this feature refuses to do.
        let cases: [(String, WebContentProbe?, Bool, Bool, String)] = [
            ("the deny list", page("chrome://settings/passwords"), true, true, Self.chrome),
            ("a local file", page("file:///Users/x/page.html"), true, true, Self.chrome),
            ("Obscura absent", page("https://example.com"), false, false, Self.chrome),
            ("an internal page in a non-Chromium browser", page("chrome://newtab"), true, true,
             Self.firefox)
        ]
        for (name, probe, obscura, laneSet, bundleId) in cases {
            let (session, collector) = session(probe: probe, bundleId: bundleId, obscura: obscura,
                                               laneSet: laneSet, browserUse: laneSet)
            await session.setAuditSink(collector.sink)
            _ = try await session.attachResolved(bundleId: bundleId, pid: nil, name: nil)
            _ = try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil)
            #expect(recommendations(collector).isEmpty, "\(name) recorded a recommendation")
        }
    }

    // MARK: - Clause 17

    @Test("a repeat of the same advice is the same act, and is recorded once")
    func repeatsAreNotNewActs() async throws {
        let (session, collector) = session(probe: page("https://example.com/a"))
        await session.setAuditSink(collector.sink)
        _ = try await session.attachResolved(bundleId: Self.chrome, pid: nil, name: nil)
        for _ in 0..<5 {
            _ = try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil)
            _ = try await session.find(window: "win-1", predicate: FindPredicate(role: "AXButton"),
                                       limit: 5)
        }
        #expect(recommendations(collector).count == 1,
                "ten advisories, one act — otherwise the trail time-stamps a browsing session")
    }

    @Test("a change of scheme records again")
    func aChangedRecommendationRecordsAgain() async throws {
        let ax = FakeAX(bundleId: Self.chrome)
        ax.webContentProbe = page("https://example.com/a")
        let collector = AuditCollector()
        let session = Session(
            ax: ax, capture: FakeCapture(),
            tools: ToolProbes(
                obscura: ToolProbe(probe: {
                    ToolPresence(tool: ObscuraTool.binary, available: true,
                                 path: "/opt/homebrew/bin/obscura")
                }),
                browserUse: ToolProbe(probe: { ToolPresence(tool: BrowserUseTool.binary,
                                                            available: false) },
                                      presentTTL: ToolProbe.presentTTL,
                                      absentTTL: ToolProbe.presentTTL),
                environment: [:]))
        await session.setAuditSink(collector.sink)
        _ = try await session.attachResolved(bundleId: Self.chrome, pid: nil, name: nil)
        _ = try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil)
        ax.webContentProbe = page("http://example.com/a")
        _ = try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil)
        let schemes = recommendations(collector).compactMap { $0.recommendation?.scheme }
        #expect(schemes == ["https", "http"])
    }

    // MARK: - Clause 18

    @Test("the entry is an advisory, not an actuation, and carries no sentence from the handoff")
    func aRecommendationIsNotAnActuation() async throws {
        let (session, collector) = session(probe: page("https://example.com/a"))
        await session.setAuditSink(collector.sink)
        _ = try await session.attachResolved(bundleId: Self.chrome, pid: nil, name: nil)
        _ = try await session.snapshot(window: "win-1", options: .init(), sinceRevision: nil)
        let entry = try #require(recommendations(collector).first)
        #expect(entry.outcome == "recommended")
        #expect(entry.outcome != "ok", "it must not read as something Proctor did to the machine")
        #expect(entry.kind == nil)
        #expect(entry.postStateHash == nil)
        #expect(entry.value == nil)
        // None of the handoff's prose. The entry is a fact about a decision, not a
        // second copy of the object that carried it.
        let line = entry.jsonLine()
        for prose in ["boundary", "continuity", "caveat", "Obscura runs its own",
                      "autonomous", "engine"] {
            #expect(!line.contains(prose))
        }
        #expect(line.count < 300, "it stays a record, not a document: \(line)")
    }

    // MARK: - Clause 19

    @Test("a recommendation that cannot be recorded never fails the call carrying it")
    func aFailedRecordDoesNotFailTheCall() async throws {
        let (session, _) = session(probe: page("https://example.com/a"))
        // The real sink drops on failure and returns false; nothing reads it. This
        // asserts the shape that guarantees it: the call still returns its result
        // with the handoff attached.
        await session.setAuditSink({ _ in })
        _ = try await session.attachResolved(bundleId: Self.chrome, pid: nil, name: nil)
        let snapshot = try await session.snapshot(window: "win-1", options: .init(),
                                                  sinceRevision: nil)
        #expect(snapshot.browser?.use == "obscura")
    }

}
