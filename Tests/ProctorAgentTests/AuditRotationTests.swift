import Testing
import Foundation
import CryptoKit
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0047, agent half: the trail is bounded, a rotation attests what it
// discarded, and an interrupted one is finished rather than reported as
// tampering.
//
// **Nothing here touches the operator's trail, the keychain or the secure
// element.** The trail is redirected into a per-test temporary directory and the
// signer and end-mark are injected in-process, for the reason PRO-0032's suite
// records: an earlier wave's suite drove a real `Session` without redirecting
// its sink, wrote into the live trail, and fired PRO-0013's deliberately
// irreversible conversion on real history.
//
// Serialized because `AuditLog`'s state, seams, clock and file lock are all
// process-wide.
@Suite("Audit rotation", .serialized)
struct AuditRotationTests {

    // MARK: - Harness

    final class TestSigner: AuditSigning, AuditAnchoring, @unchecked Sendable {
        private let lock = NSLock()
        private var key: P256.Signing.PrivateKey?
        private var anchor: AuditChain.Anchor?
        private var frozen = false

        init(available: Bool = true) { key = available ? P256.Signing.PrivateKey() : nil }
        func makeUnreachable() { lock.withLock { key = nil } }

        var signingKeyId: String? {
            lock.withLock { key.map { AuditChain.keyId(forPublicKey: $0.publicKey.rawRepresentation) } }
        }
        var signingKeyClass: AuditChain.KeyClass? { lock.withLock { key == nil ? nil : .software } }

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
            lock.withLock {
                guard !frozen else { return false }
                self.anchor = anchor
                return true
            }
        }

        /// Stop recording new end-marks, the way a key store that has started
        /// refusing writes would. The trail keeps growing; the mark does not.
        func freezeAnchor() { lock.withLock { frozen = true } }
    }

    private func withTrail(signer: TestSigner = TestSigner(),
                           now: Double = 1_000_000,
                           _ body: (URL, TestSigner) throws -> Void) rethrows {
        // Suites that redirect the trail must not overlap: the seams, the state,
        // the clock and the file lock are all process-wide, and `.serialized`
        // only orders the tests inside one suite.
        TrailIsolation.acquire()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-rotate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previousSigner = AuditLog.seams.signer
        let previousAnchors = AuditLog.seams.anchors
        let previousKeys = AuditLog.seams.keys
        let previousClock = AuditLog.clockNow
        AuditLog.seams.directory = dir
        AuditLog.seams.signer = signer
        AuditLog.seams.anchors = signer
        // An in-memory sealing pair, so this suite can read back what it wrote
        // without the login Keychain and without the live store's process-wide
        // public-key cache leaking one suite's key into the next.
        AuditLog.seams.keys = TestSealKeys()
        AuditLog.clockNow = { now }
        defer {
            AuditLog.seams.directory = nil
            AuditLog.seams.signer = previousSigner
            AuditLog.seams.anchors = previousAnchors
            AuditLog.seams.keys = previousKeys
            AuditLog.clockNow = previousClock
            try? FileManager.default.removeItem(at: dir)
            TrailIsolation.release()
        }
        try body(dir, signer)
    }

    private func record(_ n: Int) -> AuditRecord {
        AuditRecord(timestamp: Double(1000 + n), tool: "proctor_act", bundleId: "com.acme.console",
                    kind: "press", outcome: "ok", run: "run-\(n)", seq: 0, ms: 5,
                    plane: "accessibility", act: "Pressed",
                    obj: .init(text: "Send invoice", supplied: false))
    }

    private func lines(_ dir: URL) -> [String] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("audit.jsonl"),
                                     encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// The plaintext of every entry, for asserting what a rotation record says.
    private func openedReasons(_ limit: Int = 50) -> [String] {
        AuditLog.openedTail(limit).compactMap { entry in
            guard case .opened(let line) = entry, let data = line.data(using: .utf8),
                  let record = try? JSONDecoder().decode(AuditRecord.self, from: data)
            else { return nil }
            return record.reason
        }
    }

    // MARK: - The caps

    @Test("the entry cap rotates the trail")
    func entryCapRotates() {
        withTrail { dir, _ in
            let cap = HistoryRetention.Caps.minimumEntries
            for n in 0..<(cap - 1) { AuditLog.append(record(n)) }
            #expect(lines(dir).count == cap - 1)

            // One short of the cap, so nothing moves. There is deliberately no
            // way to ask for a smaller one: a floor is what stops a typo in the
            // agent's environment shredding the trail on the next append.
            AuditLog.rotateIfNeeded(caps: HistoryRetention.Caps(days: 90, entries: 1))
            #expect(lines(dir).count == cap - 1)

            AuditLog.append(record(cap))
            AuditLog.rotateIfNeeded(caps: HistoryRetention.Caps(days: 90, entries: cap))
            // The whole trail goes, and what replaces it is one record: the
            // attestation of what went.
            #expect(lines(dir).count == 1)
        }
    }

    @Test("the age cap rotates the trail")
    func ageCapRotates() {
        withTrail(now: 1_000_000) { dir, signer in
            AuditLog.append(record(0))
            #expect(signer.loadAnchor()?.startedAt == 1_000_000)

            // Fifteen days later, against a fourteen-day cap.
            AuditLog.clockNow = { 1_000_000 + 15 * 86_400 }
            AuditLog.rotateIfNeeded(caps: HistoryRetention.Caps(days: 14, entries: 100_000))
            #expect(lines(dir).count == 1)
        }
    }

    @Test("a trail inside its caps is left alone")
    func withinCapsDoesNothing() {
        withTrail { dir, _ in
            for n in 0..<3 { AuditLog.append(record(n)) }
            AuditLog.rotateIfNeeded(caps: HistoryRetention.Caps(days: 90, entries: 100_000))
            #expect(lines(dir).count == 3)
        }
    }

    // MARK: - What a rotation says

    @Test("the rotation record commits to the discarded trail's final entry")
    func rotationRecordCommitsToTheHead() throws {
        try withTrail { dir, _ in
            for n in 0..<4 { AuditLog.append(record(n)) }
            let head = AuditChain.hash(record: lines(dir).last ?? "")
            let oldTrail = AuditLog.seams.anchors.loadAnchor()?.trailId

            AuditLog.rotate(reason: .person)

            let reasons = openedReasons()
            #expect(reasons.count == 1)
            let note = try #require(reasons.first)
            // Without the head hash, "the history is gone" and "the history was
            // never there" would be the same claim.
            #expect(note.contains(head))
            #expect(note.contains("4 entries"))
            if let oldTrail { #expect(note.contains(oldTrail)) }
            #expect(note.contains("A person cleared"))
        }
    }

    @Test("a cap-driven rotation says which cap, not that a person asked")
    func rotationNamesTheCap() throws {
        try withTrail { _, _ in
            let cap = HistoryRetention.Caps.minimumEntries
            for n in 0..<cap { AuditLog.append(record(n)) }
            AuditLog.rotateIfNeeded(caps: HistoryRetention.Caps(days: 90, entries: cap))
            let note = try #require(openedReasons().first)
            #expect(note.contains("size limit"))
            #expect(!note.contains("A person cleared"))
        }
    }

    // MARK: - The trail stays checkable

    @Test("a rotated trail verifies clean, as a short trail rather than a damaged one")
    func rotatedTrailVerifiesClean() {
        withTrail { _, _ in
            for n in 0..<6 { AuditLog.append(record(n)) }
            #expect(AuditLog.verify().isClean)

            AuditLog.rotate(reason: .person)

            let verdict = AuditLog.verify()
            // This is the whole reason rotation was chosen over pruning: a
            // front-truncated chain reports a broken link, which is an
            // accusation, and a person clearing their own history is not that.
            #expect(verdict.isClean, "faults: \(verdict.faults)")
            #expect(verdict.total == 1)
            #expect(verdict.completeness.state == .proven)
        }
    }

    @Test("the new trail is a new trail, with its own identity and start time")
    func rotationStartsAFreshTrail() throws {
        try withTrail(now: 5_000) { _, signer in
            AuditLog.append(record(0))
            let before = try #require(signer.loadAnchor())

            AuditLog.clockNow = { 9_000 }
            AuditLog.rotate(reason: .person)

            let after = try #require(signer.loadAnchor())
            #expect(after.trailId != before.trailId)
            #expect(after.startedAt == 9_000)
            #expect(after.count == 1)
        }
    }

    @Test("appending after a rotation continues the new trail cleanly")
    func appendingAfterRotationStaysClean() {
        withTrail { dir, _ in
            for n in 0..<4 { AuditLog.append(record(n)) }
            AuditLog.rotate(reason: .person)
            for n in 4..<7 { AuditLog.append(record(n)) }
            #expect(lines(dir).count == 4)
            #expect(AuditLog.verify().isClean)
        }
    }

    // MARK: - No second copy

    @Test("a rotation leaves no backup, sidecar or readable copy")
    func rotationLeavesNoSidecar() {
        withTrail { dir, _ in
            for n in 0..<4 { AuditLog.append(record(n)) }
            AuditLog.rotate(reason: .person)

            // Not `(try?) ?? []`. A directory this test could not read became an
            // empty listing, and nothing with a .bak suffix is in an empty
            // listing, so all four claims below passed for the wrong reason on a
            // machine where the read failed. Found by
            // scripts/campaign/cannotfail_swift.py's defaulted-read pattern.
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))
            #expect(files != nil, "the trail directory must be readable, or this proves nothing")
            let listing = files ?? []
            #expect(listing.contains("audit.jsonl"),
                    "and it must hold the rotated trail, or an empty listing passes every claim below")
            // PRO-0013 chose no recovery path deliberately, and this is exactly
            // where somebody would be tempted to add one "just in case".
            #expect(!listing.contains { $0.hasSuffix(".bak") })
            #expect(!listing.contains { $0.hasSuffix(".orig") })
            #expect(!listing.contains { $0.contains("audit.jsonl.") })
            #expect(!listing.contains("audit.rotating"))
        }
    }

    // MARK: - Crash safety

    @Test("a rotation that was written down but never finished is completed")
    func interruptedRotationIsCompleted() throws {
        try withTrail { dir, signer in
            for n in 0..<3 { AuditLog.append(record(n)) }
            let head = AuditChain.hash(record: lines(dir).last ?? "")

            // Exactly the state a crash between writing the marker and replacing
            // the file leaves behind: the old trail still on disk, the intent
            // recorded beside it.
            let intent = AuditLog.RotationIntent(
                trailId: UUID().uuidString, reason: .age, discarded: 3,
                from: 1_000, to: 2_000, oldTrailId: signer.loadAnchor()?.trailId, head: head)
            try JSONEncoder().encode(intent)
                .write(to: dir.appendingPathComponent("audit.rotating"), options: .atomic)

            // The next ordinary append finds it and finishes the job rather than
            // leaving the verifier to report the disagreement as tampering.
            AuditLog.append(record(9))

            #expect(lines(dir).count == 2)   // the attestation, then this record
            #expect(AuditLog.verify().isClean)
            let note = try #require(openedReasons().first)
            #expect(note.contains("age limit"))
            #expect(!FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("audit.rotating").path))
        }
    }

    // MARK: - Refusing to destroy what it cannot account for

    @Test("a trail that cannot be signed is not rotated")
    func unsignableTrailIsLeftAlone() {
        withTrail { dir, signer in
            for n in 0..<4 { AuditLog.append(record(n)) }
            signer.makeUnreachable()

            AuditLog.rotate(reason: .person)

            // A rotation that cannot write its own attestation would leave
            // history deleted and nothing saying so, which is the one outcome
            // worse than keeping it.
            #expect(lines(dir).count == 4)
        }
    }

    @Test("a marker that does not decode is removed, never acted on")
    func plantedGarbageMarkerIsIgnored() {
        withTrail { dir, _ in
            for n in 0..<3 { AuditLog.append(record(n)) }
            let marker = dir.appendingPathComponent("audit.rotating")
            try? Data("not a rotation intent".utf8).write(to: marker)

            AuditLog.append(record(9))

            // Four entries, not one: a truncated or planted file must not be able
            // to drive a wipe.
            #expect(lines(dir).count == 4)
            #expect(!FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test("a planted marker cannot make Proctor sign a discard that never happened")
    func plantedMarkerCannotForgeASummary() throws {
        try withTrail { dir, signer in
            for n in 0..<3 { AuditLog.append(record(n)) }
            let realHead = AuditChain.hash(record: lines(dir).last ?? "")

            // The attacker's claim: a different trail, a different length, a
            // different tip. The marker is an ordinary file in a directory this
            // user can write, so planting one is within reach of exactly the
            // attacker PRO-0013 already names — and having Proctor *sign* their
            // numbers would be strictly worse than the deletion they could
            // already perform.
            let planted = AuditLog.RotationIntent(
                trailId: UUID().uuidString, reason: .person, discarded: 9_999,
                from: 1, to: 2, oldTrailId: "not-the-real-trail", head: "deadbeef")
            try JSONEncoder().encode(planted)
                .write(to: dir.appendingPathComponent("audit.rotating"), options: .atomic)

            AuditLog.append(record(9))

            let note = try #require(openedReasons().first)
            #expect(!note.contains("9999"))
            #expect(!note.contains("deadbeef"))
            #expect(!note.contains("not-the-real-trail"))
            // What it signs is what it could see for itself.
            #expect(note.contains("3 entries"))
            #expect(note.contains(realHead))
            _ = signer
        }
    }

    @Test("a rotation that finished but never cleaned up is not run twice")
    func completedRotationIsNotRepeated() throws {
        try withTrail { dir, signer in
            for n in 0..<3 { AuditLog.append(record(n)) }
            AuditLog.rotate(reason: .person)
            for n in 4..<7 { AuditLog.append(record(n)) }
            #expect(lines(dir).count == 4)

            // The state a crash between writing the attestation and deleting the
            // marker leaves. Re-running it would destroy the genesis it had just
            // written, and everything appended since.
            let trailId = try #require(signer.loadAnchor()?.trailId)
            let stale = AuditLog.RotationIntent(
                trailId: trailId, reason: .person, discarded: 3,
                from: nil, to: 100, oldTrailId: nil, head: nil)
            try JSONEncoder().encode(stale)
                .write(to: dir.appendingPathComponent("audit.rotating"), options: .atomic)

            AuditLog.append(record(8))

            #expect(lines(dir).count == 5)
            #expect(AuditLog.verify().isClean)
            #expect(!FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("audit.rotating").path))
        }
    }

    @Test("the cap is tested again under the lock, so a second rotation is a no-op")
    func capIsRetestedUnderTheLock() {
        withTrail { dir, _ in
            let cap = HistoryRetention.Caps.minimumEntries
            for n in 0..<cap { AuditLog.append(record(n)) }
            let caps = HistoryRetention.Caps(days: 90, entries: cap)

            AuditLog.rotateIfNeeded(caps: caps)
            #expect(lines(dir).count == 1)

            // The decision that reaches `rotate` was taken outside the lock, so
            // two agents can both arrive holding it. The second must find the
            // trail already short and leave the first one's attestation alone.
            AuditLog.rotate(reason: .size, caps: caps)
            #expect(lines(dir).count == 1)
        }
    }

    @Test("the cap follows the file when the end-mark stops being recorded")
    func capSurvivesAnUnrecordableAnchor() {
        withTrail { dir, signer in
            // A key store that refuses to record the new end-mark leaves its count
            // frozen while the file keeps growing. A cap driven by that count
            // would never fire, and the trail would grow without limit while
            // reporting that it was bounded, which is this feature's own failure
            // arrived at quietly.
            let cap = HistoryRetention.Caps.minimumEntries
            for n in 0..<(cap / 2) { AuditLog.append(record(n)) }
            signer.freezeAnchor()
            for n in 0..<(cap / 2 + 1) { AuditLog.append(record(n)) }

            AuditLog.rotateIfNeeded(caps: HistoryRetention.Caps(days: 90, entries: cap))
            #expect(lines(dir).count == 1)
        }
    }

    @Test("clearing an empty history writes nothing")
    func clearingEmptyIsANoOp() {
        withTrail { dir, _ in
            #expect(AuditLog.clear())
            #expect(lines(dir).isEmpty)
        }
    }
}
