import Foundation
import CryptoKit

// Tamper-evidence for the audit trail, pure half. PRO-0013 made the trail
// unreadable to anyone without the key; sealing needs only the *public* key, so
// anybody who could read the directory could also append a well-formed entry
// that opened cleanly. This makes that entry detectable.
//
// The construction is a chain and a signature together, because each fails
// exactly where the other works. A signature alone catches a forged entry and
// not a deleted one. A chain alone catches deletion and reordering, but its
// links are public, so anyone who can read the file can recompute a consistent
// one — it catches an accident rather than an attacker. Chained *and* signed,
// an inserted entry has no valid signature, a deleted one breaks a link, a
// reordered pair breaks two, and an edited one fails both.
//
// One rule runs through this file and is the reason it exists as its own unit:
// **every byte that is hashed or signed is defined exactly once, here, and the
// writer and the verifier both read that definition.** "Hash the previous line"
// and "sign the record" are not specifications — trailing newlines, hex case,
// key order, whitespace and duplicate keys all differ between two honest
// implementations, and the failure mode is either an accusation against honest
// history or a silent pass over edited history.
//
// What this does not claim. Anything running as this user on this Mac can ask
// the signer to sign, exactly as the agent does, so a compromised agent can sign
// a lie it was told to write. The claim is narrower and worth stating in one
// line: a clean verdict cannot be manufactured off this machine, and a fault
// verdict can always be forced by destroying the key. Detection, not prevention.
public enum AuditChain {

    /// Domain separator. Prefixing the signed material with a constant that
    /// names this construction stops a signature made here being replayed as a
    /// signature over anything else the same key might ever sign.
    public static let domain = "proctor-audit-chain-v1"

    /// Which kind of key signed an entry. Recorded per entry rather than assumed
    /// per machine, so a clean verdict says what it is worth: `secureElement`
    /// means the key cannot leave this Mac, `software` means it is an ordinary
    /// protected key on a Mac that has no secure element.
    ///
    /// It is never trusted from the record — the verifier compares it with how
    /// the key is actually stored, so a software signer cannot claim the
    /// stronger class.
    public enum KeyClass: String, Codable, Sendable, Equatable {
        case secureElement = "se"
        case software = "sw"
    }

    // MARK: - The exact definitions

    /// A record's bytes are the exact bytes of that line as it sits on disk,
    /// **excluding** the terminating newline. Everything that hashes a record
    /// hashes this, and nothing else.
    public static func recordBytes(_ record: String) -> Data { Data(record.utf8) }

    /// Lowercase hex SHA-256 over a record's bytes. The case is part of the
    /// definition: two honest implementations that disagree about it produce a
    /// broken link on every entry.
    public static func hash(record: String) -> String { hex(SHA256.hash(data: recordBytes(record))) }

    /// The genesis link: lowercase hex SHA-256 over the **entire file prefix that
    /// precedes the first chained record, newlines included, exactly as it sits
    /// on disk**. This is what pins the history that existed before signing was
    /// introduced — it could not be proved at the time, but it cannot be edited
    /// after this point without the first chained entry noticing.
    ///
    /// An empty prefix hashes as SHA-256 of no bytes rather than being omitted or
    /// zeroed, so the empty-trail case has one answer instead of three.
    public static func genesisLink(preChainRecords: [String]) -> String {
        var data = Data()
        for record in preChainRecords {
            data.append(recordBytes(record))
            data.append(0x0A)
        }
        return hex(SHA256.hash(data: data))
    }

    /// The signed material: a length-prefixed concatenation of **values**, never
    /// a re-serialised JSON document.
    ///
    /// This is the single most important decision in the file. Signing "the
    /// record's JSON" would make the signature depend on key order, whitespace,
    /// escaping and duplicate-key handling, none of which JSON pins down — so an
    /// honest writer and an honest verifier disagree, and an attacker can change
    /// the raw bytes without changing what was signed. Signing length-prefixed
    /// values removes the question: there is no canonicalisation problem because
    /// there is no serialisation.
    ///
    /// Extra keys or reordered keys in the stored line therefore do not change
    /// the signature. They change the record's *bytes*, which breaks the **next**
    /// record's link — which is where the chain catches them, and why the two
    /// halves are one construction.
    public static func signedMaterial(version: Int, trailId: String, previous: String,
                                      keyId: String, keyClass: KeyClass,
                                      sealKeyId: String, ephemeralKey: String,
                                      ciphertext: String) -> Data {
        var out = Data(domain.utf8)
        out.append(bigEndian(UInt32(truncatingIfNeeded: version)))
        append(&out, trailId)
        // The link goes in as its 32 raw bytes rather than as text, so a hex
        // string and the bytes it spells can never be two different messages.
        out.append(bigEndian(UInt32(32)))
        out.append(bytes(fromHex: previous) ?? Data(repeating: 0, count: 32))
        append(&out, keyId)
        append(&out, keyClass.rawValue)
        append(&out, sealKeyId)
        append(&out, ephemeralKey)
        append(&out, ciphertext)
        return out
    }

    private static func append(_ out: inout Data, _ text: String) {
        let raw = Data(text.utf8)
        out.append(bigEndian(UInt32(truncatingIfNeeded: raw.count)))
        out.append(raw)
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        var be = value.bigEndian
        return withUnsafeBytes(of: &be) { Data($0) }
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A short stable fingerprint of a signing key: the first 16 hex of SHA-256
    /// over its raw public bytes. Same shape as the seal's `kid`, for the same
    /// reason — an entry signed by a key this Mac no longer holds is *detected*
    /// rather than fed to the wrong key, and a later key change stays possible
    /// without a format change.
    public static func keyId(forPublicKey raw: Data) -> String {
        String(SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    public static func bytes(fromHex hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var out = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    /// The signature's stored form is the 64-byte P1363 pair, base64. Fixed size
    /// so a malformed signature is a fault rather than something the verifier has
    /// to guess at.
    public static let signatureByteCount = 64

    // MARK: - The anchor

    /// How far the trail had got, kept where an attacker with file access cannot
    /// reach it.
    ///
    /// This lives in the Mac's protected key store rather than in a file beside
    /// the trail, and that is not a detail. A marker on disk is restored together
    /// with the trail from any snapshot or backup, and the restored pair verifies
    /// perfectly — which makes rolling the trail back to an earlier version free.
    /// A marker the file system cannot reach is what makes truncation and
    /// rollback answerable at all.
    ///
    /// `preChainCount` is frozen when the chain starts. Without it, an attacker
    /// who strips every chained record leaves a file that reads as an ordinary
    /// trail written before this feature existed.
    public struct Anchor: Codable, Sendable, Equatable {
        public var trailId: String
        public var count: Int              // records anchored so far
        public var head: String            // hash of the record at `count`
        public var keyId: String
        public var preChainCount: Int

        public init(trailId: String, count: Int, head: String, keyId: String, preChainCount: Int) {
            self.trailId = trailId; self.count = count; self.head = head
            self.keyId = keyId; self.preChainCount = preChainCount
        }
    }

    // MARK: - The verdict

    public struct Fault: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            /// The signature does not check out: this entry was not written here.
            case signatureInvalid
            /// A record after the chain started that carries no link at all.
            case unsigned
            /// The link does not match the previous record: something was removed,
            /// moved or edited.
            case linkBroken
            /// Two records claim the same predecessor. A lock only binds writers
            /// who take it, so the verifier reports a fork rather than trusting it.
            case fork
            /// Genuinely signed, but for a different trail. Without this an entry
            /// could be lifted from another machine's trail and land here intact.
            case wrongTrail
            /// Signed by a key this Mac does not hold. Deliberately not the same
            /// as `signatureInvalid`: a reset key store is not an accusation.
            case keyNotHeld
            /// Claims a stronger key class than this Mac actually has.
            case wrongKeyClass
            /// Not a signature of the expected size.
            case malformedSignature
            /// Not a decodable record. Where the next record's link still matches
            /// its bytes, this is the permanent scar of a torn write rather than
            /// an edit — the chain vouches for the damage.
            case malformedRecord
            /// The file does not end in a newline: the last write was torn.
            case tornFinalEntry
        }

        public var kind: Kind
        /// 1-based, so it matches how an operator counts lines.
        public var position: Int
        public var detail: String

        public init(kind: Kind, position: Int, detail: String) {
            self.kind = kind; self.position = position; self.detail = detail
        }
    }

    public struct Completeness: Codable, Sendable, Equatable {
        public enum State: String, Codable, Sendable {
            /// Every record is accounted for against the anchor.
            case proven
            /// The trail runs ahead of its anchor and every link checks out: the
            /// ordinary state after a crash between the append and the anchor
            /// write. Those records are still signature-checked, so their
            /// contents cannot differ — only their existence is unproven.
            case unanchoredTail
            /// The trail is one record behind its anchor: a crash between the
            /// flush and the anchor write. Not an accusation.
            case lostFinalEntry
            /// Records are gone from the end, or the anchor's head is not where it
            /// should be — a truncation, or a rollback to an older copy.
            case missingFromEnd
            /// No anchor, so completeness cannot be proved. Never clean.
            case notProvable
        }

        public var state: State
        public var count: Int?
        public var reason: String?

        public init(state: State, count: Int? = nil, reason: String? = nil) {
            self.state = state; self.count = count; self.reason = reason
        }
    }

    public struct Verdict: Codable, Sendable, Equatable {
        public var total: Int
        /// Chained, signed, linked, and signed by this Mac's key.
        public var verified: Int
        /// Written before signing existed. Neither clean nor forged: nothing
        /// could have proved them at the time, and the genesis link pins them
        /// from that point on.
        public var preChain: Int
        public var faults: [Fault]
        public var completeness: Completeness
        /// False when the key store could not be reached, which makes the whole
        /// verdict "internally consistent, unconfirmed" rather than clean: a
        /// forger who supplies both the trail and the key that checks it would
        /// otherwise pass.
        public var keyConfirmed: Bool

        public var isClean: Bool {
            faults.isEmpty && keyConfirmed
                && (completeness.state == .proven || completeness.state == .unanchoredTail)
        }

        public init(total: Int, verified: Int, preChain: Int, faults: [Fault],
                    completeness: Completeness, keyConfirmed: Bool) {
            self.total = total; self.verified = verified; self.preChain = preChain
            self.faults = faults; self.completeness = completeness; self.keyConfirmed = keyConfirmed
        }
    }

    /// What the verifier expects to find, from the key store rather than from the
    /// file. Nil `keyId` means the key store could not be reached at all, which
    /// is reported as unconfirmed rather than guessed at.
    public struct Expectation: Sendable {
        public var trailId: String?
        public var keyId: String?
        public var keyClass: KeyClass?
        public var anchor: Anchor?
        public var verify: @Sendable (_ signature: Data, _ material: Data) -> Bool

        public init(trailId: String?, keyId: String?, keyClass: KeyClass?, anchor: Anchor?,
                    verify: @escaping @Sendable (_ signature: Data, _ material: Data) -> Bool) {
            self.trailId = trailId; self.keyId = keyId; self.keyClass = keyClass
            self.anchor = anchor; self.verify = verify
        }
    }

    // MARK: - Verifying

    /// Walk the trail and report what is true about it.
    ///
    /// `records` are the file's lines in file order, each without its newline.
    /// `endsWithNewline` is false only when the last write was torn.
    ///
    /// The order of business matters: the per-record checks establish that each
    /// entry is what it says it is, and the anchor placement afterwards
    /// establishes that the file has as many of them as it should. Neither alone
    /// answers the question.
    public static func verify(records: [String], endsWithNewline: Bool = true,
                              expected: Expectation) -> Verdict {
        var faults: [Fault] = []
        var verified = 0

        let parsed: [AuditSeal.SealedLine?] = records.map { AuditSeal.decode($0) }
        let chainStart = chainStartIndex(parsed: parsed, anchor: expected.anchor)

        guard let chainStart else {
            // Nothing in the file carries a link. With an anchor that says the
            // chain had started, that is a stripped trail, not an old one.
            let preChain = records.count
            var completeness = Completeness(state: .notProvable,
                                            reason: "No entry carries a chain link, so the trail's "
                                                  + "completeness cannot be proved.")
            if let anchor = expected.anchor, anchor.count > 0 {
                faults.append(Fault(kind: .unsigned, position: 1,
                                    detail: "The trail was being signed, and no entry in it carries "
                                          + "a link: every signed entry has been removed."))
                completeness = Completeness(state: .missingFromEnd, count: anchor.count,
                                            reason: "The anchor records \(anchor.count) signed "
                                                  + "entries and none is present.")
            }
            return Verdict(total: records.count, verified: 0, preChain: preChain, faults: faults,
                           completeness: completeness, keyConfirmed: expected.keyId != nil)
        }

        if !endsWithNewline, !records.isEmpty {
            faults.append(Fault(kind: .tornFinalEntry, position: records.count,
                                detail: "The trail does not end in a newline, so the last write was "
                                      + "torn."))
        }

        var seenLinks: [String: Int] = [:]
        for index in chainStart..<records.count {
            let position = index + 1
            guard let line = parsed[index] else {
                faults.append(Fault(kind: .malformedRecord, position: position,
                                    detail: "This entry is not a readable record."))
                continue
            }
            guard let prev = line.prev, let tid = line.tid, let skid = line.skid,
                  let cls = line.cls, let sig = line.sig else {
                faults.append(Fault(kind: .unsigned, position: position,
                                    detail: "This entry carries no chain link, and it was written "
                                          + "after the trail began to be signed."))
                continue
            }

            // The link, against the definition at the top of this file.
            let expectedLink = index == chainStart
                ? genesisLink(preChainRecords: Array(records[0..<chainStart]))
                : hash(record: records[index - 1])
            if prev != expectedLink {
                faults.append(Fault(kind: .linkBroken, position: position,
                                    detail: index == chainStart
                                        ? "The first signed entry does not match the history that "
                                        + "precedes it, so that history has been altered."
                                        : "This entry does not follow the one before it: an entry "
                                        + "has been removed, moved or edited."))
            }
            if let first = seenLinks[prev] {
                faults.append(Fault(kind: .fork, position: position,
                                    detail: "This entry claims the same predecessor as entry "
                                          + "\(first), so the trail forks."))
            } else {
                seenLinks[prev] = position
            }

            if let expectedTrail = expected.trailId, tid != expectedTrail {
                faults.append(Fault(kind: .wrongTrail, position: position,
                                    detail: "This entry was signed for a different trail."))
            }
            if let expectedKey = expected.keyId, skid != expectedKey {
                faults.append(Fault(kind: .keyNotHeld, position: position,
                                    detail: "This entry was signed with a key this Mac no longer "
                                          + "holds, so it can no longer be checked."))
                continue
            }
            if let expectedClass = expected.keyClass, cls != expectedClass.rawValue {
                faults.append(Fault(kind: .wrongKeyClass, position: position,
                                    detail: "This entry claims a different kind of signing key "
                                          + "from the one this Mac holds."))
            }
            guard let signature = Data(base64Encoded: sig),
                  signature.count == signatureByteCount else {
                faults.append(Fault(kind: .malformedSignature, position: position,
                                    detail: "This entry's signature is not a signature."))
                continue
            }
            let material = signedMaterial(version: line.v, trailId: tid, previous: prev,
                                          keyId: skid, keyClass: KeyClass(rawValue: cls) ?? .software,
                                          sealKeyId: line.kid, ephemeralKey: line.epk,
                                          ciphertext: line.ct)
            if !expected.verify(signature, material) {
                faults.append(Fault(kind: .signatureInvalid, position: position,
                                    detail: "This entry's signature does not check out: it was not "
                                          + "written by Proctor on this Mac."))
                continue
            }
            if faults.last?.position != position { verified += 1 }
        }

        return Verdict(total: records.count, verified: verified, preChain: chainStart,
                       faults: faults,
                       completeness: place(anchor: expected.anchor, records: records,
                                           chainStart: chainStart, faults: faults),
                       keyConfirmed: expected.keyId != nil)
    }

    /// Where the chain begins. The anchor is authoritative when it exists,
    /// because it is the half an attacker with file access cannot rewrite;
    /// without one, the first record carrying a link is the best available
    /// answer and the verdict says completeness cannot be proved.
    private static func chainStartIndex(parsed: [AuditSeal.SealedLine?], anchor: Anchor?) -> Int? {
        if let anchor, anchor.preChainCount <= parsed.count {
            // Trust the anchor even when the records there look unchained: that
            // is exactly the stripped-trail case, and it must read as a fault
            // rather than as ordinary old history.
            if anchor.count > 0 || parsed.dropFirst(anchor.preChainCount).contains(where: isChained) {
                return anchor.preChainCount
            }
        }
        return parsed.firstIndex(where: isChained)
    }

    private static func isChained(_ line: AuditSeal.SealedLine?) -> Bool {
        guard let line else { return false }
        return line.prev != nil && line.sig != nil
    }

    /// Place the anchor against the file. Both honest states — a trail running
    /// ahead of its anchor, and a trail one record behind it — are ordinary
    /// consequences of a crash, and reporting either as tampering would make the
    /// verdict useless. Everything else is reported.
    private static func place(anchor: Anchor?, records: [String], chainStart: Int,
                              faults: [Fault]) -> Completeness {
        guard let anchor else {
            return Completeness(state: .notProvable,
                                reason: "There is no record of how far the trail had got, so "
                                      + "entries removed from the end cannot be ruled out.")
        }
        if anchor.count == records.count {
            guard records.count > 0 else { return Completeness(state: .proven) }
            return hash(record: records[anchor.count - 1]) == anchor.head
                ? Completeness(state: .proven)
                : Completeness(state: .missingFromEnd, count: 0,
                               reason: "The trail's last entry is not the one the anchor recorded, "
                                     + "so the trail has been replaced or rolled back.")
        }
        if records.count > anchor.count {
            // The anchored record must still be where the anchor says it is, or
            // the tail is not growth — it is a different trail wearing the same
            // prefix length.
            guard anchor.count == 0 || (anchor.count <= records.count
                    && hash(record: records[anchor.count - 1]) == anchor.head) else {
                return Completeness(state: .missingFromEnd,
                                    reason: "The entry the anchor recorded is not where it should "
                                          + "be, so the trail has been rewritten.")
            }
            let tail = records.count - anchor.count
            // The links in that tail were checked above; a broken one is already
            // a fault, and an unchecked tail must not be reported as ordinary.
            let tailBroken = faults.contains { $0.position > anchor.count }
            return tailBroken
                ? Completeness(state: .missingFromEnd, count: tail,
                               reason: "The entries past the anchor do not follow it.")
                : Completeness(state: .unanchoredTail, count: tail)
        }
        let missing = anchor.count - records.count
        if missing == 1 {
            return Completeness(state: .lostFinalEntry,
                                reason: "One entry is missing from the end, which is what a crash "
                                      + "between writing an entry and recording it looks like.")
        }
        return Completeness(state: .missingFromEnd, count: missing,
                            reason: "\(missing) entries are missing from the end of the trail.")
    }
}
