import Testing
import Foundation
import CryptoKit
@testable import ProctorCore

// PRO-0032 — the chain and the signature, proved on real records.
//
// Everything here is pure: the seal key, the signing key and the trail are all
// made inside the test process. Nothing reaches a key store, a secure element or
// the operator's own trail — the key store is exercised by running the agent,
// which is stated in the spec as the limit of what `swift test` can witness.
//
// The trail is built the way the agent builds it, through `AuditSeal.sealLine`,
// `AuditChain.signedMaterial` and `AuditSeal.encode`, rather than by hand. A test
// that assembles records its own way proves its own assembler.

@Suite("Audit chain")
struct AuditChainTests {

    // MARK: - A trail, built as the agent builds one

    struct Trail {
        var records: [String] = []
        var anchor: AuditChain.Anchor
        let sealKey = Curve25519.KeyAgreement.PrivateKey()
        let signingKey = P256.Signing.PrivateKey()
        let trailId = UUID().uuidString
        var keyClass: AuditChain.KeyClass = .software

        var keyId: String { AuditChain.keyId(forPublicKey: signingKey.publicKey.rawRepresentation) }

        init(preChain: [String] = []) throws {
            anchor = AuditChain.Anchor(trailId: "", count: 0, head: "", keyId: "", preChainCount: 0)
            for text in preChain { records.append(try sealUnchained(text)) }
            anchor.preChainCount = records.count
        }

        /// A record sealed the way PRO-0013 sealed one, carrying no chain fields:
        /// the shape of every entry already on the reader's machine.
        /// PRO-0098, DEF-136. `AuditSeal.seal` returning nil is a real failure of
        /// the code under test, and every one of this suite's assertions is about
        /// what the chain verifier makes of the records it produces. Unwrapped, a
        /// broken seal aborted the runner and reported nothing at all.
        func sealUnchained(_ text: String) throws -> String {
            try #require(AuditSeal.seal(line: text, to: sealKey.publicKey),
                         "AuditSeal.seal returned nil for a pre-chain entry")
        }

        mutating func append(_ text: String, signWith override: P256.Signing.PrivateKey? = nil,
                             trailId override2: String? = nil,
                             keyClass override3: AuditChain.KeyClass? = nil) throws {
            let sealed = try #require(AuditSeal.sealLine(line: text, to: sealKey.publicKey),
                                      "AuditSeal.sealLine returned nil")
            let isGenesis = records.count == anchor.preChainCount
            let prev = isGenesis
                ? AuditChain.genesisLink(preChainRecords: Array(records[0..<anchor.preChainCount]))
                : AuditChain.hash(record: records[records.count - 1])
            let key = override ?? signingKey
            let cls = override3 ?? keyClass
            let skid = AuditChain.keyId(forPublicKey: key.publicKey.rawRepresentation)
            let material = AuditChain.signedMaterial(
                version: sealed.v, trailId: override2 ?? trailId, previous: prev,
                keyId: skid, keyClass: cls, sealKeyId: sealed.kid,
                ephemeralKey: sealed.epk, ciphertext: sealed.ct)
            let sig = try key.signature(for: material)
            let line = sealed.signed(prev: prev, tid: override2 ?? trailId, skid: skid,
                                     cls: cls.rawValue,
                                     sig: sig.rawRepresentation.base64EncodedString())
            records.append(try #require(AuditSeal.encode(line),
                                        "AuditSeal.encode returned nil for a signed line"))
            anchor.trailId = trailId
            anchor.keyId = keyId
            anchor.count = records.count
            anchor.head = AuditChain.hash(record: records[records.count - 1])
        }

        func expectation(anchor override: AuditChain.Anchor?? = nil,
                         keyId overrideKey: String?? = nil,
                         keyClass overrideClass: AuditChain.KeyClass?? = nil)
        -> AuditChain.Expectation {
            let publicKey = signingKey.publicKey
            return AuditChain.Expectation(
                trailId: trailId,
                keyId: overrideKey ?? keyId,
                keyClass: overrideClass ?? keyClass,
                anchor: override ?? anchor,
                verify: { signature, material in
                    guard let parsed = try? P256.Signing.ECDSASignature(
                        rawRepresentation: signature) else { return false }
                    return publicKey.isValidSignature(parsed, for: material)
                })
        }

        func verify(anchor override: AuditChain.Anchor?? = nil, endsWithNewline: Bool = true,
                    records overrideRecords: [String]? = nil) -> AuditChain.Verdict {
            AuditChain.verify(records: overrideRecords ?? records, endsWithNewline: endsWithNewline,
                              expected: expectation(anchor: override))
        }
    }

    private func trail(preChain: Int = 0, entries: Int = 4) throws -> Trail {
        var t = try Trail(preChain: (0..<preChain).map { "{\"old\":\($0)}" })
        for i in 0..<entries { try t.append("{\"tool\":\"proctor_act\",\"n\":\(i)}") }
        return t
    }

    // MARK: - Every signed entry removed

    /// Found by arming, not by reading: deleting the `unsigned` fault at the
    /// stripped-trail branch left this whole suite green, so the one verdict that
    /// says "the trail was being signed and every signed entry is gone" was
    /// carried by nothing. That is the shape a tamperer leaves behind, which
    /// makes it the fault least able to afford being unguarded.

    @Test("a trail whose signed entries were all removed reports it as a fault")
    func everySignedEntryRemoved() throws {
        let t = try trail(preChain: 3, entries: 2)
        let anchored = t.anchor
        #expect(anchored.count == 5)
        #expect(anchored.preChainCount == 3)
        // The file is now shorter than the pre-chain the anchor remembers, and
        // nothing left in it carries a link. That is a trail whose signed entries
        // were removed, not an old one that was never signed.
        let stripped = Array(t.records.prefix(2))

        let verdict = t.verify(anchor: anchored, records: stripped)
        #expect(verdict.faults.contains { $0.kind == .unsigned },
                "an anchor that counts signed entries, with none present, is a stripped trail")
        #expect(verdict.completeness.state == .missingFromEnd)
        #expect(verdict.completeness.count == 5)
        #expect(verdict.verified == 0)
        #expect(!verdict.isClean)
    }

    @Test("the same file with no anchor is an old trail rather than a stripped one")
    func noAnchorIsNotAFault() throws {
        // Without an anchor there is nothing saying the trail was ever signed, so
        // the same records must not be reported as tampering. The pair is what
        // keeps the fault from firing on every pre-signing file.
        let t = try trail(preChain: 3, entries: 2)
        let stripped = Array(t.records.prefix(2))
        let verdict = t.verify(anchor: .some(nil), records: stripped)
        #expect(!verdict.faults.contains { $0.kind == .unsigned })
        #expect(verdict.completeness.state == .notProvable)
    }

    // MARK: - Clause 1

    @Test("a trail this build wrote verifies clean end to end")
    func cleanTrailVerifies() throws {
        let t = try trail(entries: 6)
        let v = t.verify()
        #expect(v.total == 6)
        #expect(v.verified == 6)
        #expect(v.preChain == 0)
        #expect(v.faults.isEmpty)
        #expect(v.completeness.state == .proven)
        #expect(v.keyConfirmed)
        #expect(v.isClean)
    }

    // MARK: - Clause 2

    @Test("an entry appended by someone holding only the sealing key is reported as forged")
    func forgedAppendIsDetected() throws {
        var t = try trail(entries: 3)
        // The forger has what PRO-0013's design hands out freely: the public
        // sealing key. They can produce a record that opens cleanly, and before
        // this feature nothing could tell it from a real one.
        let forged = try t.sealUnchained("{\"tool\":\"proctor_act\",\"forged\":true}")
        t.records.append(forged)
        let v = t.verify(anchor: t.anchor)   // the anchor still names the honest length
        #expect(!v.isClean)
        #expect(v.faults.contains { $0.kind == .unsigned && $0.position == 4 })
        #expect(v.verified == 3, "the three honest entries still verify")
    }

    @Test("an entry signed by a different key is reported, not accepted")
    func foreignKeyIsDetected() throws {
        var t = try trail(entries: 2)
        try t.append("{\"tool\":\"proctor_act\",\"n\":\"planted\"}", signWith: P256.Signing.PrivateKey())
        let v = t.verify()
        #expect(v.faults.contains { $0.kind == .keyNotHeld && $0.position == 3 })
        #expect(!v.isClean)
    }

    // MARK: - Clause 3

    @Test("an entry removed from the middle breaks the link, with its position")
    func deletionIsDetected() throws {
        let t = try trail(entries: 5)
        var records = t.records
        records.remove(at: 2)
        let v = t.verify(records: records)
        #expect(v.faults.contains { $0.kind == .linkBroken && $0.position == 3 })
        #expect(!v.isClean)
    }

    @Test("a reordered pair is detected")
    func reorderIsDetected() throws {
        let t = try trail(entries: 5)
        var records = t.records
        records.swapAt(2, 3)
        let v = t.verify(records: records)
        #expect(v.faults.filter { $0.kind == .linkBroken }.count >= 2)
    }

    @Test("a fork — two entries claiming the same predecessor — is reported")
    func forkIsDetected() throws {
        let t = try trail(entries: 3)
        var records = t.records
        // Two writers that both took the head before either wrote. A lock only
        // binds those who take it, so the verifier has to see this itself.
        records.insert(records[2], at: 3)
        let v = t.verify(records: records)
        #expect(v.faults.contains { $0.kind == .fork })
    }

    // MARK: - Clause 4

    @Test("one flipped byte inside the sealed part is detected as forged, not as unreadable")
    func editIsDetectedAsForged() throws {
        let t = try trail(entries: 4)
        var records = t.records
        // Flip a character inside the ciphertext of entry 2. The seal alone would
        // report this as an entry that will not open; the chain reports that it
        // was altered, which is a different and more useful statement.
        let line = try #require(AuditSeal.decode(records[1]),
                                "AuditSeal.decode returned nil for a record this suite sealed")
        var ct = Array(line.ct)
        ct[4] = ct[4] == "A" ? "B" : "A"
        records[1] = try #require(AuditSeal.encode(AuditSeal.SealedLine(
            v: line.v, kid: line.kid, epk: line.epk, ct: String(ct),
            prev: line.prev, tid: line.tid, skid: line.skid, cls: line.cls, sig: line.sig)))
        let v = t.verify(records: records)
        #expect(v.faults.contains { $0.kind == .signatureInvalid && $0.position == 2 })
        // and the entry after it no longer follows, because its link is over bytes
        #expect(v.faults.contains { $0.kind == .linkBroken && $0.position == 3 })
    }

    // MARK: - Clause 5

    @Test("a trail cut short reports how many entries are missing from the end")
    func truncationIsDetected() throws {
        let t = try trail(entries: 6)
        let v = t.verify(records: Array(t.records.prefix(2)))
        #expect(v.completeness.state == .missingFromEnd)
        #expect(v.completeness.count == 4)
        #expect(!v.isClean)
    }

    @Test("a trail rolled back to an older copy of itself is detected")
    func rollbackIsDetected() throws {
        // The whole reason the anchor is not a file: restore the trail from a
        // snapshot and, if the anchor came with it, the pair verifies perfectly.
        var t = try trail(entries: 3)
        let older = t.records
        try t.append("{\"tool\":\"proctor_act\",\"n\":\"later\"}")
        try t.append("{\"tool\":\"proctor_act\",\"n\":\"later2\"}")
        let v = t.verify(records: older)
        #expect(v.completeness.state == .missingFromEnd)
        #expect(v.completeness.count == 2)
    }

    @Test("a trail one entry ahead of its anchor is normal growth after a crash, not a fault")
    func unanchoredTailIsNotAFault() throws {
        var t = try trail(entries: 4)
        let anchorBefore = t.anchor
        try t.append("{\"tool\":\"proctor_act\",\"n\":\"after the anchor write failed\"}")
        let v = t.verify(anchor: anchorBefore)
        #expect(v.completeness.state == .unanchoredTail)
        #expect(v.completeness.count == 1)
        #expect(v.faults.isEmpty)
        #expect(v.isClean, "an unanchored tail is still signature-checked, so it is not a fault")
    }

    @Test("a trail one entry behind its anchor is a lost final entry, not an accusation")
    func lostFinalEntryIsNotAnAccusation() throws {
        let t = try trail(entries: 4)
        let v = t.verify(records: Array(t.records.prefix(3)))
        #expect(v.completeness.state == .lostFinalEntry)
        #expect(!v.isClean, "it is still not a clean trail")
        #expect(v.faults.isEmpty, "but nothing in it is accused of being forged")
    }

    @Test("no anchor means completeness cannot be proved, and never means clean")
    func missingAnchorIsNotProvable() throws {
        let t = try trail(entries: 3)
        let v = t.verify(anchor: AuditChain.Anchor??.some(nil))
        #expect(v.completeness.state == .notProvable)
        #expect(v.verified == 3, "the entries themselves still check out")
        #expect(!v.isClean)
    }

    @Test("stripping every signed entry does not read as a trail that predates signing")
    func strippedTrailIsAFault() throws {
        // Without the frozen pre-chain count, deleting the chained records leaves
        // a file that looks exactly like an old unsigned trail.
        let t = try trail(preChain: 2, entries: 3)
        let v = t.verify(records: Array(t.records.prefix(2)))
        #expect(!v.isClean)
        #expect(v.completeness.state == .missingFromEnd)
    }

    // MARK: - Clause 5a

    @Test("an entry claiming a key class this Mac does not have is a fault")
    func keyClassCannotBeClaimed() throws {
        var t = try trail(entries: 2)
        try t.append("{\"tool\":\"proctor_act\",\"n\":\"claims the secure element\"}",
                 keyClass: .secureElement)
        let v = t.verify()
        #expect(v.faults.contains { $0.kind == .wrongKeyClass && $0.position == 3 })
    }

    @Test("a signature that is not a signature is a fault rather than an unreadable entry")
    func malformedSignatureIsAFault() throws {
        let t = try trail(entries: 3)
        var records = t.records
        let line = try #require(AuditSeal.decode(records[1]),
                                "AuditSeal.decode returned nil for a record this suite sealed")
        records[1] = try #require(AuditSeal.encode(AuditSeal.SealedLine(
            v: line.v, kid: line.kid, epk: line.epk, ct: line.ct, prev: line.prev,
            tid: line.tid, skid: line.skid, cls: line.cls,
            sig: Data("far too short".utf8).base64EncodedString())))
        let v = t.verify(records: records)
        #expect(v.faults.contains { $0.kind == .malformedSignature && $0.position == 2 })
    }

    // MARK: - Clause 6

    @Test("entries written before the chain verify as predating it, neither clean nor forged")
    func preChainEntriesArePreChain() throws {
        let t = try trail(preChain: 3, entries: 2)
        let v = t.verify()
        #expect(v.preChain == 3)
        #expect(v.verified == 2)
        #expect(v.faults.isEmpty)
        #expect(v.isClean)
    }

    @Test("the first chained entry pins the history before it, so a later edit to it is detected")
    func genesisPinsPreChainHistory() throws {
        let t = try trail(preChain: 3, entries: 2)
        var records = t.records
        // Rewrite an entry that predates signing. Nothing could have proved it at
        // the time; the genesis link proves it has not moved since.
        records[1] = try t.sealUnchained("{\"old\":\"rewritten after the fact\"}")
        let v = t.verify(records: records)
        #expect(v.faults.contains { $0.kind == .linkBroken && $0.position == 4 },
                "the first chained entry is where the altered history shows up")
        #expect(!v.isClean)
    }

    @Test("deleting a pre-chain entry is detected too")
    func deletingPreChainHistoryIsDetected() throws {
        let t = try trail(preChain: 3, entries: 2)
        var records = t.records
        records.remove(at: 0)
        let v = t.verify(records: records)
        #expect(!v.isClean)
    }

    // MARK: - Clause 7

    @Test("a trail whose entries cannot be opened still returns a full verdict")
    func verificationDoesNotNeedTheReadingKey() throws {
        // Verification takes the public signing key and the records. It never
        // touches the seal's private half, which is the whole point: checking and
        // reading are different privileges.
        let t = try trail(entries: 4)
        let v = t.verify()
        #expect(v.isClean)
        // and the reading key genuinely cannot open these, to prove the point
        let strangerKey = Curve25519.KeyAgreement.PrivateKey()
        #expect(AuditSeal.open(t.records[0], with: strangerKey) == nil)
    }

    // MARK: - Clause 8

    @Test("a trail signed by another key, presented with its own key, is never clean")
    func aForgersOwnKeyDoesNotYieldClean() throws {
        // The forger controls the file *and* the public key beside it. What they
        // cannot control is what this Mac holds, which is why the expectation
        // comes from the key store and not from the file.
        let forger = try trail(entries: 3)
        let verdict = AuditChain.verify(
            records: forger.records,
            expected: AuditChain.Expectation(
                trailId: forger.trailId, keyId: nil, keyClass: nil, anchor: forger.anchor,
                verify: { signature, material in
                    guard let parsed = try? P256.Signing.ECDSASignature(
                        rawRepresentation: signature) else { return false }
                    return forger.signingKey.publicKey.isValidSignature(parsed, for: material)
                }))
        #expect(verdict.faults.isEmpty, "internally it is perfectly consistent")
        #expect(!verdict.keyConfirmed)
        #expect(!verdict.isClean, "and it is still not clean, because nothing confirmed the key")
    }

    // MARK: - Clause 9

    @Test("a genuinely signed entry cannot be spliced in from another trail")
    func entriesCannotBeSplicedBetweenTrails() throws {
        var t = try trail(entries: 3)
        var other = try Trail()
        try other.append("{\"tool\":\"proctor_act\",\"from\":\"another Mac\"}")
        // Give the transplanted entry a correct link, so only the trail id is
        // wrong — the check has to be doing real work rather than riding the chain.
        let lifted = try #require(AuditSeal.decode(other.records[0]),
                                  "AuditSeal.decode returned nil for the lifted record")
        let prev = AuditChain.hash(record: t.records[2])
        let material = AuditChain.signedMaterial(
            version: lifted.v, trailId: other.trailId, previous: prev, keyId: other.keyId,
            keyClass: .software, sealKeyId: lifted.kid, ephemeralKey: lifted.epk,
            ciphertext: lifted.ct)
        let sig = try other.signingKey.signature(for: material)
        t.records.append(try #require(AuditSeal.encode(lifted.signed(
            prev: prev, tid: other.trailId, skid: other.keyId, cls: "sw",
            sig: sig.rawRepresentation.base64EncodedString()))))
        let v = t.verify(anchor: t.anchor)
        #expect(v.faults.contains { $0.kind == .wrongTrail && $0.position == 4 })
    }

    // MARK: - Clause 11 and the torn tail

    @Test("a key change is reported as a key this Mac no longer holds, not as forgery")
    func keyChangeIsNotAnAccusation() throws {
        let t = try trail(entries: 3)
        // The key store was reset: this Mac now holds a different key. The entries
        // are honest and unreadable-by-us, which is a different statement from
        // "somebody forged these".
        let v = AuditChain.verify(records: t.records,
                                  expected: t.expectation(keyId: String??.some("0000deadbeef0000")))
        #expect(v.faults.allSatisfy { $0.kind == .keyNotHeld })
        #expect(!v.faults.contains { $0.kind == .signatureInvalid })
    }

    @Test("a file that does not end in a newline reports a torn final write")
    func tornFinalEntryIsReported() throws {
        let t = try trail(entries: 3)
        let v = t.verify(endsWithNewline: false)
        #expect(v.faults.contains { $0.kind == .tornFinalEntry && $0.position == 3 })
    }

    @Test("an unreadable record is reported, and the entry after it still links to its bytes")
    func aScarredRecordDoesNotBreakTheChain() throws {
        var t = try trail(entries: 2)
        // A torn fragment the writer terminated and chained past: the damage is
        // permanent and recorded, rather than fused into the next record.
        t.records.append("{\"v\":1,\"kid\":\"trunc")
        let prev = AuditChain.hash(record: t.records[2])
        var next = t
        next.records = t.records
        next.anchor = t.anchor
        // build the following record by hand so its link is over the fragment
        let sealed = try #require(AuditSeal.sealLine(line: "{\"tool\":\"after the tear\"}",
                                                    to: t.sealKey.publicKey))
        let material = AuditChain.signedMaterial(
            version: sealed.v, trailId: t.trailId, previous: prev, keyId: t.keyId,
            keyClass: .software, sealKeyId: sealed.kid, ephemeralKey: sealed.epk,
            ciphertext: sealed.ct)
        let sig = try t.signingKey.signature(for: material)
        next.records.append(try #require(AuditSeal.encode(sealed.signed(
            prev: prev, tid: t.trailId, skid: t.keyId, cls: "sw",
            sig: sig.rawRepresentation.base64EncodedString()))))
        next.anchor.count = next.records.count
        next.anchor.head = AuditChain.hash(record: next.records[next.records.count - 1])
        let v = next.verify()
        #expect(v.faults.contains { $0.kind == .malformedRecord && $0.position == 3 })
        #expect(!v.faults.contains { $0.kind == .linkBroken },
                "the entry after the tear links to the damaged bytes, so the sequence is intact")
    }

    // MARK: - The definitions themselves

    @Test("a record's hash covers its bytes without the newline, in lowercase hex")
    func theHashDefinitionIsFixed() {
        let hash = AuditChain.hash(record: "{\"a\":1}")
        #expect(hash == hash.lowercased())
        #expect(hash.count == 64)
        #expect(hash != AuditChain.hash(record: "{\"a\":1}\n"),
                "the newline is not part of a record")
    }

    @Test("an empty pre-chain prefix hashes as the hash of no bytes")
    func genesisOverAnEmptyFileIsDefined() {
        #expect(AuditChain.genesisLink(preChainRecords: []) ==
                SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined())
    }

    @Test("the signed material is unambiguous: no two different field sets share a transcript")
    func signedMaterialIsUnambiguous() {
        // The length prefixes are what make this true. Glueing values together
        // would let "ab" + "c" and "a" + "bc" be the same message, and the fields
        // here are attacker-influenced.
        let a = AuditChain.signedMaterial(version: 1, trailId: "ab", previous: String(repeating: "0", count: 64),
                                          keyId: "c", keyClass: .software, sealKeyId: "k",
                                          ephemeralKey: "e", ciphertext: "t")
        let b = AuditChain.signedMaterial(version: 1, trailId: "a", previous: String(repeating: "0", count: 64),
                                          keyId: "bc", keyClass: .software, sealKeyId: "k",
                                          ephemeralKey: "e", ciphertext: "t")
        #expect(a != b)
    }

    @Test("the signed material covers the ciphertext, the link, the trail and the key")
    func signedMaterialCoversWhatItMustCover() {
        func material(previous: String = String(repeating: "1", count: 64), trailId: String = "t",
                      keyId: String = "k", ciphertext: String = "c",
                      keyClass: AuditChain.KeyClass = .software) -> Data {
            AuditChain.signedMaterial(version: 1, trailId: trailId, previous: previous,
                                      keyId: keyId, keyClass: keyClass, sealKeyId: "s",
                                      ephemeralKey: "e", ciphertext: ciphertext)
        }
        let base = material()
        #expect(material(previous: String(repeating: "2", count: 64)) != base)
        #expect(material(trailId: "other") != base)
        #expect(material(keyId: "other") != base)
        #expect(material(ciphertext: "other") != base)
        #expect(material(keyClass: .secureElement) != base)
    }

    @Test("high-s signatures are accepted, because half of all honest signatures are high-s")
    func highSSignaturesAreAccepted() throws {
        // Measured while planning this: 99 of 200 secure-element signatures and 97
        // of 200 software signatures are high-s. Rejecting them as non-canonical
        // would have rejected about half of every honest trail. Malleability is
        // closed by the chain instead — flipping s changes the record's bytes,
        // which breaks the next record's link.
        var t = try trail(entries: 30)
        try t.append("{\"tool\":\"proctor_act\",\"n\":30}")
        #expect(t.verify().isClean)
    }

    @Test("an entry sealed before this feature still opens, and the seal is untouched")
    func theSealItselfIsUnchanged() throws {
        let t = try trail(entries: 1)
        // A chained record still opens with the seal's own private key: the chain
        // fields sit outside the sealed box, so nothing already on disk changed
        // meaning and nothing new is harder to read.
        let opened = AuditSeal.open(t.records[0], with: t.sealKey)
        #expect(opened == "{\"tool\":\"proctor_act\",\"n\":0}")
        #expect(AuditSeal.isSealed(t.records[0]))
    }
}
